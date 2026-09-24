// The runtime directory a tree-copy manifest lives on: any filesystem but the copy's own.
use std::os::unix::fs::{DirBuilderExt, MetadataExt};
use std::path::{Path, PathBuf};

extern "C" {
    fn getuid() -> u32;
}

// Owner-only manifest directory, so a planted symlink cannot redirect the anonymous file.
const MANIFEST_MODE: u32 = 0o700;

pub fn current_uid() -> u32 {
    unsafe { getuid() }
}

// Sample input: XDG_RUNTIME_DIR=/run/user/1000 gives /run/user/1000/flea.
pub fn candidate_dirs(uid: u32) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Some(runtime) = crate::userfile::env_dir("XDG_RUNTIME_DIR") {
        out.push(runtime.join("flea"));
    }
    out.push(PathBuf::from(format!("/run/user/{uid}/flea")));
    out.push(PathBuf::from(format!("/dev/shm/flea-{uid}")));
    out.push(std::env::temp_dir().join("flea"));
    out
}

// Nearest existing ancestor's device, so a destination that does not exist yet still forbids its filesystem.
pub fn existing_dev(path: &Path) -> Option<u64> {
    let mut cur: Option<&Path> = Some(path);
    while let Some(p) = cur {
        if let Ok(meta) = p.symlink_metadata() {
            return Some(meta.dev());
        }
        cur = p.parent();
    }
    None
}

// An existing directory this uid owns at mode 0700 is reused; anything else is skipped, never repaired.
fn ensure_owned(dir: &Path, uid: u32) -> bool {
    use std::os::unix::fs::PermissionsExt;
    match dir.symlink_metadata() {
        Ok(meta) => {
            meta.is_dir()
                && !meta.file_type().is_symlink()
                && meta.uid() == uid
                && meta.permissions().mode() & 0o777 == MANIFEST_MODE
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            // Created owner-only, then re-read rather than trusted, so a planted symlink loses.
            std::fs::DirBuilder::new().recursive(true).mode(MANIFEST_MODE).create(dir).is_ok()
                && matches!(dir.symlink_metadata(), Ok(meta) if meta.is_dir() && !meta.file_type().is_symlink() && meta.uid() == uid)
        }
        Err(_) => false,
    }
}

// First candidate on neither forbidden device wins; every other is skipped, and none qualifying is an error.
#[cfg(test)]
pub fn pick(candidates: &[PathBuf], forbid: &[u64], uid: u32) -> Result<PathBuf, String> {
    qualifying_dirs(candidates, forbid, uid)
        .into_iter()
        .next()
        .ok_or_else(|| "no runtime directory for the copy manifest stays off the copy filesystems".into())
}

// Every candidate that qualifies, in order, so a caller can try each one until it holds an anonymous file.
pub fn qualifying_dirs(candidates: &[PathBuf], forbid: &[u64], uid: u32) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for dir in candidates {
        if !ensure_owned(dir, uid) {
            continue;
        }
        match dir.symlink_metadata() {
            Ok(meta) if !forbid.contains(&meta.dev()) => out.push(dir.clone()),
            _ => {}
        }
    }
    out
}

// The devices one copy must stay off: its source's and its destination's, the destination read through
// its nearest existing parent because it rarely exists yet.
pub fn forbid_for(src: &Path, dst: &Path) -> Vec<u64> {
    let mut forbid = Vec::new();
    if let Some(dev) = existing_dev(src) {
        forbid.push(dev);
    }
    if let Some(dev) = existing_dev(dst) {
        if !forbid.contains(&dev) {
            forbid.push(dev);
        }
    }
    forbid
}

#[cfg(test)]
#[path = "manifestdir_tests.rs"]
mod tests;
