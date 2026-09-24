// The path bar's folder jump: the three sources ui/PathJump.qml filters, answered once per open of the
// bar; see docs/protocol.md "jump". Nothing here writes, to zoxide's database or anywhere else.
use crate::backend::opsreq::OpMsg;
use crate::json::escape;
use std::collections::{BTreeSet, HashSet};
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
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
// A zoxide still running, and the paths whose stat has not come back, from any earlier open: the next
// open skips them, so a wedged mount holds one thread for good rather than one more per open.
static ZOXIDE_RUNNING: AtomicBool = AtomicBool::new(false);
static CHECKING: Mutex<BTreeSet<String>> = Mutex::new(BTreeSet::new());

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
    let found = existing(candidates(favourites, &ranked, recent), CHECK_LIMIT, folder);
    jumped_line(id, &found, started.elapsed().as_secs_f64() * 1000.0)
}

// --all lists missing folders too, which is what keeps zoxide from pruning its own database on a query Flea made;
// the existence check below drops them instead. A zoxide that is not installed is an empty source and says nothing.
fn zoxide(program: &str, limit: Duration) -> Vec<String> {
    if ZOXIDE_RUNNING.swap(true, Ordering::SeqCst) {
        return Vec::new();
    }
    let spawned = Command::new(program)
        .args(["query", "--list", "--all"])
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

// Sample input, one folder per line, best ranked first:
//   /home/gm/Documents
//   /home/gm/Work/field
// A cut read can end halfway through a path, so its last line is dropped; anything not absolute is not a folder.
fn ranked_paths(text: &str, whole: bool) -> Vec<String> {
    let mut lines: Vec<&str> = text.lines().collect();
    if !whole {
        lines.pop();
    }
    lines.into_iter().filter(|line| line.starts_with('/')).take(ZOXIDE_ROWS).map(String::from).collect()
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

// One check, unless an earlier open's check of the same path has still not come back.
fn checked(candidate: &Candidate, check: fn(&Candidate) -> Option<String>) -> Option<String> {
    if !CHECKING.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).insert(candidate.path.clone()) {
        return None;
    }
    let answer = check(candidate);
    CHECKING.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).remove(&candidate.path);
    answer
}

// Each source is checked on a thread of its own, in its own order, and whatever has not answered by the
// limit is dropped: a blocked stat cannot be cancelled, so it finishes later into a closed channel.
fn existing(candidates: Vec<Candidate>, limit: Duration, check: fn(&Candidate) -> Option<String>) -> Vec<(Source, String)> {
    let total = candidates.len();
    let (tx, rx) = channel();
    for source in SOURCES {
        let own: Vec<(usize, Candidate)> =
            candidates.iter().cloned().enumerate().filter(|(_, candidate)| candidate.source == source).collect();
        let tx = tx.clone();
        std::thread::spawn(move || {
            for (index, candidate) in own {
                if tx.send((index, candidate.source, checked(&candidate, check))).is_err() {
                    return;
                }
            }
        });
    }
    drop(tx);
    let deadline = Instant::now() + limit;
    let mut found: Vec<Option<(Source, String)>> = vec![None; total];
    // Ends at the limit, or as soon as every source's thread has finished and dropped its sender.
    while let Ok((index, source, resolved)) = rx.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
        found[index] = resolved.map(|path| (source, path));
    }
    found.into_iter().flatten().collect()
}

// A folder appears once, in the first source that names it, the same first-position rule Places.favorites follows.
fn jumped_line(id: usize, found: &[(Source, String)], ms: f64) -> String {
    let mut seen = HashSet::new();
    let mut lists: [Vec<String>; 3] = [Vec::new(), Vec::new(), Vec::new()];
    for (source, folder) in found {
        if seen.insert(folder.as_str()) {
            lists[*source as usize].push(format!("\"{}\"", escape(folder)));
        }
    }
    format!(
        r#"{{"t":"jumped","id":{},"favourites":[{}],"zoxide":[{}],"recent":[{}],"ms":{:.3}}}"#,
        id, lists[0].join(","), lists[1].join(","), lists[2].join(","), ms
    )
}

#[cfg(test)]
#[path = "jump_tests.rs"]
mod tests;
