// The captures Omarchy has just taken, which is the one file a shelf is most often asked to hand
// onward. The directories resolve exactly the way omarchy-capture-screenshot and
// omarchy-capture-screenrecording resolve them: the environment first, then ~/.config/user-dirs.dirs,
// then the defaults. ShelfEmpty rule 4: a missing directory is an empty tray and never an error.
use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

const SCREENSHOT_PREFIX: &str = "screenshot-";
const SCREENSHOT_SUFFIX: &str = ".png";
const RECORDING_PREFIX: &str = "screenrecording-";
const RECORDING_SUFFIX: &str = ".mp4";
// ShelfEmpty rule 7: the tray is a setting between none and six, so this is the ceiling it can ask for.
pub const MAX_CAPTURES: usize = 6;

pub struct Capture {
    pub path: String,
    pub mtime_ms: u64,
}

pub fn newest(count: usize) -> Vec<Capture> {
    let mut found = Vec::new();
    collect(&screenshot_dir(), SCREENSHOT_PREFIX, SCREENSHOT_SUFFIX, &mut found);
    collect(&recording_dir(), RECORDING_PREFIX, RECORDING_SUFFIX, &mut found);
    newest_of(found, count)
}

// The merge and the cut, kept apart from the filesystem so a test can hand it its own entries.
pub fn newest_of(mut found: Vec<Capture>, count: usize) -> Vec<Capture> {
    found.sort_by(|a, b| b.mtime_ms.cmp(&a.mtime_ms).then_with(|| a.path.cmp(&b.path)));
    found.truncate(count.min(MAX_CAPTURES));
    found
}

// Only the names the capture scripts write: a shelf tray is not a listing of the pictures directory.
pub fn collect(dir: &Path, prefix: &str, suffix: &str, found: &mut Vec<Capture>) {
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if !name.starts_with(prefix) || !name.ends_with(suffix) {
            continue;
        }
        let meta = match entry.metadata() {
            Ok(meta) => meta,
            Err(_) => continue,
        };
        if !meta.is_file() {
            continue;
        }
        let mtime_ms = meta
            .modified()
            .ok()
            .and_then(|at| at.duration_since(UNIX_EPOCH).ok())
            .map(|since| since.as_millis() as u64)
            .unwrap_or(0);
        found.push(Capture { path: entry.path().to_string_lossy().to_string(), mtime_ms });
    }
}

fn screenshot_dir() -> PathBuf {
    resolve("OMARCHY_SCREENSHOT_DIR", "XDG_PICTURES_DIR", "Pictures")
}

fn recording_dir() -> PathBuf {
    resolve("OMARCHY_SCREENRECORD_DIR", "XDG_VIDEOS_DIR", "Videos")
}

fn resolve(own: &str, xdg: &str, fallback: &str) -> PathBuf {
    if let Some(dir) = std::env::var(own).ok().filter(|dir| !dir.is_empty()) {
        return PathBuf::from(dir);
    }
    if let Some(dir) = std::env::var(xdg).ok().filter(|dir| !dir.is_empty()) {
        return PathBuf::from(dir);
    }
    let home = std::env::var("HOME").unwrap_or_default();
    if let Some(dir) = user_dirs_entry(&read_user_dirs(&home), xdg, &home) {
        return PathBuf::from(dir);
    }
    PathBuf::from(home).join(fallback)
}

fn read_user_dirs(home: &str) -> String {
    fs::read_to_string(Path::new(home).join(".config/user-dirs.dirs")).unwrap_or_default()
}

// Sample input, one line of ~/.config/user-dirs.dirs, which the capture scripts source as shell:
// XDG_PICTURES_DIR="$HOME/Pictures"
pub fn user_dirs_entry(text: &str, key: &str, home: &str) -> Option<String> {
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('#') {
            continue;
        }
        let (name, value) = match line.split_once('=') {
            Some(pair) => pair,
            None => continue,
        };
        if name.trim() != key {
            continue;
        }
        let value = value.trim().trim_matches('"');
        if value.is_empty() {
            return None;
        }
        return Some(value.replace("$HOME", home));
    }
    None
}

// flea shelf captures [count]: one line per capture, newest first, the mtime then the path.
pub fn command(rest: &[String]) -> i32 {
    let count = rest.first().and_then(|n| n.parse::<usize>().ok()).unwrap_or(3);
    for capture in newest(count) {
        println!("{} {}", capture.mtime_ms, capture.path);
    }
    0
}

#[cfg(test)]
#[path = "captures_tests.rs"]
mod tests;
