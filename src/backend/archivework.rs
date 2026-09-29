// The staging directory every delegated archive job writes into, the jail those jobs run in, and the
// two reads an extract is verified against. The jobs themselves are archiveops.rs.
use crate::backend::sandbox;
use crate::backend::archive::Formats;
use crate::backend::archivespec::ListSpec;
use crate::backend::archivelist::parse_reader;
use crate::backend::opsreq::op_err;
use crate::error::{from_io, FleaError};
use std::io::{self, Read};
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus};
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

// The signal a job died from, named for the ones these tools can die from; anything else keeps its
// number alone, because a message that guesses a name is worse than one that states a number.
fn signal_name(signal: i32) -> Option<&'static str> {
    match signal {
        6 => Some("SIGABRT"),
        9 => Some("SIGKILL"),
        11 => Some("SIGSEGV"),
        15 => Some("SIGTERM"),
        24 => Some("SIGXCPU"),
        _ => None,
    }
}

// The tool's own last line is the best diagnosis there is, and it is what an operator sees for a bad
// archive. When there is none, the exit status is the only evidence there is, and issue #211 is what the
// old one-sentence fallback cost: a 55 GiB Zip64 whose legitimate unpack a 30 s RLIMIT_CPU killed arrived
// as "The archive tool failed.", which names a bad archive for a job the kernel killed. Two spellings of
// one death are read here, because bwrap maps an application the kernel killed to exit 128+n and keeps a
// real signal for its own death (measured on the box; see AGENTS.md "Thumbnail pool"), so a launcher
// SIGKILLed by its parent and an extractor SIGKILLed inside the jail both report the signal.
fn failure_message(what: &str, status: &ExitStatus, stderr: &str) -> String {
    // A blank line is not a diagnosis, which the old last-line read of stderr took it for.
    if let Some(line) = stderr.lines().rev().find(|line| !line.trim().is_empty()) {
        return line.trim().to_string();
    }
    let killed = |signal: i32| match signal_name(signal) {
        Some(name) => format!("the {} tool was killed by signal {} ({})", what, name, signal),
        None => format!("the {} tool was killed by signal {}", what, signal),
    };
    if let Some(signal) = status.signal() {
        return killed(signal);
    }
    match status.code() {
        // 128+n is bwrap's rendering of a signal, so the number is read back into the sentence; an
        // unknown 128+n is left as an exit status rather than claimed as a kill.
        Some(code) if signal_name(code - 128).is_some() => killed(code - 128),
        Some(code) => format!("the {} tool exited with status {}", what, code),
        // A status is either a code or a signal, so this arm is unreachable; it answers a sentence
        // rather than panicking, because producing one is this function's whole job.
        None => format!("the {} tool failed", what),
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
    let full = sandbox::wrap_archive(&inner, read_only, writable);
    let out = Command::new(&full[0])
        .args(&full[1..])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .output()
        .map_err(|e| from_io(what, &full[0], &e))?;
    if out.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&out.stderr);
    Err(op_err(what, "", &failure_message(what, &out.status, &stderr)))
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
    let full = sandbox::wrap_archive(&inner, read_only, writable);
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
                return Err(op_err(what, "", &failure_message(what, &status, &text)));
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
#[path = "archivework_tests.rs"]
mod tests;
