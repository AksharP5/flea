// The copy primitives every transfer is built from: streaming, symlink-preserving, and refusing to overwrite.
use crate::error::{from_io, FleaError};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

// Big enough that the syscall count stops mattering, small enough that a cancel is noticed promptly.
const CHUNK: usize = 256 * 1024;
// rename(2) sets EXDEV when the two paths are on different filesystems, which is the one failure that means "copy instead".
const EXDEV: i32 = 18;
use crate::oflags::O_NOFOLLOW;

// What a copy reports as it runs; a directory has no total without a sweep, so it reports 0 and renders indeterminate.
pub struct Progress<'a> {
    pub cancel: &'a AtomicBool,
    pub on_bytes: &'a mut dyn FnMut(u64, u64),
    // Some once the copy is inside a directory tree, holding the bytes its earlier files already copied, so a tree reports one running count and no total: the size of a tree is not known without a sweep.
    pub tree: Option<u64>,
    // The destination a copy created and then failed to finish for a reason other than a cancel. It
    // stays on disk, because removing it would destroy data on a transient error, and the caller
    // journals it so undo removes it as one step. A cancel never sets it: the cancel path removes.
    pub partial: Option<PathBuf>,
}

pub fn cancelled(p: &Progress) -> bool {
    p.cancel.load(Ordering::Relaxed)
}

// Copies one regular file, creating the destination exclusively so an existing file is never destroyed.
pub fn copy_file(src: &Path, dst: &Path, total: u64, p: &mut Progress) -> Result<(), FleaError> {
    // Anything reaching here that is not a regular file was swapped in after copy_any's stat:
    // O_NOFOLLOW refuses a symlink, and regfile's non-blocking open and fstat refuse every other kind.
    let mut r = crate::backend::regfile::open_if_regular(src, O_NOFOLLOW)
        .map_err(|e| from_io("copy", &src.to_string_lossy(), &e))?;
    let mut w = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(dst)
        .map_err(|e| from_io("copy", &dst.to_string_lossy(), &e))?;
    // From here the destination exists, and every failure below leaves it for the caller to journal.
    let mut buf = vec![0u8; CHUNK];
    let mut done: u64 = 0;
    loop {
        if cancelled(p) {
            // The partial file goes with the cancel: a half-written destination is not a result anyone asked for.
            drop(w);
            let _ = std::fs::remove_file(dst);
            return Err(cancel_err(dst));
        }
        let n = match r.read(&mut buf) {
            Ok(n) => n,
            Err(e) => return Err(left_partial(p, dst, from_io("copy", &src.to_string_lossy(), &e))),
        };
        if n == 0 {
            break;
        }
        if let Err(e) = w.write_all(&buf[..n]) {
            return Err(left_partial(p, dst, from_io("copy", &dst.to_string_lossy(), &e)));
        }
        done += n as u64;
        let (reported, against) = match p.tree {
            Some(carried) => (carried + done, 0),
            None => (done, total),
        };
        (p.on_bytes)(reported, against);
    }
    if let Err(e) = w.flush() {
        return Err(left_partial(p, dst, from_io("copy", &dst.to_string_lossy(), &e)));
    }
    if let Some(carried) = p.tree.as_mut() {
        *carried += done;
    }
    Ok(())
}

// A failure after the destination was created, and not a cancel: the partial stays, and is reported for the journal.
fn left_partial(p: &mut Progress, dst: &Path, e: FleaError) -> FleaError {
    p.partial = Some(dst.to_path_buf());
    e
}

// A symlink is copied as a symlink and never followed, matching cp -a and every rival in the parity audit.
pub fn copy_symlink(src: &Path, dst: &Path) -> Result<(), FleaError> {
    let target = std::fs::read_link(src).map_err(|e| from_io("copy", &src.to_string_lossy(), &e))?;
    std::os::unix::fs::symlink(&target, dst).map_err(|e| from_io("copy", &dst.to_string_lossy(), &e))
}

// Copies a file, a symlink, a whole directory tree, or any other node by recreating it. The
// destination must not already exist.
pub fn copy_any(src: &Path, dst: &Path, p: &mut Progress) -> Result<(), FleaError> {
    let meta = src
        .symlink_metadata()
        .map_err(|e| from_io("copy", &src.to_string_lossy(), &e))?;
    if meta.file_type().is_symlink() {
        return copy_symlink(src, dst);
    }
    if meta.is_dir() {
        return copy_dir(src, dst, p);
    }
    if meta.is_file() {
        return copy_file(src, dst, meta.len(), p);
    }
    // A fifo, a socket and a device node are the rest, and none of them has contents copy_file could
    // stream: the fifo's open waits, the socket's fails, and the device's would never end.
    crate::backend::copynode::copy_node(&meta, dst)
}

fn copy_dir(src: &Path, dst: &Path, p: &mut Progress) -> Result<(), FleaError> {
    std::fs::create_dir(dst).map_err(|e| from_io("copy", &dst.to_string_lossy(), &e))?;
    // Set once at the top of the tree, so a directory inside it goes on counting rather than starting again.
    if p.tree.is_none() {
        p.tree = Some(0);
    }
    let r = copy_dir_entries(src, dst, p);
    if r.is_err() {
        if cancelled(p) {
            // The tree goes with the cancel, the same rule copy_file already applies to a partial file: a
            // half-copied directory is not a result anyone asked for, and no journal step records one.
            // Gated on the flag rather than the message, because a nested copy_file returns its own cancel.
            let _ = std::fs::remove_dir_all(dst);
            p.partial = None;
        } else {
            // Any other failure leaves what was copied, since removing it would destroy data on a
            // transient error, and reports the whole tree as the one partial the journal records.
            p.partial = Some(dst.to_path_buf());
        }
    }
    r
}

fn copy_dir_entries(src: &Path, dst: &Path, p: &mut Progress) -> Result<(), FleaError> {
    let entries = std::fs::read_dir(src).map_err(|e| from_io("copy", &src.to_string_lossy(), &e))?;
    for entry in entries {
        if cancelled(p) {
            return Err(cancel_err(dst));
        }
        let entry = entry.map_err(|e| from_io("copy", &src.to_string_lossy(), &e))?;
        copy_any(&entry.path(), &dst.join(entry.file_name()), p)?;
    }
    Ok(())
}

// Same filesystem is a rename; a different one is copy-then-remove, and the source only goes once the copy is complete.
pub fn move_any(src: &Path, dst: &Path, p: &mut Progress) -> Result<(), FleaError> {
    match crate::backend::renamecompat::rename_noreplace(src, dst) {
        Ok(()) => Ok(()),
        Err(e) if e.raw_os_error() == Some(EXDEV) => {
            copy_any(src, dst, p)?;
            remove_any(src)
        }
        Err(e) => Err(from_io("rename", &dst.to_string_lossy(), &e)),
    }
}

pub fn remove_any(path: &Path) -> Result<(), FleaError> {
    let meta = path
        .symlink_metadata()
        .map_err(|e| from_io("move", &path.to_string_lossy(), &e))?;
    let r = if meta.is_dir() && !meta.file_type().is_symlink() {
        std::fs::remove_dir_all(path)
    } else {
        std::fs::remove_file(path)
    };
    r.map_err(|e| from_io("move", &path.to_string_lossy(), &e))
}

fn cancel_err(path: &Path) -> FleaError {
    FleaError {
        where_: "copy".to_string(),
        path: path.to_string_lossy().to_string(),
        msg: "cancelled".to_string(),
    }
}

#[cfg(test)]
#[path = "copyfile_tests.rs"]
mod tests;
