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
    // The write leg answering EINVAL, so the copy falls back to the final fsync.
    static FAIL_RANGE_WRITE: Cell<bool> = const { Cell::new(false) };
    // The wait leg answering this errno, 0 for no failure.
    static FAIL_RANGE_WAIT: Cell<i32> = const { Cell::new(0) };
    // Completed slice waits, so a test pins reports against waits.
    static RANGE_WAITS: Cell<usize> = const { Cell::new(0) };
    // Range calls in order, so a test pins the pipelined sequence.
    static RANGE_LOG: RefCell<Vec<String>> = const { RefCell::new(Vec::new()) };
    // The syncfs leg answering failure, so a batch confirm keeps every source.
    static FAIL_SYNCFS: Cell<bool> = const { Cell::new(false) };
    // Completed syncfs calls, so a batch pins one per confirm.
    static SYNCFS_FLUSHES: Cell<usize> = const { Cell::new(0) };
    // Files released on the calling thread, so scoped closes still count.
    static RELEASES: Cell<usize> = const { Cell::new(0) };
    // Release, syncfs, folder and removal steps in order, so a batch pins its sequence.
    static ORDER_LOG: RefCell<Vec<String>> = const { RefCell::new(Vec::new()) };
}

// errno 22 means no range writeback, not a lost byte; errno 5 is a drive refusing bytes.
pub(crate) const EINVAL: i32 = 22;
#[cfg(test)]
pub(crate) const EIO: i32 = 5;

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

// Sample input: "/dev/sda1" trues, "remote:" falses.
fn source_is_block(source: &str) -> bool {
    source.starts_with("/dev/")
}

// Sample input: ("/media/stick", "vfat /dev/sda1") trues, ("cifs //nas/media") falses.
pub(crate) fn batch_syncfs_for(dest: &Path, body: &str, durable: bool, rclone: bool) -> bool {
    if !durable || rclone {
        return false;
    }
    match crate::backend::mountinfo::mount_entry_in(dest, body) {
        Some(e) => source_is_block(&e.source) && fat_name_is_durable(&e.fstype),
        None => false,
    }
}

// The done line's own words for a folder the drive would not confirm, printable as-is.
pub const DIR_UNCONFIRMED: &str = "copied, but the drive did not confirm the folder";

// 64 held files bound one unconfirmed batch, the same bound movebatch closes on.
const HELD_CAP: usize = 64;

// The done line's own words for a copy onto rclone, printable as-is.
pub const RCLONE_NOTE: &str = "rclone uploads them in the background";

// One operation's durability, created from its destination and carried down through Progress.
pub struct Durability {
    pub durable: bool,
    pub rclone: bool,
    pub file_failed: bool,
    pub batch_syncfs: bool,
    held: Vec<std::fs::File>,
    touched: HashSet<PathBuf>,
    last: Option<PathBuf>,
}

impl Durability {
    // Classified once per operation, never per file; rclone stays non-durable to keep its upload in the background.
    pub fn begin(dest: &Path) -> Durability {
        let rclone = dest_is_rclone(dest);
        let durable = !rclone && dest_is_durable(dest);
        let batch_syncfs = match std::fs::read_to_string("/proc/self/mountinfo") {
            Ok(body) => batch_syncfs_for(dest, &body, durable, rclone),
            Err(_) => false,
        };
        Durability { durable, rclone, file_failed: false, batch_syncfs, held: Vec::new(),
            touched: HashSet::new(), last: None }
    }

    // A landed file stays open until its batch confirms, so 64 closes land at once.
    pub fn hold(&mut self, file: std::fs::File) {
        self.held.push(file);
        if self.held.len() >= HELD_CAP {
            self.release_held();
        }
    }

    // Each held close runs on its own scoped thread, so one 100 ms vfat close never waits on another.
    pub fn release_held(&mut self) {
        if self.held.is_empty() {
            return;
        }
        let files: Vec<std::fs::File> = std::mem::take(&mut self.held);
        #[cfg(test)]
        {
            RELEASES.with(|v| v.set(v.get() + files.len()));
            ORDER_LOG.with(|v| v.borrow_mut().extend(files.iter().map(|_| "release".to_string())));
        }
        std::thread::scope(|s| {
            for file in files {
                s.spawn(move || drop(file));
            }
        });
    }

    // A test pins the held count without touching the descriptors.
    #[cfg(test)]
    pub(crate) fn held_len(&self) -> usize {
        self.held.len()
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

    // One confirm for a whole move batch: every touched folder any of its items filled, flushed once.
    pub fn flush_dirs_for_many(&self, dsts: &[PathBuf]) -> std::io::Result<()> {
        let mut first: Option<std::io::Error> = None;
        for dir in self.ordered() {
            let wanted = dsts.iter().any(|dst| dir.starts_with(dst) || Some(dir.as_path()) == dst.parent());
            if wanted {
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
    #[cfg(test)]
    RANGE_LOG.with(|v| v.borrow_mut().push("fsync".to_string()));
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
    fn syncfs(fd: i32) -> i32;
}

// One written slice starts its writeback without waiting, so the next slice writes while it flies.
pub fn sync_range_write(f: &std::fs::File, offset: u64, len: u64) -> std::io::Result<()> {
    #[cfg(test)]
    RANGE_LOG.with(|v| v.borrow_mut().push(format!("write {offset}")));
    #[cfg(test)]
    if FAIL_RANGE_WRITE.with(|v| v.get()) {
        return Err(std::io::Error::from_raw_os_error(EINVAL));
    }
    if seam_flush(false) {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "simulated fsync failure"));
    }
    use std::os::unix::io::AsRawFd;
    let rc = unsafe { sync_file_range(f.as_raw_fd(), offset as i64, len as i64, SYNC_FILE_RANGE_WRITE) };
    if rc == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

// One written slice is confirmed to the drive; a failure refuses the bytes the same way an fsync failure does.
pub fn sync_range(f: &std::fs::File, offset: u64, len: u64) -> std::io::Result<()> {
    #[cfg(test)]
    RANGE_LOG.with(|v| v.borrow_mut().push(format!("wait {offset}")));
    #[cfg(test)]
    {
        let errno = FAIL_RANGE_WAIT.with(|v| v.get());
        if errno != 0 {
            return Err(std::io::Error::from_raw_os_error(errno));
        }
    }
    if seam_flush(false) {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "simulated fsync failure"));
    }
    use std::os::unix::io::AsRawFd;
    let flags = SYNC_FILE_RANGE_WAIT_BEFORE | SYNC_FILE_RANGE_WRITE | SYNC_FILE_RANGE_WAIT_AFTER;
    let rc = unsafe { sync_file_range(f.as_raw_fd(), offset as i64, len as i64, flags) };
    if rc == 0 {
        #[cfg(test)]
        RANGE_WAITS.with(|v| v.set(v.get() + 1));
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

// EINVAL, ESPIPE, ENOSYS and EOPNOTSUPP say the filesystem has no range writeback, not that a byte was lost.
pub fn range_unsupported(e: &std::io::Error) -> bool {
    const ESPIPE: i32 = 29;
    const ENOSYS: i32 = 38;
    const EOPNOTSUPP: i32 = 95;
    matches!(e.raw_os_error(), Some(EINVAL) | Some(ESPIPE) | Some(ENOSYS) | Some(EOPNOTSUPP))
}

pub fn fsync_dir(path: &Path) -> std::io::Result<()> {
    if seam_flush(true) {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "simulated fsync failure"));
    }
    // Logged after the counting seam, so a failed flush never reads as confirmed.
    #[cfg(test)]
    ORDER_LOG.with(|v| v.borrow_mut().push("dir".to_string()));
    std::fs::File::open(path)?.sync_all()
}

// One filesystem-wide confirm after a batch's closes, so vfat's per-close flush never runs.
pub fn syncfs_dir(path: &Path) -> std::io::Result<()> {
    #[cfg(test)]
    {
        SYNCFS_FLUSHES.with(|v| v.set(v.get() + 1));
        ORDER_LOG.with(|v| v.borrow_mut().push("syncfs".to_string()));
        if FAIL_SYNCFS.with(|v| v.get()) {
            return Err(std::io::Error::new(std::io::ErrorKind::Other, "simulated syncfs failure"));
        }
    }
    use std::os::unix::io::AsRawFd;
    let file = std::fs::File::open(path)?;
    let rc = unsafe { syncfs(file.as_raw_fd()) };
    if rc == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
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

// After the last landed file: one writing line, then the batch syncfs, then every touched directory.
pub fn finish(id: usize, tx: &std::sync::mpsc::Sender<crate::backend::opsreq::OpMsg>, durability: &mut Durability, dest: &Path, landed: usize) -> Finish {
    if durability.batch_syncfs {
        durability.release_held();
    }
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
    // No destination fd stays open at transferdone, so an eject right after never waits on one.
    if durability.batch_syncfs && syncfs_dir(dest).is_err() {
        return Finish { ok: false, note: DIR_UNCONFIRMED.to_string() };
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
    FAIL_RANGE_WRITE.with(|v| v.set(false));
    FAIL_RANGE_WAIT.with(|v| v.set(0));
    RANGE_WAITS.with(|v| v.set(0));
    RANGE_LOG.with(|v| v.borrow_mut().clear());
    FAIL_SYNCFS.with(|v| v.set(false));
    SYNCFS_FLUSHES.with(|v| v.set(0));
    RELEASES.with(|v| v.set(0));
    ORDER_LOG.with(|v| v.borrow_mut().clear());
}

#[cfg(test)]
pub fn test_reset_counts() {
    FAIL_FILE.with(|v| v.set(false));
    FAIL_DIR.with(|v| v.set(false));
    FILE_FLUSHES.with(|v| v.set(0));
    DIR_FLUSHES.with(|v| v.set(0));
    FAIL_RANGE_WRITE.with(|v| v.set(false));
    FAIL_RANGE_WAIT.with(|v| v.set(0));
    RANGE_WAITS.with(|v| v.set(0));
    RANGE_LOG.with(|v| v.borrow_mut().clear());
    FAIL_SYNCFS.with(|v| v.set(false));
    SYNCFS_FLUSHES.with(|v| v.set(0));
    RELEASES.with(|v| v.set(0));
    ORDER_LOG.with(|v| v.borrow_mut().clear());
}

#[cfg(test)]
pub fn test_counts() -> (usize, usize) {
    (FILE_FLUSHES.with(|v| v.get()), DIR_FLUSHES.with(|v| v.get()))
}

// A batch_syncfs confirm counts one syncfs beside its file and folder counts.
#[cfg(test)]
pub fn test_syncfs_count() -> usize {
    SYNCFS_FLUSHES.with(|v| v.get())
}

// Closes counted on the calling thread, so scoped threads never hide one.
#[cfg(test)]
pub fn test_releases() -> usize {
    RELEASES.with(|v| v.get())
}

// Release, syncfs, folder and removal steps in the order they ran.
#[cfg(test)]
pub fn test_order() -> Vec<String> {
    ORDER_LOG.with(|v| v.borrow().clone())
}

// One ordered step from outside this module, so a batch pins a removal after its folder.
#[cfg(test)]
pub(crate) fn test_log(step: &str) {
    ORDER_LOG.with(|v| v.borrow_mut().push(step.to_string()));
}

#[cfg(test)]
pub fn test_range_waits() -> usize {
    RANGE_WAITS.with(|v| v.get())
}

#[cfg(test)]
pub fn test_range_log() -> Vec<String> {
    RANGE_LOG.with(|v| v.borrow().clone())
}

// The write leg answers EINVAL, so the copy falls back to the final fsync.
#[cfg(test)]
pub fn test_set_fail_range_write(fail: bool) {
    FAIL_RANGE_WRITE.with(|v| v.set(fail));
}

// The wait leg answers this errno, 0 clears it.
#[cfg(test)]
pub fn test_set_fail_range_wait(errno: i32) {
    FAIL_RANGE_WAIT.with(|v| v.set(errno));
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

// The syncfs leg answers failure, so a batch keeps every source.
#[cfg(test)]
pub fn test_set_fail_syncfs(fail: bool) {
    FAIL_SYNCFS.with(|v| v.set(fail));
}

#[cfg(test)]
pub fn test_mark_durable(path: &Path) {
    FORCE.with(|v| v.borrow_mut().push(path.to_path_buf()));
}

#[cfg(test)]
#[path = "durable_tests.rs"]
mod tests;
