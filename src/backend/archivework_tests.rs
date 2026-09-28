use super::*;
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
    let work = Work::new(d.path(), "ext").expect("work");
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
                                           d.path(), &work.dir, &cancel, &started_pid).unwrap_err();
    notifier.join().expect("the cancellation notifier finished");
    // The child dies by SIGKILL here, so a runner that read the status before the cancel token would
    // report a kill for a cancel the operator asked for; this asserts the token wins.
    assert_eq!(e.msg, "cancelled");
    assert!(began.elapsed() < Duration::from_secs(10), "a cancelled child was waited out");
    assert!(work.dir.is_dir(), "the runner must not remove the caller's staging directory");
    let pid = started_pid.load(Ordering::SeqCst);
    assert_ne!(pid, 0, "the cancellation fixture never observed its child pid");
    let proc_entry = PathBuf::from(format!("/proc/{pid}"));
    assert!(!proc_entry.exists(), "the owned child was not reaped");
}

// Issue #211: an extractor the kernel killed arrived as the empty-stderr fallback, which names a bad
// archive for a job that was killed. The status is then the only evidence, and bwrap spells an
// application the kernel killed as exit 128+n while keeping a real signal for its own death, so both
// spellings have to read as the one sentence. Raw values are wait(2) statuses: 9 is a signal, n << 8 an
// exit status.
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

// The tool's own line is the better diagnosis and it is what an operator gets for a genuinely bad
// archive. The old read took the last line whatever it was, so a trailing blank one produced an empty
// message and a whitespace one produced whitespace.
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

// The sentence above through the real jail, so the wiring is proven and not only the formatter, and so
// is the other half of #211's ask: a job that only exited non-zero says that, and nothing claims a kill
// it did not see.
#[test]
fn a_killed_tool_is_reported_as_killed_rather_than_as_a_bad_archive() {
    if crate::backend::sandboxprobe::skipped() { return; }
    let d = TestDir::new("archkilled");
    let work = Work::new(d.path(), "kill").expect("work");
    // The tool kills itself and prints nothing, which is what a killed unpack looks like from here.
    let killed = run_boxed("archive",
                           vec!["/usr/bin/sh".to_string(), "-c".to_string(), "kill -9 $$".to_string()],
                           d.path(), &work.dir).unwrap_err();
    assert!(killed.msg.contains("killed by signal SIGKILL (9)"), "a kill must name the signal: {}", killed.msg);
    assert!(!killed.msg.contains("failed"), "and must not read as the old empty-stderr fallback: {}", killed.msg);
    let exited = run_boxed("archive", vec!["/usr/bin/false".to_string()], d.path(), &work.dir).unwrap_err();
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
