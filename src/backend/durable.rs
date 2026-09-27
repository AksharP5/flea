// Durable copies onto usb, phone and network targets: fsync each file, then each directory.
#[cfg(test)]
use std::cell::{Cell, RefCell};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

// Test builds only: forced-durable paths, fsync fault flags, flush counts; a release build has none of it.
#[cfg(test)]
thread_local! {
    static FORCE: RefCell<Vec<PathBuf>> = const { RefCell::new(Vec::new()) };
    static FAIL_FILE: Cell<bool> = const { Cell::new(false) };
    static FAIL_DIR: Cell<bool> = const { Cell::new(false) };
    static FILE_FLUSHES: Cell<usize> = const { Cell::new(0) };
    static DIR_FLUSHES: Cell<usize> = const { Cell::new(0) };
}

// Sample input: "fuse.rclone" trues, "fuse.sshfs" falses.
pub fn fstype_is_rclone(fstype: &str) -> bool {
    fstype.to_ascii_lowercase().contains("rclone")
}

// Sample input: "vfat" trues, "ext4" falses.
pub fn fat_name_is_durable(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower == "vfat" || lower == "exfat" || lower == "ntfs"
}

// Sample input: 0x4D44 trues, 0xEF53 falses.
pub fn fat_magic_is_durable(magic: i64) -> bool {
    magic == 0x4D44 || magic == 0x2011BAB0 || magic == 0x5346544E
}

#[cfg(test)]
fn forced(dest: &Path) -> bool {
    FORCE.with(|v| v.borrow().iter().any(|p| dest == p || dest.starts_with(p)))
}

#[cfg(not(test))]
fn forced(_dest: &Path) -> bool {
    false
}

// A test counts every flush and can make one fail; a release build always answers "not failed".
#[cfg(test)]
fn seam_flush(dir: bool) -> bool {
    if dir {
        DIR_FLUSHES.with(|v| v.set(v.get() + 1));
        FAIL_DIR.with(|v| v.get())
    } else {
        FILE_FLUSHES.with(|v| v.set(v.get() + 1));
        FAIL_FILE.with(|v| v.get())
    }
}

#[cfg(not(test))]
fn seam_flush(_dir: bool) -> bool {
    false
}

// True when the destination is an rclone mount: the copy lands in rclone's cache first,
// so an fsync here would force the upload the verdict below says happens in the background.
pub fn dest_is_rclone(dest: &Path) -> bool {
    std::fs::read_to_string("/proc/self/mountinfo").is_ok_and(|body| {
        crate::backend::mountinfo::mount_entry_in(dest, &body).is_some_and(|e| fstype_is_rclone(&e.fstype))
    })
}

// True when the destination needs its bytes confirmed: usb, phone, network, or vfat/exfat/ntfs.
pub fn dest_is_durable(dest: &Path) -> bool {
    if forced(dest) {
        return true;
    }
    if crate::backend::extclass::classify(dest) != "" {
        return true;
    }
    if let Ok(body) = std::fs::read_to_string("/proc/self/mountinfo") {
        if let Some(e) = crate::backend::mountinfo::mount_entry_in(dest, &body) {
            if fat_name_is_durable(&e.fstype) {
                return true;
            }
        }
    }
    if crate::backend::fsinfo::magic_of(dest).is_some_and(fat_magic_is_durable) {
        return true;
    }
    if crate::backend::fsinfo::read(dest).is_some_and(|i| fat_name_is_durable(&i.name)) {
        return true;
    }
    false
}

// The done line's own words for a folder the drive would not confirm, printable as-is.
pub const DIR_UNCONFIRMED: &str = "copied, but the drive did not confirm the folder";

// The done line's own words for a copy onto rclone, printable as-is: the files landed in
// rclone's cache and its own upload follows, so the UI never claims the drive confirmed them.
pub const RCLONE_NOTE: &str = "rclone uploads them in the background";

// One operation's durability, created from its destination and carried down through Progress.
pub struct Ctx {
    pub durable: bool,
    pub rclone: bool,
    pub file_failed: bool,
    touched: HashSet<PathBuf>,
    last: Option<PathBuf>,
}

impl Ctx {
    // Classified once per operation, so a copy never classifies per file. An rclone target
    // is not durable: every fsync on it would force a synchronous upload of what the note
    // above says uploads in the background.
    pub fn begin(dest: &Path) -> Ctx {
        let rclone = dest_is_rclone(dest);
        Ctx { durable: !rclone && dest_is_durable(dest), rclone, file_failed: false,
            touched: HashSet::new(), last: None }
    }

    // One entry per directory however many files land in it: a 100,000-file copy into one
    // folder records one path, and the set covers a tree that revisits a parent.
    pub fn touch(&mut self, dir: &Path) {
        if !self.durable {
            return;
        }
        if self.last.as_deref() == Some(dir) {
            return;
        }
        self.last = Some(dir.to_path_buf());
        self.touched.insert(dir.to_path_buf());
    }

    pub fn note_file_failed(&mut self) {
        self.file_failed = true;
    }

    // Deepest first, so a child's entry is confirmed before its parent's.
    fn ordered(&self) -> Vec<PathBuf> {
        let mut dirs: Vec<PathBuf> = self.touched.iter().cloned().collect();
        dirs.sort_by_key(|p| std::cmp::Reverse(p.components().count()));
        dirs
    }

    // Every touched directory, best effort per directory: one bad folder never skips the rest.
    pub fn flush_dirs(&self) -> std::io::Result<()> {
        let mut first: Option<std::io::Error> = None;
        for dir in self.ordered() {
            if let Err(e) = fsync_dir(&dir) {
                if first.is_none() {
                    first = Some(e);
                }
            }
        }
        match first {
            Some(e) => Err(e),
            None => Ok(()),
        }
    }
}

// Counted through this seam, never timed: tests assert the counts.
pub fn fsync_file(f: &std::fs::File) -> std::io::Result<()> {
    if seam_flush(false) {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "simulated fsync failure"));
    }
    f.sync_all()
}

pub fn fsync_dir(path: &Path) -> std::io::Result<()> {
    if seam_flush(true) {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "simulated fsync failure"));
    }
    std::fs::File::open(path)?.sync_all()
}

// Sample input: /run/media/gm/128GB answers "128GB".
pub fn drive_name(dest: &Path) -> String {
    dest.file_name().map(|n| n.to_string_lossy().into_owned()).filter(|n| !n.is_empty()).unwrap_or_else(|| dest.to_string_lossy().into_owned())
}

// Sample output: {"t":"transferprogress","id":1,"index":0,"name":"","bytes":0,"total":0,"scanned":0,"phase":"writing","drive":"128GB"}
pub fn writing_line(id: usize, drive: &str) -> String {
    format!(r#"{{"t":"transferprogress","id":{},"index":0,"name":"","bytes":0,"total":0,"scanned":0,"phase":"writing","drive":"{}"}}"#, id, crate::json::escape(drive))
}

pub struct Finish {
    pub ok: bool,
    pub note: String,
}

// After the last file: one writing line, then every touched directory. Cancel is not
// honoured here because every file is already complete. An rclone target answers its note
// with no flush at all, so neither the writing phase nor a "written to the drive" line exists for it.
pub fn finish(id: usize, tx: &std::sync::mpsc::Sender<crate::backend::opsreq::OpMsg>, ctx: &Ctx, dest: &Path) -> Finish {
    if ctx.rclone {
        return Finish { ok: false, note: RCLONE_NOTE.to_string() };
    }
    if !ctx.durable {
        return Finish { ok: false, note: String::new() };
    }
    let _ = tx.send(crate::backend::opsreq::OpMsg::Meta { line: writing_line(id, &drive_name(dest)) });
    if ctx.file_failed {
        return Finish { ok: false, note: String::new() };
    }
    match ctx.flush_dirs() {
        Ok(()) => Finish { ok: true, note: String::new() },
        Err(_) => Finish { ok: false, note: DIR_UNCONFIRMED.to_string() },
    }
}

#[cfg(test)]
pub fn test_reset() {
    FORCE.with(|v| v.borrow_mut().clear());
    FAIL_FILE.with(|v| v.set(false));
    FAIL_DIR.with(|v| v.set(false));
    FILE_FLUSHES.with(|v| v.set(0));
    DIR_FLUSHES.with(|v| v.set(0));
}

#[cfg(test)]
pub fn test_reset_counts() {
    FAIL_FILE.with(|v| v.set(false));
    FAIL_DIR.with(|v| v.set(false));
    FILE_FLUSHES.with(|v| v.set(0));
    DIR_FLUSHES.with(|v| v.set(0));
}

#[cfg(test)]
pub fn test_counts() -> (usize, usize) {
    (FILE_FLUSHES.with(|v| v.get()), DIR_FLUSHES.with(|v| v.get()))
}

#[cfg(test)]
pub fn test_set_fail(fail: bool) {
    FAIL_FILE.with(|v| v.set(fail));
    FAIL_DIR.with(|v| v.set(fail));
}

#[cfg(test)]
pub fn test_set_fail_dirs(fail: bool) {
    FAIL_DIR.with(|v| v.set(fail));
}

#[cfg(test)]
pub fn test_mark_durable(path: &Path) {
    FORCE.with(|v| v.borrow_mut().push(path.to_path_buf()));
}

#[cfg(test)]
#[path = "durable_tests.rs"]
mod tests;
