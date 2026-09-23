// What a tree copy created, recorded as it runs so undo of a failed copy removes
// exactly those paths and nothing else. The records live in an anonymous file beside
// the journal's own pattern (trashmanifest.rs), never in the in-memory journal entry.
use crate::backend::trashmanifest::{Manifest, Records};
use crate::error::FleaError;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt;
use std::path::{Component, Path, PathBuf};

// Twice the largest tree this product is benched against; past it the copy still
// runs, but undo falls back to the whole-tree check rather than recording more.
const MAX_ENTRIES: usize = 200_000;
// About 32 bytes of header plus short names times the entry cap, rounded up.
const MAX_BYTES: u64 = 32 * 1024 * 1024;
// dev(8) + ino(8) + kind(4) + len(8) + mtime sec(8) + mtime nsec(8).
const HEADER: usize = 44;

// Recorded while the copy runs, one append per created path, so a 100,000-file
// tree never sits in memory whole; dropped unread when the copy succeeds.
pub struct Writer {
    inner: Manifest,
    root: PathBuf,
    count: usize,
    overflow: bool,
}

// The journal step holds this instead of the records: an fd to the same anonymous
// file, so dropping the step closes the last holder and the manifest goes with it.
#[derive(Clone, Debug)]
pub struct Handle {
    records: Records,
    root: PathBuf,
    count: usize,
}

// PartialEq is journal identity (which copy this belongs to), never proof that the
// filesystem still holds those paths; the per-record checks at undo time are that.
impl PartialEq for Handle {
    fn eq(&self, other: &Self) -> bool {
        self.root == other.root && self.count == other.count
    }
}

pub struct Kept {
    pub path: PathBuf,
    pub reason: &'static str,
}

pub struct Report {
    pub total: usize,
    pub removed: usize,
    pub kept: Vec<Kept>,
}

// Fallback means the stream never verified a single record, so the caller runs
// today's whole-tree check; anything already verified deleted stays deleted.
pub enum Outcome {
    Done(Report),
    Fallback,
}

// A tree copy records its destination; anything else keeps today's single check.
pub fn writer_for(src: &Path, dst: &Path) -> Option<Writer> {
    let meta = src.symlink_metadata().ok()?;
    if meta.file_type().is_symlink() || !meta.is_dir() || !dst.is_absolute() {
        return None;
    }
    Writer::create(&dst.parent()?.to_path_buf(), dst).ok()
}

impl Writer {
    fn create(parent: &Path, root: &Path) -> Result<Self, String> {
        if !root.is_absolute() {
            return Err("a manifest root must be absolute".into());
        }
        Ok(Self { inner: Manifest::new(parent)?, root: root.to_path_buf(), count: 0, overflow: false })
    }

    // Recording never fails the copy: once the bound is hit every later path is
    // simply unrecorded and finish() answers None, which journals without a manifest.
    // The identity comes from the caller's own descriptor where one is at hand
    // (fstat, no lookup at all), so a rename between the create and this call cannot
    // substitute another file's identity for the one the copy made.
    pub fn record(&mut self, named: &Path, meta: &std::fs::Metadata) {
        if self.overflow || self.count >= MAX_ENTRIES || self.inner.len() >= MAX_BYTES {
            self.overflow = true;
            return;
        }
        let rel = match named.strip_prefix(&self.root) {
            Ok(rel) => rel,
            Err(_) => {
                self.overflow = true;
                return;
            }
        };
        if self.inner.append(&encode(meta, rel.as_os_str().as_bytes())).is_err() {
            self.overflow = true;
            return;
        }
        self.count += 1;
    }

    // Symlinks and nodes have no descriptor to fstat; the at-path pins every parent
    // directory, leaving only the final name to resolve, the way copyfile.rs holds them.
    pub fn record_stat(&mut self, at: &Path, named: &Path) {
        match at.symlink_metadata() {
            Ok(meta) => self.record(named, &meta),
            Err(_) => self.overflow = true,
        }
    }

    pub fn overflow(&mut self) {
        self.overflow = true;
    }

    pub fn finish(self) -> Option<Handle> {
        if self.overflow || self.count == 0 {
            return None;
        }
        Some(Handle { records: self.inner.records(), root: self.root, count: self.count })
    }
}

fn encode(meta: &std::fs::Metadata, rel: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(HEADER + rel.len());
    out.extend_from_slice(&meta.dev().to_le_bytes());
    out.extend_from_slice(&meta.ino().to_le_bytes());
    out.extend_from_slice(&(meta.mode() & 0o170000).to_le_bytes());
    out.extend_from_slice(&meta.len().to_le_bytes());
    out.extend_from_slice(&meta.mtime().to_le_bytes());
    out.extend_from_slice(&meta.mtime_nsec().to_le_bytes());
    out.extend_from_slice(&rel);
    out
}

struct Decoded {
    dev: u64,
    ino: u64,
    kind: u32,
    len: u64,
    mtime: (i64, i64),
    rel: PathBuf,
}

fn decode(bytes: &[u8]) -> Option<Decoded> {
    if bytes.len() < HEADER {
        return None;
    }
    let num = |range: std::ops::Range<usize>| -> Option<[u8; 8]> { bytes.get(range)?.try_into().ok() };
    let rel = std::ffi::OsStr::from_bytes(bytes.get(HEADER..)?);
    Some(Decoded {
        dev: u64::from_le_bytes(num(0..8)?),
        ino: u64::from_le_bytes(num(8..16)?),
        kind: u32::from_le_bytes(bytes.get(16..20)?.try_into().ok()?),
        len: u64::from_le_bytes(num(20..28)?),
        mtime: (i64::from_le_bytes(num(28..36)?), i64::from_le_bytes(num(36..44)?)),
        rel: PathBuf::from(rel),
    })
}

// A manifest path is always under its root; anything else is kept, never followed.
fn contained(root: &Path, rel: &Path) -> Option<PathBuf> {
    if rel.is_absolute() || rel.components().any(|part| part == Component::ParentDir) {
        return None;
    }
    let abs = root.join(rel);
    if abs.starts_with(root) {
        Some(abs)
    } else {
        None
    }
}

// Reverse creation order is deepest first, because a copy makes a directory before
// anything inside it; Records::previous streams that way without holding the manifest whole.
pub fn remove_owned(handle: &Handle) -> Outcome {
    let mut report = Report { total: handle.count, removed: 0, kept: Vec::new() };
    let mut offset = handle.records.end();
    let mut processed = 0usize;
    loop {
        let bytes = match handle.records.previous(&mut offset) {
            Ok(Some(bytes)) => bytes,
            Ok(None) => break,
            Err(_) => return unfinished(handle, report, processed),
        };
        processed += 1;
        let Some(record) = decode(&bytes) else { return unfinished(handle, report, processed - 1) };
        remove_one(handle, &record, &mut report);
    }
    Outcome::Done(report)
}

// A damaged stream after verified deletions must never widen into a whole-tree
// removal; the rest stays on disk and the report says the manifest unreadable.
fn unfinished(handle: &Handle, mut report: Report, processed: usize) -> Outcome {
    if processed == 0 {
        return Outcome::Fallback;
    }
    report.kept.push(Kept { path: handle.root.clone(), reason: "the copy manifest is unreadable" });
    Outcome::Done(report)
}

fn remove_one(handle: &Handle, record: &Decoded, report: &mut Report) {
    let Some(abs) = contained(&handle.root, &record.rel) else {
        report.kept.push(Kept { path: handle.root.join(&record.rel), reason: "was replaced after the copy" });
        return;
    };
    let meta = match abs.symlink_metadata() {
        Ok(meta) => meta,
        // Gone already is the state undo wanted; it is neither removed nor kept.
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return,
        Err(_) => {
            report.kept.push(Kept { path: abs, reason: "could not be removed" });
            return;
        }
    };
    if meta.dev() != record.dev || meta.ino() != record.ino || meta.mode() & 0o170000 != record.kind {
        report.kept.push(Kept { path: abs, reason: "was replaced after the copy" });
        return;
    }
    if meta.is_file() && (meta.len() != record.len || (meta.mtime(), meta.mtime_nsec()) != record.mtime) {
        report.kept.push(Kept { path: abs, reason: "was modified after the copy" });
        return;
    }
    if meta.is_dir() && !meta.file_type().is_symlink() {
        match std::fs::remove_dir(&abs) {
            Ok(()) => report.removed += 1,
            Err(e) if e.kind() == std::io::ErrorKind::DirectoryNotEmpty => {
                report.kept.push(Kept { path: abs, reason: "is not empty" })
            }
            Err(e) => report.kept.push(Kept {
                path: abs,
                reason: if e.kind() == std::io::ErrorKind::NotFound { return } else { "could not be removed" },
            }),
        }
        return;
    }
    // Unlink, never through the link: a symlink the copy made goes without touching its target.
    match std::fs::remove_file(&abs) {
        Ok(()) => report.removed += 1,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(_) => report.kept.push(Kept { path: abs, reason: "could not be removed" }),
    }
}

// One line for the existing undo reply shape: how many went and what each kept one is.
pub fn summarize(report: &Report) -> String {
    let mut msg = format!("undo removed {} of {} copied items", report.removed, report.total);
    if report.kept.is_empty() {
        return msg;
    }
    msg.push_str(&format!("; {} kept: ", report.kept.len()));
    let mut parts: Vec<String> = report.kept.iter().take(3).map(|kept| {
        format!("{} {}", kept.path.to_string_lossy(), kept.reason)
    }).collect();
    if report.kept.len() > 3 {
        parts.push(format!("and {} more", report.kept.len() - 3));
    }
    msg.push_str(&parts.join("; "));
    msg
}

pub fn undo_err(to: &Path, msg: String) -> FleaError {
    FleaError { where_: "undo".into(), path: to.to_string_lossy().into(), msg }
}

#[cfg(test)]
#[path = "copymanifest_tests.rs"]
mod tests;
