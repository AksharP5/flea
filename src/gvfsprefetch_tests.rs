// src/gvfsprefetch.rs's tests, kept beside it so that file stays a mechanism file.
use super::*;
use crate::backend::testdir::TestDir;
use std::os::unix::fs::PermissionsExt;
use std::sync::Mutex;

// Process-wide XDG_RUNTIME_DIR setters hold this; the _in variants take the dir and skip it.
static ENV_LOCK: Mutex<()> = Mutex::new(());

// A literal gvfs path, so is_gvfs answers without reading the environment.
const SHARE: &str = "/run/user/1000/gvfs/smb-share:server=t,share=u/dir";
// Sample gio output, two rows; the hidden one is dropped unless the scan asks for it.
const TWO_ROWS: &str = "smb://h/share/a.txt\t3\t(regular)\ttime::modified=100\nsmb://h/share/.hidden\t1\t(regular)\ttime::modified=100\n";

fn runtime_fixture(tag: &str) -> (TestDir, PathBuf) {
    let dir = TestDir::new(tag);
    let runtime = dir.path().join("runtime/flea");
    std::fs::create_dir_all(&runtime).unwrap();
    std::fs::set_permissions(&runtime, std::fs::Permissions::from_mode(0o700)).unwrap();
    (dir, runtime)
}

fn write_prefetch(runtime: &Path, name: &str, body: &str) -> PathBuf {
    let dest = runtime.join(name);
    std::fs::write(&dest, body).unwrap();
    dest
}

fn fake_gio(dir: &TestDir, name: &str, body: &str) -> String {
    let p = dir.join(name);
    std::fs::write(&p, body).unwrap();
    std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
    p.to_string_lossy().into_owned()
}

fn live_deadline() -> SystemTime {
    SystemTime::now() + Duration::from_secs(15)
}

#[test]
fn a_completed_prefetch_adopts_without_spawning_gio() {
    let (_dir, runtime) = runtime_fixture("gvfs-adopt");
    let marker = runtime.join("gio-ran");
    let fake = format!("#!/bin/sh\ntouch {}\nprintf 'should never run\\n'\n", marker.display());
    let script = _dir.join("gio");
    std::fs::write(&script, fake).unwrap();
    std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
    let dest = write_prefetch(&runtime, "gvfs-1.list", TWO_ROWS);
    let (listing, _) = adopt_in(SHARE, false, &dest, live_deadline(), SystemTime::now(), Some(&runtime))
        .expect("a complete file for the path adopts");
    assert_eq!((listing.len(), listing.name(0)), (1, "a.txt"), "the hidden row is filtered at parse time");
    assert!(!marker.exists(), "adoption spawns no gio child at all");
    assert!(!dest.exists(), "the file is deleted on read and never read again");
}

#[test]
fn a_hidden_scan_keeps_what_a_plain_scan_filters() {
    let (_dir, runtime) = runtime_fixture("gvfs-hidden");
    let dest = write_prefetch(&runtime, "gvfs-1.list", TWO_ROWS);
    let (listing, _) = adopt_in(SHARE, true, &dest, live_deadline(), SystemTime::now(), Some(&runtime)).unwrap();
    assert_eq!((listing.len(), listing.name(1)), (2, ".hidden"));
}

#[test]
fn garbage_is_refused_and_deleted_so_the_scan_lists_itself() {
    let (_dir, runtime) = runtime_fixture("gvfs-garbage");
    let dest = write_prefetch(&runtime, "gvfs-1.list", "this is not a gio line\n");
    assert!(adopt_in(SHARE, false, &dest, live_deadline(), SystemTime::now(), Some(&runtime)).is_none());
    assert!(!dest.exists(), "garbage is consumed, not left for the next listing");
}

#[test]
fn a_stale_file_is_refused_and_kept() {
    let (_dir, runtime) = runtime_fixture("gvfs-stale");
    let dest = write_prefetch(&runtime, "gvfs-1.list", TWO_ROWS);
    let mtime = dest.metadata().unwrap().modified().unwrap();
    let now = mtime + Duration::from_secs(STALE_SECS + 10);
    assert!(adopt_in(SHARE, false, &dest, live_deadline(), now, Some(&runtime)).is_none());
    assert!(dest.exists(), "a refused file is left for the sweeper, not deleted");
}

#[test]
fn a_missing_file_past_the_deadline_answers_at_once() {
    let (_dir, runtime) = runtime_fixture("gvfs-missing");
    let t = Instant::now();
    assert!(adopt_in(SHARE, false, &runtime.join("gvfs-absent.list"), UNIX_EPOCH, SystemTime::now(), Some(&runtime))
        .is_none());
    assert!(t.elapsed() < Duration::from_secs(5), "no wait past a deadline that already passed");
}

#[test]
fn a_temp_file_alone_is_a_partial_write_and_adopts_nothing() {
    let (_dir, runtime) = runtime_fixture("gvfs-partial");
    let dest = runtime.join("gvfs-1.list");
    std::fs::write(runtime.join("gvfs-1.list.123.tmp"), TWO_ROWS).unwrap();
    assert!(adopt_in(SHARE, false, &dest, live_deadline(), SystemTime::now(), Some(&runtime)).is_none());
}

#[test]
fn a_world_readable_runtime_dir_is_refused() {
    let (_dir, runtime) = runtime_fixture("gvfs-dir755");
    std::fs::set_permissions(&runtime, std::fs::Permissions::from_mode(0o755)).unwrap();
    let dest = write_prefetch(&runtime, "gvfs-1.list", TWO_ROWS);
    assert!(adopt_in(SHARE, false, &dest, live_deadline(), SystemTime::now(), Some(&runtime)).is_none());
    assert!(dest.exists(), "a refused file is left alone");
}

#[test]
fn a_symlinked_dest_is_refused_rather_than_followed() {
    let (_dir, runtime) = runtime_fixture("gvfs-symlink");
    let real = write_prefetch(&runtime, "real.list", TWO_ROWS);
    let dest = runtime.join("gvfs-1.list");
    std::os::unix::fs::symlink(&real, &dest).unwrap();
    assert!(adopt_in(SHARE, false, &dest, live_deadline(), SystemTime::now(), Some(&runtime)).is_none());
}

#[test]
fn a_file_outside_the_runtime_dir_is_not_this_launch() {
    let (dir, runtime) = runtime_fixture("gvfs-outside");
    let elsewhere = dir.path().join("elsewhere");
    std::fs::create_dir_all(&elsewhere).unwrap();
    let dest = elsewhere.join("gvfs-1.list");
    std::fs::write(&dest, TWO_ROWS).unwrap();
    assert!(adopt_in(SHARE, false, &dest, live_deadline(), SystemTime::now(), Some(&runtime)).is_none());
}

#[test]
fn the_subcommand_publishes_gio_bytes_exclusively_at_0600() {
    let (dir, runtime) = runtime_fixture("gvfs-run-ok");
    let gio = fake_gio(&dir, "gio", "#!/bin/sh\nprintf 'smb://h/share/a.txt\\t3\\t(regular)\\ttime::modified=100\\n'\n");
    let dest = runtime.join("gvfs-9.list");
    assert_eq!(run_in(SHARE, &dest, &gio, Some(&runtime)), 0);
    assert!(dest.is_file());
    assert_eq!(std::fs::read_to_string(&dest).unwrap(), "smb://h/share/a.txt\t3\t(regular)\ttime::modified=100\n");
    assert_eq!(dest.metadata().unwrap().permissions().mode() & 0o777, 0o600);
    assert_eq!(std::fs::read_dir(&runtime).unwrap().count(), 1, "no temp file is left behind");
}

#[test]
fn the_subcommand_reports_a_gio_failure_and_writes_nothing() {
    let (dir, runtime) = runtime_fixture("gvfs-run-fail");
    let gio = fake_gio(&dir, "gio", "#!/bin/sh\nexit 1\n");
    let dest = runtime.join("gvfs-9.list");
    assert_eq!(run_in(SHARE, &dest, &gio, Some(&runtime)), 1);
    assert!(!dest.exists());
}

#[test]
fn the_subcommand_refuses_a_dest_outside_the_runtime_dir() {
    let (dir, runtime) = runtime_fixture("gvfs-run-dest");
    let gio = fake_gio(&dir, "gio", "#!/bin/sh\nexit 0\n");
    let dest = dir.path().join("gvfs-9.list");
    assert_eq!(run_in(SHARE, &dest, &gio, Some(&runtime)), 2);
    assert!(!dest.exists());
}

#[test]
fn the_subcommand_refuses_a_local_path_and_a_bad_dir() {
    let (dir, runtime) = runtime_fixture("gvfs-run-refuse");
    let gio = fake_gio(&dir, "gio", "#!/bin/sh\nexit 0\n");
    assert_eq!(run_in("/home/gm", &runtime.join("gvfs-9.list"), &gio, Some(&runtime)), 2);
    std::fs::set_permissions(&runtime, std::fs::Permissions::from_mode(0o755)).unwrap();
    assert_eq!(run_in(SHARE, &runtime.join("gvfs-9.list"), &gio, Some(&runtime)), 2);
}

#[test]
fn the_sweeper_reaps_only_old_prefetch_files() {
    let (_dir, runtime) = runtime_fixture("gvfs-sweep");
    let old = write_prefetch(&runtime, "gvfs-old.list", TWO_ROWS);
    assert!(std::process::Command::new("touch").arg("-d").arg("70 seconds ago").arg(&old).status().unwrap().success());
    let fresh = write_prefetch(&runtime, "gvfs-fresh.list", TWO_ROWS);
    let other = write_prefetch(&runtime, "notes.txt", TWO_ROWS);
    sweep_dir(&runtime, SystemTime::now());
    assert!(!old.exists(), "a leftover older than a minute goes");
    assert!(fresh.exists(), "this launch's file stays");
    assert!(other.exists(), "a name this launcher never writes stays");
}

#[test]
fn a_different_path_never_consumes_the_prefetch() {
    let (_dir, runtime) = runtime_fixture("gvfs-other-path");
    let dest = write_prefetch(&runtime, "gvfs-1.list", TWO_ROWS);
    let other = Prefetch { dest: dest.clone(), path: SHARE.to_string(), start_ms: 1 };
    assert!(adopt_matching("/run/user/1000/gvfs/smb-share:server=t,share=u/other", false, &other).is_none());
    assert!(dest.exists(), "another path takes today's gio path and leaves the file");
}

// The one test that spends the process-wide once flag, so every other test adopts
// through adopt_in and never trips it; the two scans run sequentially inside it.
#[test]
fn the_scan_adopts_once_then_falls_back_to_gio() {
    let _guard = ENV_LOCK.lock().unwrap();
    let dir = TestDir::new("gvfs-once");
    let runtime = dir.path().join("runtime/flea");
    std::fs::create_dir_all(&runtime).unwrap();
    std::fs::set_permissions(&runtime, std::fs::Permissions::from_mode(0o700)).unwrap();
    std::env::set_var("XDG_RUNTIME_DIR", dir.path().join("runtime"));
    let marker = dir.path().join("gio-ran");
    let gio = fake_gio(
        &dir,
        "gio",
        &format!("#!/bin/sh\ntouch {}\nprintf 'smb://h/share/from-gio.txt\\t5\\t(regular)\\ttime::modified=7\\n'\n", marker.display()),
    );
    let start_ms = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64;
    let dest = runtime.join("gvfs-1.list");
    std::fs::write(&dest, TWO_ROWS).unwrap();
    let prefetch = Prefetch { dest: dest.clone(), path: SHARE.to_string(), start_ms };
    let (first, _) = crate::backend::scan::scan_with(SHARE, false, Some(prefetch), &gio).unwrap();
    assert_eq!((first.len(), first.name(0)), (1, "a.txt"), "the first scan of the path spawns no gio child");
    assert!(!marker.exists());
    std::fs::write(&dest, TWO_ROWS).unwrap();
    let again = Prefetch { dest, path: SHARE.to_string(), start_ms };
    let (second, _) = crate::backend::scan::scan_with(SHARE, false, Some(again), &gio).unwrap();
    assert_eq!((second.len(), second.name(0)), (1, "from-gio.txt"));
    assert!(marker.exists(), "the second listing takes today's gio path");
    std::env::remove_var("XDG_RUNTIME_DIR");
}

#[test]
fn the_launcher_arms_only_a_gvfs_path() {
    let _guard = ENV_LOCK.lock().unwrap();
    let dir = TestDir::new("gvfs-prepare");
    let root = dir.path().join("runtime");
    std::fs::create_dir_all(&root).unwrap();
    std::env::set_var("XDG_RUNTIME_DIR", &root);
    assert!(prepare("/home/gm").is_none(), "a local launch does nothing new");
    let (dest, start_ms) = prepare(SHARE).expect("a gvfs launch names its file");
    assert!(start_ms > 0);
    assert_eq!(dest.parent(), Some(runtime_dir().as_deref().unwrap()));
    assert!(dest.file_name().unwrap().to_string_lossy().starts_with("gvfs-"));
    assert_eq!(dest.parent().unwrap().metadata().unwrap().permissions().mode() & 0o777, 0o700);
    std::env::remove_var("XDG_RUNTIME_DIR");
}

#[test]
fn the_environment_names_all_three_or_nothing() {
    let _guard = ENV_LOCK.lock().unwrap();
    std::env::set_var("XDG_RUNTIME_DIR", "/run/user/1000");
    std::env::set_var(PREFETCH_ENV, "/run/user/1000/flea/gvfs-1.list");
    std::env::set_var(PATH_ENV, SHARE);
    std::env::set_var(START_ENV, "12345");
    let named = env_prefetch().expect("three set variables read as one prefetch");
    assert_eq!((named.path.as_str(), named.start_ms), (SHARE, 12345));
    std::env::set_var(START_ENV, "not-a-number");
    assert!(env_prefetch().is_none(), "an unparsable start is no prefetch");
    std::env::remove_var(PREFETCH_ENV);
    std::env::remove_var(PATH_ENV);
    std::env::remove_var(START_ENV);
    std::env::remove_var("XDG_RUNTIME_DIR");
}
