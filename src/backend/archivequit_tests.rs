// u11 round 4: a quit cancels each detached compress and convert under one shutdown budget.
use super::{archivedone_line, compress, convert_one, run_archive, run_convert};
use crate::backend::archive::Formats;
use crate::backend::archivework::{drain_secs, Work, CANCEL_DRAIN_SECS, WORK_PREFIX};
use crate::backend::convert;
use crate::backend::dirsizeworker::Worker;
use crate::backend::events::Event;
use crate::backend::opscancel::DetachedJobs;
use crate::backend::opsdispatch::Ops;
use crate::backend::opsreq::OpMsg;
use crate::backend::run::{drain, DRAIN_LIMIT, UI_QUIT_DEADLINE_SECS};
use crate::backend::sandbox;
use crate::backend::state::{State, Tables};
use crate::backend::thumbcache::Cache;
use crate::backend::thumbs::{Done, Outcome, Pool};
use crate::backend::testdir::TestDir;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

// Sample wire line: {"t":"archivedone","id":41,"ok":false,"verified":true,"err":"cancelled"}
#[test]
fn a_pre_cancelled_compress_answers_cancelled_and_leaves_no_work_folder() {
    let d = TestDir::new("archquitcancel");
    d.file("a.txt", "body");
    let dest = d.join("out.zip");
    let paths = vec![d.join("a.txt").to_string_lossy().to_string()];
    let f = Formats::from_tools(true, true);
    let (tx, rx) = std::sync::mpsc::channel();
    let cancel = Arc::new(AtomicBool::new(true));
    let began = Instant::now();
    run_archive(41, true, paths, "zip".to_string(), PathBuf::from("/nonexistent"),
        dest.clone(), &f, tx, None, Arc::clone(&cancel), None);
    let line = match rx.recv_timeout(Duration::from_secs(15)).unwrap() {
        OpMsg::Meta { line } => line,
        other => panic!("a compress answers Meta, got {:?}", std::mem::discriminant(&other)),
    };
    assert!(began.elapsed() < Duration::from_secs(drain_secs()),
        "a pre-cancelled compress waited out the drain bound");
    assert!(!crate::json::field_bool(&line, "ok"), "a cancelled compress must not report ok: {}", line);
    assert!(crate::json::field_str(&line, "err").unwrap_or_default().contains("cancelled"),
        "a quit cancel must reach the running compress: {}", line);
    assert!(!dest.exists(), "a cancelled compress published a destination");
    assert_eq!(work_litter(d.path()), 0, "a cancelled compress left its staging directory behind");
}

// A compress nobody cancelled answers its own error, never the quit one.
#[test]
fn a_compress_without_a_cancel_is_never_answered_cancelled() {
    let d = TestDir::new("archquitclean");
    d.file("a.txt", "body");
    let dest = d.join("out.zip");
    let paths = vec![d.join("a.txt").to_string_lossy().to_string()];
    let f = Formats::from_tools(false, false);
    let (tx, rx) = std::sync::mpsc::channel();
    run_archive(42, true, paths, "zip".to_string(), PathBuf::from("/nonexistent"),
        dest.clone(), &f, tx, None, Arc::new(AtomicBool::new(false)), None);
    let line = match rx.recv_timeout(Duration::from_secs(15)).unwrap() {
        OpMsg::Meta { line } => line,
        other => panic!("a compress answers Meta, got {:?}", std::mem::discriminant(&other)),
    };
    assert!(!crate::json::field_bool(&line, "ok"));
    assert!(!crate::json::field_str(&line, "err").unwrap_or_default().contains("cancelled"),
        "a compress nobody cancelled must not read as cancelled: {}", line);
    assert!(!dest.exists(), "a failed compress published a destination");
}

// The tracked flag is removed with the answer, so a later quit cancels nothing.
#[test]
fn a_finished_compress_leaves_no_tracked_flag_for_a_quit() {
    let tracked = Arc::new(DetachedJobs::new());
    let flag = Arc::new(AtomicBool::new(false));
    tracked.insert(43, &flag);
    let jobs = Arc::clone(&tracked);
    let d = TestDir::new("archquittrack");
    d.file("a.txt", "body");
    let dest = d.join("out.zip");
    let paths = vec![d.join("a.txt").to_string_lossy().to_string()];
    let f = Formats::from_tools(false, false);
    let (tx, rx) = std::sync::mpsc::channel();
    run_archive(43, true, paths, "zip".to_string(), PathBuf::from("/nonexistent"),
        dest, &f, tx, None, Arc::new(AtomicBool::new(false)), Some(jobs));
    rx.recv_timeout(Duration::from_secs(15)).unwrap();
    assert!(tracked.is_empty(), "a finished compress kept its quit flag behind");
    tracked.cancel_all();
    assert!(!flag.load(Ordering::Relaxed));
}

// A thumb finishing during the detached wait is reported, and the drain still ends promptly.
#[test]
fn a_thumb_finishing_during_the_detached_wait_is_reported() {
    let d = TestDir::new("archquitdrainthumb");
    let tb = Tables::load();
    let (done_tx, _done_rx) = std::sync::mpsc::channel();
    let pool = Pool::new(1, done_tx, d.join("thumbs"), Arc::clone(&tb.aliases), Arc::clone(&tb.thumbs));
    let cache = Cache::at(d.join("cache"));
    let (ev_tx, ev_rx) = std::sync::mpsc::channel();
    let mut st = State::new(Worker::new(ev_tx.clone()));
    let (op_tx, _op_rx) = std::sync::mpsc::channel();
    let mut ops = Ops::new(op_tx);
    // One asked thumb row still outstanding.
    let row_path = d.join("pic.jpg");
    std::fs::write(&row_path, "pixels").expect("row file");
    st.asked.push((row_path.clone(), 7));
    st.outstanding = 1;
    // One detached job held open the way a running compress is.
    let work = Work::new(d.path(), "arc").expect("work");
    let flag = Arc::new(AtomicBool::new(false));
    ops.detached.insert(77, &flag);
    let waiter = Arc::clone(&flag);
    let jobs = Arc::clone(&ops.detached);
    let answer = ev_tx.clone();
    std::thread::spawn(move || {
        while !waiter.load(Ordering::Relaxed) { std::thread::sleep(Duration::from_millis(10)); }
        drop(work);
        let _ = answer.send(Event::Op(OpMsg::Meta { line: archivedone_line(77, false, true, "cancelled") }));
        jobs.remove(77);
    });
    // The thumb lands while the detached job is still running.
    let thumb_file = d.join("pic.png");
    ev_tx.send(Event::Thumb(Done { path: row_path, result: Outcome::Ready(thumb_file), ms: 1.0, trace: None })).ok();
    let mut out = Vec::new();
    let began = Instant::now();
    drain(&mut out, &mut st, &mut ops, &ev_rx, &pool, &cache);
    assert!(began.elapsed() < DRAIN_LIMIT, "drain waited out its budget with work already answered");
    let text = String::from_utf8(out).unwrap();
    assert!(text.contains(r#""row":7"#) && text.contains("pic.png"), "a thumb finishing mid-drain was dropped: {}", text);
    assert!(text.contains(r#""id":77"#) && text.contains("cancelled"), "drain returned before the job's archivedone: {}", text);
    assert!(ops.detached.is_empty() && st.outstanding == 0, "drain returned with work still tracked");
    assert_eq!(work_litter(d.path()), 0, "a quit drain left the job's staging directory behind");
}

// A job that forgets its id a moment after its line must not leave the drain waiting out the whole budget.
#[test]
fn a_drain_rechecks_the_registry_when_the_id_leaves_after_the_line() {
    let d = TestDir::new("archquitlate");
    let tb = Tables::load();
    let (done_tx, _done_rx) = std::sync::mpsc::channel();
    let pool = Pool::new(1, done_tx, d.join("thumbs"), Arc::clone(&tb.aliases), Arc::clone(&tb.thumbs));
    let cache = Cache::at(d.join("cache"));
    let (ev_tx, ev_rx) = std::sync::mpsc::channel();
    let mut st = State::new(Worker::new(ev_tx.clone()));
    let (op_tx, _op_rx) = std::sync::mpsc::channel();
    let mut ops = Ops::new(op_tx);
    ops.detached.insert(78, &Arc::new(AtomicBool::new(false)));
    let jobs = Arc::clone(&ops.detached);
    std::thread::spawn(move || {
        let _ = ev_tx.send(Event::Op(OpMsg::Meta { line: archivedone_line(78, false, true, "cancelled") }));
        std::thread::sleep(Duration::from_millis(300));
        jobs.remove(78);
    });
    let mut out = Vec::new();
    let began = Instant::now();
    drain(&mut out, &mut st, &mut ops, &ev_rx, &pool, &cache);
    assert!(began.elapsed() < Duration::from_secs(5), "the drain waited out its budget for an id that left just after its line");
    assert!(String::from_utf8(out).unwrap().contains(r#""id":78"#), "the drain dropped the job's archivedone");
}

// The single shutdown budget covers the cancel drain bound and stays under the UI deadline.
#[test]
fn the_shutdown_budget_covers_the_cancel_drain_and_beats_the_ui_deadline() {
    assert!(DRAIN_LIMIT.as_secs() > CANCEL_DRAIN_SECS, "the shutdown budget must cover the cancel drain bound");
    assert!(DRAIN_LIMIT.as_secs() < UI_QUIT_DEADLINE_SECS, "the shutdown budget must beat the UI quit deadline");
}

// Two detached jobs finishing together both answer, because each line precedes its removal.
#[test]
fn two_detached_jobs_finishing_together_both_answer() {
    let d = TestDir::new("archquittwo");
    let input = d.file("in.png", "pixels");
    let taken = d.file("out.jpg", "taken");
    for round in 0..20 {
        let jobs = Arc::new(DetachedJobs::new());
        let (tx, rx) = std::sync::mpsc::channel();
        // Registration precedes the spawn the way start_archive and start_convert do it.
        jobs.insert(61, &Arc::new(AtomicBool::new(false)));
        jobs.insert(62, &Arc::new(AtomicBool::new(false)));
        let first = std::thread::spawn({
            let jobs = Arc::clone(&jobs);
            let tx = tx.clone();
            let none = Formats::from_tools(false, false);
            let path = d.join("a.txt");
            std::fs::write(&path, "body").ok();
            let paths = vec![path.to_string_lossy().to_string()];
            move || run_archive(61, true, paths, "zip".to_string(), PathBuf::from("/nonexistent"),
                PathBuf::from("/nonexistent/out.zip"), &none, tx, None,
                Arc::new(AtomicBool::new(false)), Some(jobs))
        });
        let second = std::thread::spawn({
            let jobs = Arc::clone(&jobs);
            let tx = tx.clone();
            let (my_in, my_taken) = (input.clone(), taken.clone());
            move || run_convert(62, round, my_in, my_taken, false, tx, None,
                Arc::new(AtomicBool::new(false)), Some(jobs))
        });
        // A drain sees the empty registry and stops; both lines must already be readable then.
        while !jobs.is_empty() { std::thread::yield_now(); }
        let a = rx.try_recv();
        let b = rx.try_recv();
        first.join().expect("compress thread");
        second.join().expect("convert thread");
        assert!(jobs.is_empty());
        let a = a.expect("drain saw an empty registry with a terminal line still unread");
        let b = b.expect("drain saw an empty registry with a terminal line still unread");
        // Either thread can answer first; what matters is both lines precede the empty registry.
        let (compress, convert) = match (&a, &b) {
            (OpMsg::Meta { line }, _) if line.contains(r#""id":61"#) => (line_of(&a), line_of(&b)),
            _ => (line_of(&b), line_of(&a)),
        };
        assert!(compress.contains(r#""id":61"#), "no compress answer among the two lines: {} / {}", line_of(&a), line_of(&b));
        assert!(convert.contains(r#""id":62"#), "no convert answer among the two lines: {} / {}", line_of(&a), line_of(&b));
    }
}

// Convert runs under a finite cap equal to its own, and a failure there names convert.
#[test]
fn convert_keeps_its_cpu_cap_and_names_itself_on_failure() {
    if crate::backend::sandboxprobe::skipped() { return; }
    let d = TestDir::new("archconvertcap");
    let mut work = Work::new(d.path(), "cvt").expect("work");
    let idle = AtomicBool::new(false);
    // The jail reports the convert cap itself, which is what makes the measurement about convert.
    let probe = vec!["/usr/bin/python3".to_string(), "-c".to_string(),
        format!("import resource,sys; sys.exit(0 if resource.getrlimit(resource.RLIMIT_CPU)[0]=={} else 1)", sandbox::CPU_SECONDS)];
    crate::backend::archivework::run_boxed_cancellable_capped("convert", probe, d.path(), &mut work, &idle)
        .expect("convert runs under its finite cap");
    let failing = crate::backend::archivework::run_boxed_cancellable_capped(
        "convert", vec!["/usr/bin/false".to_string()], d.path(), &mut work, &idle).unwrap_err();
    assert_eq!(failing.where_, "convert", "a failure on the convert path names convert");
}

// Sample wire line: {"t":"convertdone","id":51,"requestId":9,"source":"/x/a.png","ok":false,"path":"/x/a.jpg","err":"cancelled","collision":false}
#[test]
fn a_pre_cancelled_convert_answers_cancelled_and_leaves_no_work_folder() {
    let d = TestDir::new("archquitconvert");
    let input = d.file("a.png", "pixels");
    let dest = d.join("a.jpg");
    let (tx, rx) = std::sync::mpsc::channel();
    run_convert(51, 9, input, dest.clone(), false, tx, None, Arc::new(AtomicBool::new(true)), None);
    let line = match rx.recv_timeout(Duration::from_secs(15)).unwrap() {
        OpMsg::Meta { line } => line,
        other => panic!("a convert answers Meta, got {:?}", std::mem::discriminant(&other)),
    };
    assert!(!crate::json::field_bool(&line, "ok"), "a cancelled convert must not report ok: {}", line);
    assert!(crate::json::field_str(&line, "err").unwrap_or_default().contains("cancelled"),
        "a quit cancel must reach the running convert: {}", line);
    assert!(!dest.exists(), "a cancelled convert published a destination");
    assert_eq!(work_litter(d.path()), 0, "a cancelled convert left its staging directory behind");
}

// A convert nobody cancelled answers its own error, never the quit one.
#[test]
fn a_convert_without_a_cancel_is_never_answered_cancelled() {
    let d = TestDir::new("archquitconvertclean");
    let input = d.file("a.png", "pixels");
    let dest = d.file("a.jpg", "taken");
    let (tx, rx) = std::sync::mpsc::channel();
    run_convert(52, 9, input, dest, false, tx, None, Arc::new(AtomicBool::new(false)), None);
    let line = match rx.recv_timeout(Duration::from_secs(15)).unwrap() {
        OpMsg::Meta { line } => line,
        other => panic!("a convert answers Meta, got {:?}", std::mem::discriminant(&other)),
    };
    assert!(!crate::json::field_bool(&line, "ok"));
    assert!(!crate::json::field_str(&line, "err").unwrap_or_default().contains("cancelled"),
        "a convert nobody cancelled must not read as cancelled: {}", line);
}

// A flag set while compress already runs cancels the child and cleans the stage.
#[test]
fn a_flag_set_while_compress_runs_cancels_and_cleans_up() {
    if crate::backend::sandboxprobe::skipped() { return; }
    if !have_bsdtar() { return; }
    let d = TestDir::new("archquitmidcompress");
    let fifo = d.join("stall.bin");
    crate::backend::fifotest::mkfifo(&fifo);
    let dest = d.join("out.zip");
    let flag = Arc::new(AtomicBool::new(false));
    let worker = Arc::clone(&flag);
    let parent = d.path().to_path_buf();
    let handle = std::thread::spawn(move || {
        let f = Formats::from_tools(true, true);
        compress(&f, &parent, &["stall.bin".to_string()], "zip", &parent.join("out.zip"), &worker)
    });
    // Past registration, inside the runner: the stage exists and the tool is blocked on the fifo.
    wait_for_work_dir(d.path(), Duration::from_secs(10));
    flag.store(true, Ordering::Relaxed);
    let done = Instant::now() + Duration::from_secs(20);
    while !handle.is_finished() && Instant::now() < done { std::thread::sleep(Duration::from_millis(50)); }
    assert!(handle.is_finished(), "a running compress ignored the quit flag");
    let e = handle.join().expect("compress thread").unwrap_err();
    assert!(e.msg.contains("cancelled"), "a cancelled compress must say so: {}", e.msg);
    assert!(!dest.exists(), "a cancelled compress published a destination");
    assert_eq!(work_litter(d.path()), 0, "a cancelled compress left its staging directory behind");
}

// A flag set while convert already runs cancels the child and cleans the stage.
#[test]
fn a_flag_set_while_convert_runs_cancels_and_cleans_up() {
    if crate::backend::sandboxprobe::skipped() { return; }
    if !convert::available() { return; }
    let d = TestDir::new("archquitmidconvert");
    let fifo = d.join("stall.png");
    crate::backend::fifotest::mkfifo(&fifo);
    let dest = d.join("out.jpg");
    let flag = Arc::new(AtomicBool::new(false));
    let worker = Arc::clone(&flag);
    let (fifo_in, dest_in) = (fifo.clone(), dest.clone());
    let handle = std::thread::spawn(move || convert_one(&fifo_in, &dest_in, false, &worker));
    // Past the early check, inside the runner: the stage exists and the tool is blocked on the fifo.
    wait_for_work_dir(d.path(), Duration::from_secs(10));
    flag.store(true, Ordering::Relaxed);
    let done = Instant::now() + Duration::from_secs(20);
    while !handle.is_finished() && Instant::now() < done { std::thread::sleep(Duration::from_millis(50)); }
    assert!(handle.is_finished(), "a running convert ignored the quit flag");
    let e = handle.join().expect("convert thread").unwrap_err();
    assert!(e.msg.contains("cancelled"), "a cancelled convert must say so: {}", e.msg);
    assert!(!dest.exists(), "a cancelled convert published a destination");
    assert_eq!(work_litter(d.path()), 0, "a cancelled convert left its staging directory behind");
}

// How many staging folders a directory holds; every destructive test funnels through here.
fn work_litter(dir: &Path) -> usize {
    std::fs::read_dir(dir).unwrap()
        .filter(|e| e.as_ref().map(|x| x.file_name().to_string_lossy().starts_with(WORK_PREFIX)).unwrap_or(false))
        .count()
}

// The job is past registration once its stage exists; a flag set then lands mid-run.
fn wait_for_work_dir(dir: &Path, bound: Duration) {
    let start = Instant::now();
    while start.elapsed() < bound {
        if work_litter(dir) > 0 { return; }
        std::thread::sleep(Duration::from_millis(10));
    }
    panic!("the job never reached its work directory");
}

// bsdtar builds the stall fixture, so without it the mid-run compress test proves nothing.
fn have_bsdtar() -> bool {
    std::process::Command::new("bsdtar").arg("--version").output().map(|o| o.status.success()).unwrap_or(false)
}

// The line inside a terminal message, for failure shapes that name the wrong answer.
fn line_of(msg: &OpMsg) -> &str {
    match msg {
        OpMsg::Meta { line } => line,
        _ => "<not a terminal line>",
    }
}
