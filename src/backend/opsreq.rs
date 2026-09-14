// The operations request layer: the response lines, and the one thread an operation runs on.
use crate::backend::copyfile::{copy_any, move_any, Progress};
use crate::backend::ops;
use crate::backend::trash;
use crate::backend::undo::{self, Entry, ItemIdentity, Step};
use crate::error::{from_io, io_message, FleaError};
use crate::json::escape;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::time::{Duration, Instant};

// One progress line per item at most this often, so a fast copy of a small file may emit none at all.
pub(crate) const PROGRESS_EVERY: Duration = Duration::from_millis(150);

// What an operation thread sends back, joined onto the same receiver every other event already arrives on.
pub enum OpMsg {
    // scanned is the batch's own total, 0 until the sweep beside the copy settles on one.
    Progress { id: usize, index: usize, name: String, bytes: u64, total: u64, scanned: u64 },
    Item { id: usize, index: usize, name: String, ok: bool, err: String },
    TransferDone { id: usize, ok: usize, failed: usize, skipped: usize, cancelled: bool, entry: Entry,
                   retry: Vec<(PathBuf, ItemIdentity)> },
    Trashed { ok: usize, failed: usize, entry: Entry },
    Duplicated { ok: bool, path: String, err: String, entry: Entry },
    RedoDone { journal: super::undo::Journal, result: Result<String, FleaError> },
    MenuDeleteDone { line: String },
    // Not an operation: meta rides this channel because a media probe is a subprocess and the loop
    // must not wait on one. Nothing about it claims the one-at-a-time slot.
    Meta { line: String },
}

// moving is the verb the request actually resolved to, so the client names the operation from the
// wire rather than from a clipboard it may have already spent or never owned.
pub fn transferstarted_line(id: usize, n: usize, moving: bool) -> String {
    format!(r#"{{"t":"transferstarted","id":{},"n":{},"moving":{}}}"#, id, n, moving)
}

// total is 0 for a directory, whose size the item's own progress never knows in advance. scanned is
// the whole batch's, 0 until the sweep beside the copy settles on one: directive 45's counting state.
pub fn transferprogress_line(id: usize, index: usize, name: &str, bytes: u64, total: u64, scanned: u64) -> String {
    format!(
        r#"{{"t":"transferprogress","id":{},"index":{},"name":"{}","bytes":{},"total":{},"scanned":{}}}"#,
        id, index, escape(name), bytes, total, scanned
    )
}

// err rides only on a failure, so a successful item's line carries no empty field to reason about.
pub fn transferitem_line(id: usize, index: usize, name: &str, ok: bool, err: &str) -> String {
    if ok {
        return format!(
            r#"{{"t":"transferitem","id":{},"index":{},"name":"{}","ok":true}}"#,
            id, index, escape(name)
        );
    }
    format!(
        r#"{{"t":"transferitem","id":{},"index":{},"name":"{}","ok":false,"err":"{}"}}"#,
        id, index, escape(name), escape(err)
    )
}

pub fn transferdone_line(id: usize, ok: usize, failed: usize, skipped: usize, cancelled: bool,
                         retry: &[(PathBuf, ItemIdentity)]) -> String {
    let paths: Vec<_> = retry.iter().map(|(path, _)| format!("\"{}\"", escape(&path.to_string_lossy()))).collect();
    format!(
        r#"{{"t":"transferdone","id":{},"ok":{},"failed":{},"skipped":{},"cancelled":{},"retryPaths":[{}]}}"#,
        id, ok, failed, skipped, cancelled, paths.join(",")
    )
}

// Permission repair may change ctime; retry selects the original inode and link kind, never a replacement at its name.
pub fn retain_retry(retry: &[(PathBuf, ItemIdentity)], matches: &mut Vec<(&str, usize)>) {
    let originals: HashMap<_, _> = retry.iter().map(|(path, identity)| (path.as_path(), identity)).collect();
    matches.retain(|(path, _)| originals.get(Path::new(path)).is_some_and(|original|
        ItemIdentity::inspect(Path::new(path)).is_ok_and(|current| original.same_item(&current))));
}

pub fn trashed_line(ok: usize, failed: usize) -> String {
    format!(r#"{{"t":"trashed","ok":{},"failed":{}}}"#, ok, failed)
}

pub fn renamed_line(ok: bool, path: &str) -> String {
    format!(r#"{{"t":"renamed","ok":{},"path":"{}"}}"#, ok, escape(path))
}

pub fn duplicated_line(ok: bool, path: &str) -> String {
    format!(r#"{{"t":"duplicated","ok":{},"path":"{}"}}"#, ok, escape(path))
}

pub fn made_line(ok: bool, path: &str) -> String {
    format!(r#"{{"t":"made","ok":{},"path":"{}"}}"#, ok, escape(path))
}

pub fn undone_line(op: &str, ok: bool) -> String {
    format!(r#"{{"t":"undone","op":"{}","ok":{}}}"#, escape(op), ok)
}

// A destination Flea will not create as a side effect, checked once before any item is touched.
pub fn usable_dest(dest: &str) -> Result<PathBuf, FleaError> {
    let p = PathBuf::from(dest);
    if !p.is_absolute() {
        return Err(op_err("transfer", dest, "a destination must be an absolute path"));
    }
    match p.metadata() {
        Ok(m) if m.is_dir() => Ok(p),
        Ok(_) => Err(op_err("transfer", dest, "the destination is not a directory")),
        Err(e) => Err(from_io("transfer", dest, &e)),
    }
}

pub fn op_err(where_: &str, path: &str, msg: &str) -> FleaError {
    FleaError { where_: where_.to_string(), path: path.to_string(), msg: msg.to_string() }
}

fn base_name(p: &Path) -> String {
    p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default()
}

pub const INTO_ITSELF: &str = "cannot move or copy a folder into itself";
pub const ALREADY_THERE: &str = "already in that folder";

// Copy or move, one top-level item at a time, reporting each item's own terminal line as it lands.
pub fn run_transfer(
    id: usize,
    moving: bool,
    paths: Vec<String>,
    dest: PathBuf,
    cancel: Arc<AtomicBool>,
    tx: Sender<OpMsg>,
) {
    run_transfer_checked(id, moving, paths, dest, cancel, tx, None, None)
}

// A tree this far in is a tree the operator is watching, so the sweep gives up rather than holding a
// thread on a mount that has stopped answering; what it costs then is the estimate, never the copy.
const TOTAL_SWEEP_MS: u64 = 30_000;

// The scan a batch's total comes from, on its own thread so the first byte never waits for it. It
// publishes into the cell every progress sample reads, and a walk that hits the deadline or meets a
// cancel publishes nothing: the card shows no total rather than a floor, and no time left with it.
fn spawn_total(paths: &[String], cancel: &Arc<AtomicBool>, settled: &Arc<AtomicU64>) {
    let paths: Vec<String> = paths.to_vec();
    let cancel = Arc::clone(cancel);
    let settled = Arc::clone(settled);
    std::thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_millis(TOTAL_SWEEP_MS);
        let mut bytes = 0u64;
        for raw in &paths {
            if cancel.load(Ordering::Relaxed) {
                return;
            }
            let meta = match std::fs::symlink_metadata(raw) {
                Ok(meta) => meta,
                Err(_) => return,
            };
            if !meta.is_dir() {
                // A symlink is copied as the link, so its own size is what it costs and not its target's.
                bytes += meta.len();
                continue;
            }
            let seen = crate::backend::dirsize::walk_until(Path::new(raw), deadline);
            if seen.partial {
                return;
            }
            bytes += seen.bytes;
        }
        settled.store(bytes, Ordering::Relaxed);
    });
}

pub(crate) fn run_transfer_checked(
    id: usize, moving: bool, paths: Vec<String>, dest: PathBuf,
    cancel: Arc<AtomicBool>, tx: Sender<OpMsg>, selection: Option<Vec<super::menu_actions::Selected>>,
    destination: Option<super::menu_actions::Selected>,
) {
    // Directive 45: a batch gets a time left once it knows what it is copying, and a tree's size is
    // not known without a walk. This is that walk, beside the copy rather than before it.
    let settled = Arc::new(AtomicU64::new(0));
    spawn_total(&paths, &cancel, &settled);
    let mut steps: Vec<Step> = Vec::new();
    let mut retry = Vec::new();
    let (mut ok, mut failed, mut skipped) = (0usize, 0usize, 0usize);
    let mut was_cancelled = false;
    // Resolved once: a destination reached through a symlinked directory names the same inode under
    // another string, and the per-item guards below compare against this rather than the raw path.
    let dest_real = dest.canonicalize().unwrap_or_else(|_| dest.clone());
    for (index, raw) in paths.iter().enumerate() {
        if cancel.load(Ordering::Relaxed) {
            was_cancelled = true;
            skipped += 1;
            continue;
        }
        let src = PathBuf::from(raw);
        let name = base_name(&src);
        let dst = dest.join(&name);
        let checked = if let Some(items) = &selection {
            items.get(index).filter(|item| item.path == src)
                .ok_or_else(|| "Menu selection no longer matches this transfer.".to_string())
                .and_then(|item| item.current())
        } else {
            src.symlink_metadata().map_err(|error| io_message(&error))
        };
        let metadata = match checked {
            Ok(metadata) => metadata,
            Err(err) => {
                failed += 1;
                let _ = tx.send(OpMsg::Item { id, index, name, ok: false, err });
                continue;
            }
        };
        let source = ItemIdentity::record(&metadata);
        if let Some(destination) = &destination {
            if destination.path != dest || destination.current().is_err() {
                failed += 1;
                retry.push((src, source));
                let _ = tx.send(OpMsg::Item { id, index, name, ok: false,
                    err: "Dropbox account folder changed or disappeared; this item was not moved.".into() });
                continue;
            }
        }
        // A symlink is copied or moved as the link itself (copy_any, move_any), so it holds nothing and its target's tree is not its own; only a real directory can contain the destination.
        let src_is_link = metadata.file_type().is_symlink();
        let src_real = if src_is_link { src.clone() } else { src.canonicalize().unwrap_or_else(|_| src.clone()) };
        // A folder into itself or its own subtree: copy_dir would read its own fresh copy until the disk
        // is full, so the refusal ui/js/Drag.js canDropInto makes is made again here, per item.
        if !src_is_link && dest_real.starts_with(&src_real) {
            failed += 1;
            retry.push((src, source));
            let _ = tx.send(OpMsg::Item { id, index, name, ok: false, err: INTO_ITSELF.to_string() });
            continue;
        }
        // Where the entry itself lives, link or not: its parent resolved, plus its own name.
        let src_here = match src.parent() {
            Some(parent) => parent.canonicalize().unwrap_or_else(|_| parent.to_path_buf()).join(&name),
            None => src.clone(),
        };
        // An item dropped into the folder it already lives in: copy_file would truncate it onto itself.
        if dst == src || dest_real.join(&name) == src_here {
            failed += 1;
            retry.push((src, source));
            let _ = tx.send(OpMsg::Item { id, index, name, ok: false, err: ALREADY_THERE.to_string() });
            continue;
        }
        match one_item(id, index, &name, moving, &src, &dst, source.clone(), &cancel, &tx, &settled, &mut steps) {
            Ok(()) => {
                ok += 1;
                let _ = tx.send(OpMsg::Item { id, index, name, ok: true, err: String::new() });
            }
            Err(e) => {
                if e.msg == "cancelled" {
                    was_cancelled = true;
                    skipped += 1;
                } else {
                    failed += 1;
                    retry.push((src, source));
                }
                let _ = tx.send(OpMsg::Item { id, index, name, ok: false, err: e.msg });
            }
        }
    }
    let entry = Entry { op: if moving { "move".to_string() } else { "copy".to_string() }, steps };
    let _ = tx.send(OpMsg::TransferDone { id, ok, failed, skipped, cancelled: was_cancelled, entry, retry });
}

// A directory reports the bytes its tree has copied so far and no total, see copyfile.rs Progress.
// Its journal steps land in `steps` either way: a failure that created its destination left a partial there.
fn one_item(
    id: usize,
    index: usize,
    name: &str,
    moving: bool,
    src: &Path,
    dst: &Path,
    source: ItemIdentity,
    cancel: &AtomicBool,
    tx: &Sender<OpMsg>,
    settled: &AtomicU64,
    steps: &mut Vec<Step>,
) -> Result<(), FleaError> {
    let mut last = Instant::now() - PROGRESS_EVERY;
    let mut sink = |done: u64, total: u64| {
        if last.elapsed() < PROGRESS_EVERY {
            return;
        }
        last = Instant::now();
        let _ = tx.send(OpMsg::Progress {
            id,
            index,
            name: name.to_string(),
            bytes: done,
            total,
            // Still 0 while the sweep counts, and the batch's own total from the moment it settles.
            scanned: settled.load(Ordering::Relaxed),
        });
    };
    let mut p = Progress { cancel, on_bytes: &mut sink, partial: None, tree: None };
    let outcome = if moving { move_any(src, dst, &mut p) } else { copy_any(src, dst, &mut p) };
    match &outcome {
        Ok(()) if moving => steps.push(undo::moved(src, dst, source)?),
        Ok(()) => steps.push(undo::copied(src, dst, source)?),
        // The partial is this operation's, so it is journaled and undo removes it like any created path.
        Err(_) => {
            if let Some(path) = p.partial.take() {
                steps.push(undo::copied(src, &path, source)?);
            }
        }
    }
    outcome
}

pub(crate) fn run_trash(paths: Vec<String>, tx: Sender<OpMsg>, selection: Option<Vec<super::menu_actions::Selected>>) {
    let owned: Vec<PathBuf> = paths.iter().map(PathBuf::from).collect();
    let (entries, failed) = match trash::trash_checked(&owned, selection.as_deref()) {
        Ok(result) => result,
        Err(error) => {
            let line = super::proto::error_line(&op_err("trash", "", &error));
            let _ = tx.send(OpMsg::Meta { line });
            (Vec::new(), owned.len())
        }
    };
    let ok = entries.len();
    let steps = entries.into_iter().map(Step::Trashed).collect();
    let entry = Entry { op: "trash".to_string(), steps };
    let _ = tx.send(OpMsg::Trashed { ok, failed, entry });
}

pub fn run_duplicate(path: String, tx: Sender<OpMsg>) {
    run_duplicate_checked(path, tx, None)
}

pub(crate) fn run_duplicate_checked(path: String, tx: Sender<OpMsg>, selection: Option<Vec<super::menu_actions::Selected>>) {
    let (outcome, steps) = match super::menu_actions::validate_sources(selection.as_deref(), &[PathBuf::from(&path)]) {
        Ok(()) => ops::duplicate(Path::new(&path)),
        Err(error) => (Err(op_err("duplicate", &path, &error)), Vec::new()),
    };
    // Carried on a failure too: the steps then name the partial copy the failure left behind.
    let entry = Entry { op: "duplicate".to_string(), steps };
    let msg = match outcome {
        Ok(dst) => OpMsg::Duplicated { ok: true, path: dst.to_string_lossy().to_string(), err: String::new(), entry },
        Err(e) => OpMsg::Duplicated { ok: false, path: String::new(), err: e.msg, entry },
    };
    let _ = tx.send(msg);
}

#[cfg(test)]
mod tests;
