// flea shelf zip: a pile becomes one archive, on the shelf rather than in a folder the operator then
// has to find. Split from shelfops.rs at the 400 line cap, the seam between the transfer verbs and
// this one.
use crate::backend::archive::Formats;
use crate::backend::archiveops::compress;
use crate::backend::proto::error_line;
use crate::shelf::Shelf;
use crate::uistore;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

const DIR: &str = "omarchy/flea-shelf";
// The mode uistore writes its own files at, because a probe is a file this process alone ever sees.
const OWNER_ONLY_FILE: u32 = 0o600;

// flea shelf zip <date> <path>...: the four become one, and the archive is on the shelf rather than
// written to a folder the operator then has to find. A pile spans folders, which is exactly the case
// the pane's own compress refuses, so the names are taken relative to their own common ancestor.
pub fn zip(rest: &[String]) -> i32 {
    let (date, paths) = match rest.split_first() {
        Some((date, paths)) if !paths.is_empty() => (date.as_str(), paths.to_vec()),
        _ => {
            eprintln!("flea: shelf zip takes today's date, then the paths");
            return 2;
        }
    };
    if !date.chars().all(|c| c.is_ascii_digit() || c == '-') || date.is_empty() {
        eprintln!("flea: shelf zip takes a date, which is digits and dashes");
        return 2;
    }
    if let Some(relative) = paths.iter().find(|path| !Path::new(path).is_absolute()) {
        eprintln!("flea: shelf zip takes absolute paths, and {} is not one", relative);
        return 2;
    }
    let shelf = match Shelf::user() {
        Ok(shelf) => shelf,
        Err(e) => {
            eprintln!("flea: {}", e);
            return 2;
        }
    };
    let (parent, names) = match relative_to_ancestor(&paths) {
        Some(split) => split,
        None => {
            eprintln!("flea: those paths have no directory in common to archive them from");
            return 2;
        }
    };
    let dir = match archives_dir() {
        Ok(dir) => dir,
        Err(e) => {
            eprintln!("flea: {}", e);
            return 2;
        }
    };
    if let Err(e) = uistore::make_dir(&dir) {
        eprintln!("flea: {}", e);
        return 2;
    }
    if let Err(e) = writable(&parent) {
        eprintln!("flea: {}", e);
        return 2;
    }
    let dest = match free_name(&dir, date) {
        Some(dest) => dest,
        None => {
            eprintln!("flea: there are already a hundred shelf archives for {}", date);
            return 2;
        }
    };
    // The archive tool stages beside its sources and renames the result into place, so the archive is
    // written there first and relocated after: a pile on another filesystem cannot be renamed home.
    let staged = parent.join(format!(".flea-shelf-{}-{}.zip", std::process::id(), date));
    if let Err(e) = compress(&Formats::probe(), &parent, &names, "zip", &staged) {
        eprintln!("flea: {}", error_line(&e));
        let _ = std::fs::remove_file(&staged);
        let _ = std::fs::remove_file(&dest);
        return 2;
    }
    if let Err(e) = relocate(&staged, &dest) {
        eprintln!("flea: {}", e);
        let _ = std::fs::remove_file(&staged);
        let _ = std::fs::remove_file(&dest);
        return 2;
    }
    // Rule 4: a zip replaces the ones it zipped with the one archive, so the pile says what happened.
    let archive = dest.to_string_lossy().to_string();
    // The archive is on disk from here, so its path is printed before the shelf's own bookkeeping:
    // a refusal after this point must still tell the operator where the file went.
    println!("{}", archive);
    let mut kept = 0;
    if let Err(e) = shelf.settle(&paths) {
        eprintln!("flea: the shelf kept its references ({})", e);
        kept = 2;
    }
    if let Err(e) = shelf.add(&[archive]) {
        eprintln!("flea: {}", e);
        kept = 2;
    }
    kept
}

// The archive tool works inside the sources' own directory, so a pile whose only common ancestor is
// one nobody can write in cannot be archived there, and saying which is the whole of the answer.
fn writable(parent: &Path) -> Result<(), String> {
    let probe = parent.join(format!(".flea-shelf-probe-{}", std::process::id()));
    let _ = std::fs::remove_file(&probe);
    // Exclusively, the way uistore::write_new creates: a name left at this path by somebody else is
    // refused rather than followed and truncated.
    std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(OWNER_ONLY_FILE)
        .open(&probe)
        .map_err(|e| format!("{} is the only directory those paths have in common, and it cannot be written in ({:?})",
                             parent.display(), e.kind()))?;
    let _ = std::fs::remove_file(&probe);
    Ok(())
}

// A rename where the two are on one filesystem, and a copy where they are not, which is the case a
// pile gathered from /tmp or a mount produces.
fn relocate(from: &Path, to: &Path) -> Result<(), String> {
    if std::fs::rename(from, to).is_ok() {
        return Ok(());
    }
    if let Err(e) = std::fs::copy(from, to) {
        // A failed copy leaves a partial at the destination, and that name would stay spent.
        let _ = std::fs::remove_file(to);
        return Err(format!("the archive could not be put on the shelf ({:?})", e.kind()));
    }
    if let Err(e) = std::fs::remove_file(from) {
        eprintln!("flea: the staged archive stayed behind at {} ({:?})", from.display(), e.kind());
    }
    Ok(())
}

// shelf-2026-09-12.zip, and the second one that day is -2, because a name that silently replaced an
// archive would lose a pile nobody can get back.
fn free_name(dir: &std::path::Path, date: &str) -> Option<PathBuf> {
    let first = dir.join(format!("shelf-{}.zip", date));
    if reserve(&first) {
        return Some(first);
    }
    for n in 2..=ARCHIVES_A_DAY {
        let next = dir.join(format!("shelf-{}-{}.zip", date, n));
        if reserve(&next) {
            return Some(next);
        }
    }
    None
}

// The name is taken by creating it exclusively, so two zips of one date cannot pick the same one and
// the second archive cannot land on the first. The caller removes it again if nothing is written.
fn reserve(path: &Path) -> bool {
    std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(OWNER_ONLY_FILE)
        .open(path)
        .is_ok()
}

// A hundred archives of one date is not a case this product has, and the alternative to a ceiling
// here is a name that silently replaces one.
const ARCHIVES_A_DAY: u32 = 100;

fn archives_dir() -> Result<PathBuf, String> {
    Ok(uistore::state_home()?.join(DIR).join("archives"))
}

// The deepest directory every path is under, and each path spelled from it, which is what an archive
// of a pile has to carry so two files of the same name from two folders stay two files.
pub fn relative_to_ancestor(paths: &[String]) -> Option<(PathBuf, Vec<String>)> {
    let first = Path::new(paths.first()?).parent()?.to_path_buf();
    let mut ancestor = first;
    for path in paths.iter().skip(1) {
        let parent = Path::new(path).parent()?;
        while !parent.starts_with(&ancestor) {
            ancestor = ancestor.parent()?.to_path_buf();
        }
    }
    let mut names = Vec::new();
    for path in paths {
        names.push(Path::new(path).strip_prefix(&ancestor).ok()?.to_string_lossy().to_string());
    }
    Some((ancestor, names))
}

#[cfg(test)]
#[path = "shelfzip_tests.rs"]
mod tests;
