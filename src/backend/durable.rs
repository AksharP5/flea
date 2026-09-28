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
    lower == "vfat" || lower == "exfat" || lower == "ntfs" || lower == "ntfs3"
}

// Linux statfs magics for removable Windows filesystems; MSDOS and EXFAT match linux/magic.h.
const MSDOS_SUPER_MAGIC: i64 = 0x4D44;
const EXFAT_SUPER_MAGIC: i64 = 0x2011BAB0;
// NTFS legacy driver magic and the ntfs3 magic from fs/ntfs3/super.c (lowercase sftn).
const NTFS_SUPER_MAGIC: i64 = 0x5346544E;
const NTFS3_SUPER_MAGIC: i64 = 0x7366746e;

// Sample input: 0x4D44 trues, 0xEF53 falses.
pub fn fat_magic_is_durable(magic: i64) -> bool {
    magic == MSDOS_SUPER_MAGIC || magic == EXFAT_SUPER_MAGIC || magic == NTFS_SUPER_MAGIC || magic == NTFS3_SUPER_MAGIC
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

// Rclone lands in its cache first, so an fsync here would force its background upload now.
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

// The done line's own words for a copy onto rclone, printable as-is.
pub const RCLONE_NOTE: &str = "rclone uploads them in the background";

// One operation's durability, created from its destination and carried down through Progress.
pub struct Durability {
    pub durable: bool,
    pub rclone: bool,
    pub file_failed: bool,
    touched: HashSet<PathBuf>,
    last: Option<PathBuf>,
}

impl Durability {
    // Classified once per operation, never per file; rclone stays non-durable to keep its upload in the background.
    pub fn begin(dest: &Path) -> Durability {
        let rclone = dest_is_rclone(dest);
        Durability { durable: !rclone && dest_is_durable(dest), rclone, file_failed: false,
            touched: HashSet::new(), last: None }
    }

    // One entry per directory however many files land in it, covering a tree that revisits a parent.
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

    // A cancelled tree removed its own folders, so they leave the touched set with it.
    pub fn forget_tree(&mut self, root: &Path) {
        self.touched.retain(|p| p != root && !p.starts_with(root));
        if self.last.as_deref().is_some_and(|l| l == root || l.starts_with(root)) {
            self.last = None;
        }
    }

    // Deepest first, so a child's entry is confirmed before its parent's.
    fn ordered(&self) -> Vec<PathBuf> {
        let mut dirs: Vec<PathBuf> = self.touched.iter().cloned().collect();
        dirs.sort_by_key(|p| std::cmp::Reverse(p.components().count()));
        dirs
    }

    // Only the touched folders a copy to dst filled, so a move confirms its destination without the source side.
    pub fn flush_dirs_for(&self, dst: &Path) -> std::io::Result<()> {
        let mut first: Option<std::io::Error> = None;
        for dir in self.ordered() {
            if dir.starts_with(dst) || Some(dir.as_path()) == dst.parent() {
                if let Err(e) = fsync_dir(&dir) {
                    first.get_or_insert(e);
                }
            }
        }
        match first {
            Some(e) => Err(e),
            None => Ok(()),
        }
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

// sync_file_range(2) writes one slice back without the whole-file wait, so the card counts confirmed bytes mid-file.
const SYNC_FILE_RANGE_WAIT_BEFORE: u32 = 1;
const SYNC_FILE_RANGE_WRITE: u32 = 2;
const SYNC_FILE_RANGE_WAIT_AFTER: u32 = 4;

// std already links the system libc, so the one symbol is declared here rather than taking a crate.
extern "C" {
    fn sync_file_range(fd: i32, offset: i64, nbytes: i64, flags: u32) -> i32;
}

// One written slice is confirmed to the drive; a failure refuses the bytes the same way an fsync failure does.
pub fn sync_range(f: &std::fs::File, offset: u64, len: u64) -> std::io::Result<()> {
    if seam_flush(false) {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "simulated fsync failure"));
    }
    use std::os::unix::io::AsRawFd;
    let flags = SYNC_FILE_RANGE_WAIT_BEFORE | SYNC_FILE_RANGE_WRITE | SYNC_FILE_RANGE_WAIT_AFTER;
    let rc = unsafe { sync_file_range(f.as_raw_fd(), offset as i64, len as i64, flags) };
    if rc == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

// EINVAL, ESPIPE, ENOSYS and EOPNOTSUPP say the filesystem has no range writeback, not that a byte was lost.
pub fn range_unsupported(e: &std::io::Error) -> bool {
    const EINVAL: i32 = 22;
    const ESPIPE: i32 = 29;
    const ENOSYS: i32 = 38;
    const EOPNOTSUPP: i32 = 95;
    matches!(e.raw_os_error(), Some(EINVAL) | Some(ESPIPE) | Some(ENOSYS) | Some(EOPNOTSUPP))
}

pub fn fsync_dir(path: &Path) -> std::io::Result<()> {
    if seam_flush(true) {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "simulated fsync failure"));
    }
    std::fs::File::open(path)?.sync_all()
}

// Sample input: "smb-share:server=nas,share=media" answers "media".
fn gvfs_drive_name(root: &Path) -> Option<String> {
    let name = root.file_name()?.to_str()?;
    for key in ["share=", "server=", "host="] {
        if let Some(at) = name.find(key) {
            let rest = &name[at + key.len()..];
            let end = rest.find(',').unwrap_or(rest.len());
            let value = rest[..end].trim();
            if !value.is_empty() {
                return Some(value.to_string());
            }
        }
    }
    None
}

// Sample input: dest "/run/media/gm/128GB/photos" with mount "/run/media/gm/128GB" answers "128GB".
pub fn drive_name_in(dest: &Path, body: &str) -> String {
    if let Some(root) = crate::backend::extclass::gvfs_root(dest) {
        if let Some(name) = gvfs_drive_name(&root) {
            return name;
        }
    }
    if let Some(entry) = crate::backend::mountinfo::mount_entry_in(dest, body) {
        if let Some(name) = entry.mount.file_name().and_then(|n| n.to_str()).filter(|n| !n.is_empty()) {
            return name.to_string();
        }
    }
    dest.file_name().map(|n| n.to_string_lossy().into_owned()).filter(|n| !n.is_empty()).unwrap_or_else(|| dest.to_string_lossy().into_owned())
}

// Sample input: /run/media/gm/128GB/photos answers "128GB".
pub fn drive_name(dest: &Path) -> String {
    let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    drive_name_in(dest, &body)
}

// Sample output: {"t":"transferprogress","id":1,"index":0,"name":"","bytes":0,"total":0,"scanned":0,"phase":"writing","drive":"128GB"}
pub fn writing_line(id: usize, drive: &str) -> String {
    format!(r#"{{"t":"transferprogress","id":{},"index":0,"name":"","bytes":0,"total":0,"scanned":0,"phase":"writing","drive":"{}"}}"#, id, crate::json::escape(drive))
}

pub struct Finish {
    pub ok: bool,
    pub note: String,
}

// After the last landed file: one writing line, then every touched directory.
pub fn finish(id: usize, tx: &std::sync::mpsc::Sender<crate::backend::opsreq::OpMsg>, durability: &Durability, dest: &Path, landed: usize) -> Finish {
    if landed == 0 {
        return Finish { ok: false, note: String::new() };
    }
    if durability.rclone {
        return Finish { ok: false, note: RCLONE_NOTE.to_string() };
    }
    if !durability.durable {
        return Finish { ok: false, note: String::new() };
    }
    let _ = tx.send(crate::backend::opsreq::OpMsg::Meta { line: writing_line(id, &drive_name(dest)) });
    if durability.file_failed {
        return Finish { ok: false, note: String::new() };
    }
    match durability.flush_dirs() {
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
pub fn test_set_fail_files(fail: bool) {
    FAIL_FILE.with(|v| v.set(fail));
}

#[cfg(test)]
pub fn test_mark_durable(path: &Path) {
    FORCE.with(|v| v.borrow_mut().push(path.to_path_buf()));
}

#[cfg(test)]
#[path = "durable_tests.rs"]
mod tests;
