// Where a shelf action can send files, which is Flea's own places list and not a second picker:
// the destinations this shelf used last, then Home, the XDG user directories and the bookmarks the
// rail already draws. Actions: recent destinations first, because the same folder is usually the
// answer twice running.
use crate::jsondoc::{self, Json};
use crate::uistore;
use std::fs;
use std::path::{Path, PathBuf};

const DIR: &str = "omarchy/flea-shelf";
const RECENTS: &str = "dests.json";
// Five, the same number of piles the card's own menu keeps, and the same reason: a list, not a log.
const KEPT: usize = 5;

pub fn file() -> PathBuf {
    uistore::state_home().unwrap_or_else(|_| PathBuf::from("/tmp")).join(DIR).join(RECENTS)
}

pub fn recents() -> Vec<String> {
    let text = fs::read_to_string(file()).unwrap_or_default();
    let doc = match jsondoc::parse(&text) {
        Ok(doc) => doc,
        Err(_) => return Vec::new(),
    };
    doc.get("dests")
        .and_then(Json::as_array)
        .map(|list| list.iter().filter_map(Json::as_str).map(String::from).collect())
        .unwrap_or_default()
}

// A destination used again moves to the front rather than appearing twice.
pub fn remember(dest: &str) -> Result<(), String> {
    let mut kept: Vec<String> = recents().into_iter().filter(|held| held != dest).collect();
    kept.insert(0, dest.to_string());
    kept.truncate(KEPT);
    let doc = Json::Obj(vec![(
        "dests".to_string(),
        Json::Arr(kept.into_iter().map(Json::Str).collect()),
    )]);
    let path = file();
    uistore::make_dir(path.parent().ok_or("the shelf has no directory to write in")?)?;
    uistore::replace(&path, &jsondoc::render(&doc))
}

// flea shelf places: one path per line, in the order the card offers them.
pub fn command() -> i32 {
    for place in places() {
        println!("{}", place);
    }
    0
}

pub fn places() -> Vec<String> {
    let home = std::env::var("HOME").unwrap_or_default();
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for dest in recents() {
        if Path::new(&dest).is_dir() && seen.insert(dest.clone()) {
            out.push(dest);
        }
    }
    if !home.is_empty() && seen.insert(home.clone()) {
        out.push(home.clone());
    }
    for dir in user_dirs(&fs::read_to_string(Path::new(&home).join(".config/user-dirs.dirs")).unwrap_or_default(), &home) {
        if dir != home && Path::new(&dir).is_dir() && seen.insert(dir.clone()) {
            out.push(dir);
        }
    }
    for mark in bookmarks(&fs::read_to_string(Path::new(&home).join(".config/gtk-3.0/bookmarks")).unwrap_or_default()) {
        if Path::new(&mark).is_dir() && seen.insert(mark.clone()) {
            out.push(mark);
        }
    }
    out
}

// flea shelf choose <title> [start]: the "Choose a folder" row of the destination flyout, which is
// Flea's own picker rather than a second one. It prints the directory that came back, and nothing at
// all when the operator pressed esc in it.
pub fn choose(rest: &[String]) -> i32 {
    let title = rest.first().map(String::as_str).unwrap_or("Choose a folder");
    let start = rest.get(1).map(String::as_str).unwrap_or("");
    let reply = uistore::state_home().unwrap_or_else(|_| PathBuf::from("/tmp")).join(DIR).join("reply.json");
    if let Err(e) = uistore::make_dir(reply.parent().unwrap_or(Path::new("/tmp"))) {
        eprintln!("flea: {}", e);
        return 2;
    }
    let _ = fs::remove_file(&reply);
    let request = Json::Obj(vec![
        ("mode".to_string(), Json::Str("open".to_string())),
        ("directory".to_string(), Json::Bool(true)),
        ("multiple".to_string(), Json::Bool(false)),
        ("title".to_string(), Json::Str(title.to_string())),
        ("folder".to_string(), Json::Str(start.to_string())),
    ]);
    let exe = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("flea"));
    let finished = std::process::Command::new(exe)
        .arg("--pick")
        .arg(&reply)
        .env("FLEA_PICKER", jsondoc::render(&request))
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .status();
    if finished.map(|s| !s.success()).unwrap_or(true) {
        eprintln!("flea: the chooser could not be opened");
        return 2;
    }
    let answer = fs::read_to_string(&reply).unwrap_or_default();
    let _ = fs::remove_file(&reply);
    if let Some(path) = chosen_dir(&answer) {
        println!("{}", path);
    }
    0
}

// Sample input, what the picker writes into its reply file:
// {"response":0,"uris":["file:///home/gm/Work"]}
pub fn chosen_dir(answer: &str) -> Option<String> {
    let doc = jsondoc::parse(answer).ok()?;
    if doc.get("response").and_then(Json::as_f64)? as i64 != 0 {
        return None;
    }
    let uri = doc.get("uris").and_then(Json::as_array)?.first().and_then(Json::as_str)?;
    let path = uri.strip_prefix("file://")?;
    Some(decode(path))
}

// Sample input, one line of ~/.config/user-dirs.dirs: XDG_DOWNLOAD_DIR="$HOME/Downloads"
pub fn user_dirs(text: &str, home: &str) -> Vec<String> {
    let mut out = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('#') || !line.starts_with("XDG_") {
            continue;
        }
        let Some((_, value)) = line.split_once('=') else { continue };
        let path = value.trim().trim_matches('"').replace("$HOME", home);
        let path = path.trim_end_matches('/').to_string();
        // corner: this box points TEMPLATES, PUBLICSHARE and DESKTOP at $HOME, which is not a place.
        if path.is_empty() || path == home {
            continue;
        }
        out.push(path);
    }
    out
}

// Sample input, one line of ~/.config/gtk-3.0/bookmarks: file:///home/gm/Work Work
pub fn bookmarks(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        // corner: a bookmark may be smb:// or sftp://, which is a location and not a folder here.
        if !line.starts_with("file://") {
            continue;
        }
        let uri = line.split_whitespace().next().unwrap_or_default();
        out.push(decode(&uri["file://".len()..]));
    }
    out
}

// Percent escapes, which a bookmarks file carries for every space in a path.
fn decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(byte) = u8::from_str_radix(&text[i + 1..i + 3], 16) {
                out.push(byte);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

#[cfg(test)]
#[path = "shelfplaces_tests.rs"]
mod tests;
