use super::*;
use crate::backend::testdir::TestDir;
use std::sync::atomic::AtomicUsize;
use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard};

// zoxide runs one at a time, so the tests that run one take turns under SERIAL.
static SERIAL: Mutex<()> = Mutex::new(());
// How long a test waits for an earlier test's killed zoxide to be reaped.
const REAP_WAIT: Duration = Duration::from_secs(2);

fn serial() -> MutexGuard<'static, ()> {
    let guard = SERIAL.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    reaped();
    guard
}

// Every run is reaped on a thread of its own, so a test starting another run waits for the slot first.
fn reaped() {
    let started = Instant::now();
    while ZOXIDE_RUNNING.load(Ordering::SeqCst) && started.elapsed() < REAP_WAIT {
        std::thread::sleep(Duration::from_millis(5));
    }
}

fn strings(paths: &[&str]) -> Vec<String> {
    paths.iter().map(|path| path.to_string()).collect()
}

fn script(dir: &TestDir, name: &str, body: &str) -> String {
    dir.script(name, &format!("#!/bin/sh\n{}\n", body)).to_string_lossy().into_owned()
}

#[test]
fn a_zoxide_that_is_not_installed_is_an_empty_source() {
    let _turn = serial();
    assert!(zoxide("/nonexistent/flea-test-zoxide", ZOXIDE_LIMIT).is_empty());
    assert!(!ZOXIDE_RUNNING.load(Ordering::SeqCst), "a spawn that failed must not hold the one zoxide slot");
}

#[test]
fn zoxide_is_asked_for_every_folder_and_its_ranking_is_kept() {
    let _turn = serial();
    let dir = TestDir::new("jump-zoxide");
    let fake = script(&dir, "zoxide", r#"[ "$*" = "query --list --all --score" ] || exit 3; printf '  12.5 /b\n   1.0 relative\n   nan /c\n   3.0 /a\n'"#);
    assert_eq!(zoxide(&fake, ZOXIDE_LIMIT), vec![("/b".to_string(), 12.5), ("/a".to_string(), 3.0)]);
}

#[test]
fn a_wedged_zoxide_is_ended_at_the_limit_and_draws_nothing() {
    let _turn = serial();
    // A first-ever open, so no kept ranking stands in for the one that never came.
    *LAST_ZOXIDE.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Vec::new();
    let dir = TestDir::new("jump-wedged");
    let fake = script(&dir, "zoxide", &format!("echo $$ > '{}/pid'; printf '/a\\n'; exec sleep 30", dir.path().display()));
    let started = Instant::now();
    assert!(zoxide(&fake, Duration::from_millis(200)).is_empty());
    assert!(started.elapsed() < Duration::from_secs(5), "took {:?}", started.elapsed());
    // The kill is pinned: the slot is released and the fake process is gone, both within a bound.
    let pid: String = std::fs::read_to_string(dir.path().join("pid")).unwrap().trim().to_string();
    let deadline = Instant::now() + Duration::from_secs(5);
    while ZOXIDE_RUNNING.load(Ordering::SeqCst) && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(5));
    }
    assert!(!ZOXIDE_RUNNING.load(Ordering::SeqCst), "the killed run released the one zoxide slot");
    assert!(!PathBuf::from(format!("/proc/{}", pid)).exists(), "the fake zoxide process is gone");
}

#[test]
fn a_run_past_its_limit_keeps_the_ranking_that_answered_in_time() {
    let _turn = serial();
    let dir = TestDir::new("jump-keep");
    let full = script(&dir, "full", "printf '   2.0 /a\\n'");
    // Two rows, so a cut read would keep one: an empty or kept answer then comes from the limit, never from the cut.
    let wedged = script(&dir, "wedged", "printf '   9.0 /b\\n   8.0 /c\\n'; exec sleep 30");
    assert_eq!(zoxide(&full, ZOXIDE_LIMIT), vec![("/a".to_string(), 2.0)], "a run inside its limit keeps its ranking");
    reaped();
    assert_eq!(zoxide(&wedged, Duration::from_millis(200)), vec![("/a".to_string(), 2.0)], "a run past its limit draws the ranking that answered in time");
    reaped();
    assert_eq!(last_ranking(), vec![("/a".to_string(), 2.0)], "and never overwrites it");
    *LAST_ZOXIDE.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Vec::new();
}

#[test]
fn a_second_open_while_zoxide_is_still_wedged_starts_no_second_one() {
    let _turn = serial();
    *LAST_ZOXIDE.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Vec::new();
    let dir = TestDir::new("jump-second");
    let counted = script(&dir, "counted", &format!("printf x >> '{}/spawned'; printf '   2.0 /a\\n'", dir.path().display()));
    ZOXIDE_RUNNING.store(true, Ordering::SeqCst);
    let taken = zoxide(&counted, ZOXIDE_LIMIT);
    // Released before any assert, so a failure here cannot hold the slot for the tests after it.
    ZOXIDE_RUNNING.store(false, Ordering::SeqCst);
    assert!(taken.is_empty(), "with no ranking kept, the wedged open draws no zoxide");
    assert!(!dir.path().join("spawned").exists(), "and it spawned nothing");
    assert_eq!(zoxide(&counted, ZOXIDE_LIMIT), vec![("/a".to_string(), 2.0)], "a free slot runs it");
    assert!(dir.path().join("spawned").exists());
    *LAST_ZOXIDE.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Vec::new();
}

#[test]
fn a_slow_zoxide_answers_the_last_ranking_and_starts_nothing() {
    let _turn = serial();
    *LAST_ZOXIDE.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Vec::new();
    let dir = TestDir::new("jump-cached");
    let counted = script(&dir, "counted", &format!("printf x >> '{}/spawned'; printf '   2.0 /b\\n'", dir.path().display()));
    let full = script(&dir, "full", "printf '   2.0 /a\\n'");
    assert_eq!(zoxide(&full, ZOXIDE_LIMIT), vec![("/a".to_string(), 2.0)], "a run inside its limit keeps its ranking");
    ZOXIDE_RUNNING.store(true, Ordering::SeqCst);
    let taken = zoxide(&counted, ZOXIDE_LIMIT);
    // Released before any assert, so a failure here cannot hold the slot for the tests after it.
    ZOXIDE_RUNNING.store(false, Ordering::SeqCst);
    assert_eq!(taken, vec![("/a".to_string(), 2.0)], "the open behind a slow run draws the kept ranking");
    assert!(!dir.path().join("spawned").exists(), "and it spawned nothing");
    *LAST_ZOXIDE.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Vec::new();
}

#[test]
fn a_database_past_the_byte_cap_is_cut_at_its_ranked_head() {
    let _turn = serial();
    let dir = TestDir::new("jump-cap");
    // One process that never stops writing, so the cap and not the pipe's end is what stops the read.
    let fake = script(&dir, "zoxide", "exec yes '   1.0 /home/gm/a-folder-name'");
    let started = Instant::now();
    let rows = zoxide(&fake, ZOXIDE_LIMIT);
    assert_eq!(rows.len(), ZOXIDE_ROWS);
    assert!(started.elapsed() < ZOXIDE_LIMIT, "the cap answers before the limit, took {:?}", started.elapsed());
}

#[test]
fn a_cut_read_drops_its_last_line_and_a_whole_one_keeps_it() {
    let scored = |pairs: &[(&str, f64)]| pairs.iter().map(|(path, score)| (path.to_string(), *score)).collect::<Vec<_>>();
    assert_eq!(ranked_paths("  4.0 /a\n  2.0 /b\n  1.0 /ha", false), scored(&[("/a", 4.0), ("/b", 2.0)]));
    assert_eq!(ranked_paths("  4.0 /a\n  2.0 /b\n", true), scored(&[("/a", 4.0), ("/b", 2.0)]));
    // A path with a space keeps it, a score that is not a number and a line with no path are not rows.
    assert_eq!(ranked_paths("  1.5 /a b\n  x /c\n  2.0\ninf /d\n", true), scored(&[("/a b", 1.5)]));
    assert!(ranked_paths("", true).is_empty());
}

#[test]
fn missing_folders_are_dropped_and_a_recent_file_stands_for_its_folder() {
    let dir = TestDir::new("jump-exists");
    let root = dir.path().to_string_lossy().into_owned();
    std::fs::create_dir(dir.path().join("kept")).unwrap();
    std::fs::write(dir.path().join("kept/note.txt"), "x").unwrap();
    let favourites = strings(&[&format!("{}/kept", root), &format!("{}/gone", root), "relative"]);
    let ranked = strings(&[&format!("{}/gone-too", root), &root, &format!("{}/kept", root)]);
    let mut found = existing(candidates(&favourites, &ranked), CHECK_LIMIT, is_dir_path, &[]);
    // Recent files take the production recent path: parents resolve once, then each file stands for its folder.
    let recent = strings(&[&format!("{}/kept/note.txt", root), &format!("{}/gone/file.txt", root), &format!("{}/kept/deleted.txt", root)]);
    let (parents, files) = recent_parents(&recent);
    let resolved = resolve_parents(parents, CHECK_LIMIT, &[]);
    let recent_candidates: Vec<Candidate> = files.into_iter()
        .filter(|(_, parent)| resolved.contains(parent))
        .map(|(file, _)| Candidate { source: Source::Recent, path: file })
        .collect();
    found.extend(existing(recent_candidates, CHECK_LIMIT, recent_folder, &[]));
    assert_eq!(found, vec![
        (Source::Favourite, format!("{}/kept", root)),
        (Source::Zoxide, root.clone()),
        (Source::Recent, format!("{}/kept", root)),
        (Source::Recent, format!("{}/kept", root)),
    ]);
}

#[test]
fn recent_parents_names_each_folder_once_in_first_seen_order() {
    let (parents, files) = recent_parents(&strings(&["/a/f.txt", "/a/g.txt", "/b/h.txt", "relative", "/a/f.txt"]));
    assert_eq!(parents, vec!["/a".to_string(), "/b".to_string()]);
    assert_eq!(files, vec![
        ("/a/f.txt".to_string(), "/a".to_string()),
        ("/a/g.txt".to_string(), "/a".to_string()),
        ("/b/h.txt".to_string(), "/b".to_string()),
        ("/a/f.txt".to_string(), "/a".to_string()),
    ]);
}

#[test]
fn a_recent_folder_stands_for_itself_and_a_file_for_its_parent() {
    let dir = TestDir::new("jump-resolve-recent");
    let root = dir.path().to_string_lossy().into_owned();
    std::fs::create_dir(dir.path().join("kept")).unwrap();
    std::fs::write(dir.path().join("kept/note.txt"), "x").unwrap();
    #[cfg(unix)]
    std::os::unix::fs::symlink(dir.path().join("kept"), dir.path().join("link")).unwrap();
    // The caller checks the parent resolved first; recent_folder answers the file itself or that parent.
    let folder = |path: &str| recent_folder(&Candidate { source: Source::Recent, path: path.to_string() });
    assert_eq!(folder(&format!("{}/kept", root)), Some(format!("{}/kept", root)));
    assert_eq!(folder(&format!("{}/kept/note.txt", root)), Some(format!("{}/kept", root)));
    assert_eq!(folder(&format!("{}/kept/gone.txt", root)), Some(format!("{}/kept", root)));
    assert_eq!(folder("relative"), None);
    #[cfg(unix)]
    assert_eq!(folder(&format!("{}/link", root)), Some(format!("{}/link", root)));
}

#[test]
fn recent_files_sharing_one_parent_answer_their_folder_once() {
    let _turn = serial();
    let dir = TestDir::new("jump-shared-parent");
    let root = dir.path().to_string_lossy().into_owned();
    std::fs::create_dir(dir.path().join("shared")).unwrap();
    std::fs::write(dir.path().join("shared/a.txt"), "x").unwrap();
    std::fs::write(dir.path().join("shared/b.txt"), "x").unwrap();
    // The recent files are the only source here, and every one of them names the one folder.
    let fake = script(&dir, "zoxide", "exit 0");
    let recent = strings(&[&format!("{}/shared/a.txt", root), &format!("{}/shared/b.txt", root),
        &format!("{}/shared", root), &format!("{}/shared/gone.txt", root), &format!("{}/gone/gone.txt", root)]);
    let line = answer(&fake, 9, &[], &recent);
    let expected = format!(r#"{{"t":"jumped","id":9,"favourites":[],"zoxide":[],"recent":["{}/shared"],"frecency":{{}},"ms":"#, root);
    assert!(line.starts_with(&expected), "{}", line);
}

// A check that blocks on any path ending in /stuck, the shape a stat takes on a mount that stopped answering.
static STUCK_CALLS: AtomicUsize = AtomicUsize::new(0);
const STUCK_FOR: Duration = Duration::from_secs(3);

fn stuck_check(candidate: &Candidate) -> Option<String> {
    if candidate.path.ends_with("/stuck") {
        STUCK_CALLS.fetch_add(1, Ordering::SeqCst);
        std::thread::sleep(STUCK_FOR);
    }
    Some(candidate.path.clone())
}

// The production recent check with a wedged stat stood in for the real one; its own counter keeps test order free.
static STUCK_RECENT_CALLS: AtomicUsize = AtomicUsize::new(0);

fn stuck_recent_check(candidate: &Candidate) -> Option<String> {
    // Only the wedged path counts, so the kept file's own check never moves the counter.
    if candidate.path.ends_with("/stuck") {
        STUCK_RECENT_CALLS.fetch_add(1, Ordering::SeqCst);
        std::thread::sleep(STUCK_FOR);
    }
    recent_folder(candidate)
}

#[test]
fn a_stuck_recent_file_returns_within_the_limit_with_the_other_sources() {
    let _turn = serial();
    let dir = TestDir::new("jump-stuck-recent");
    let root = dir.path().to_string_lossy().into_owned();
    std::fs::create_dir(dir.path().join("kept")).unwrap();
    std::fs::write(dir.path().join("kept/note.txt"), "x").unwrap();
    std::fs::create_dir(dir.path().join("ranked")).unwrap();
    std::fs::create_dir(dir.path().join("stuckparent")).unwrap();
    let fake = script(&dir, "zoxide", &format!("printf '   8.0 {}/ranked\\n'", root));
    // The good file sorts first, so its row is answered before the wedged check spends the budget.
    let recent = strings(&[&format!("{}/kept/note.txt", root), &format!("{}/stuckparent/stuck", root)]);
    let limit = Duration::from_millis(300);
    let stuck_before = STUCK_RECENT_CALLS.load(Ordering::SeqCst);
    let started = Instant::now();
    let line = answer_checked(&fake, 11, &strings(&[&root]), &recent, limit, stuck_recent_check);
    assert!(started.elapsed() < STUCK_FOR, "the budget answers, took {:?}", started.elapsed());
    assert!(STUCK_RECENT_CALLS.load(Ordering::SeqCst) > stuck_before, "the wedged file was reached, so the budget and not a pre-filter answered");
    let expected = format!(r#"{{"t":"jumped","id":11,"favourites":["{}"],"zoxide":["{}/ranked"],"recent":["{}/kept"],"frecency":{{"{}/ranked":8}},"ms":"#, root, root, root, root);
    assert!(line.starts_with(&expected), "{}", line);
}

#[test]
fn a_stuck_favourite_costs_its_own_source_and_never_the_other_two() {
    let dir = TestDir::new("jump-stuck");
    let root = dir.path().to_string_lossy().into_owned();
    std::fs::create_dir(dir.path().join("after")).unwrap();
    std::fs::create_dir(dir.path().join("ranked")).unwrap();
    std::fs::create_dir(dir.path().join("recent")).unwrap();
    std::fs::write(dir.path().join("recent/note.txt"), "x").unwrap();
    let stuck = format!("{}/stuck", root);
    let favourites = strings(&[&stuck, &format!("{}/after", root)]);
    let ranked = strings(&[&format!("{}/ranked", root)]);
    // Recent files take the production recent path, so this pins the stuck favourite against real rows.
    let recent = strings(&[&format!("{}/recent/note.txt", root)]);
    let (parents, files) = recent_parents(&recent);
    let resolved = resolve_parents(parents, CHECK_LIMIT, &[]);
    let recent_now = || {
        let candidates: Vec<Candidate> = files.clone().into_iter()
            .filter(|(_, parent)| resolved.contains(parent))
            .map(|(file, _)| Candidate { source: Source::Recent, path: file })
            .collect();
        existing(candidates, CHECK_LIMIT, recent_folder, &[])
    };
    let limit = Duration::from_millis(300);
    let started = Instant::now();
    let mut found = existing(candidates(&favourites, &ranked), limit, stuck_check, &[]);
    found.extend(recent_now());
    assert!(started.elapsed() < STUCK_FOR, "the budget answers, took {:?}", started.elapsed());
    assert_eq!(found, vec![(Source::Zoxide, format!("{}/ranked", root)), (Source::Recent, format!("{}/recent", root))]);
    // The next open does not queue a second check behind the first one, which is still blocked.
    let mut again = existing(candidates(&favourites, &ranked), limit, stuck_check, &[]);
    again.extend(recent_now());
    assert_eq!(STUCK_CALLS.load(Ordering::SeqCst), 1, "the stuck path was checked once across two opens");
    assert_eq!(again, vec![
        (Source::Favourite, format!("{}/after", root)),
        (Source::Zoxide, format!("{}/ranked", root)),
        (Source::Recent, format!("{}/recent", root)),
    ]);
}

#[test]
fn a_path_named_twice_is_checked_once_in_its_first_source() {
    // Cross-source dedup now lives in jumped_line; candidates pins the favourite over zoxide.
    let found = candidates(&strings(&["/a", "/b"]), &strings(&["/a", "/c"]));
    let named: Vec<(Source, &str)> = found.iter().map(|c| (c.source, c.path.as_str())).collect();
    assert_eq!(named, vec![(Source::Favourite, "/a"), (Source::Favourite, "/b"), (Source::Zoxide, "/c")]);
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
    // zoxide ranks /a, drawn as the favourite, and /b "q"; /c it never ranked, so it carries no frecency.
    let scores = [("/a".to_string(), 12.5), ("/b \"q\"".to_string(), 3.0), ("/gone".to_string(), 9.0)];
    assert_eq!(jumped_line(7, &found, &scores, 1.5),
        r#"{"t":"jumped","id":7,"favourites":["/a"],"zoxide":["/b \"q\""],"recent":["/c"],"frecency":{"/a":12.5,"/b \"q\"":3},"ms":1.500}"#);
    assert_eq!(jumped_line(0, &[], &[], 0.0), r#"{"t":"jumped","id":0,"favourites":[],"zoxide":[],"recent":[],"frecency":{},"ms":0.000}"#);
}

#[test]
fn one_answer_joins_the_three_sources_in_order() {
    let _turn = serial();
    let dir = TestDir::new("jump-answer");
    let root = dir.path().to_string_lossy().into_owned();
    std::fs::create_dir(dir.path().join("ranked")).unwrap();
    let fake = script(&dir, "zoxide", &format!("printf '  %s %s\\n' 8.0 '{}/ranked' 2.5 '{}'", root, root));
    let recent = strings(&[&format!("{}/ranked/file.txt", root), &format!("{}/other.txt", root)]);
    let line = answer(&fake, 3, &strings(&[&root]), &recent);
    // The recent file's folder is already zoxide's row and its second file's is the favourite, so recent draws nothing.
    let expected = format!(r#"{{"t":"jumped","id":3,"favourites":["{}"],"zoxide":["{}/ranked"],"recent":[],"frecency":{{"{}":2.5,"{}/ranked":8}},"ms":"#, root, root, root, root);
    assert!(line.starts_with(&expected), "{}", line);
}

// Blocks on every path under a /wedged folder, the shape of a remote mount that stopped answering.
static WEDGED_CALLS: AtomicUsize = AtomicUsize::new(0);

fn wedged_check(candidate: &Candidate) -> Option<String> {
    if candidate.path.contains("/wedged/") {
        WEDGED_CALLS.fetch_add(1, Ordering::SeqCst);
        std::thread::sleep(STUCK_FOR);
    }
    Some(candidate.path.clone())
}

#[test]
fn a_wedged_remote_mount_is_skipped_whole_so_no_open_stacks_a_thread_on_it() {
    let dir = TestDir::new("jump-mount");
    let root = dir.path().to_string_lossy().into_owned();
    let wedged = format!("{}/wedged", root);
    let mounts = vec![(PathBuf::from("/"), "ext4".to_string()), (PathBuf::from(&wedged), "fuse.sshfs".to_string())];
    let favourites = strings(&[&format!("{}/a", wedged), &format!("{}/b", wedged)]);
    let ranked = strings(&[&format!("{}/c", wedged), &format!("{}/local", root)]);
    let limit = Duration::from_millis(300);
    let first = existing(candidates(&favourites, &ranked), limit, wedged_check, &mounts);
    assert!(first.is_empty(), "both sources are behind the wedged mount first: {:?}", first);
    let calls = WEDGED_CALLS.load(Ordering::SeqCst);
    assert_eq!(calls, 2, "one wedged check per source thread");
    let again = existing(candidates(&favourites, &ranked), limit, wedged_check, &mounts);
    assert_eq!(WEDGED_CALLS.load(Ordering::SeqCst), calls, "the next open checks nothing on that mount");
    assert_eq!(again, vec![(Source::Zoxide, format!("{}/local", root))]);
}

static SLOW_CALLS: AtomicUsize = AtomicUsize::new(0);
const SLOW_FOR: Duration = Duration::from_millis(250);

fn slow_check(candidate: &Candidate) -> Option<String> {
    SLOW_CALLS.fetch_add(1, Ordering::SeqCst);
    std::thread::sleep(SLOW_FOR);
    Some(candidate.path.clone())
}

#[test]
fn a_check_still_inside_its_budget_is_slow_not_wedged_so_the_next_open_checks_again() {
    let dir = TestDir::new("jump-slow");
    let slow = format!("{}/slow", dir.path().display());
    let favourites = strings(&[&slow]);
    let first_favourites = favourites.clone();
    let earlier = std::thread::spawn(move || existing(candidates(&first_favourites, &[]), CHECK_LIMIT, slow_check, &[]));
    std::thread::sleep(SLOW_FOR / 5);
    let later = existing(candidates(&favourites, &[]), CHECK_LIMIT, slow_check, &[]);
    assert_eq!(later, vec![(Source::Favourite, slow.clone())], "an open racing a slow one still gets its row");
    assert_eq!(earlier.join().unwrap(), vec![(Source::Favourite, slow)]);
    assert_eq!(SLOW_CALLS.load(Ordering::SeqCst), 2);
}

#[test]
fn a_remote_filesystem_is_keyed_by_its_mount_and_a_local_one_by_its_path() {
    let mounts = vec![(PathBuf::from("/"), "ext4".to_string()),
                      (PathBuf::from("/mnt/nas"), "cifs".to_string()),
                      (PathBuf::from("/run/user/1000/gvfs"), "fuse.gvfsd-fuse".to_string())];
    assert_eq!(key_for("/mnt/nas/a/b", &mounts), "mount /mnt/nas");
    assert_eq!(key_for("/run/user/1000/gvfs/smb-share:server=nas,share=x/y", &mounts), "mount /run/user/1000/gvfs");
    assert_eq!(key_for("/home/gm/Work", &mounts), "/home/gm/Work");
    assert_eq!(key_for("/mnt/nasty", &mounts), "/mnt/nasty");
    assert_eq!(key_for("/anything", &[]), "/anything");
}
