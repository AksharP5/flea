// The shelf's own file actions, Actions rule 1: every one is a `flea shelf` call, and they run the
// same Rust transfer engine, conflict handling, undo and trash the pane runs. Rule 2: no new file
// operation exists here, because one the pane cannot do would be a feature in the wrong place.
use crate::backend::archive::Formats;
use crate::backend::archiveops::compress;
use crate::backend::opsreq::{run_transfer_checked, transferdone_line, transferitem_line,
                             transferprogress_line, transferstarted_line, usable_dest, OpMsg};
use crate::backend::proto::error_line;
use crate::shelf::Shelf;
use crate::shelfplaces;
use crate::uistore;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::channel;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

const DIR: &str = "omarchy/flea-shelf";
const CANCEL: &str = "cancel";
// The card is another process and this binary carries no signal handling, so a cancel is a file the
// card writes and the transfer watches. Fast enough that esc feels immediate, slow enough to be free.
const CANCEL_POLL_MS: u64 = 100;

// flea shelf move|copy <dest> <path>...: the paths are what the card chose, because chosen-or-whole
// is the card's question and the answer crosses as an argument list rather than as a rule here.
pub fn transfer(moving: bool, rest: &[String]) -> i32 {
    let (dest, paths) = match rest.split_first() {
        Some((dest, paths)) if !paths.is_empty() => (dest, paths.to_vec()),
        _ => {
            eprintln!("flea: shelf move and copy take a destination, then the paths");
            return 2;
        }
    };
    let dest_name = dest.clone();
    let dest_dir = dest.clone();
    let dest = match usable_dest(dest) {
        Ok(dest) => dest,
        Err(e) => {
            println!("{}", error_line(&e));
            return 2;
        }
    };
    let shelf = match Shelf::user() {
        Ok(shelf) => shelf,
        Err(e) => {
            eprintln!("flea: {}", e);
            return 2;
        }
    };
    let cancel = Arc::new(AtomicBool::new(false));
    let marker = cancel_file();
    let _ = std::fs::remove_file(&marker);
    watch_cancel(&marker, &cancel);
    println!("{}", transferstarted_line(0, paths.len(), moving));
    let (tx, rx) = channel::<OpMsg>();
    let watched = paths.clone();
    let engine = {
        let cancel = Arc::clone(&cancel);
        thread::spawn(move || run_transfer_checked(0, moving, paths, dest, cancel, tx, None, None))
    };
    let (moved, failed) = report(rx, &watched, moving);
    let _ = engine.join();
    cancel.store(true, Ordering::Relaxed);
    let _ = std::fs::remove_file(&marker);
    // Main rule 10: a pinned row survives its own move, so its entry follows the file to the new
    // path while every other moved reference leaves the pile.
    let pinned = shelf.pinned_among(&moved);
    let followed: Vec<(String, String)> = pinned
        .iter()
        .map(|from| (from.clone(), moved_to(&dest_dir, from)))
        .collect();
    // Rule 4: a move empties what it moved and nothing else; a copy leaves the pile exactly as it was.
    if let Err(e) = shelf.settle(&moved) {
        eprintln!("flea: the shelf kept its references ({})", e);
    }
    if let Err(e) = shelf.repoint(&followed) {
        eprintln!("flea: a pin stayed on the old path ({})", e);
    }
    if let Err(e) = shelfplaces::remember(&dest_name) {
        eprintln!("flea: the destination was not remembered ({})", e);
    }
    i32::from(failed > 0)
}

// Where a moved file landed: the destination directory and the name it went in with, which is what
// a pin has to follow. A rename on collision is the engine's own and is not reported per item.
fn moved_to(dest: &str, from: &str) -> String {
    let name = Path::new(from).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    Path::new(dest).join(name).to_string_lossy().to_string()
}

// Every line the pane's own transfer prints, in the same vocabulary, so the card reads one protocol.
fn report(rx: std::sync::mpsc::Receiver<OpMsg>, paths: &[String], moving: bool) -> (Vec<String>, usize) {
    let mut moved = Vec::new();
    let mut failed = 0;
    for msg in rx {
        match msg {
            OpMsg::Progress { id, index, name, bytes, total, scanned } => {
                println!("{}", transferprogress_line(id, index, &name, bytes, total, scanned));
            }
            OpMsg::Item { id, index, name, ok, err } => {
                println!("{}", transferitem_line(id, index, &name, ok, &err));
                if !ok {
                    failed += 1;
                } else if moving {
                    if let Some(path) = paths.get(index) {
                        moved.push(path.clone());
                    }
                }
            }
            OpMsg::TransferDone { id, ok, failed: bad, skipped, cancelled, retry, .. } => {
                println!("{}", transferdone_line(id, ok, bad, skipped, cancelled, &retry));
            }
            _ => {}
        }
    }
    (moved, failed)
}

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
    let dir = archives_dir();
    if let Err(e) = uistore::make_dir(&dir) {
        eprintln!("flea: {}", e);
        return 2;
    }
    let dest = free_name(&dir, date);
    // The archive tool stages beside its sources and renames the result into place, so the archive is
    // written there first and relocated after: a pile on another filesystem cannot be renamed home.
    let staged = parent.join(format!(".{}", dest.file_name().unwrap_or_default().to_string_lossy()));
    let _ = std::fs::remove_file(&staged);
    if let Err(e) = compress(&Formats::probe(), &parent, &names, "zip", &staged) {
        println!("{}", error_line(&e));
        return 2;
    }
    if let Err(e) = relocate(&staged, &dest) {
        eprintln!("flea: {}", e);
        let _ = std::fs::remove_file(&staged);
        return 2;
    }
    // Rule 4: a zip replaces the ones it zipped with the one archive, so the pile says what happened.
    if let Err(e) = shelf.settle(&paths) {
        eprintln!("flea: the shelf kept its references ({})", e);
        return 2;
    }
    let archive = dest.to_string_lossy().to_string();
    if let Err(e) = shelf.add(&[archive.clone()]) {
        eprintln!("flea: {}", e);
        return 2;
    }
    println!("{}", archive);
    0
}

// A rename where the two are on one filesystem, and a copy where they are not, which is the case a
// pile gathered from /tmp or a mount produces.
fn relocate(from: &Path, to: &Path) -> Result<(), String> {
    if std::fs::rename(from, to).is_ok() {
        return Ok(());
    }
    std::fs::copy(from, to).map_err(|e| format!("the archive could not be put on the shelf ({:?})", e.kind()))?;
    std::fs::remove_file(from).map_err(|e| format!("the staged archive stayed behind ({:?})", e.kind()))
}

// shelf-2026-09-12.zip, and the second one that day is -2, because a name that silently replaced an
// archive would lose a pile nobody can get back.
fn free_name(dir: &std::path::Path, date: &str) -> PathBuf {
    let first = dir.join(format!("shelf-{}.zip", date));
    if first.symlink_metadata().is_err() {
        return first;
    }
    for n in 2..100 {
        let next = dir.join(format!("shelf-{}-{}.zip", date, n));
        if next.symlink_metadata().is_err() {
            return next;
        }
    }
    first
}

fn archives_dir() -> PathBuf {
    uistore::state_home().unwrap_or_else(|_| PathBuf::from("/tmp")).join(DIR).join("archives")
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

// flea shelf paths <path>...: newline joined absolute paths, the one thing a terminal-first operator
// actually wants from a pile. The card puts them on the clipboard, because a clipboard is a display.
pub fn paths(rest: &[String]) -> i32 {
    for path in rest {
        println!("{}", path);
    }
    0
}

// flea shelf send <peer> <path>...: Taildrop already ships in Flea, and a pile gathered from five
// folders is the best payload it will ever get. Rule 4: a send leaves the pile exactly as it was,
// because a send reports only by notification and nobody here knows whether it landed.
pub fn send(rest: &[String]) -> i32 {
    let (peer, paths) = match rest.split_first() {
        Some((peer, paths)) if !paths.is_empty() => (peer, paths.to_vec()),
        _ => {
            eprintln!("flea: shelf send takes a peer, then the paths");
            return 2;
        }
    };
    let finished = std::process::Command::new("omarchy-tailscale-send")
        .arg(peer)
        .args(&paths)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
    match finished {
        Ok(status) if status.success() => 0,
        Ok(_) => {
            eprintln!("flea: {} did not take that send", peer);
            2
        }
        Err(_) => {
            eprintln!("flea: this box has no omarchy-tailscale-send to send with");
            2
        }
    }
}

// flea shelf peers: the send flyout's rows. Sample input, the fields Taildrop.js reads of
// `tailscale status --json`: {"Peer":{"nodekey:aa":{"DNSName":"macbookair.tail1234.ts.net.","HostName":"macbookair","Online":true}}}
pub fn peers() -> i32 {
    let out = std::process::Command::new("tailscale")
        .arg("status")
        .arg("--json")
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output();
    let Ok(out) = out else { return 0 };
    if !out.status.success() {
        return 0;
    }
    for peer in peer_names(&String::from_utf8_lossy(&out.stdout)) {
        println!("{}", peer);
    }
    0
}

pub fn peer_names(status: &str) -> Vec<String> {
    let Ok(doc) = crate::jsondoc::parse(status) else { return Vec::new() };
    let Some(crate::jsondoc::Json::Obj(peers)) = doc.get("Peer") else { return Vec::new() };
    let mut out = Vec::new();
    for (_, peer) in peers {
        let dns = peer.get("DNSName").and_then(crate::jsondoc::Json::as_str).unwrap_or_default();
        let host = peer.get("HostName").and_then(crate::jsondoc::Json::as_str).unwrap_or_default();
        let name = if dns.is_empty() { host.to_string() } else { dns.trim_end_matches('.').to_string() };
        // An exit-node relay is never a send target, the same rule the OEM's own isMullvadPeer applies.
        if name.is_empty() || name.contains(".mullvad.ts.net") {
            continue;
        }
        out.push(name);
    }
    out.sort();
    out
}

// flea shelf cancel: esc in the card while an action runs, which the engine reads as its own cancel.
pub fn cancel() -> i32 {
    let marker = cancel_file();
    let dir = match marker.parent() {
        Some(dir) => dir,
        None => return 2,
    };
    if let Err(e) = uistore::make_dir(dir) {
        eprintln!("flea: {}", e);
        return 2;
    }
    match std::fs::write(&marker, "cancel\n") {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("flea: the cancel could not be written ({:?})", e.kind());
            2
        }
    }
}

fn watch_cancel(marker: &Path, cancel: &Arc<AtomicBool>) {
    let marker = marker.to_path_buf();
    let flag = Arc::clone(cancel);
    thread::spawn(move || {
        while !flag.load(Ordering::Relaxed) {
            if marker.symlink_metadata().is_ok() {
                flag.store(true, Ordering::Relaxed);
                return;
            }
            thread::sleep(Duration::from_millis(CANCEL_POLL_MS));
        }
    });
}

fn cancel_file() -> PathBuf {
    let home = uistore::state_home().unwrap_or_else(|_| PathBuf::from("/tmp"));
    home.join(DIR).join(CANCEL)
}

#[cfg(test)]
#[path = "shelfops_tests.rs"]
mod tests;
