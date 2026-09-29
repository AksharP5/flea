// A quit cancels each detached compress and convert under one shutdown budget, and a job leaves the quit registry when its line is written.
use super::{archivedone_line, compress, convert_one, run_archive, run_convert};
use crate::backend::archive::Formats;
use crate::backend::archivework::{drain_secs, last_cpu, Work, WORK_PREFIX};
use crate::backend::convert;
use crate::backend::dirsizeworker::Worker;
use crate::backend::events::Event;
use crate::backend::opsdispatch::{report_op, Ops};
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
use std::sync::mpsc::{Receiver, Sender};
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
        dest.clone(), &f, tx, None, Arc::clone(&cancel));
    let line = match rx.recv_timeout(Duration::from_secs(15)).unwrap() {
        OpMsg::DetachedDone { id, line } => { assert_eq!(id, 41, "the terminal message must carry the registry id"); line }
        other => panic!("a compress answers DetachedDone, got {:?}", std::mem::discriminant(&other)),
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
        dest.clone(), &f, tx, None, Arc::new(AtomicBool::new(false)));
    let line = match rx.recv_timeout(Duration::from_secs(15)).unwrap() {
        OpMsg::DetachedDone { id, line } => { assert_eq!(id, 42, "the terminal message must carry the registry id"); line }
        other => panic!("a compress answers DetachedDone, got {:?}", std::mem::discriminant(&other)),
    };
    assert!(!crate::json::field_bool(&line, "ok"));
    assert!(!crate::json::field_str(&line, "err").unwrap_or_default().contains("cancelled"),
        "a compress nobody cancelled must not read as cancelled: {}", line);
    assert!(!dest.exists(), "a failed compress published a destination");
}

// A job leaves the quit registry when its line is written, so a later quit cancels nothing.
#[test]
fn writing_a_jobs_terminal_line_forgets_it_for_a_quit() {
    let (op_tx, _op_rx) = std::sync::mpsc::channel();
    let mut ops = Ops::new(op_tx);
    let flag = Arc::new(AtomicBool::new(false));
    ops.detached.insert(43, &flag);
    let mut out = Vec::new();
    report_op(&mut out, &mut ops, OpMsg::DetachedDone { id: 43, line: archivedone_line(43, true, true, "") });
    assert!(ops.detached.is_empty(), "a written terminal line kept its quit flag behind");
    ops.detached.cancel_all();
    assert!(!flag.load(Ordering::Relaxed));
    assert!(String::from_utf8(out).unwrap().contains(r#""id":43"#), "the terminal line was not written");
}

// The parts drain reads and writes, over a channel the test feeds the way the op forwarder does.
fn drain_rig(d: &TestDir) -> (State, Ops, Pool, Cache, Sender<Event>, Receiver<Event>) {
    let tb = Tables::load();
    let (done_tx, _done_rx) = std::sync::mpsc::channel();
    let pool = Pool::new(1, done_tx, d.join("thumbs"), Arc::clone(&tb.aliases), Arc::clone(&tb.thumbs));
    let (ev_tx, ev_rx) = std::sync::mpsc::channel();
    let st = State::new(Worker::new(ev_tx.clone()));
    let (op_tx, _op_rx) = std::sync::mpsc::channel();
    (st, Ops::new(op_tx), pool, Cache::at(d.join("cache")), ev_tx, ev_rx)
}

// A thumb finishing during the detached wait is reported, and the drain still ends promptly.
#[test]
fn a_thumb_finishing_during_the_detached_wait_is_reported() {
    let d = TestDir::new("archquitdrainthumb");
    let (mut st, mut ops, pool, cache, ev_tx, ev_rx) = drain_rig(&d);
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
    let answer = ev_tx.clone();
    std::thread::spawn(move || {
        while !waiter.load(Ordering::Relaxed) { std::thread::sleep(Duration::from_millis(10)); }
        drop(work);
        let _ = answer.send(Event::Op(OpMsg::DetachedDone { id: 77, line: archivedone_line(77, false, true, "cancelled") }));
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

// Lines queued behind each other are all written before the registry can read empty, because only writing a line empties it.
#[test]
fn a_drain_writes_every_detached_line_before_the_registry_reads_empty() {
    let d = TestDir::new("archquittwo");
    let (mut st, mut ops, pool, cache, ev_tx, ev_rx) = drain_rig(&d);
    for id in [61, 62] {
        ops.detached.insert(id, &Arc::new(AtomicBool::new(false)));
        ev_tx.send(Event::Op(OpMsg::DetachedDone { id, line: archivedone_line(id, false, true, "cancelled") })).ok();
    }
    let mut out = Vec::new();
    let began = Instant::now();
    drain(&mut out, &mut st, &mut ops, &ev_rx, &pool, &cache);
    let text = String::from_utf8(out).unwrap();
    assert!(text.contains(r#""id":61"#) && text.contains(r#""id":62"#), "a drain left a terminal line unwritten: {}", text);
    assert!(ops.detached.is_empty(), "a drain returned with a job still tracked");
    assert!(began.elapsed() < Duration::from_secs(5), "a drain waited out its budget with every line already queued");
}

// The backend's shutdown budget is measured against ui/Backend.qml's quitDeadline, so a lowered UI deadline goes red here.
// Sample input: a Timer block `id: quitDeadline` followed by `interval: 30000`.
#[test]
fn the_ui_quit_deadline_is_the_one_the_shutdown_budget_stays_under() {
    let qml = include_str!("../../ui/Backend.qml");
    let timer = &qml[qml.find("id: quitDeadline").expect("Backend.qml names quitDeadline")..];
    let interval = timer.lines().find_map(|line| line.trim().strip_prefix("interval:")).expect("quitDeadline has an interval");
    let millis: u64 = interval.trim().parse().expect("quitDeadline's interval is milliseconds");
    assert_eq!(millis, UI_QUIT_DEADLINE_SECS * 1000, "ui/Backend.qml quitDeadline and run.rs UI_QUIT_DEADLINE_SECS must agree");
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
    run_convert(51, 9, input, dest.clone(), false, tx, None, Arc::new(AtomicBool::new(true)));
    let line = match rx.recv_timeout(Duration::from_secs(15)).unwrap() {
        OpMsg::DetachedDone { id, line } => { assert_eq!(id, 51, "the terminal message must carry the registry id"); line }
        other => panic!("a convert answers DetachedDone, got {:?}", std::mem::discriminant(&other)),
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
    run_convert(52, 9, input, dest, false, tx, None, Arc::new(AtomicBool::new(false)));
    let line = match rx.recv_timeout(Duration::from_secs(15)).unwrap() {
        OpMsg::DetachedDone { id, line } => { assert_eq!(id, 52, "the terminal message must carry the registry id"); line }
        other => panic!("a convert answers DetachedDone, got {:?}", std::mem::discriminant(&other)),
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
        let result = compress(&f, &parent, &["stall.bin".to_string()], "zip", &parent.join("out.zip"), &worker);
        (result, last_cpu())
    });
    // Past registration, inside the runner: the stage exists and the tool is blocked on the fifo.
    wait_for_work_dir(d.path(), Duration::from_secs(10));
    flag.store(true, Ordering::Relaxed);
    let done = Instant::now() + Duration::from_secs(20);
    while !handle.is_finished() && Instant::now() < done { std::thread::sleep(Duration::from_millis(50)); }
    assert!(handle.is_finished(), "a running compress ignored the quit flag");
    let (result, cap) = handle.join().expect("compress thread");
    let e = result.unwrap_err();
    assert!(e.msg.contains("cancelled"), "a cancelled compress must say so: {}", e.msg);
    assert_eq!(cap, Some(None), "compress must run its jail without a CPU cap");
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
    let handle = std::thread::spawn(move || (convert_one(&fifo_in, &dest_in, false, &worker), last_cpu()));
    // Past the early check, inside the runner: the stage exists and the tool is blocked on the fifo.
    wait_for_work_dir(d.path(), Duration::from_secs(10));
    flag.store(true, Ordering::Relaxed);
    let done = Instant::now() + Duration::from_secs(20);
    while !handle.is_finished() && Instant::now() < done { std::thread::sleep(Duration::from_millis(50)); }
    assert!(handle.is_finished(), "a running convert ignored the quit flag");
    let (result, cap) = handle.join().expect("convert thread");
    let e = result.unwrap_err();
    assert!(e.msg.contains("cancelled"), "a cancelled convert must say so: {}", e.msg);
    assert_eq!(cap, Some(Some(sandbox::CPU_SECONDS)), "convert_one must run its jail under the finite CPU cap");
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
