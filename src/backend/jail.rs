// A cancel that only kills bwrap leaves the jailed tool running when it lands during bwrap's
// startup, before --die-with-parent is armed. --json-status-fd names the sandbox init so both die.
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::Arc;

// No pid yet, so kill_tree kills only the launcher.
pub(crate) const GONE: i32 = -1;
const SIGKILL: i32 = 9;
// fcntl F_SETFD, to clear CLOEXEC on the status write end.
const F_SETFD: i32 = 2;

extern "C" {
    fn pipe(fds: *mut i32) -> i32;
    fn fcntl(fd: i32, cmd: i32, arg: i32) -> i32;
    fn dup2(oldfd: i32, newfd: i32) -> i32;
    fn close(fd: i32) -> i32;
    fn kill(pid: i32, sig: i32) -> i32;
    fn setpgid(pid: i32, pgid: i32) -> i32;
}

pub struct Jailed {
    pub child: std::process::Child,
    pub sandbox_pid: Arc<AtomicI32>,
}

// Sample input: b"{\"child-pid\": 1234}\n" answers 1234; the tool never writes this pipe.
pub fn parse_child_pid(buf: &[u8]) -> Option<i32> {
    let key = b"\"child-pid\"";
    let mut i = 0;
    while i + key.len() <= buf.len() {
        if &buf[i..i + key.len()] == key {
            let mut j = i + key.len();
            while j < buf.len() && !buf[j].is_ascii_digit() {
                j += 1;
            }
            let start = j;
            while j < buf.len() && buf[j].is_ascii_digit() {
                j += 1;
            }
            if start < j {
                if let Ok(text) = std::str::from_utf8(&buf[start..j]) {
                    if let Ok(pid) = text.parse::<i32>() {
                        if pid > 0 {
                            return Some(pid);
                        }
                    }
                }
            }
        }
        i += 1;
    }
    None
}

fn status_reader(fd: OwnedFd, out: Arc<AtomicI32>) {
    use std::io::Read;
    let mut file = std::fs::File::from(fd);
    let mut buf = Vec::new();
    let mut tmp = [0u8; 512];
    loop {
        match file.read(&mut tmp) {
            Ok(0) => break,
            Ok(n) => {
                buf.extend_from_slice(&tmp[..n]);
                if let Some(pid) = parse_child_pid(&buf) {
                    out.store(pid, Ordering::SeqCst);
                }
            }
            Err(_) => break,
        }
    }
}

// Sample argv: ["prlimit","bwrap","--json-status-fd","7",...] with STATUS_FD open.
pub fn spawn_jailed(full: &[String], setup: impl FnOnce(&mut std::process::Command)) -> std::io::Result<Jailed> {
    if full.is_empty() {
        return Err(std::io::Error::other("empty jail argv"));
    }
    let mut fds = [0, 0];
    if unsafe { pipe(fds.as_mut_ptr()) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    let read_fd = unsafe { OwnedFd::from_raw_fd(fds[0]) };
    let write_fd = unsafe { OwnedFd::from_raw_fd(fds[1]) };
    unsafe { fcntl(write_fd.as_raw_fd(), F_SETFD, 0) };
    let read_raw = read_fd.as_raw_fd();
    let write_raw = write_fd.as_raw_fd();
    let status_fd = crate::backend::sandbox::STATUS_FD;
    let mut cmd = std::process::Command::new(&full[0]);
    cmd.args(&full[1..]);
    setup(&mut cmd);
    unsafe {
        use std::os::unix::process::CommandExt;
        cmd.pre_exec(move || {
            close(read_raw);
            if dup2(write_raw, status_fd) < 0 {
                return Err(std::io::Error::last_os_error());
            }
            if write_raw != status_fd {
                close(write_raw);
            }
            setpgid(0, 0);
            Ok(())
        });
    }
    let child = cmd.spawn()?;
    drop(write_fd);
    let pid = Arc::new(AtomicI32::new(GONE));
    let reader_pid = Arc::clone(&pid);
    std::thread::spawn(move || status_reader(read_fd, reader_pid));
    Ok(Jailed { child, sandbox_pid: pid })
}

// SIGKILLs the sandbox init as well as bwrap, then waits; never blocks on any pipe reader.
pub fn kill_tree(jailed: &mut Jailed) {
    let first = jailed.sandbox_pid.load(Ordering::SeqCst);
    if first > 0 {
        unsafe { kill(first, SIGKILL) };
    }
    let pid = jailed.child.id() as i32;
    unsafe { kill(-pid, SIGKILL) };
    let _ = jailed.child.kill();
    let _ = jailed.child.wait();
    let late = jailed.sandbox_pid.load(Ordering::SeqCst);
    if late > 0 && late != first {
        unsafe { kill(late, SIGKILL) };
    }
    wait_gone(first.max(late));
}

fn wait_gone(pid: i32) {
    if pid <= 0 {
        return;
    }
    for _ in 0..200 {
        if unsafe { kill(pid, 0) } != 0 {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_status_parser_names_only_the_sandbox_pid() {
        assert_eq!(parse_child_pid(b"{\"child-pid\": 1234}\n"), Some(1234));
        assert_eq!(parse_child_pid(b"noise {\"child-pid\":42} tail"), Some(42));
        assert_eq!(parse_child_pid(b"no key here"), None);
        assert_eq!(parse_child_pid(b"{\"child-pid\": 0}"), None);
        assert_eq!(parse_child_pid(b"{\"child-pid\":}"), None);
    }

    // Cancels immediately after spawn in a loop; on the base this waits out the sleep and leaves it running.
    #[test]
    fn an_immediate_cancel_ends_every_process_in_the_jail_promptly() {
        if crate::backend::sandboxprobe::skipped() {
            return;
        }
        let token = format!("30.{}", std::process::id());
        for _ in 0..200 {
            let inner = vec!["/usr/bin/sleep".to_string(), token.clone()];
            let mut full = crate::backend::sandbox::wrap_readonly(&inner, std::path::Path::new("/usr/bin/sleep"));
            crate::backend::sandbox::add_status(&mut full, inner.len());
            let began = std::time::Instant::now();
            let mut jailed = spawn_jailed(&full, |cmd| {
                cmd.stdin(std::process::Stdio::null());
                cmd.stdout(std::process::Stdio::null());
                cmd.stderr(std::process::Stdio::null());
            })
            .expect("jailed sleep did not start");
            kill_tree(&mut jailed);
            assert!(began.elapsed() < std::time::Duration::from_secs(2), "a cancelled jail was waited out");
        }
        assert!(!proc_with_token(&token), "a jailed sleep outlived its cancel");
    }

    // Sample /proc/<pid>/cmdline: NUL-separated argv, so the token matches exactly one argument.
    fn proc_with_token(token: &str) -> bool {
        let procs = match std::fs::read_dir("/proc") {
            Ok(p) => p,
            Err(_) => return false,
        };
        procs.flatten().any(|p| match std::fs::read(p.path().join("cmdline")) {
            Ok(c) => c.split(|b| *b == 0).any(|arg| arg == token.as_bytes()),
            Err(_) => false,
        })
    }
}
