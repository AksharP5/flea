// The staging directory every delegated archive job writes into, the jail those jobs run in, and the
// two reads an extract is verified against. The jobs themselves are archiveops.rs.
use crate::backend::sandbox;
use crate::backend::archive::Formats;
use crate::backend::archivespec::ListSpec;
use crate::backend::archivelist::parse_reader;
use crate::backend::opsreq::op_err;
use crate::error::{from_io, FleaError};
use std::io::{self, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::time::{Duration, Instant};

// A private directory beside the destination, so the rename that follows never crosses a filesystem.
pub(crate) const WORK_PREFIX: &str = ".flea-work-";
// A cancel is observed within this; a killed child is reaped on the next round.
const CANCEL_STEP: Duration = Duration::from_millis(50);

pub struct Work {
    pub dir: PathBuf,
}

// Archive and convert run concurrently by design, so the pid alone does not name a job: two of them
// beside the same destination would claim one path, and the second's cleanup would destroy the
// first's in-flight output. The counter is what makes a name belong to one job.
static WORK_SEQ: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

// A name already taken means a leftover from a killed run, and stepping past it is bounded so a
// directory full of them cannot spin.
const WORK_ATTEMPTS: usize = 64;

impl Work {
    // create_dir, not create_dir_all: a name already taken is a collision and must never merge, and
    // create_new semantics are also what stops this from adopting somebody else's live directory.
    pub fn new(beside: &Path, tag: &str) -> Result<Work, FleaError> {
        let mut last = String::new();
        for _ in 0..WORK_ATTEMPTS {
            let seq = WORK_SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            let dir = beside.join(format!("{}{}-{}-{}", WORK_PREFIX, tag, std::process::id(), seq));
            match std::fs::create_dir(&dir) {
                Ok(()) => return Ok(Work { dir }),
                // Nothing is ever removed here: a name in use may be a live sibling's, and the only
                // safe answer to a taken name is a different name.
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                    last = dir.to_string_lossy().to_string();
                }
                Err(e) => return Err(from_io("archive", &dir.to_string_lossy(), &e)),
            }
        }
        Err(op_err("archive", &last, "no free work directory beside the destination"))
    }
}

impl Drop for Work {
    fn drop(&mut self) {
        // Only ever a directory this process made, under a name only this module writes.
        if self.dir.file_name().is_some_and(|n| n.to_string_lossy().starts_with(WORK_PREFIX)) {
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }
}

// The tools print their own diagnosis on stderr and do not always exit non-zero, so success is read
// off the filesystem: the file the job was told to produce either exists afterwards or it does not.
// what names the operation this jail is running, because the same jail runs the archive tools and
// the image converter: reporting every one of them as "archive" told an operator converting a PNG
// that the archive tool had failed.
pub fn run_boxed(what: &str, inner: Vec<String>, read_only: &Path, writable: &Path) -> Result<(), FleaError> {
    // Fail closed: the jail is the only containment for these tools, so a missing bwrap or prlimit
    // refuses the job rather than running it unsandboxed, the same rule thumbs.rs already follows.
    if !sandbox::available() {
        let tool = inner.first().map_or("", |s| s.as_str());
        return Err(op_err(what, tool, "the sandbox is unavailable: bwrap or prlimit is not on PATH"));
    }
    let full = sandbox::wrap(&inner, read_only, writable);
    let out = Command::new(&full[0])
        .args(&full[1..])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .output()
        .map_err(|e| from_io(what, &full[0], &e))?;
    if out.status.success() {
        return Ok(());
    }
    let text = String::from_utf8_lossy(&out.stderr);
    let fallback = format!("the {} tool failed", what);
    Err(op_err(what, "", text.lines().last().unwrap_or(&fallback)))
}


// run_boxed, watched for a cancel: kill and reap here, so nothing is renamed and stderr is drained.
pub fn run_boxed_cancellable(what: &str, inner: Vec<String>, read_only: &Path, writable: &Path,
                             cancel: &AtomicBool) -> Result<(), FleaError> {
    run_boxed_cancellable_inner(what, inner, read_only, writable, cancel, None)
}

fn run_boxed_cancellable_inner(what: &str, inner: Vec<String>, read_only: &Path, writable: &Path,
                               cancel: &AtomicBool, started: Option<&AtomicU32>) -> Result<(), FleaError> {
    if !sandbox::available() {
        let tool = inner.first().map_or("", |s| s.as_str());
        return Err(op_err(what, tool, "the sandbox is unavailable: bwrap or prlimit is not on PATH"));
    }
    let full = sandbox::wrap(&inner, read_only, writable);
    let mut child = Command::new(&full[0])
        .args(&full[1..])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| from_io(what, &full[0], &e))?;
    if let Some(pid) = started {
        pid.store(child.id(), Ordering::SeqCst);
    }
    let stderr = child.stderr.take();
    let reader = std::thread::spawn(move || {
        let mut text = String::new();
        if let Some(mut pipe) = stderr {
            pipe.read_to_string(&mut text).ok();
        }
        text
    });
    loop {
        if cancel.load(Ordering::Relaxed) {
            // --die-with-parent takes the decoder; the wait here is what reaps the launcher.
            child.kill().ok();
            child.wait().ok();
            reader.join().ok();
            return Err(op_err(what, "", "cancelled"));
        }
        match child.try_wait() {
            Ok(Some(status)) => {
                let text = reader.join().unwrap_or_default();
                if status.success() {
                    return Ok(());
                }
                let fallback = format!("the {} tool failed", what);
                return Err(op_err(what, "", text.lines().last().unwrap_or(&fallback)));
            }
            Ok(None) => std::thread::sleep(CANCEL_STEP),
            Err(e) => {
                child.kill().ok();
                child.wait().ok();
                reader.join().ok();
                return Err(from_io(what, &full[0], &e));
            }
        }
    }
}

#[cfg(test)]
fn run_boxed_cancellable_observed(what: &str, inner: Vec<String>, read_only: &Path, writable: &Path,
                                  cancel: &AtomicBool, started: &AtomicU32) -> Result<(), FleaError> {
    run_boxed_cancellable_inner(what, inner, read_only, writable, cancel, Some(started))
}

pub fn is_empty_dir(dir: &Path) -> bool {
    std::fs::read_dir(dir).map(|mut e| e.next().is_none()).unwrap_or(true)
}

// How many members the index names that should have produced something in the destination, per
// Row::produces_destination_entry, or None when the index could not be read at all. None is the
// honest answer for a listing that failed, timed out or was truncated, because a count of zero from a
// read that never finished is indistinguishable from an archive holding nothing, and reading the
// first as the second is what restored the defect this check exists for.
#[cfg(test)]
pub fn archive_produced_count(formats: &Formats, archive: &Path) -> Option<usize> {
    let cancel = AtomicBool::new(false);
    let (inner, spec) = formats.list_argv(archive)?;
    archive_produced_count_inner(inner, spec, archive, &cancel, None, None).ok().flatten()
}

// The extract owns this token too: an empty staging directory is the one branch that reads the archive again.
pub fn archive_produced_count_cancellable(formats: &Formats, archive: &Path,
                                          cancel: &AtomicBool) -> Result<Option<usize>, FleaError> {
    let (inner, spec) = match formats.list_argv(archive) {
        Some(value) => value,
        None => return Ok(None),
    };
    archive_produced_count_inner(inner, spec, archive, cancel, None, None)
}

fn archive_produced_count_inner(inner: Vec<String>, spec: ListSpec, read_only: &Path,
                                cancel: &AtomicBool, started: Option<&AtomicU32>,
                                ready: Option<Arc<AtomicBool>>) -> Result<Option<usize>, FleaError> {
    if !sandbox::available() {
        return Ok(None);
    }
    let full = sandbox::wrap_readonly(&inner, read_only);
    // Streamed, not .output(): buffering the whole index here would contradict the streaming
    // contract the parser exists for, and a 200k-entry archive is exactly the case that motivated it.
    let mut child = match Command::new(&full[0])
        .args(&full[1..])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return Ok(None),
    };
    if let Some(pid) = started {
        pid.store(child.id(), Ordering::SeqCst);
    }
    let deadline = Instant::now() + Duration::from_millis(crate::backend::archivelist::ARCHIVE_READ_MS);
    let output = match child.stdout.take() {
        Some(output) => output,
        None => {
            kill_and_reap(&mut child);
            return Ok(None);
        }
    };
    let parser = std::thread::spawn(move || {
        parse_reader(std::io::BufReader::new(ReadyReader { reader: output, ready }), &spec)
    });
    loop {
        if cancelled(cancel) {
            kill_and_reap(&mut child);
            let _ = parser.join();
            return Err(op_err("archive", "", "cancelled"));
        }
        match child.try_wait() {
            Ok(Some(status)) => {
                let listed = match parser.join() {
                    Ok(listed) => listed,
                    Err(_) => return Ok(None),
                };
                if cancelled(cancel) {
                    return Err(op_err("archive", "", "cancelled"));
                }
                if !status.success() || listed.failed {
                    return Ok(None);
                }
                return Ok(Some(listed.produced_entries));
            }
            Ok(None) if Instant::now() >= deadline => {
                kill_and_reap(&mut child);
                let _ = parser.join();
                return Ok(None);
            }
            Ok(None) => std::thread::sleep(CANCEL_STEP),
            Err(_) => {
                kill_and_reap(&mut child);
                let _ = parser.join();
                return Ok(None);
            }
        }
    }
}

fn cancelled(cancel: &AtomicBool) -> bool {
    cancel.load(Ordering::Relaxed)
}

fn kill_and_reap(child: &mut Child) {
    child.kill().ok();
    child.wait().ok();
}

struct ReadyReader<R> {
    reader: R,
    ready: Option<Arc<AtomicBool>>,
}

impl<R: Read> Read for ReadyReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let read = self.reader.read(buf);
        if read.as_ref().is_ok_and(|count| *count > 0) {
            if let Some(flag) = &self.ready {
                flag.store(true, Ordering::SeqCst);
            }
        }
        read
    }
}

#[cfg(test)]
fn archive_produced_count_with_inner(inner: Vec<String>, spec: ListSpec, read_only: &Path,
                                     cancel: &AtomicBool, started: &AtomicU32,
                                     ready: &Arc<AtomicBool>) -> Result<Option<usize>, FleaError> {
    archive_produced_count_inner(inner, spec, read_only, cancel, Some(started),
                                 Some(Arc::clone(ready)))
}


#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;

    #[test]
    fn a_work_directory_is_made_beside_the_destination_and_goes_with_its_own_drop() {
        let d = TestDir::new("archwork");
        let kept;
        {
            let w = Work::new(d.path(), "arc").expect("work");
            kept = w.dir.clone();
            assert!(kept.is_dir());
            assert!(kept.file_name().unwrap().to_string_lossy().starts_with(WORK_PREFIX));
            // Beside the destination, so the rename that follows never crosses a filesystem.
            assert_eq!(kept.parent().unwrap(), d.path());
        }
        assert!(!kept.exists(), "the work directory goes with the job that made it");
    }

    // Cancel kills and reaps; the exact spawned pid keeps the /proc gate off other suites' processes.
    #[test]
    fn a_cancelled_child_is_killed_and_reaped_rather_than_left_running() {
        if crate::backend::sandboxprobe::skipped() { return; }
        let d = TestDir::new("archworkcancel");
        let work = Work::new(d.path(), "ext").expect("work");
        let cancel = std::sync::Arc::new(AtomicBool::new(false));
        let started_pid = std::sync::Arc::new(AtomicU32::new(0));
        let flag = std::sync::Arc::clone(&cancel);
        let child_pid = std::sync::Arc::clone(&started_pid);
        let notifier = std::thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(5);
            while child_pid.load(Ordering::SeqCst) == 0 && Instant::now() < deadline {
                std::thread::yield_now();
            }
            flag.store(true, Ordering::Relaxed);
        });
        let seconds = format!("30.{}", std::process::id());
        let began = std::time::Instant::now();
        let e = run_boxed_cancellable_observed("archive", vec!["/usr/bin/sleep".to_string(), seconds],
                                               d.path(), &work.dir, &cancel, &started_pid).unwrap_err();
        notifier.join().expect("the cancellation notifier finished");
        assert_eq!(e.msg, "cancelled");
        assert!(began.elapsed() < Duration::from_secs(10), "a cancelled child was waited out");
        assert!(work.dir.is_dir(), "the runner must not remove the caller's staging directory");
        let pid = started_pid.load(Ordering::SeqCst);
        assert_ne!(pid, 0, "the cancellation fixture never observed its child pid");
        let proc_entry = PathBuf::from(format!("/proc/{pid}"));
        assert!(!proc_entry.exists(), "the owned child was not reaped");
    }

    // The parser must cancel while a real jailed child holds stdout open after one bounded line.
    #[test]
    fn a_cancelled_index_reader_kills_and_reaps_a_child_blocked_on_stdout() {
        if crate::backend::sandboxprobe::skipped() { return; }
        let d = TestDir::new("archworkindexcancel");
        let cancel = std::sync::Arc::new(AtomicBool::new(false));
        let started = std::sync::Arc::new(AtomicU32::new(0));
        let ready = std::sync::Arc::new(AtomicBool::new(false));
        let flag = std::sync::Arc::clone(&cancel);
        let parsed = std::sync::Arc::clone(&ready);
        let notifier = std::thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(5);
            while !parsed.load(Ordering::SeqCst) && Instant::now() < deadline {
                std::thread::yield_now();
            }
            flag.store(true, Ordering::Relaxed);
        });
        let fixture = "printf '%s\\n' '-rw-r--r-- 0 gm gm 1 Jan 1 00:00 a.txt'; exec /usr/bin/sleep 600";
        let result = archive_produced_count_with_inner(
            vec!["/usr/bin/sh".to_string(), "-c".to_string(), fixture.to_string()],
            crate::backend::archivespec::tar_spec(), d.path(), &cancel, &started, &ready,
        );
        notifier.join().expect("the readiness notifier finished");
        let error = result.unwrap_err();
        assert_eq!(error.msg, "cancelled");
        assert!(ready.load(Ordering::SeqCst), "the fixture never delivered its first line");
        let pid = started.load(Ordering::SeqCst);
        assert_ne!(pid, 0, "the verification fixture never exposed its child pid");
        let proc_entry = PathBuf::from(format!("/proc/{pid}"));
        assert!(!proc_entry.exists(), "the blocked verification child was not reaped");
    }

    #[test]
    fn two_work_directories_beside_the_same_destination_never_share_a_path() {
        let d = TestDir::new("archwork2");
        let first = Work::new(d.path(), "ext").expect("first");
        let second = Work::new(d.path(), "ext").expect("second");
        assert_ne!(first.dir, second.dir, "a second job must not claim the first job's directory");
        assert!(first.dir.is_dir(), "and must not have destroyed it");
        assert!(second.dir.is_dir());
        // In flight, so a live sibling's contents have to survive the other one being created.
        std::fs::write(first.dir.join("in-flight"), b"payload").expect("write");
        let third = Work::new(d.path(), "ext").expect("third");
        assert!(first.dir.join("in-flight").is_file(), "a third job must not destroy either");
        assert_ne!(third.dir, first.dir);
        assert_ne!(third.dir, second.dir);
    }
}
