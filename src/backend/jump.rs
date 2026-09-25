// The path bar's folder jump: the three sources ui/PathJump.qml filters, answered once per open of the
// bar; see docs/protocol.md "jump". Nothing here writes, to zoxide's database or anywhere else.
use crate::backend::opsreq::OpMsg;
use crate::json::escape;
use crate::backend::mountinfo::{enclosing, mounts_in};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{channel, Sender};
use std::sync::Mutex;
use std::time::{Duration, Instant};

// zoxide answers from one local file in milliseconds, so past this it is wedged and its source draws nothing.
const ZOXIDE_LIMIT: Duration = Duration::from_secs(2);
// About ten thousand paths, far past any ranking a person reads; a larger database is cut at its tail.
const ZOXIDE_BYTES: u64 = 1 << 20;
// The ranked head kept for the existence checks, which is already more than a dropdown ever draws.
const ZOXIDE_ROWS: usize = 1000;
// One budget for every existence check, so a stat wedged on a dead network mount costs its own source's
// rows from that one on, never the other sources and never the whole answer.
const CHECK_LIMIT: Duration = Duration::from_secs(1);
// One zoxide at a time, and every existence check in flight from any open with that open's deadline: a
// check its own open has given up on is wedged, and the next open skips its key rather than wedge behind it.
static ZOXIDE_RUNNING: AtomicBool = AtomicBool::new(false);
static CHECKING: Mutex<BTreeMap<String, Vec<(u64, Instant)>>> = Mutex::new(BTreeMap::new());
static TICKETS: AtomicU64 = AtomicU64::new(0);
// Where the mount table is read, once per answer, and never through the filesystems it lists.
const MOUNTINFO: &str = "/proc/self/mountinfo";

// Where a candidate came from, in the order the dropdown draws the sources.
#[derive(Clone, Copy, PartialEq, Debug)]
enum Source {
    Favourite,
    Zoxide,
    Recent,
}

const SOURCES: [Source; 3] = [Source::Favourite, Source::Zoxide, Source::Recent];

#[derive(Clone)]
struct Candidate {
    source: Source,
    path: String,
}

// Answered on its own thread, because zoxide is a subprocess and a stat can block on a mount; the loop
// never waits on either. id is the client's own, echoed so it can tell this open's answer from an older one.
pub fn request(id: usize, favourites: Vec<String>, recent: Vec<String>, replies: Sender<OpMsg>) {
    // Meta's variant carries any finished line; it exists for the same reason, a subprocess the loop must not wait on.
    std::thread::spawn(move || {
        let _ = replies.send(OpMsg::Meta { line: answer("zoxide", id, &favourites, &recent) });
    });
}

// program is zoxide's name on PATH; the tests hand it a script of their own, so no test reads a real database.
fn answer(program: &str, id: usize, favourites: &[String], recent: &[String]) -> String {
    let started = Instant::now();
    let ranked = zoxide(program, ZOXIDE_LIMIT);
    let paths: Vec<String> = ranked.iter().map(|(path, _)| path.clone()).collect();
    let mounts = mounts_in(&std::fs::read_to_string(MOUNTINFO).unwrap_or_default());
    // A favourite or a zoxide row must itself be a folder; a recent file stands for the folder holding
    // it, whose parents resolve first so one open stats each folder once no matter how many files sit
    // in it. jumped_line answers each folder once in its first source either way.
    let mut found = existing(candidates(favourites, &paths, &[]), CHECK_LIMIT, folder, &mounts);
    let (parents, files) = recent_parents(recent);
    let resolved = resolve_parents(parents, CHECK_LIMIT, &mounts);
    for (file, parent) in files {
        if let Some(folder) = resolve_recent(&file, &parent, &resolved) {
            found.push((Source::Recent, folder));
        }
    }
    jumped_line(id, &found, &ranked, started.elapsed().as_secs_f64() * 1000.0)
}

// --all lists missing folders too, which is what keeps zoxide from pruning its own database on a query Flea made;
// the existence check below drops them instead. --score is the frecency the client ranks by, and a zoxide
// that is not installed is an empty source and says nothing.
fn zoxide(program: &str, limit: Duration) -> Vec<(String, f64)> {
    if ZOXIDE_RUNNING.swap(true, Ordering::SeqCst) {
        return Vec::new();
    }
    let spawned = Command::new(program)
        .args(["query", "--list", "--all", "--score"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn();
    let mut child = match spawned {
        Ok(child) => child,
        Err(_) => {
            ZOXIDE_RUNNING.store(false, Ordering::SeqCst);
            return Vec::new();
        }
    };
    let pipe = child.stdout.take();
    let (tx, rx) = channel();
    std::thread::spawn(move || {
        let mut text = Vec::new();
        if let Some(pipe) = pipe {
            let _ = pipe.take(ZOXIDE_BYTES).read_to_end(&mut text);
        }
        let _ = tx.send(text);
    });
    let text = rx.recv_timeout(limit).unwrap_or_default();
    // Short of the cap means the pipe closed; at the cap, or past the limit with nothing, zoxide may still be running.
    let whole = !text.is_empty() && (text.len() as u64) < ZOXIDE_BYTES;
    if !whole {
        let _ = child.kill();
    }
    // A zoxide blocked in the kernel outlives even SIGKILL until its read returns, so the reap has a thread of its own.
    std::thread::spawn(move || {
        let _ = child.wait();
        ZOXIDE_RUNNING.store(false, Ordering::SeqCst);
    });
    ranked_paths(&String::from_utf8_lossy(&text), whole)
}

// Sample input, `zoxide query --list --all --score`, one folder per line, best ranked first:
//     80.0 /home/gm/Documents
//      0.2 /home/gm/Work/field
// A cut read can end halfway through a line, so its last line is dropped. A line is a row only when its
// score is a finite number and its path is absolute; the path is everything after the score's one space.
fn ranked_paths(text: &str, whole: bool) -> Vec<(String, f64)> {
    let mut lines: Vec<&str> = text.lines().collect();
    if !whole {
        lines.pop();
    }
    let mut out = Vec::new();
    for line in lines {
        let (score, path) = match line.trim_start().split_once(' ') {
            Some(pair) => pair,
            None => continue,
        };
        match score.parse::<f64>() {
            Ok(score) if score.is_finite() && path.starts_with('/') => out.push((path.to_string(), score)),
            _ => continue,
        }
        if out.len() == ZOXIDE_ROWS {
            break;
        }
    }
    out
}

// Favourites, then zoxide's ranking, then the recent history, each in its own order. A path named twice is
// kept in its first source only, so no two checks of one path run at once and a favourite stays a favourite.
fn candidates(favourites: &[String], ranked: &[String], recent: &[String]) -> Vec<Candidate> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for (source, paths) in SOURCES.into_iter().zip([favourites, ranked, recent]) {
        for path in paths.iter().filter(|path| path.starts_with('/')) {
            if seen.insert(path.as_str()) {
                out.push(Candidate { source, path: path.clone() });
            }
        }
    }
    out
}

// The folder a candidate stands for now, or None: a favourite or a zoxide row must itself be a directory,
// and a recent entry is a file, so it stands for the folder it sits in unless it is a folder itself.
fn folder(candidate: &Candidate) -> Option<String> {
    let path = Path::new(&candidate.path);
    if path.is_dir() {
        return Some(candidate.path.clone());
    }
    if candidate.source != Source::Recent {
        return None;
    }
    let parent = path.parent()?;
    parent.is_dir().then(|| parent.to_string_lossy().into_owned())
}

// Each recent file with the folder it sits in, and every such folder once in first-seen order, so one
// open stats each folder a single time no matter how many files sit in it. Sample input:
// ["/a/f.txt", "/a/g.txt", "/b/h.txt"] names "/a" and "/b" once each and pairs every file with its
// folder; a path that is not absolute, and the root's own empty parent, name no folder to check.
fn recent_parents(recent: &[String]) -> (Vec<String>, Vec<(String, String)>) {
    let mut seen = HashSet::new();
    let mut parents = Vec::new();
    let mut files = Vec::new();
    for file in recent.iter().filter(|path| path.starts_with('/')) {
        let parent = Path::new(file).parent().map(|parent| parent.to_string_lossy().into_owned()).unwrap_or_default();
        if !parent.is_empty() && seen.insert(parent.clone()) {
            parents.push(parent.clone());
        }
        files.push((file.clone(), parent));
    }
    (parents, files)
}

// What one recent file stands for now: itself when it is a folder, the folder it sits in when that
// folder resolved above, and nothing when neither does. The metadata follows links, the rule folder()
// follows, so a symlink to a folder still stands for itself; a file stands for its folder without a
// second stat, because a file that exists sits in a folder that does.
fn resolve_recent(file: &str, parent: &str, resolved: &HashSet<String>) -> Option<String> {
    match std::fs::metadata(file) {
        Ok(meta) if meta.is_dir() => Some(file.to_string()),
        Ok(_) => Some(parent.to_string()),
        Err(_) => resolved.contains(parent).then(|| parent.to_string()),
    }
}

// Every folder recent files sit in, checked once on the same budget and wedged-mount keys the per-row
// checks use: a parent that never answers drops every file under it, the way one wedged stat drops its
// source's rows from that one on.
fn resolve_parents(parents: Vec<String>, limit: Duration, mounts: &[(PathBuf, String)]) -> HashSet<String> {
    let own: Vec<Candidate> = parents.into_iter().map(|path| Candidate { source: Source::Recent, path }).collect();
    existing(own, limit, is_dir_path, mounts).into_iter().map(|(_, path)| path).collect()
}

// A folder stands for itself when it is one.
fn is_dir_path(candidate: &Candidate) -> Option<String> {
    Path::new(&candidate.path).is_dir().then(|| candidate.path.clone())
}

// A filesystem that answers over the network or through FUSE, the kind whose stat can wedge for good.
fn remote(kind: &str) -> bool {
    matches!(kind, "nfs" | "nfs4" | "cifs" | "smb3" | "smbfs" | "9p" | "ceph" | "afs" | "fuse") || kind.starts_with("fuse.")
}

// What a check is known by: on a remote mount, the mount, because one wedged stat there means every path
// there wedges; anywhere else the path itself. Lexical, so it never touches the filesystem it names.
fn key_for(path: &str, mounts: &[(PathBuf, String)]) -> String {
    match enclosing(Path::new(path), mounts) {
        Some((point, kind)) if remote(kind) => format!("mount {}", point.display()),
        _ => path.to_string(),
    }
}

fn checking() -> std::sync::MutexGuard<'static, BTreeMap<String, Vec<(u64, Instant)>>> {
    CHECKING.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

// One check, unless a check on the same key is still running past the deadline of the open that started it:
// that one is wedged and this one would only wedge behind it. One inside its deadline is merely slow, so
// this checks again rather than skip a row the earlier open may still answer.
fn checked(candidate: &Candidate, key: &str, deadline: Instant, check: fn(&Candidate) -> Option<String>) -> Option<String> {
    let ticket = TICKETS.fetch_add(1, Ordering::SeqCst);
    {
        let mut table = checking();
        let running = table.entry(key.to_string()).or_default();
        if running.iter().any(|(_, given_up)| Instant::now() >= *given_up) {
            return None;
        }
        running.push((ticket, deadline));
    }
    let answer = check(candidate);
    let mut table = checking();
    if let Some(running) = table.get_mut(key) {
        running.retain(|(own, _)| *own != ticket);
        if running.is_empty() {
            table.remove(key);
        }
    }
    answer
}

// Each source is checked on a thread of its own, in its own order, and whatever has not answered by the
// limit is dropped: a blocked stat cannot be cancelled, so it finishes later into a closed channel.
fn existing(candidates: Vec<Candidate>, limit: Duration, check: fn(&Candidate) -> Option<String>, mounts: &[(PathBuf, String)]) -> Vec<(Source, String)> {
    let total = candidates.len();
    let deadline = Instant::now() + limit;
    let (tx, rx) = channel();
    for source in SOURCES {
        let own: Vec<(usize, Candidate, String)> = candidates.iter().enumerate()
            .filter(|(_, candidate)| candidate.source == source)
            .map(|(index, candidate)| (index, candidate.clone(), key_for(&candidate.path, mounts)))
            .collect();
        let tx = tx.clone();
        std::thread::spawn(move || {
            for (index, candidate, key) in own {
                if tx.send((index, candidate.source, checked(&candidate, &key, deadline, check))).is_err() {
                    return;
                }
            }
        });
    }
    drop(tx);
    let mut found: Vec<Option<(Source, String)>> = vec![None; total];
    // Ends at the limit, or as soon as every source's thread has finished and dropped its sender.
    while let Ok((index, source, resolved)) = rx.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
        found[index] = resolved.map(|path| (source, path));
    }
    found.into_iter().flatten().collect()
}


// A folder appears once, in the first source that names it, the same first-position rule Places.favorites
// follows. frecency carries zoxide's score for each folder answered that zoxide ranks, whichever source
// draws it, which is what the client ranks by after the match itself.
fn jumped_line(id: usize, found: &[(Source, String)], scores: &[(String, f64)], ms: f64) -> String {
    let ranked: HashMap<&str, f64> = scores.iter().map(|(path, score)| (path.as_str(), *score)).collect();
    let mut seen = HashSet::new();
    let mut lists: [Vec<String>; 3] = [Vec::new(), Vec::new(), Vec::new()];
    let mut frecency = Vec::new();
    for (source, folder) in found {
        if seen.insert(folder.as_str()) {
            lists[*source as usize].push(format!("\"{}\"", escape(folder)));
            if let Some(score) = ranked.get(folder.as_str()) {
                frecency.push(format!("\"{}\":{}", escape(folder), score));
            }
        }
    }
    format!(
        r#"{{"t":"jumped","id":{},"favourites":[{}],"zoxide":[{}],"recent":[{}],"frecency":{{{}}},"ms":{:.3}}}"#,
        id, lists[0].join(","), lists[1].join(","), lists[2].join(","), frecency.join(","), ms
    )
}

#[cfg(test)]
#[path = "jump_tests.rs"]
mod tests;
