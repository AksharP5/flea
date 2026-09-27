// The gvfs early listing: the launcher starts gio while the window builds, and the
// backend's first scan of that path adopts the output instead of spawning gio itself.
// Local and USB launches do nothing past the is_gvfs prefix check in prepare.
use crate::backend::gvfslist;
use crate::backend::listing::Listing;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

// The launcher hands qs the prefetch file, the path it lists and the launch start in
// these variables, which the backend Process inherits; empty is absent throughout.
pub const PREFETCH_ENV: &str = "FLEA_GVFS_PREFETCH";
pub const PATH_ENV: &str = "FLEA_GVFS_PATH";
pub const START_ENV: &str = "FLEA_GVFS_START";
// A file older than this never names the launch's directory, so it is refused, not read.
const STALE_SECS: u64 = 10;
// A launch's leftovers stop being adoptable long before this reaps them.
const SWEEP_SECS: u64 = 60;
// The wait between dest polls while the prefetch child is still enumerating.
const POLL_MS: u64 = 20;
// A 10k NAS listing is about a megabyte; anything past this is not gio's output.
const MAX_BYTES: u64 = 64 * 1024 * 1024;
// A prefetch is adopted once: the file is deleted on read, and this stops a second
// listing from adopting one that arrived after the first listing's deadline passed.
static CONSUMED: AtomicBool = AtomicBool::new(false);
// Two prepares in one process still name different files.
static NEXT: AtomicU64 = AtomicU64::new(0);

// std already links the system libc, so the one symbol is declared here rather than taking a crate.
extern "C" {
    fn geteuid() -> u32;
}

// The one adoption the backend attempts: None unless the launcher named all three.
pub struct Prefetch {
    pub dest: PathBuf,
    pub path: String,
    pub start_ms: u64,
}

// Sample input: FLEA_GVFS_PATH "/run/user/1000/gvfs/smb-share:server=x,share=y/dir".
pub fn env_prefetch() -> Option<Prefetch> {
    let dest = std::env::var_os(PREFETCH_ENV).filter(|v| !v.is_empty()).map(PathBuf::from)?;
    let path = std::env::var(PATH_ENV).ok().filter(|v| !v.is_empty())?;
    let start_ms = std::env::var(START_ENV).ok()?.parse::<u64>().ok()?;
    Some(Prefetch { dest, path, start_ms })
}

// $XDG_RUNTIME_DIR/flea, or None when the session names none.
pub fn runtime_dir() -> Option<PathBuf> {
    let root = std::env::var_os("XDG_RUNTIME_DIR").filter(|v| !v.is_empty())?;
    Some(PathBuf::from(root).join("flea"))
}

// A directory this user owns and only this user can enter; anything else refuses the prefetch.
fn check_dir(dir: &Path) -> Result<(), String> {
    let meta = std::fs::symlink_metadata(dir)
        .map_err(|e| format!("gvfs prefetch dir {} could not be read ({:?})", dir.display(), e.kind()))?;
    if meta.file_type().is_symlink() {
        return Err(format!("gvfs prefetch dir {} is a symlink", dir.display()));
    }
    if !meta.is_dir() {
        return Err(format!("gvfs prefetch dir {} is not a directory", dir.display()));
    }
    if meta.mode() & 0o777 != 0o700 {
        return Err(format!("gvfs prefetch dir {} is not 0700", dir.display()));
    }
    if meta.uid() != unsafe { geteuid() } {
        return Err(format!("gvfs prefetch dir {} is not owned by this user", dir.display()));
    }
    Ok(())
}

// Our own runtime dir, created when missing and refused when wrong; never repaired.
fn ensure_dir(dir: &Path) -> Result<(), String> {
    if std::fs::symlink_metadata(dir).is_err() {
        std::fs::create_dir_all(dir)
            .map_err(|e| format!("gvfs prefetch dir {} could not be created ({:?})", dir.display(), e.kind()))?;
        std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700))
            .map_err(|e| format!("gvfs prefetch dir {} could not be made 0700 ({:?})", dir.display(), e.kind()))?;
    }
    check_dir(dir)
}

// A previous launch's leftovers, reaped by age; best effort, so errors are ignored.
fn sweep_dir(dir: &Path, now: SystemTime) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        if !entry.file_name().to_string_lossy().starts_with("gvfs-") {
            continue;
        }
        let path = entry.path();
        let keep = std::fs::symlink_metadata(&path)
            .ok()
            .filter(|meta| !meta.file_type().is_symlink() && meta.is_file())
            .and_then(|meta| meta.modified().ok())
            .and_then(|mtime| now.duration_since(mtime).ok())
            .is_some_and(|age| age <= Duration::from_secs(SWEEP_SECS));
        if !keep {
            let _ = std::fs::remove_file(&path);
        }
    }
}

// The launcher's side: our dir, last launch's leftovers gone, this launch's file named.
// None means local rules: no gvfs path, no runtime dir, or a dir that is not ours.
pub fn prepare(path: &str) -> Option<(PathBuf, u64)> {
    if !gvfslist::is_gvfs(Path::new(path)) {
        return None;
    }
    let dir = runtime_dir()?;
    ensure_dir(&dir).ok()?;
    let now = SystemTime::now();
    sweep_dir(&dir, now);
    let start_ms = now.duration_since(UNIX_EPOCH).ok()?.as_millis() as u64;
    let n = NEXT.fetch_add(1, Ordering::Relaxed);
    let dest = dir.join(format!("gvfs-{}-{}-{}.list", std::process::id(), start_ms, n));
    Some((dest, start_ms))
}

// The enumeration starts while the window builds; the child outlives the exec below it.
pub fn spawn(path: &str, dest: &Path) {
    let Ok(exe) = std::env::current_exe() else { return };
    let _ = Command::new(exe)
        .arg("--gvfs-prefetch")
        .arg(path)
        .arg(dest)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn();
}

// flea --gvfs-prefetch <path> <dest>: the same gio call the backend would make, with hidden
// entries included so either hidden setting can adopt it. 0 published, 1 gio or the write
// failed and dest is untouched, 2 the request itself is refused.
pub fn run(path: &str, dest: &Path, gio: &str) -> i32 {
    run_in(path, dest, gio, runtime_dir().as_deref())
}

// Split so a test can name the runtime dir without touching this process's environment.
pub(crate) fn run_in(path: &str, dest: &Path, gio: &str, runtime: Option<&Path>) -> i32 {
    let Some(dir) = dest.parent() else {
        eprintln!("flea: gvfs prefetch destination has no parent directory");
        return 2;
    };
    // dest must be a fresh name inside our own runtime dir, never an arbitrary path.
    if Some(dir) != runtime {
        eprintln!("flea: gvfs prefetch destination {} is not inside the runtime dir", dest.display());
        return 2;
    }
    if !gvfslist::is_gvfs(Path::new(path)) {
        eprintln!("flea: gvfs prefetch needs a gvfs path, got {}", path);
        return 2;
    }
    if let Err(e) = check_dir(dir) {
        eprintln!("flea: {}", e);
        return 2;
    }
    match gvfslist::raw_output(path, true, gio, gvfslist::GIO_TIMEOUT) {
        Ok(bytes) => match publish(dest, &bytes) {
            Ok(()) => 0,
            Err(e) => {
                eprintln!("flea: {}", e);
                1
            }
        },
        Err(e) => {
            eprintln!("flea: gvfs prefetch for {} failed ({}), the window lists it itself", path, e);
            1
        }
    }
}

// Our own temp file, created exclusively at 0600, then a rename; only gio's exit 0 reaches here,
// so a reader never sees a partial file.
fn publish(dest: &Path, bytes: &[u8]) -> Result<(), String> {
    let tmp = PathBuf::from(format!("{}.{}.tmp", dest.display(), std::process::id()));
    let _ = std::fs::remove_file(&tmp);
    let written = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&tmp)
        .map_err(|e| format!("gvfs prefetch temp {} could not be created ({:?})", tmp.display(), e.kind()))
        .and_then(|mut file| {
            use std::io::Write;
            file.write_all(bytes)
                .map_err(|e| format!("gvfs prefetch temp {} could not be written ({:?})", tmp.display(), e.kind()))
        })
        .and_then(|()| {
            std::fs::rename(&tmp, dest)
                .map_err(|e| format!("gvfs prefetch {} could not be published ({:?})", dest.display(), e.kind()))
        });
    if written.is_err() {
        let _ = std::fs::remove_file(&tmp);
    }
    written
}

// The backend's first gvfs scan of exactly the prefetched path waits for the file up to the
// launch's deadline, parses it with gvfslist's parser, deletes it and never reads it again.
// Anything else answers None and the scan takes today's gio path unchanged.
pub(crate) fn adopt_matching(path: &str, hidden: bool, prefetch: &Prefetch) -> Option<(Listing, f64)> {
    if prefetch.path != path {
        return None;
    }
    if CONSUMED.swap(true, Ordering::SeqCst) {
        return None;
    }
    let deadline = UNIX_EPOCH + Duration::from_millis(prefetch.start_ms) + gvfslist::GIO_TIMEOUT;
    adopt(path, hidden, &prefetch.dest, deadline)
}

pub(crate) fn adopt(path: &str, hidden: bool, dest: &Path, deadline: SystemTime) -> Option<(Listing, f64)> {
    adopt_in(path, hidden, dest, deadline, SystemTime::now(), runtime_dir().as_deref())
}

// Split so a test can name the clock and the runtime dir without touching the environment.
pub(crate) fn adopt_in(
    path: &str,
    hidden: bool,
    dest: &Path,
    deadline: SystemTime,
    now: SystemTime,
    runtime: Option<&Path>,
) -> Option<(Listing, f64)> {
    let t = Instant::now();
    // The file may still be enumerating; wait for it, but never past the launch's own deadline.
    loop {
        if std::fs::symlink_metadata(dest).is_ok() {
            break;
        }
        if SystemTime::now() >= deadline {
            return None;
        }
        std::thread::sleep(Duration::from_millis(POLL_MS));
    }
    let bytes = read_prefetch(dest, now, runtime)?;
    let _ = std::fs::remove_file(dest);
    let text = String::from_utf8(bytes).ok()?;
    Some((gvfslist::build_listing(&text, hidden, path).ok()?, t.elapsed().as_secs_f64() * 1000.0))
}

// The checks a reader applies before trusting a file it did not write itself.
fn read_prefetch(dest: &Path, now: SystemTime, runtime: Option<&Path>) -> Option<Vec<u8>> {
    // The file must live in our own runtime dir, or it is not this launch's.
    let dir = dest.parent()?;
    if Some(dir) != runtime {
        return None;
    }
    check_dir(dir).ok()?;
    let meta = std::fs::symlink_metadata(dest).ok()?;
    // A planted symlink is refused rather than followed; the open below repeats the refusal.
    if meta.file_type().is_symlink() || !meta.is_file() {
        return None;
    }
    if meta.uid() != unsafe { geteuid() } {
        return None;
    }
    // Older than a few seconds is a previous launch's, swept but not yet gone.
    let age = now.duration_since(meta.modified().ok()?).ok()?;
    if age > Duration::from_secs(STALE_SECS) {
        return None;
    }
    if meta.len() > MAX_BYTES {
        return None;
    }
    let file = std::fs::OpenOptions::new().read(true).custom_flags(crate::oflags::O_NOFOLLOW).open(dest).ok()?;
    if !file.metadata().ok()?.is_file() {
        return None;
    }
    let mut bytes = Vec::new();
    use std::io::Read;
    file.take(MAX_BYTES + 1).read_to_end(&mut bytes).ok()?;
    if bytes.len() as u64 > MAX_BYTES {
        return None;
    }
    Some(bytes)
}

#[cfg(test)]
#[path = "gvfsprefetch_tests.rs"]
mod tests;
