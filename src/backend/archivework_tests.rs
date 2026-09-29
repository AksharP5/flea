use super::*;
use crate::backend::archive::Formats;
use crate::backend::archiveops::compress;
use crate::backend::testdir::TestDir;

#[test]
fn a_work_directory_is_made_beside_the_destination_and_goes_with_its_own_drop() {
    let d = TestDir::new("archwork");
    let kept;
    {
        let w = Work::new(d.path(), "arc").expect("work");
        kept = w.dir.clone();
        assert!(kept.is_dir());
        assert!(kept.file_name().unwrap().to_string_lossy().starts_with(WORK_PREFIX));
        // Beside the destination, so the rename that follows never crosses a filesystem.
        assert_eq!(kept.parent().unwrap(), d.path());
    }
    assert!(!kept.exists(), "the work directory goes with the job that made it");
}

// Cancel kills and reaps; the exact spawned pid keeps the /proc gate off other suites' processes.
#[test]
fn a_cancelled_child_is_killed_and_reaped_rather_than_left_running() {
    if crate::backend::sandboxprobe::skipped() { return; }
    let d = TestDir::new("archworkcancel");
    let mut work = Work::new(d.path(), "ext").expect("work");
    let cancel = std::sync::Arc::new(AtomicBool::new(false));
    let started_pid = std::sync::Arc::new(AtomicU32::new(0));
    let flag = std::sync::Arc::clone(&cancel);
    let child_pid = std::sync::Arc::clone(&started_pid);
    let notifier = std::thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(5);
        while child_pid.load(Ordering::SeqCst) == 0 && Instant::now() < deadline {
            std::thread::yield_now();
        }
        flag.store(true, Ordering::Relaxed);
    });
    let seconds = format!("30.{}", std::process::id());
    let began = std::time::Instant::now();
    let e = run_boxed_cancellable_observed("archive", vec!["/usr/bin/sleep".to_string(), seconds],
                                           d.path(), &mut work, &cancel, &started_pid).unwrap_err();
    notifier.join().expect("the cancellation notifier finished");
    // The child dies by SIGKILL, so this asserts the cancel token wins over the status.
    assert_eq!(e.msg, "cancelled");
    assert!(began.elapsed() < Duration::from_secs(10), "a cancelled child was waited out");
    assert!(work.dir.is_dir(), "the runner must not remove the caller's staging directory");
    let pid = started_pid.load(Ordering::SeqCst);
    assert_ne!(pid, 0, "the cancellation fixture never observed its child pid");
    let proc_entry = PathBuf::from(format!("/proc/{pid}"));
    assert!(!proc_entry.exists(), "the owned child was not reaped");
}

// Issue #211: a kernel kill arrives as exit 128+n through bwrap or a real signal, never the old fallback.
#[test]
fn a_status_alone_is_read_into_a_sentence_naming_the_signal_or_the_exit() {
    let signalled = ExitStatus::from_raw(9);
    let killed_through_bwrap = ExitStatus::from_raw(137 << 8);
    let exited = ExitStatus::from_raw(3 << 8);
    assert_eq!(failure_message("archive", &signalled, ""), "the archive tool was killed by signal SIGKILL (9)");
    assert_eq!(failure_message("archive", &killed_through_bwrap, ""),
               "the archive tool was killed by signal SIGKILL (9)",
               "137 is how bwrap renders a SIGKILL, and it must not read as a bad archive");
    assert_eq!(failure_message("archive", &exited, ""), "the archive tool exited with status 3");
    // No name in the table means the number alone: this function never invents one.
    assert_eq!(failure_message("archive", &ExitStatus::from_raw(13), ""), "the archive tool was killed by signal 13");
    // And 128+n above the table's range is an exit status rather than a claimed kill.
    assert_eq!(failure_message("archive", &ExitStatus::from_raw(200 << 8), ""), "the archive tool exited with status 200");
}

// The tool's own last non-blank line is the diagnosis; a blank stderr falls back to the status.
#[test]
fn the_tools_own_last_line_wins_over_the_blank_one_and_over_the_status() {
    let exited = ExitStatus::from_raw(1 << 8);
    assert_eq!(failure_message("archive", &exited, "bsdtar: Error opening archive\n"),
               "bsdtar: Error opening archive");
    assert_eq!(failure_message("archive", &exited, "warning: x\nbsdtar: Error opening archive\n\n"),
               "bsdtar: Error opening archive", "trailing blank lines are not the diagnosis");
    assert_eq!(failure_message("archive", &exited, "\n"), "the archive tool exited with status 1",
               "a blank stderr is not a diagnosis either");
    assert_eq!(failure_message("archive", &exited, "   \n"), "the archive tool exited with status 1",
               "neither is whitespace");
    assert_eq!(failure_message("archive", &exited, "  bsdtar: could not read  "), "bsdtar: could not read",
               "the line is trimmed, because it is pasted into a sentence");
}

// The sentence above through the real jail, so the wiring is proven and not only the formatter.
#[test]
fn a_killed_tool_is_reported_as_killed_rather_than_as_a_bad_archive() {
    if crate::backend::sandboxprobe::skipped() { return; }
    let d = TestDir::new("archkilled");
    let mut work = Work::new(d.path(), "kill").expect("work");
    let idle = AtomicBool::new(false);
    // The tool kills itself and prints nothing, which is what a killed unpack looks like from here.
    let killed = run_boxed_cancellable_capped("archive",
                           vec!["/usr/bin/sh".to_string(), "-c".to_string(), "kill -9 $$".to_string()],
                           d.path(), &mut work, &idle).unwrap_err();
    assert!(killed.msg.contains("killed by signal SIGKILL (9)"), "a kill must name the signal: {}", killed.msg);
    assert!(!killed.msg.contains("failed"), "and must not read as the old empty-stderr fallback: {}", killed.msg);
    let exited = run_boxed_cancellable_capped("archive", vec!["/usr/bin/false".to_string()], d.path(), &mut work, &idle).unwrap_err();
    assert!(exited.msg.contains("exited with status 1"), "an exit is reported as an exit: {}", exited.msg);
}

// The parser must cancel while a real jailed child holds stdout open after one bounded line.
#[test]
fn a_cancelled_index_reader_kills_and_reaps_a_child_blocked_on_stdout() {
    if crate::backend::sandboxprobe::skipped() { return; }
    let d = TestDir::new("archworkindexcancel");
    let cancel = std::sync::Arc::new(AtomicBool::new(false));
    let started = std::sync::Arc::new(AtomicU32::new(0));
    let ready = std::sync::Arc::new(AtomicBool::new(false));
    let flag = std::sync::Arc::clone(&cancel);
    let parsed = std::sync::Arc::clone(&ready);
    let notifier = std::thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(5);
        while !parsed.load(Ordering::SeqCst) && Instant::now() < deadline {
            std::thread::yield_now();
        }
        flag.store(true, Ordering::Relaxed);
    });
    let fixture = "printf '%s\\n' '-rw-r--r-- 0 gm gm 1 Jan 1 00:00 a.txt'; exec /usr/bin/sleep 600";
    let result = archive_produced_count_with_inner(
        vec!["/usr/bin/sh".to_string(), "-c".to_string(), fixture.to_string()],
        crate::backend::archivespec::tar_spec(), d.path(), &cancel, &started, &ready,
    );
    notifier.join().expect("the readiness notifier finished");
    let error = result.unwrap_err();
    assert_eq!(error.msg, "cancelled");
    assert!(ready.load(Ordering::SeqCst), "the fixture never delivered its first line");
    let pid = started.load(Ordering::SeqCst);
    assert_ne!(pid, 0, "the verification fixture never exposed its child pid");
    let proc_entry = PathBuf::from(format!("/proc/{pid}"));
    assert!(!proc_entry.exists(), "the blocked verification child was not reaped");
}

// Issue #211 correction: the archive jail carries no CPU cap while the convert runner keeps its own, both driven through the runners the jobs use.
#[test]
fn the_archive_jail_has_no_cpu_cap_but_a_boxed_burner_is_stopped() {
    if crate::backend::sandboxprobe::skipped() { return; }
    let d = TestDir::new("archcpucap");
    let mut work = Work::new(d.path(), "cpu").expect("work");
    let cancel = AtomicBool::new(false);
    run_boxed_cancellable("archive", uncapped_probe(), d.path(), &mut work, &cancel)
        .expect("the archive jail carries no CPU cap");
    // Burns CPU time past a 1 s cap, then would exit 0: a wall-clock loop finishes under the cap on a loaded host, so this one counts its own CPU.
    let burner = || vec!["/usr/bin/python3".to_string(), "-c".to_string(),
        "import resource,time\ns=time.time()\nx=0\nwhile True:\n x+=1\n if x%200000==0:\n  u=resource.getrusage(resource.RUSAGE_SELF)\n  if u.ru_utime+u.ru_stime>3: break\n  if time.time()-s>120: break".to_string()];
    let stopped = run_boxed_cancellable_capped_with_cpu("convert", burner(), d.path(), &mut work, &cancel, 1).unwrap_err();
    assert!(stopped.msg.contains("killed by signal"),
            "a boxed job past its bound must be stopped, not silent: {}", stopped.msg);
}

#[test]
fn two_work_directories_beside_the_same_destination_never_share_a_path() {
    let d = TestDir::new("archwork2");
    let first = Work::new(d.path(), "ext").expect("first");
    let second = Work::new(d.path(), "ext").expect("second");
    assert_ne!(first.dir, second.dir, "a second job must not claim the first job's directory");
    assert!(first.dir.is_dir(), "and must not have destroyed it");
    assert!(second.dir.is_dir());
    // In flight, so a live sibling's contents have to survive the other one being created.
    std::fs::write(first.dir.join("in-flight"), b"payload").expect("write");
    let third = Work::new(d.path(), "ext").expect("third");
    assert!(first.dir.join("in-flight").is_file(), "a third job must not destroy either");
    assert_ne!(third.dir, first.dir);
    assert_ne!(third.dir, second.dir);
}

// bsdtar is only the tool under test, run inside the jail; without it the compress below proves nothing.
fn bsdtar_or_skip() -> bool {
    if std::process::Command::new("bsdtar").arg("--version").output().map(|o| o.status.success()).unwrap_or(false) {
        return true;
    }
    let who = std::thread::current().name().unwrap_or("a sandboxed test").to_string();
    let line = format!("SKIP {who}: no bsdtar on this box, so no archive fixture can be built\n");
    let _ = std::io::Write::write_all(&mut std::io::stderr(), line.as_bytes());
    false
}

// Exits 0 only where RLIMIT_CPU is unlimited, so a capped jail fails it outright.
fn uncapped_probe() -> Vec<String> {
    vec!["/usr/bin/python3".to_string(), "-c".to_string(),
        "import resource,sys; sys.exit(0 if resource.getrlimit(resource.RLIMIT_CPU)[0]==resource.RLIM_INFINITY else 1)".to_string()]
}

// The compressor shares the extract's uncapped jail: the probe through compress's own runner reports no CPU cap.
#[test]
fn the_compressor_shares_the_extracts_uncapped_jail() {
    if crate::backend::sandboxprobe::skipped() || !bsdtar_or_skip() { return; }
    let d = TestDir::new("archcompressjail");
    let mut work = Work::new(d.path(), "cpu").expect("work");
    let cancel = AtomicBool::new(false);
    run_boxed_cancellable("archive", uncapped_probe(), d.path(), &mut work, &cancel)
        .expect("the archive jail carries no CPU cap");
    let formats = Formats::from_tools(true, true);
    d.dir("src");
    d.file("src/a.txt", "body");
    let dest = d.join("out.zip");
    compress(&formats, d.path(), &["src".to_string()], "zip", &dest, &AtomicBool::new(false)).expect("a small compress publishes");
    assert!(dest.is_file(), "and its destination really landed");
}

// X1: a cancel answers only after the last writer's EOF, bounded; a sleeping writer stands in with no jail.
#[test]
fn a_cancel_drains_the_last_writer_before_it_answers() {
    let mut writer = std::process::Command::new("/usr/bin/sleep")
        .arg("1")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .expect("sleep did not start");
    let out = writer.stdout.take().expect("piped stdout");
    let reader = std::thread::spawn(move || {
        let mut out = out;
        let mut text = String::new();
        std::io::Read::read_to_string(&mut out, &mut text).ok();
        text
    });
    let began = Instant::now();
    assert!(drain_reader(reader), "the drain reported no EOF though the writer exited");
    let waited = began.elapsed();
    let _ = writer.wait();
    assert!(waited >= Duration::from_millis(900), "the drain answered before the writer's EOF, {waited:?}");
    assert!(waited < Duration::from_secs(CANCEL_DRAIN_SECS), "the drain waited past its bound, {waited:?}");
}

// K1: the pin drives compress() itself through the probe seam, so a capped runner fails the tool it runs.
#[test]
fn compress_itself_runs_outside_any_cpu_cap() {
    if crate::backend::sandboxprobe::skipped() { return; }
    let d = TestDir::new("archcompressprobe");
    let dest = d.join("out.zip");
    compress(&Formats::test_probe(), d.path(), &["src".to_string()], "zip", &dest, &AtomicBool::new(false))
        .expect("compress() itself must run outside any CPU cap");
    assert!(dest.is_file(), "and its destination really landed");
}

// The reader holds a second past the kill: the cancel answers only after that hold.
#[test]
fn a_cancel_waits_for_the_reader_hold_before_it_answers() {
    if crate::backend::sandboxprobe::skipped() { return; }
    let d = TestDir::new("archcancelhold");
    let mut work = Work::new(d.path(), "hld").expect("work");
    let inner = vec!["/usr/bin/sleep".to_string(), "30".to_string()];
    let cancel = Arc::new(AtomicBool::new(false));
    let flag = Arc::clone(&cancel);
    let started = Arc::new(AtomicU32::new(0));
    let child_pid = Arc::clone(&started);
    let notifier = std::thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(5);
        while child_pid.load(Ordering::SeqCst) == 0 && Instant::now() < deadline {
            std::thread::yield_now();
        }
        flag.store(true, Ordering::Relaxed);
    });
    set_reader_hold_ms(1000);
    let began = Instant::now();
    let result = run_boxed_cancellable_observed("archive", inner, d.path(), &mut work, &cancel, &started);
    set_reader_hold_ms(0);
    let error = result.unwrap_err();
    notifier.join().expect("the cancellation notifier finished");
    let elapsed = began.elapsed();
    assert_eq!(error.msg, "cancelled");
    assert!(elapsed + Duration::from_millis(100) >= Duration::from_secs(1),
            "the cancel answered before the hold, {elapsed:?}");
    assert!(elapsed < Duration::from_secs(CANCEL_DRAIN_SECS), "a cancelled job was waited out");
}

// The hold outlasts a short bound: the answer names the kept folder, and the folder stands.
#[test]
fn a_cancel_past_the_drain_bound_keeps_naming_the_work_folder() {
    if crate::backend::sandboxprobe::skipped() { return; }
    let d = TestDir::new("archcancelkeep");
    let mut work = Work::new(d.path(), "kp").expect("work");
    let name = work.dir.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    let inner = vec!["/usr/bin/sleep".to_string(), "30".to_string()];
    let cancel = Arc::new(AtomicBool::new(false));
    let flag = Arc::clone(&cancel);
    let started = Arc::new(AtomicU32::new(0));
    let child_pid = Arc::clone(&started);
    let notifier = std::thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(5);
        while child_pid.load(Ordering::SeqCst) == 0 && Instant::now() < deadline {
            std::thread::yield_now();
        }
        flag.store(true, Ordering::Relaxed);
    });
    set_reader_hold_ms(2000);
    set_drain_secs(1);
    let began = Instant::now();
    let result = run_boxed_cancellable_observed("archive", inner, d.path(), &mut work, &cancel, &started);
    set_reader_hold_ms(0);
    set_drain_secs(CANCEL_DRAIN_SECS);
    let error = result.unwrap_err();
    notifier.join().expect("the cancellation notifier finished");
    assert_eq!(error.msg, format!("cancelled; the archive tool did not exit, so its work folder {name} was left in place"));
    assert!(began.elapsed() < Duration::from_secs(2), "a cancelled job waited past its bound");
    // The folder outlives the guard: asserting while work is still in scope cannot tell keep from leak.
    let kept = work.dir.clone();
    drop(work);
    assert!(kept.is_dir(), "the kept folder was removed under a live writer");
}

// keep() disarms the cleanup: the directory stands after its own drop, for the caller to remove.
#[test]
fn a_kept_work_directory_survives_its_own_drop() {
    let d = TestDir::new("archworkkeep");
    let kept = {
        let mut w = Work::new(d.path(), "k").expect("work");
        let dir = w.dir.clone();
        w.keep();
        dir
    };
    assert!(kept.is_dir(), "keep() did not disarm the cleanup");
    d.assert_contains(&kept);
    std::fs::remove_dir_all(&kept).ok();
}
