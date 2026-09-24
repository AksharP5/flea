use super::*;
use crate::backend::testdir::TestDir;
use std::os::unix::fs::PermissionsExt;
use std::sync::atomic::AtomicUsize;
use std::sync::{Mutex, MutexGuard};

// zoxide is one process at a time by design, so the tests that run one take turns, and each waits for the
// last one's reap before it starts.
static SERIAL: Mutex<()> = Mutex::new(());
// How long a test waits for an earlier test's killed zoxide to be reaped.
const REAP_WAIT: Duration = Duration::from_secs(2);

fn serial() -> MutexGuard<'static, ()> {
    let guard = SERIAL.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let started = Instant::now();
    while ZOXIDE_RUNNING.load(Ordering::SeqCst) && started.elapsed() < REAP_WAIT {
        std::thread::sleep(Duration::from_millis(5));
    }
    guard
}

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
    let _turn = serial();
    assert!(zoxide("/nonexistent/flea-test-zoxide", ZOXIDE_LIMIT).is_empty());
    assert!(!ZOXIDE_RUNNING.load(Ordering::SeqCst), "a spawn that failed must not hold the one zoxide slot");
}

#[test]
fn zoxide_is_asked_for_every_folder_and_its_ranking_is_kept() {
    let _turn = serial();
    let dir = TestDir::new("jump-zoxide");
    let fake = script(&dir, "zoxide", r#"[ "$*" = "query --list --all" ] || exit 3; printf '/b\nrelative\n/a\n'"#);
    assert_eq!(zoxide(&fake, ZOXIDE_LIMIT), strings(&["/b", "/a"]));
}

#[test]
fn a_wedged_zoxide_is_ended_at_the_limit_and_draws_nothing() {
    let _turn = serial();
    let dir = TestDir::new("jump-wedged");
    let fake = script(&dir, "zoxide", "printf '/a\\n'; exec sleep 30");
    let started = Instant::now();
    assert!(zoxide(&fake, Duration::from_millis(200)).is_empty());
    assert!(started.elapsed() < Duration::from_secs(5), "took {:?}", started.elapsed());
}

#[test]
fn a_second_open_while_zoxide_is_still_wedged_starts_no_second_one() {
    let _turn = serial();
    let dir = TestDir::new("jump-second");
    let counted = script(&dir, "counted", &format!("printf x >> '{}/spawned'; printf '/a\\n'", dir.path().display()));
    ZOXIDE_RUNNING.store(true, Ordering::SeqCst);
    let taken = zoxide(&counted, ZOXIDE_LIMIT);
    // Released before any assert, so a failure here cannot hold the slot for the tests after it.
    ZOXIDE_RUNNING.store(false, Ordering::SeqCst);
    assert!(taken.is_empty(), "the slot was taken, so this open draws no zoxide");
    assert!(!dir.path().join("spawned").exists(), "and it spawned nothing");
    assert_eq!(zoxide(&counted, ZOXIDE_LIMIT), strings(&["/a"]), "a free slot runs it");
    assert!(dir.path().join("spawned").exists());
}

#[test]
fn a_database_past_the_byte_cap_is_cut_at_its_ranked_head() {
    let _turn = serial();
    let dir = TestDir::new("jump-cap");
    // One process that never stops writing, so the cap and not the pipe's end is what stops the read.
    let fake = script(&dir, "zoxide", "exec yes /home/gm/a-folder-name");
    let started = Instant::now();
    let rows = zoxide(&fake, ZOXIDE_LIMIT);
    assert_eq!(rows.len(), ZOXIDE_ROWS);
    assert!(started.elapsed() < ZOXIDE_LIMIT, "the cap answers before the limit, took {:?}", started.elapsed());
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
    let ranked = strings(&[&format!("{}/gone-too", root), &root, &format!("{}/kept", root)]);
    let recent = strings(&[&format!("{}/kept/note.txt", root), &format!("{}/gone/file.txt", root), &format!("{}/kept/deleted.txt", root)]);
    let found = existing(candidates(&favourites, &ranked, &recent), CHECK_LIMIT, folder);
    assert_eq!(found, vec![
        (Source::Favourite, format!("{}/kept", root)),
        (Source::Zoxide, root.clone()),
        (Source::Recent, format!("{}/kept", root)),
        (Source::Recent, format!("{}/kept", root)),
    ]);
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

#[test]
fn a_stuck_favourite_costs_its_own_source_and_never_the_other_two() {
    let dir = TestDir::new("jump-stuck");
    let root = dir.path().to_string_lossy().into_owned();
    let stuck = format!("{}/stuck", root);
    let favourites = strings(&[&stuck, &format!("{}/after", root)]);
    let ranked = strings(&[&format!("{}/ranked", root)]);
    let recent = strings(&[&format!("{}/recent", root)]);
    let limit = Duration::from_millis(300);
    let started = Instant::now();
    let found = existing(candidates(&favourites, &ranked, &recent), limit, stuck_check);
    assert!(started.elapsed() < STUCK_FOR, "the budget answers, took {:?}", started.elapsed());
    assert_eq!(found, vec![(Source::Zoxide, format!("{}/ranked", root)), (Source::Recent, format!("{}/recent", root))]);
    // The next open does not queue a second check behind the first one, which is still blocked.
    let again = existing(candidates(&favourites, &ranked, &recent), limit, stuck_check);
    assert_eq!(STUCK_CALLS.load(Ordering::SeqCst), 1, "the stuck path was checked once across two opens");
    assert_eq!(again, vec![
        (Source::Favourite, format!("{}/after", root)),
        (Source::Zoxide, format!("{}/ranked", root)),
        (Source::Recent, format!("{}/recent", root)),
    ]);
}

#[test]
fn a_path_named_twice_is_checked_once_in_its_first_source() {
    let found = candidates(&strings(&["/a", "/b"]), &strings(&["/a", "/c"]), &strings(&["/b"]));
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
    assert_eq!(jumped_line(7, &found, 1.5),
        r#"{"t":"jumped","id":7,"favourites":["/a"],"zoxide":["/b \"q\""],"recent":["/c"],"ms":1.500}"#);
    assert_eq!(jumped_line(0, &[], 0.0), r#"{"t":"jumped","id":0,"favourites":[],"zoxide":[],"recent":[],"ms":0.000}"#);
}

#[test]
fn one_answer_joins_the_three_sources_in_order() {
    let _turn = serial();
    let dir = TestDir::new("jump-answer");
    let root = dir.path().to_string_lossy().into_owned();
    std::fs::create_dir(dir.path().join("ranked")).unwrap();
    let fake = script(&dir, "zoxide", &format!("printf '%s\\n' '{}/ranked' '{}'", root, root));
    let recent = strings(&[&format!("{}/ranked/file.txt", root), &format!("{}/other.txt", root)]);
    let line = answer(&fake, 3, &strings(&[&root]), &recent);
    // The recent file's folder is already zoxide's row and its second file's is the favourite, so recent draws nothing.
    let expected = format!(r#"{{"t":"jumped","id":3,"favourites":["{}"],"zoxide":["{}/ranked"],"recent":[],"ms":"#, root, root);
    assert!(line.starts_with(&expected), "{}", line);
}
