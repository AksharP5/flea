// The backend's side of `flea --thumb-worker`: one worker for the whole pool, started on the first
// video that qualifies, and given up on for good the first time it fails. Every way this can go
// wrong answers None, and the caller then runs the job the way it always has; see AGENTS.md
// "Thumbnail worker".
use crate::backend::child::Ran;
use crate::backend::fdpass;
use crate::backend::sandbox;
use crate::backend::thumbspec::Spec;
use crate::backend::thumbworker::{FAILED, NOT_STARTED, READY, REQUEST_BYTES, SUCCEEDED};
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

// Sample Exec, the one ffmpegthumbnailer ships: "ffmpegthumbnailer -i %i -o %o -s %s -f". Some(film
// strip) only for exactly that program with exactly those options, so the worker never guesses at a
// flag and every other thumbnailer, and every other spelling of this one, stays on the exec path.
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

    // Started under the lock, so four pool threads meeting their first video start one worker between them.
    fn spawn() -> Option<(Child, OwnedFd)> {
        let exe = std::fs::canonicalize("/proc/self/exe").ok()?;
        let exe_text = exe.to_str()?.to_string();
        let (mine, theirs) = fdpass::pair().ok()?;
        let argv = sandbox::wrap_worker(&[exe_text, "--thumb-worker".to_string()], &exe);
        // corner: bwrap's --die-with-parent follows the thread that spawns it, and a pool thread lives as long as the backend.
        let mut child = Command::new(&argv[0])
            .args(&argv[1..])
            .stdin(Stdio::from(theirs))
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .ok()?;
        if read_byte(&mine, READY_LIMIT) == Some(READY) {
            return Some((child, mine));
        }
        let _ = child.kill();
        let _ = child.wait();
        None
    }

    // Holding the lock across the send keeps a request whole and lets one failure retire the worker for every thread.
    fn send(&self, payload: &[u8], fds: &[i32]) -> bool {
        let mut state = self.state.lock().unwrap();
        if matches!(*state, State::Unstarted) {
            *state = match WorkerLink::spawn() {
                Some((child, requests)) => State::Running { child, requests },
                None => {
                    eprintln!("flea: the thumbnail worker did not start, so videos use the thumbnailer program");
                    State::Gone
                }
            };
        }
        let sent = match &*state {
            State::Running { requests, .. } => fdpass::send(requests.as_raw_fd(), payload, fds).is_ok(),
            _ => return false,
        };
        if !sent {
            WorkerLink::retire(&mut state);
        }
        sent
    }

    fn retire(state: &mut State) {
        if let State::Running { child, .. } = state {
            let _ = child.kill();
            let _ = child.wait();
            eprintln!("flea: the thumbnail worker stopped answering, so videos use the thumbnailer program");
        }
        *state = State::Gone;
    }

    // Some(verdict) when the worker judged the job, None when the job has to go down the exec path.
    pub fn generate(&self, input: &Path, output: &Path, size: u32, film_strip: bool, limit: Duration) -> Option<Ran> {
        if matches!(*self.state.lock().unwrap(), State::Gone) {
            return None;
        }
        let input = std::fs::OpenOptions::new()
            .read(true)
            .custom_flags(O_NONBLOCK | O_NOCTTY)
            .open(input)
            .ok()?;
        // corner: a fifo or a device swapped in after the listing judges nothing, and the exec path would only hang on it.
        if !input.metadata().ok()?.is_file() {
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
            Some(FAILED) => Some(Ran::Failed),
            Some(NOT_STARTED) => Some(Ran::NotStarted),
            // No verdict at all is the worker dying or wedging, which says nothing about this file.
            _ => {
                WorkerLink::retire(&mut self.state.lock().unwrap());
                None
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
