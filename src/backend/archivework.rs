// The staging directory every delegated archive job writes into, the jail those jobs run in, and the
// two reads an extract is verified against. The jobs themselves are archiveops.rs.
use crate::backend::sandbox;
use crate::backend::archive::Formats;
use crate::backend::archivelist::parse_reader;
use crate::backend::opsreq::op_err;
use crate::error::{from_io, FleaError};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

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

pub fn is_empty_dir(dir: &Path) -> bool {
    std::fs::read_dir(dir).map(|mut e| e.next().is_none()).unwrap_or(true)
}

// How many members the index names that should have produced something in the destination, per
// Row::produces_destination_entry, or None when the index could not be read at all. None is the
// honest answer for a listing that failed, timed out or was truncated, because a count of zero from a
// read that never finished is indistinguishable from an archive holding nothing, and reading the
// first as the second is what restored the defect this check exists for.
pub fn archive_produced_count(formats: &Formats, archive: &Path) -> Option<usize> {
    let (inner, spec) = formats.list_argv(archive)?;
    if !sandbox::available() {
        return None;
    }
    let full = sandbox::wrap_readonly(&inner, archive);
    // Streamed, not .output(): buffering the whole index here would contradict the streaming
    // contract the parser exists for, and a 200k-entry archive is exactly the case that motivated it.
    let mut child = Command::new(&full[0])
        .args(&full[1..])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .ok()?;
    let listed = match child.stdout.take() {
        Some(out) => parse_reader(std::io::BufReader::new(out), &spec),
        None => {
            let _ = child.wait();
            return None;
        }
    };
    let status = child.wait().ok()?;
    if !status.success() || listed.failed {
        return None;
    }
    Some(listed.produced_entries)
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

    // Cancel kills and reaps; the pid-named duration keeps the /proc gate off other suites' sleeps.
    #[test]
    fn a_cancelled_child_is_killed_and_reaped_rather_than_left_running() {
        if crate::backend::sandboxprobe::skipped() { return; }
        let d = TestDir::new("archworkcancel");
        let work = Work::new(d.path(), "ext").expect("work");
        let cancel = std::sync::Arc::new(AtomicBool::new(false));
        let flag = std::sync::Arc::clone(&cancel);
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(200));
            flag.store(true, Ordering::Relaxed);
        });
        let seconds = format!("30.{}", std::process::id());
        let started = std::time::Instant::now();
        let e = run_boxed_cancellable("archive", vec!["/usr/bin/sleep".to_string(), seconds.clone()],
                                      d.path(), &work.dir, &cancel).unwrap_err();
        assert_eq!(e.msg, "cancelled");
        assert!(started.elapsed() < Duration::from_secs(10), "a cancelled child was waited out");
        assert!(work.dir.is_dir(), "the runner must not remove the caller's staging directory");
        std::thread::sleep(Duration::from_millis(200));
        let want = format!("/usr/bin/sleep\0{}\0", seconds);
        let alive = std::fs::read_dir("/proc").map(|p| p.flatten().any(|e| std::fs::read(e.path().join("cmdline")).map(|c| c == want.as_bytes()).unwrap_or(false))).unwrap_or(false);
        assert!(!alive, "the sandboxed child outlived its cancel");
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
