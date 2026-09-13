use crate::backend::aliases::Aliases;
use crate::backend::icons::Names;
use crate::backend::kind::Kinds;
use crate::backend::meta::stat_range;
use crate::backend::mime::Db;
use crate::backend::fsinfo::dev_of;
use crate::backend::proto::listed_line;
use crate::backend::rows::rows_line;
use crate::backend::scan::scan;
use crate::backend::sort::sort_by_name;
use crate::backend::thumbspec::Thumbnailers;
use crate::error::{from_io, FleaError};
use std::fs::{self, OpenOptions};
use std::io::{BufWriter, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

// Owner-only: the listing names every file in the directory.
const PREWARM_MODE: u32 = 0o600;

// Overlaps Qt init instead of queueing behind it, see AGENTS.md "Prewarm".
pub fn write_prewarm(path: &str, first: usize, dest: &Path) -> Result<(), FleaError> {
    // The pid keeps two launchers off each other's file, see AGENTS.md "Predictable path writes".
    let tmp = PathBuf::from(format!("{}.{}.tmp", dest.display(), std::process::id()));
    let wrote = write_to_tmp(path, first, dest, &tmp);
    if wrote.is_err() {
        // Our own temp file only: dest is the caller's path and exit status is the contract.
        let _ = fs::remove_file(&tmp);
    }
    wrote
}

fn write_to_tmp(path: &str, first: usize, dest: &Path, tmp: &Path) -> Result<(), FleaError> {
    // Prewarm never asks for dotfiles: it mirrors list's own default, see docs/protocol.md.
    let (mut listing, read_ms) = scan(path, false)?;
    let sort_ms = sort_by_name(&mut listing, false);

    // corner: unlink our own leftover then create exclusively, see AGENTS.md.
    let _ = fs::remove_file(tmp);
    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(PREWARM_MODE)
        .open(tmp)
        .map_err(|e| from_io("prewarm", &tmp.display().to_string(), &e))?;
    let mut out = BufWriter::new(file);

    writeln!(out, "{}", listed_line(listing.len(), read_ms, sort_ms, dev_of(&PathBuf::from(path)), path, listing.longest_name()))
        .map_err(|e| from_io("prewarm", &tmp.display().to_string(), &e))?;
    let (metas, ms) = stat_range(&PathBuf::from(path), &listing, 0, first);
    // Its own copy: prewarm is one shot, so there is no loop to hoist the load out of.
    let (mime, icons, aliases) = (Db::load(), Names::load(), Aliases::load());
    let thumbs = Thumbnailers::load(&aliases);
    let mut kinds = Kinds::new();
    writeln!(out, "{}", rows_line(&listing, &metas, 0, ms, &mime, &icons, &aliases, &thumbs, &mut kinds))
        .map_err(|e| from_io("prewarm", &tmp.display().to_string(), &e))?;
    out.flush()
        .map_err(|e| from_io("prewarm", &tmp.display().to_string(), &e))?;
    drop(out);

    // Rename last, so the UI never reads a half-written file.
    fs::rename(tmp, dest).map_err(|e| from_io("prewarm", &dest.display().to_string(), &e))
}
