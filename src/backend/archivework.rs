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
use std::process::{Command, ExitStatus};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::time::{Duration, Instant};

// A private directory beside the destination, so the rename that follows never crosses a filesystem.
pub(crate) const WORK_PREFIX: &str = ".flea-work-";
// A cancel is observed within this; a killed child is reaped on the next round.
const CANCEL_STEP: Duration = Duration::from_millis(50);
// How long a cancel waits for the jail's last writer to reach EOF before it answers.
const CANCEL_DRAIN_SECS: u64 = 10;
// The EOF wait polls at this step, so a fast EOF answers promptly rather than at the bound.
const CANCEL_DRAIN_STEP: Duration = Duration::from_millis(10);

pub struct Work {
    pub dir: PathBuf,
    kept: bool,
}

// Concurrent jobs share a destination, so a counter names each work directory rather than the pid alone.
static WORK_SEQ: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

// A taken name is a killed run's leftover, so the search for a free one is bounded.
const WORK_ATTEMPTS: usize = 64;

impl Work {
    // create_dir alone: a taken name is a collision and must never merge with a live directory.
    pub fn new(beside: &Path, tag: &str) -> Result<Work, FleaError> {
        let mut last = String::new();
        for _ in 0..WORK_ATTEMPTS {
            let seq = WORK_SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            let dir = beside.join(format!("{}{}-{}-{}", WORK_PREFIX, tag, std::process::id(), seq));
            match std::fs::create_dir(&dir) {
                Ok(()) => return Ok(Work { dir, kept: false }),
                // A taken name may be a live sibling's, so the only safe answer is a different name.
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                    last = dir.to_string_lossy().to_string();
                }
                Err(e) => return Err(from_io("archive", &dir.to_string_lossy(), &e)),
            }
        }
        Err(op_err("archive", &last, "no free work directory beside the destination"))
    }

    // A cancel past the drain bound leaves the folder for the operator: the tool may still write.
    pub fn keep(&mut self) {
        self.kept = true;
    }
}

impl Drop for Work {
    fn drop(&mut self) {
        if self.kept {
            return;
        }        // Only ever a directory this process made, under a name only this module writes.
        if self.dir.file_name().is_some_and(|n| n.to_string_lossy().starts_with(WORK_PREFIX)) {
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }
}

// The signal a job died from; anything else keeps its number rather than a guessed name.
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

// bwrap renders a tool the kernel killed as exit 128+n, so this offset recovers the signal.
const BWRAP_SIGNAL_BASE: i32 = 128;

// Issue #211: stderr's last non-blank line diagnoses a bad archive; otherwise the status names the signal.
fn failure_message(what: &str, status: &ExitStatus, stderr: &str) -> String {
    // A blank line is not a diagnosis.
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
        // 128+n is bwrap's rendering of a signal; an unknown one stays an exit status.
        Some(code) if signal_name(code - BWRAP_SIGNAL_BASE).is_some() => killed(code - BWRAP_SIGNAL_BASE),
        Some(code) => format!("the {} tool exited with status {}", what, code),
        // Unreachable in practice; this function always answers a sentence rather than panicking.
        None => format!("the {} tool failed", what),
    }
}

// Success is read off the filesystem; convert stays on this capped runner, the archive jobs run on the uncapped cancellable one below.
pub fn run_boxed(what: &str, inner: Vec<String>, read_only: &Path, writable: &Path) -> Result<(), FleaError> {
    run_boxed_inner(what, inner, read_only, writable, Some(sandbox::CPU_SECONDS))
}

// Test seam: lowers the CPU cap so a test burns seconds, not 30 s; release always uses CPU_SECONDS.
#[cfg(test)]
fn run_boxed_with_cpu(what: &str, inner: Vec<String>, read_only: &Path, writable: &Path,
                       cpu_seconds: u32) -> Result<(), FleaError> {
    run_boxed_inner(what, inner, read_only, writable, Some(cpu_seconds))
}

fn run_boxed_inner(what: &str, inner: Vec<String>, read_only: &Path, writable: &Path,
                    cpu_seconds: Option<u32>) -> Result<(), FleaError> {
    // Fail closed: without bwrap or prlimit the job is refused, never run unsandboxed.
    if !sandbox::available() {
        let tool = inner.first().map_or("", |s| s.as_str());
        return Err(op_err(what, tool, "the sandbox is unavailable: bwrap or prlimit is not on PATH"));
    }
    let full = sandbox::wrap_with(&inner, read_only, writable, cpu_seconds);
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


// A writer past the kill can still hold stderr open; true means its EOF arrived in bound.
fn drain_reader(reader: std::thread::JoinHandle<String>) -> bool {
    let eof = Instant::now() + Duration::from_secs(CANCEL_DRAIN_SECS);
    while !reader.is_finished() && Instant::now() < eof {
        std::thread::sleep(CANCEL_DRAIN_STEP);
    }
    if !reader.is_finished() {
        return false;
    }
    reader.join().ok();
    true
}

// run_boxed, watched for a cancel: kill and reap here, so nothing is renamed and stderr is drained.
pub fn run_boxed_cancellable(what: &str, inner: Vec<String>, read_only: &Path, work: &mut Work,
                             cancel: &AtomicBool) -> Result<(), FleaError> {
    run_boxed_cancellable_inner(what, inner, read_only, work, cancel, None)
}

fn run_boxed_cancellable_inner(what: &str, inner: Vec<String>, read_only: &Path, work: &mut Work,
                               cancel: &AtomicBool, started: Option<&AtomicU32>) -> Result<(), FleaError> {
    if !sandbox::available() {
        let tool = inner.first().map_or("", |s| s.as_str());
        return Err(op_err(what, tool, "the sandbox is unavailable: bwrap or prlimit is not on PATH"));
    }
    let mut full = sandbox::wrap_archive(&inner, read_only, &work.dir);
    sandbox::add_status(&mut full, inner.len());
    let mut jailed = crate::backend::jail::spawn_jailed(&full, |cmd| {
        cmd.stdin(std::process::Stdio::null());
        cmd.stdout(std::process::Stdio::null());
        cmd.stderr(std::process::Stdio::piped());
    })
    .map_err(|e| from_io(what, &full[0], &e))?;
    if let Some(pid) = started {
        pid.store(jailed.child.id(), Ordering::SeqCst);
    }
    let stderr = jailed.child.stderr.take();
    let reader = std::thread::spawn(move || {
        let mut text = String::new();
        if let Some(mut pipe) = stderr {
            pipe.read_to_string(&mut text).ok();
        }
        text
    });
    loop {
        if cancel.load(Ordering::Relaxed) {
            crate::backend::jail::kill_tree(&mut jailed);
            if drain_reader(reader) {
                return Err(op_err(what, "", "cancelled"));
            }
            let name = work.dir.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            work.keep();
            return Err(op_err(what, "", &format!("cancelled; the archive tool did not exit, so its work folder {name} was left in place")));
        }
        match jailed.child.try_wait() {
            Ok(Some(status)) => {
                let text = reader.join().unwrap_or_default();
                if status.success() {
                    return Ok(());
                }
                return Err(op_err(what, "", &failure_message(what, &status, &text)));
            }
            Ok(None) => std::thread::sleep(CANCEL_STEP),
            Err(e) => {
                crate::backend::jail::kill_tree(&mut jailed);
                reader.join().ok();
                return Err(from_io(what, &full[0], &e));
            }
        }
    }
}

#[cfg(test)]
fn run_boxed_cancellable_observed(what: &str, inner: Vec<String>, read_only: &Path, work: &mut Work,
                                  cancel: &AtomicBool, started: &AtomicU32) -> Result<(), FleaError> {
    run_boxed_cancellable_inner(what, inner, read_only, work, cancel, Some(started))
}

pub fn is_empty_dir(dir: &Path) -> bool {
    std::fs::read_dir(dir).map(|mut e| e.next().is_none()).unwrap_or(true)
}

// How many members the index names that should appear in the destination, or None for an index that could not be read: a zero from an unfinished read is not an empty result.
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
    let mut full = sandbox::wrap_readonly(&inner, read_only);
    sandbox::add_status(&mut full, inner.len());
    // Streamed, not .output(): a 200k-entry index must never be buffered whole.
    let mut jailed = match crate::backend::jail::spawn_jailed(&full, |cmd| {
        cmd.stdin(std::process::Stdio::null());
        cmd.stdout(std::process::Stdio::piped());
        cmd.stderr(std::process::Stdio::null());
    }) {
        Ok(jailed) => jailed,
        Err(_) => return Ok(None),
    };
    if let Some(pid) = started {
        pid.store(jailed.child.id(), Ordering::SeqCst);
    }
    let deadline = Instant::now() + Duration::from_millis(crate::backend::archivelist::ARCHIVE_READ_MS);
    let output = match jailed.child.stdout.take() {
        Some(output) => output,
        None => {
            crate::backend::jail::kill_tree(&mut jailed);
            return Ok(None);
        }
    };
    let parser = std::thread::spawn(move || {
        parse_reader(std::io::BufReader::new(ReadyReader { reader: output, ready }), &spec)
    });
    loop {
        if cancelled(cancel) {
            // Kills the sandbox init too, and never waits for the parser drain.
            crate::backend::jail::kill_tree(&mut jailed);
            return Err(op_err("archive", "", "cancelled"));
        }
        match jailed.child.try_wait() {
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
                crate::backend::jail::kill_tree(&mut jailed);
                return Ok(None);
            }
            Ok(None) => std::thread::sleep(CANCEL_STEP),
            Err(_) => {
                crate::backend::jail::kill_tree(&mut jailed);
                return Ok(None);
            }
        }
    }
}

fn cancelled(cancel: &AtomicBool) -> bool {
    cancel.load(Ordering::Relaxed)
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
