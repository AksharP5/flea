// Cross-device moves in batches: each copy lands with its file fsync as today, but the
// destination folders confirm once per batch instead of once per item. Same-filesystem
// renames and replaces never enter a batch and run exactly as before.
use crate::backend::collide::{cancelled, CANCELLED};
use crate::backend::copyfile::{copy_any, remove_any, Progress};
use crate::backend::durable::{fsync_dir, Durability, DIR_UNCONFIRMED};
use crate::backend::opsreq::{OpMsg, PROGRESS_EVERY};
use crate::backend::undo::{self, ItemIdentity, Step};
use crate::error::{from_io, FleaError};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::Sender;
use std::time::Instant;

// 64 items keep one folder fsync per batch while bounding what a cancel must clean up.
pub(crate) const BATCH_ITEMS: usize = 64;
// rename(2) sets EXDEV when the two paths are on different filesystems, the one failure that means "copy instead".
const EXDEV: i32 = 18;

// One landed copy waiting on its batch's folder confirm; the source is still whole.
pub(crate) struct PendingMove {
    index: usize,
    name: String,
    src: PathBuf,
    dst: PathBuf,
    source: ItemIdentity,
    manifest: Option<crate::backend::copymanifest::Writer>,
}

pub(crate) struct MoveBatch {
    pending: Vec<PendingMove>,
    parent: Option<PathBuf>,
}

// What one moving item did: answered now, or copied and waiting on its batch's confirm.
pub(crate) enum MoveOutcome {
    Done(Result<(), FleaError>),
    Deferred,
}

#[derive(Default)]
pub(crate) struct CloseCounts {
    pub ok: usize,
    pub failed: usize,
    pub skipped: usize,
    pub cancelled: bool,
}

#[cfg(test)]
#[path = "movebatch_tests.rs"]
mod tests;

impl MoveBatch {
    pub(crate) fn new() -> Self {
        MoveBatch { pending: Vec::new(), parent: None }
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.pending.is_empty()
    }

    // A batch closes after BATCH_ITEMS items, so one folder fsync never covers an unbounded move.
    pub(crate) fn full(&self) -> bool {
        self.pending.len() >= BATCH_ITEMS
    }

    // A batch holds one destination folder, so a move elsewhere closes it first.
    pub(crate) fn folder_changed(&self, dst: &Path) -> bool {
        if self.pending.is_empty() {
            return false;
        }
        match (self.parent.as_deref(), dst.parent()) {
            (Some(a), Some(b)) => a != b,
            _ => true,
        }
    }

    pub(crate) fn push(&mut self, item: PendingMove) {
        if self.parent.is_none() {
            self.parent = item.dst.parent().map(Path::to_path_buf);
        }
        self.pending.push(item);
    }
}

// One terminal line per batched item, sent when its batch closes rather than when its copy landed.
fn send_item(tx: &Sender<OpMsg>, id: usize, index: usize, name: &str, ok: bool, err: &str) {
    let _ = tx.send(OpMsg::Item { id, index, name: name.to_string(), ok, err: err.to_string() });
}

// A copy the batch cannot finish, journaled as the partial one_item journals for any failed copy.
fn journal_partial(
    src: &Path,
    dst: &Path,
    source: &ItemIdentity,
    manifest: Option<crate::backend::copymanifest::Writer>,
    steps: &mut Vec<Step>,
    err: &mut FleaError,
) -> Result<(), FleaError> {
    let (manifest, loud) = crate::backend::copymanifest::finish_loud(manifest);
    if let Some(e) = loud {
        err.msg.push_str(&format!("; copy manifest failed: {e}"));
    }
    steps.push(undo::copied_partial(src, dst, source.clone(), manifest)?);
    Ok(())
}

// The folders a batch filled, confirmed once instead of once per item; a failure keeps every source.
fn confirm_batch(durability: &mut Durability, dsts: &[PathBuf]) -> Result<(), FleaError> {
    let failed = if durability.durable {
        durability.flush_dirs_for_many(dsts).is_err()
    } else {
        // No touched set without a durability context, so each filled parent confirms once.
        let mut parents: Vec<&Path> = Vec::new();
        for dst in dsts {
            if let Some(parent) = dst.parent() {
                if !parents.contains(&parent) {
                    parents.push(parent);
                }
            }
        }
        let mut failed = false;
        for parent in parents {
            if fsync_dir(parent).is_err() {
                failed = true;
            }
        }
        failed
    };
    if failed {
        let first = dsts.first().map(|dst| dst.to_string_lossy().to_string()).unwrap_or_default();
        return Err(FleaError { where_: "move".to_string(), path: first, msg: DIR_UNCONFIRMED.to_string() });
    }
    Ok(())
}

// A same-filesystem rename answers at once; a cross-device copy stages into the batch.
pub(crate) fn land_move(
    id: usize,
    index: usize,
    name: &str,
    src: &Path,
    dst: &Path,
    source: ItemIdentity,
    cancel: &AtomicBool,
    tx: &Sender<OpMsg>,
    settled: &AtomicU64,
    steps: &mut Vec<Step>,
    durability: &mut Durability,
    batch: &mut MoveBatch,
) -> MoveOutcome {
    match crate::backend::renamecompat::rename_noreplace(src, dst) {
        Ok(()) => {
            // One rename rewrote two directory entries, so both folders are confirmed.
            if let Some(parent) = dst.parent() {
                durability.touch(parent);
            }
            if let Some(parent) = src.parent() {
                durability.touch(parent);
            }
            match undo::moved(src, dst, source) {
                Ok(step) => {
                    steps.push(step);
                    MoveOutcome::Done(Ok(()))
                }
                Err(e) => MoveOutcome::Done(Err(e)),
            }
        }
        Err(e) if e.raw_os_error() == Some(EXDEV) => {
            stage_copy(id, index, name, src, dst, source, cancel, tx, settled, steps, durability, batch)
        }
        Err(e) => MoveOutcome::Done(Err(from_io("rename", &dst.to_string_lossy(), &e))),
    }
}

// The EXDEV half of land_move: copy with today's file fsync, then wait on the batch's confirm.
pub(crate) fn stage_copy(
    id: usize,
    index: usize,
    name: &str,
    src: &Path,
    dst: &Path,
    source: ItemIdentity,
    cancel: &AtomicBool,
    tx: &Sender<OpMsg>,
    settled: &AtomicU64,
    steps: &mut Vec<Step>,
    durability: &mut Durability,
    batch: &mut MoveBatch,
) -> MoveOutcome {
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
            scanned: settled.load(Ordering::Relaxed),
        });
    };
    let mut p = Progress {
        cancel,
        on_bytes: &mut sink,
        partial: None,
        tree: None,
        manifest: crate::backend::copymanifest::writer_for_move(src, dst),
        durability: Some(durability),
    };
    let outcome = copy_any(src, dst, &mut p);
    let partial = p.partial.take();
    let manifest = p.manifest.take();
    drop(p);
    match outcome {
        Ok(()) => {
            batch.push(PendingMove {
                index,
                name: name.to_string(),
                src: src.to_path_buf(),
                dst: dst.to_path_buf(),
                source,
                manifest,
            });
            MoveOutcome::Deferred
        }
        Err(mut err) => {
            if let Some(path) = partial {
                if let Err(record) = journal_partial(src, &path, &source, manifest, steps, &mut err) {
                    return MoveOutcome::Done(Err(record));
                }
            }
            MoveOutcome::Done(Err(err))
        }
    }
}

// A full batch, a moved-on folder, a failure or the end: confirm once, then remove each source.
pub(crate) fn close_normal(
    batch: &mut MoveBatch,
    id: usize,
    tx: &Sender<OpMsg>,
    steps: &mut Vec<Step>,
    durability: &mut Durability,
) -> (CloseCounts, Vec<(PathBuf, ItemIdentity)>) {
    let mut counts = CloseCounts::default();
    let mut retry = Vec::new();
    if batch.pending.is_empty() {
        return (counts, retry);
    }
    let dsts: Vec<PathBuf> = batch.pending.iter().map(|item| item.dst.clone()).collect();
    if confirm_batch(durability, &dsts).is_err() {
        // Every source stays whole and every copy is journaled as a partial, as one_item does.
        for item in batch.pending.drain(..) {
            let mut err = FleaError {
                where_: "move".to_string(),
                path: item.dst.to_string_lossy().to_string(),
                msg: DIR_UNCONFIRMED.to_string(),
            };
            let err = match journal_partial(&item.src, &item.dst, &item.source, item.manifest, steps, &mut err) {
                Ok(()) => err,
                Err(record) => record,
            };
            counts.failed += 1;
            retry.push((item.src.clone(), item.source.clone()));
            send_item(tx, id, item.index, &item.name, false, &err.msg);
        }
        batch.parent = None;
        return (counts, retry);
    }
    for item in batch.pending.drain(..) {
        match remove_any(&item.src) {
            Ok(()) => {
                if let Some(parent) = item.src.parent() {
                    durability.touch(parent);
                }
                match undo::moved(&item.src, &item.dst, item.source.clone()) {
                    Ok(step) => {
                        steps.push(step);
                        counts.ok += 1;
                        send_item(tx, id, item.index, &item.name, true, "");
                    }
                    Err(e) => {
                        counts.failed += 1;
                        retry.push((item.src.clone(), item.source));
                        send_item(tx, id, item.index, &item.name, false, &e.msg);
                    }
                }
            }
            Err(e) => {
                counts.failed += 1;
                retry.push((item.src.clone(), item.source));
                send_item(tx, id, item.index, &item.name, false, &e.msg);
            }
        }
    }
    batch.parent = None;
    (counts, retry)
}

// A cancel before the confirm removes what the batch copied and keeps every source whole.
pub(crate) fn close_cancelled(
    batch: &mut MoveBatch,
    id: usize,
    tx: &Sender<OpMsg>,
    steps: &mut Vec<Step>,
    durability: &mut Durability,
) -> (CloseCounts, Vec<(PathBuf, ItemIdentity)>) {
    let mut counts = CloseCounts::default();
    let mut retry = Vec::new();
    if batch.pending.is_empty() {
        return (counts, retry);
    }
    counts.cancelled = true;
    for item in batch.pending.drain(..) {
        match remove_any(&item.dst) {
            Ok(()) => {
                durability.forget_tree(&item.dst);
                counts.skipped += 1;
                send_item(tx, id, item.index, &item.name, false, CANCELLED);
            }
            Err(_) => {
                // The copy stays, so it is journaled for undo exactly as a cancelled tree copy is.
                let mut err = FleaError {
                    where_: "copy".to_string(),
                    path: item.dst.to_string_lossy().to_string(),
                    msg: CANCELLED.to_string(),
                };
                let err = match journal_partial(&item.src, &item.dst, &item.source, item.manifest, steps, &mut err) {
                    Ok(()) => err,
                    Err(record) => record,
                };
                if cancelled(&err.msg) {
                    counts.skipped += 1;
                } else {
                    // Only the journal failure lands here; the loop counts it as a failure, as one_item does.
                    counts.failed += 1;
                    retry.push((item.src.clone(), item.source.clone()));
                }
                send_item(tx, id, item.index, &item.name, false, &err.msg);
            }
        }
    }
    batch.parent = None;
    (counts, retry)
}
