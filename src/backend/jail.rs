// A cancel during bwrap startup needs --json-status-fd: it names the sandbox init so both die.
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::Arc;
use std::time::Duration;

// No pid yet, so kill_tree kills only the launcher.
pub(crate) const GONE: i32 = -1;
const SIGKILL: i32 = 9;
// pipe2 O_CLOEXEC, so a spawn from another thread mid-jail never inherits the status pipe.
const O_CLOEXEC: i32 = 0o2000000;
// fcntl F_SETFD, to clear CLOEXEC where dup2(fd, fd) would leave it set.
const F_SETFD: i32 = 2;
// A cancel before bwrap wrote the init pid waits this long for it, so the kill lands while bwrap can still prove ownership.
pub(crate) const STATUS_WAIT_MS: u64 = 200;
const STATUS_STEP_MS: u64 = 5;
// How long kill_tree waits for a killed pid to vanish; the cancel tests pin their promptness to this same bound.
pub(crate) const WAIT_GONE_SECS: u64 = 2;
const WAIT_GONE_STEP_MS: u64 = 10;

extern "C" {
    fn pipe2(fds: *mut i32, flags: i32) -> i32;
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

// Sample /proc/<pid>/stat: "123 (bwrap) S 456 ..." so the ppid is the second field after the last ")".
fn ppid_of_stat(text: &str) -> Option<i32> {
    let after = text.rsplit_once(')')?.1;
    let mut fields = after.split_whitespace();
    fields.next()?;
    fields.next()?.parse::<i32>().ok()
}

fn stat_ppid(pid: i32) -> Option<i32> {
    let text = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    ppid_of_stat(&text)
}

// A forged child-pid must never be signalled, so a reported pid is killed only while its parent is this jail's own bwrap.
fn owned_by(pid: i32, bwrap: i32) -> bool {
    stat_ppid(pid) == Some(bwrap)
}

// SIGKILLs a reported sandbox pid only while its parent is still this jail's bwrap; anything else is refused.
pub(crate) fn kill_sandbox(out: &Arc<AtomicI32>, bwrap: i32) {
    let pid = out.load(Ordering::SeqCst);
    if pid > 0 && owned_by(pid, bwrap) {
        unsafe { kill(pid, SIGKILL) };
    }
}

fn status_reader(fd: OwnedFd, out: Arc<AtomicI32>) {
    use std::io::Read;
    let mut file = std::fs::File::from(fd);
    let mut buf = Vec::new();
    let mut tmp = [0u8; 512];
    // EOF with no pid means bwrap left without writing, so 0 ends the wait at once; every kill path already requires pid > 0.
    let mut saw_pid = false;
    loop {
        match file.read(&mut tmp) {
            Ok(0) => break,
            Ok(n) => {
                buf.extend_from_slice(&tmp[..n]);
                if let Some(pid) = parse_child_pid(&buf) {
                    saw_pid = true;
                    out.store(pid, Ordering::SeqCst);
                }
            }
            Err(_) => break,
        }
    }
    if !saw_pid {
        out.store(0, Ordering::SeqCst);
    }
}

// Sample argv: ["prlimit","bwrap","--json-status-fd","7",...] with STATUS_FD open.
pub fn spawn_jailed(full: &[String], setup: impl FnOnce(&mut std::process::Command)) -> std::io::Result<Jailed> {
    if full.is_empty() {
        return Err(std::io::Error::other("empty jail argv"));
    }
    let mut fds = [0, 0];
    if unsafe { pipe2(fds.as_mut_ptr(), O_CLOEXEC) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    let read_fd = unsafe { OwnedFd::from_raw_fd(fds[0]) };
    let write_fd = unsafe { OwnedFd::from_raw_fd(fds[1]) };
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
            if write_raw == status_fd {
                // dup2(fd, fd) leaves CLOEXEC set, so only this child clears it.
                if fcntl(status_fd, F_SETFD, 0) < 0 {
                    return Err(std::io::Error::last_os_error());
                }
            } else {
                // dup2 clears CLOEXEC on the new fd, so only bwrap's status fd stays open past exec.
                if dup2(write_raw, status_fd) < 0 {
                    return Err(std::io::Error::last_os_error());
                }
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
    // A reader that never starts leaves the child running, so it is killed here and the caller answers NotStarted.
    if std::thread::Builder::new()
        .name("flea-jail-status".to_string())
        .spawn(move || status_reader(read_fd, reader_pid))
        .is_err()
    {
        let mut jailed = Jailed { child, sandbox_pid: pid };
        kill_tree(&mut jailed);
        return Err(std::io::Error::other("the jail status reader could not start"));
    }
    Ok(Jailed { child, sandbox_pid: pid })
}

// SIGKILLs the sandbox init as well as bwrap, then waits; the init is killed while bwrap is alive, since after the reap no parent check can pass.
pub fn kill_tree(jailed: &mut Jailed) {
    let bwrap = jailed.child.id() as i32;
    // Ownership is proven before any kill: after the reap the kernel reparents the init, so a later check refuses every time.
    let first = wait_for_pid(&jailed.sandbox_pid);
    let mut killed = GONE;
    if first > 0 && owned_by(first, bwrap) {
        unsafe { kill(first, SIGKILL) };
        killed = first;
    }
    let pid = jailed.child.id() as i32;
    unsafe { kill(-pid, SIGKILL) };
    let _ = jailed.child.kill();
    let _ = jailed.child.wait();
    wait_gone(killed);
}

fn wait_for_pid(out: &Arc<AtomicI32>) -> i32 {
    for _ in 0..STATUS_WAIT_MS / STATUS_STEP_MS {
        let pid = out.load(Ordering::SeqCst);
        if pid != GONE {
            return pid;
        }
        std::thread::sleep(Duration::from_millis(STATUS_STEP_MS));
    }
    out.load(Ordering::SeqCst)
}

fn wait_gone(pid: i32) {
    if pid <= 0 {
        return;
    }
    for _ in 0..WAIT_GONE_SECS * 1000 / WAIT_GONE_STEP_MS {
        if unsafe { kill(pid, 0) } != 0 {
            return;
        }
        std::thread::sleep(Duration::from_millis(WAIT_GONE_STEP_MS));
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

    // Sample /proc/<pid>/stat rows: the comm may hold spaces and parens, so the ppid follows the last ")".
    #[test]
    fn the_stat_parser_reads_the_ppid_past_any_comm() {
        assert_eq!(ppid_of_stat("123 (bwrap) S 456 789"), Some(456));
        assert_eq!(ppid_of_stat("123 (my tool) S 456 789"), Some(456));
        assert_eq!(ppid_of_stat("123 (we)ird) S 456 789"), Some(456));
        assert_eq!(ppid_of_stat("no parens at all"), None);
        assert_eq!(ppid_of_stat("123 (bwrap)"), None);
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
            assert!(began.elapsed() < std::time::Duration::from_secs(WAIT_GONE_SECS), "a cancelled jail was waited out");
        }
        assert!(!proc_with_token(&token), "a jailed sleep outlived its cancel");
    }

    // The status-fd branch is the point: with the sandbox pid learned before the cancel, only killing that pid ends the jail promptly.
    #[test]
    fn a_learned_sandbox_pid_is_killed_not_waited_out() {
        if crate::backend::sandboxprobe::skipped() {
            return;
        }
        let token = format!("31.{}", std::process::id());
        let inner = vec!["/usr/bin/sleep".to_string(), token.clone()];
        let mut full = crate::backend::sandbox::wrap_readonly(&inner, std::path::Path::new("/usr/bin/sleep"));
        crate::backend::sandbox::add_status(&mut full, inner.len());
        let mut jailed = spawn_jailed(&full, |cmd| {
            cmd.stdin(std::process::Stdio::null());
            cmd.stdout(std::process::Stdio::null());
            cmd.stderr(std::process::Stdio::null());
        })
        .expect("jailed sleep did not start");
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while jailed.sandbox_pid.load(Ordering::SeqCst) <= 0 && std::time::Instant::now() < deadline {
            std::thread::yield_now();
        }
        let learned = jailed.sandbox_pid.load(Ordering::SeqCst);
        assert!(learned > 0, "the sandbox pid was never learned, so this pins nothing");
        let began = std::time::Instant::now();
        kill_tree(&mut jailed);
        assert!(began.elapsed() < std::time::Duration::from_secs(WAIT_GONE_SECS), "a cancel with a learned pid was waited out");
        assert!(!proc_with_token(&token), "the learned sandbox process outlived its cancel");
    }

    // A child spawned while a jail is alive must not see the jail's status pipe: the read end stays open here until the jail ends, so without CLOEXEC every later spawn inherits it.
    #[test]
    fn a_concurrent_spawn_does_not_inherit_the_status_pipe() {
        let before = child_fd_count();
        let mut jailed = spawn_jailed(&["/usr/bin/sleep".to_string(), "30".to_string()], |cmd| {
            cmd.stdin(std::process::Stdio::null());
            cmd.stdout(std::process::Stdio::null());
            cmd.stderr(std::process::Stdio::null());
        })
        .expect("plain sleep jail did not start");
        let during = child_fd_count();
        kill_tree(&mut jailed);
        assert_eq!(during, before, "a child spawned during a jail inherited the status pipe");
    }

    // A forged child-pid naming a process this jail did not start must never be signalled.
    #[test]
    fn a_reported_pid_owned_by_someone_else_is_never_killed() {
        let mut victim = std::process::Command::new("/usr/bin/sleep")
            .arg("30")
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .expect("victim sleep did not start");
        let victim_pid = victim.id() as i32;
        let mut jailed = spawn_jailed(&["/usr/bin/sleep".to_string(), "30".to_string()], |cmd| {
            cmd.stdin(std::process::Stdio::null());
            cmd.stdout(std::process::Stdio::null());
            cmd.stderr(std::process::Stdio::null());
        })
        .expect("holder jail did not start");
        jailed.sandbox_pid.store(victim_pid, Ordering::SeqCst);
        kill_tree(&mut jailed);
        let alive = victim.try_wait().expect("wait on victim").is_none();
        let _ = victim.kill();
        let _ = victim.wait();
        assert!(alive, "kill_tree signalled a pid its jail never owned");
    }

    // setsid puts the sleep outside the group like bwrap's --new-session, so only the learned-pid kill ends it.
    #[test]
    fn a_learned_pid_outside_the_group_is_killed_by_its_own_pid() {
        let token = format!("32.{}", std::process::id());
        let fd = crate::backend::sandbox::STATUS_FD;
        let script = format!("/usr/bin/setsid /usr/bin/sleep {token} & /usr/bin/sleep 0.05; printf '{{\"child-pid\": %d}}' $! >&{fd}; wait");
        let mut jailed = spawn_jailed(&["/bin/sh".to_string(), "-c".to_string(), script], |cmd| {
            cmd.stdin(std::process::Stdio::null());
            cmd.stdout(std::process::Stdio::null());
            cmd.stderr(std::process::Stdio::null());
        })
        .expect("shell jail did not start");
        // The sleep must exist before the kill, or the group kill lands pre-fork and the test passes vacuously.
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while !proc_with_token(&token) && std::time::Instant::now() < deadline {
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
        assert!(proc_with_token(&token), "the fixture never started its sleep");
        kill_tree(&mut jailed);
        assert!(!proc_with_token(&token), "the setsid sleep outlived a kill_tree that learned its pid");
    }

    // A jail whose argv never writes the status fd still returns within the bounded wait.
    #[test]
    fn a_jail_that_never_writes_the_status_fd_still_returns_promptly() {
        let mut jailed = spawn_jailed(&["/usr/bin/sleep".to_string(), "30".to_string()], |cmd| {
            cmd.stdin(std::process::Stdio::null());
            cmd.stdout(std::process::Stdio::null());
            cmd.stderr(std::process::Stdio::null());
        })
        .expect("plain sleep jail did not start");
        let began = std::time::Instant::now();
        kill_tree(&mut jailed);
        assert!(
            began.elapsed() < std::time::Duration::from_millis(STATUS_WAIT_MS) + std::time::Duration::from_secs(1),
            "a jail with no status writer hung past the bounded wait"
        );
    }

    // Sample /proc/self/fd listing: one numeric entry per open descriptor, so the count is the inheritance signal.
    fn child_fd_count() -> usize {
        let out = std::process::Command::new("/usr/bin/ls")
            .arg("/proc/self/fd")
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .output()
            .expect("ls /proc/self/fd did not run");
        assert!(out.status.success());
        String::from_utf8_lossy(&out.stdout).lines().count()
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
