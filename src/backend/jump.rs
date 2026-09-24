// The path bar's folder jump: the three sources ui/PathJump.qml filters, answered once per open of the
// bar; see docs/protocol.md "jump". Nothing here writes, to zoxide's database or anywhere else.
use crate::backend::opsreq::OpMsg;
use crate::json::escape;
use std::collections::HashSet;
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::mpsc::{channel, Sender};
use std::time::{Duration, Instant};

// zoxide answers from one local file in milliseconds, so past this it is wedged and its source draws nothing.
const ZOXIDE_LIMIT: Duration = Duration::from_secs(2);
// About ten thousand paths, far past any ranking a person reads; a larger database is cut at its tail.
const ZOXIDE_BYTES: u64 = 1 << 20;
// The ranked head kept for the existence checks, which is already more than a dropdown ever draws.
const ZOXIDE_ROWS: usize = 1000;
// One budget for every existence check, so a stat wedged on a dead network mount costs its own row and the rows after it, never the dropdown.
const CHECK_LIMIT: Duration = Duration::from_secs(1);

// Where a candidate came from, in the order the dropdown draws the sources.
#[derive(Clone, Copy, PartialEq, Debug)]
enum Source {
    Favourite,
    Zoxide,
    Recent,
}

struct Candidate {
    source: Source,
    path: String,
}

// Answered on its own thread, because zoxide is a subprocess and a stat can block on a mount; the loop never waits on either.
pub fn request(favourites: Vec<String>, recent: Vec<String>, replies: Sender<OpMsg>) {
    // Meta's variant carries any finished line; it exists for the same reason, a subprocess the loop must not wait on.
    std::thread::spawn(move || {
        let _ = replies.send(OpMsg::Meta { line: answer("zoxide", &favourites, &recent) });
    });
}

// program is zoxide's name on PATH; the tests hand it a script of their own, so no test reads a real database.
fn answer(program: &str, favourites: &[String], recent: &[String]) -> String {
    let started = Instant::now();
    let ranked = zoxide(program, ZOXIDE_LIMIT);
    let found = existing(candidates(favourites, &ranked, recent), CHECK_LIMIT);
    jumped_line(&found, started.elapsed().as_secs_f64() * 1000.0)
}

// --all lists missing folders too, which is what keeps zoxide from pruning its own database on a query Flea made;
// the existence check below drops them instead. A zoxide that is not installed is an empty source and says nothing.
fn zoxide(program: &str, limit: Duration) -> Vec<String> {
    let mut child = match Command::new(program)
        .args(["query", "--list", "--all"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return Vec::new(),
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
    let _ = child.wait();
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

// Favourites, then zoxide's ranking, then the recent history, each in its own order.
fn candidates(favourites: &[String], ranked: &[String], recent: &[String]) -> Vec<Candidate> {
    let sources = [(Source::Favourite, favourites), (Source::Zoxide, ranked), (Source::Recent, recent)];
    let mut out = Vec::new();
    for (source, paths) in sources {
        for path in paths.iter().filter(|path| path.starts_with('/')) {
            out.push(Candidate { source, path: path.clone() });
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

// Every check runs on one more thread, and whatever has not answered by the limit is dropped with the
// rows after it: a blocked stat cannot be cancelled, so it is left to finish into a closed channel.
fn existing(candidates: Vec<Candidate>, limit: Duration) -> Vec<(Source, String)> {
    let total = candidates.len();
    let (tx, rx) = channel();
    std::thread::spawn(move || {
        for (index, candidate) in candidates.iter().enumerate() {
            if tx.send((index, candidate.source, folder(candidate))).is_err() {
                return;
            }
        }
    });
    let deadline = Instant::now() + limit;
    let mut found: Vec<Option<(Source, String)>> = vec![None; total];
    for _ in 0..total {
        match rx.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
            Ok((index, source, resolved)) => found[index] = resolved.map(|path| (source, path)),
            Err(_) => break,
        }
    }
    found.into_iter().flatten().collect()
}

// A folder appears once, in the first source that names it, the same first-position rule Places.favorites follows.
fn jumped_line(found: &[(Source, String)], ms: f64) -> String {
    let mut seen = HashSet::new();
    let mut lists: [Vec<String>; 3] = [Vec::new(), Vec::new(), Vec::new()];
    for (source, folder) in found {
        if seen.insert(folder.as_str()) {
            lists[*source as usize].push(format!("\"{}\"", escape(folder)));
        }
    }
    format!(
        r#"{{"t":"jumped","favourites":[{}],"zoxide":[{}],"recent":[{}],"ms":{:.3}}}"#,
        lists[0].join(","), lists[1].join(","), lists[2].join(","), ms
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;
    use std::os::unix::fs::PermissionsExt;

    fn strings(paths: &[&str]) -> Vec<String> {
        paths.iter().map(|path| path.to_string()).collect()
    }

    fn script(dir: &TestDir, name: &str, body: &str) -> String {
        let path = dir.path().join(name);
        dir.assert_contains(&path);
        std::fs::write(&path, format!("#!/bin/sh\n{}\n", body)).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn a_zoxide_that_is_not_installed_is_an_empty_source() {
        assert!(zoxide("/nonexistent/flea-test-zoxide", ZOXIDE_LIMIT).is_empty());
    }

    #[test]
    fn zoxide_is_asked_for_every_folder_and_its_ranking_is_kept() {
        let dir = TestDir::new("jump-zoxide");
        let fake = script(&dir, "zoxide", r#"[ "$*" = "query --list --all" ] || exit 3; printf '/b\nrelative\n/a\n'"#);
        assert_eq!(zoxide(&fake, ZOXIDE_LIMIT), strings(&["/b", "/a"]));
    }

    #[test]
    fn a_wedged_zoxide_is_ended_at_the_limit_and_draws_nothing() {
        let dir = TestDir::new("jump-wedged");
        let fake = script(&dir, "zoxide", "printf '/a\\n'; exec sleep 30");
        let started = Instant::now();
        assert!(zoxide(&fake, Duration::from_millis(200)).is_empty());
        assert!(started.elapsed() < Duration::from_secs(5), "took {:?}", started.elapsed());
    }

    #[test]
    fn a_cut_read_drops_its_last_line_and_a_whole_one_keeps_it() {
        assert_eq!(ranked_paths("/a\n/b\n/half", false), strings(&["/a", "/b"]));
        assert_eq!(ranked_paths("/a\n/b\n", true), strings(&["/a", "/b"]));
        assert!(ranked_paths("", true).is_empty());
    }

    #[test]
    fn missing_folders_are_dropped_and_a_recent_file_stands_for_its_folder() {
        let dir = TestDir::new("jump-exists");
        let root = dir.path().to_string_lossy().into_owned();
        std::fs::create_dir(dir.path().join("kept")).unwrap();
        std::fs::write(dir.path().join("kept/note.txt"), "x").unwrap();
        let favourites = strings(&[&format!("{}/kept", root), &format!("{}/gone", root), "relative"]);
        let ranked = strings(&[&format!("{}/gone-too", root), &root]);
        let recent = strings(&[&format!("{}/kept/note.txt", root), &format!("{}/gone/file.txt", root), &format!("{}/kept/deleted.txt", root)]);
        let found = existing(candidates(&favourites, &ranked, &recent), CHECK_LIMIT);
        assert_eq!(found, vec![
            (Source::Favourite, format!("{}/kept", root)),
            (Source::Zoxide, root.clone()),
            (Source::Recent, format!("{}/kept", root)),
            (Source::Recent, format!("{}/kept", root)),
        ]);
    }

    #[test]
    fn a_folder_is_answered_once_in_the_first_source_that_names_it() {
        let found = vec![
            (Source::Favourite, "/a".to_string()),
            (Source::Zoxide, "/a".to_string()),
            (Source::Zoxide, "/b \"q\"".to_string()),
            (Source::Recent, "/b \"q\"".to_string()),
            (Source::Recent, "/c".to_string()),
        ];
        assert_eq!(jumped_line(&found, 1.5),
            r#"{"t":"jumped","favourites":["/a"],"zoxide":["/b \"q\""],"recent":["/c"],"ms":1.500}"#);
        assert_eq!(jumped_line(&[], 0.0), r#"{"t":"jumped","favourites":[],"zoxide":[],"recent":[],"ms":0.000}"#);
    }

    #[test]
    fn one_answer_joins_the_three_sources_in_order() {
        let dir = TestDir::new("jump-answer");
        let root = dir.path().to_string_lossy().into_owned();
        std::fs::create_dir(dir.path().join("ranked")).unwrap();
        let fake = script(&dir, "zoxide", &format!("printf '%s\\n' '{}/ranked' '{}'", root, root));
        let recent = strings(&[&format!("{}/ranked/file.txt", root), &format!("{}/other.txt", root)]);
        let line = answer(&fake, &strings(&[&root]), &recent);
        // The recent file's folder is already zoxide's row and its second file's is the favourite, so recent draws nothing.
        let expected = format!(r#"{{"t":"jumped","favourites":["{}"],"zoxide":["{}/ranked"],"recent":[],"ms":"#, root, root);
        assert!(line.starts_with(&expected), "{}", line);
    }
}
