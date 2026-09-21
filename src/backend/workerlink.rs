// The backend's side of `flea --thumb-worker`: one worker for the pool, started on the first video that qualifies and retired for good at its first failure; see AGENTS.md "Thumbnail worker".
use crate::backend::child::Ran;
use crate::backend::fdpass;
use crate::backend::sandbox;
use crate::backend::thumbspec::Spec;
use crate::backend::thumbworker::{FAILED, NOT_STARTED, NO_LANDLOCK, NO_LIBRARY, READY, REQUEST_BYTES, SONAME, SUCCEEDED};
use std::os::fd::{AsRawFd, OwnedFd};
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::time::Duration;

// The worker answers READY after one dlopen and one Landlock probe, measured at tens of milliseconds.
const READY_LIMIT: Duration = Duration::from_secs(5);
// The worker enforces the job's own deadline, so the backend only waits this much longer for its word.
const REPLY_GRACE: Duration = Duration::from_secs(5);
// open(2) flags: never block on a fifo swapped in after the listing, never follow a link at the temp's name.
const O_NONBLOCK: i32 = 0o4000;
const O_NOFOLLOW: i32 = 0o400000;
const O_NOCTTY: i32 = 0o400;
// poll(2) POLLIN, and EINTR, which is a retry.
const POLLIN: i16 = 1;
const EINTR: i32 = 4;
// The operator's way back to the exec path, and the battery's way to run it on purpose.
const OFF_SWITCH: &str = "FLEA_THUMB_WORKER";

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

extern "C" {
    fn poll(fds: *mut PollFd, nfds: usize, timeout: i32) -> i32;
}

enum State {
    Unstarted,
    Running { child: Child, requests: OwnedFd },
    Gone,
}

pub struct WorkerLink {
    state: Mutex<State>,
}

// Sample Exec, the one ffmpegthumbnailer ships: "ffmpegthumbnailer -i %i -o %o -s %s -f"; any other program, flag or spelling stays on the exec path.
pub fn worker_shape(spec: &Spec) -> Option<bool> {
    let mut tokens = spec.exec.iter().map(String::as_str);
    let program = tokens.next()?;
    if Path::new(program).file_name()?.to_str()? != "ffmpegthumbnailer" {
        return None;
    }
    let (mut input, mut output, mut size, mut film_strip) = (false, false, false, false);
    while let Some(flag) = tokens.next() {
        let seen = match flag {
            "-i" if tokens.next() == Some("%i") => &mut input,
            "-o" if tokens.next() == Some("%o") => &mut output,
            "-s" if tokens.next() == Some("%s") => &mut size,
            "-f" => &mut film_strip,
            _ => return None,
        };
        if *seen {
            return None;
        }
        *seen = true;
    }
    (input && output && size).then_some(film_strip)
}

// Why a worker that did not answer READY is not serving, from its first byte and how long it took; None before the limit is an exit, not a timeout.
fn why_not(answer: Option<u8>, waited: Duration) -> String {
    match answer {
        Some(NO_LIBRARY) => format!("{} did not load", SONAME.to_string_lossy()),
        Some(NO_LANDLOCK) => String::from("this kernel has no Landlock"),
        Some(other) => format!("it answered the unknown byte {}", other),
        None if waited >= READY_LIMIT => format!("it did not answer within {} s", READY_LIMIT.as_secs()),
        None => String::from("it exited before it answered"),
    }
}

// Waits for one byte on a socket, or answers None on a timeout, a closed peer or an error.
fn read_byte(sock: &OwnedFd, limit: Duration) -> Option<u8> {
    let deadline = std::time::Instant::now() + limit;
    loop {
        let left = deadline.saturating_duration_since(std::time::Instant::now());
        let ms = left.as_millis().saturating_add(1).min(i32::MAX as u128) as i32;
        let mut fds = PollFd { fd: sock.as_raw_fd(), events: POLLIN, revents: 0 };
        let ready = unsafe { poll(&mut fds, 1, ms) };
        if ready == 0 {
            return None;
        }
        if ready < 0 {
            if std::io::Error::last_os_error().raw_os_error() == Some(EINTR) {
                continue;
            }
            return None;
        }
        return match fdpass::recv(sock.as_raw_fd()) {
            Ok(Some(message)) if message.payload.len() == 1 => Some(message.payload[0]),
            _ => None,
        };
    }
}

impl WorkerLink {
    pub fn new() -> WorkerLink {
        let off = std::env::var(OFF_SWITCH).is_ok_and(|v| v == "off");
        WorkerLink { state: Mutex::new(if off { State::Gone } else { State::Unstarted }) }
    }

    // Started under the lock, so pool threads meeting their first video together start one worker between them.
    fn spawn() -> Result<(Child, OwnedFd), String> {
        let exe = std::fs::canonicalize("/proc/self/exe").map_err(|e| format!("/proc/self/exe did not resolve: {}", e))?;
        let exe_text = exe.to_str().ok_or("the flea executable's path is not UTF-8")?.to_string();
        let (mine, theirs) = fdpass::pair().map_err(|e| format!("no socket pair: {}", e))?;
        let argv = sandbox::wrap_worker(&[exe_text, "--thumb-worker".to_string()], &exe);
        // corner: bwrap's --die-with-parent follows the thread that spawns it, and a pool thread lives as long as the backend.
        let mut child = Command::new(&argv[0])
            .args(&argv[1..])
            .stdin(Stdio::from(theirs))
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("bwrap did not start: {}", e))?;
        let asked = std::time::Instant::now();
        let answer = read_byte(&mine, READY_LIMIT);
        if answer == Some(READY) {
            return Ok((child, mine));
        }
        let waited = asked.elapsed();
        let _ = child.kill();
        let _ = child.wait();
        Err(why_not(answer, waited))
    }

    // Holding the lock across the send keeps a request whole and lets one failure retire the worker for every thread.
    fn send(&self, payload: &[u8], fds: &[i32]) -> bool {
        let mut state = self.state.lock().unwrap();
        if matches!(*state, State::Unstarted) {
            *state = match WorkerLink::spawn() {
                Ok((child, requests)) => State::Running { child, requests },
                Err(why) => {
                    eprintln!("flea: the thumbnail worker did not start ({}), so videos use the thumbnailer program", why);
                    State::Gone
                }
            };
        }
        let sent = match &*state {
            State::Running { requests, .. } => fdpass::send(requests.as_raw_fd(), payload, fds).is_ok(),
            _ => return false,
        };
        if !sent {
            WorkerLink::retire(&mut state, "stopped taking requests");
        }
        sent
    }

    fn retire(state: &mut State, why: &str) {
        if let State::Running { child, .. } = state {
            let _ = child.kill();
            let _ = child.wait();
            eprintln!("flea: the thumbnail worker {}, so videos use the thumbnailer program", why);
        }
        *state = State::Gone;
    }

    // Some only for a thumbnail the worker made or an input that is not a file to judge; None sends the job down the exec path.
    pub fn generate(&self, input: &Path, output: &Path, size: u32, film_strip: bool, limit: Duration) -> Option<Ran> {
        if matches!(*self.state.lock().unwrap(), State::Gone) {
            return None;
        }
        // corner: an input that no longer opens, or a fifo or device swapped in after the listing, judges nothing, and the exec path would fail or hang on it.
        let Ok(input) = std::fs::OpenOptions::new().read(true).custom_flags(O_NONBLOCK | O_NOCTTY).open(input) else {
            return Some(Ran::NotStarted);
        };
        if !input.metadata().is_ok_and(|m| m.is_file()) {
            return Some(Ran::NotStarted);
        }
        let output = std::fs::OpenOptions::new().write(true).custom_flags(O_NOFOLLOW | O_NOCTTY).open(output).ok()?;
        let (reply, theirs) = fdpass::pair().ok()?;
        let mut payload = [0u8; REQUEST_BYTES];
        payload[..4].copy_from_slice(&size.to_le_bytes());
        payload[4] = u8::from(film_strip);
        if !self.send(&payload, &[input.as_raw_fd(), output.as_raw_fd(), theirs.as_raw_fd()]) {
            return None;
        }
        // Only the worker may hold the far end, or its death would never read as a closed socket here.
        drop(theirs);
        match read_byte(&reply, limit + REPLY_GRACE) {
            Some(SUCCEEDED) => Some(Ran::Succeeded),
            // The exec path judges this file again, so only the thumbnailer program ever records a failure.
            Some(FAILED) => None,
            Some(NOT_STARTED) => {
                WorkerLink::retire(&mut self.state.lock().unwrap(), "failed a job on this machine");
                None
            }
            // No verdict at all is the worker dying or wedging, which says nothing about this file.
            _ => {
                WorkerLink::retire(&mut self.state.lock().unwrap(), "stopped answering");
                None
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;
    use crate::backend::thumbs::THUMB_SIZE;

    // Stands in for the worker: answers the one request it is sent with `verdict`, on the reply socket that request carried.
    fn answered_by(verdict: u8) -> (WorkerLink, std::thread::JoinHandle<()>) {
        let (mine, theirs) = fdpass::pair().unwrap();
        let child = Command::new("true").spawn().unwrap();
        let link = WorkerLink { state: Mutex::new(State::Running { child, requests: mine }) };
        let answering = std::thread::spawn(move || {
            let request = fdpass::recv(theirs.as_raw_fd()).unwrap().expect("a request");
            let reply = request.fds.into_iter().nth(2).expect("a reply socket");
            fdpass::send_byte(&reply, verdict).unwrap();
        });
        (link, answering)
    }

    #[test]
    fn only_a_thumbnail_is_final_and_a_machine_failure_retires_the_worker() {
        let dir = TestDir::new("worker-verdicts");
        let input = dir.file("clip.mp4", "not a video");
        let output = dir.file("out.png", "");
        for (verdict, published, keeps_serving) in [(SUCCEEDED, true, true), (FAILED, false, true), (NOT_STARTED, false, false)] {
            let (link, answering) = answered_by(verdict);
            let got = link.generate(&input, &output, THUMB_SIZE, true, Duration::from_secs(1));
            answering.join().unwrap();
            assert_eq!(matches!(got, Some(Ran::Succeeded)), published, "verdict {}", verdict as char);
            assert_eq!(got.is_none(), !published, "verdict {} must send the job down the exec path", verdict as char);
            assert_eq!(matches!(*link.state.lock().unwrap(), State::Running { .. }), keeps_serving, "verdict {}", verdict as char);
        }
    }

    #[test]
    fn a_worker_that_is_not_serving_says_why() {
        assert_eq!(why_not(Some(NO_LIBRARY), Duration::ZERO), "libffmpegthumbnailer.so.4 did not load");
        assert_eq!(why_not(Some(NO_LANDLOCK), Duration::ZERO), "this kernel has no Landlock");
        assert_eq!(why_not(None, Duration::ZERO), "it exited before it answered");
        assert_eq!(why_not(None, READY_LIMIT), "it did not answer within 5 s");
    }

    fn spec(exec: &str) -> Spec {
        Spec { exec: exec.split(' ').map(str::to_string).collect() }
    }

    #[test]
    fn the_shipped_exec_line_is_the_worker_shape() {
        assert_eq!(worker_shape(&spec("ffmpegthumbnailer -i %i -o %o -s %s -f")), Some(true));
        assert_eq!(worker_shape(&spec("/usr/bin/ffmpegthumbnailer -s %s -i %i -o %o")), Some(false));
    }

    #[test]
    fn any_other_program_or_flag_stays_on_the_exec_path() {
        for exec in [
            "glycin-thumbnailer -i %i -o %o -s %s",
            "ffmpegthumbnailerx -i %i -o %o -s %s",
            "ffmpegthumbnailer -i %i -o %o -s %s -t 20",
            "ffmpegthumbnailer -i %u -o %o -s %s",
            "ffmpegthumbnailer -i %i -o %o",
            "ffmpegthumbnailer -i %i -o %o -s %s -f -f",
            "ffmpegthumbnailer -i %i -i %i -o %o -s %s",
            "ffmpegthumbnailer -i",
        ] {
            assert_eq!(worker_shape(&spec(exec)), None, "{} took the worker", exec);
        }
    }
}
