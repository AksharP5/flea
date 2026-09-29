// u11 round 2: a quit sets each detached flag, then waits past the cancel drain bound.
use super::{archivedone_line, run_archive, run_convert};
use crate::backend::archive::Formats;
use crate::backend::archivework::{drain_secs, set_drain_secs, Work, CANCEL_DRAIN_SECS, WORK_PREFIX};
use crate::backend::events::Event;
use crate::backend::opscancel::DetachedJobs;
use crate::backend::opsdispatch::Ops;
use crate::backend::opsreq::OpMsg;
use crate::backend::run::{drain_detached, DETACHED_WAIT};
use crate::backend::testdir::TestDir;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

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
    let began = std::time::Instant::now();
    run_archive(41, true, paths, "zip".to_string(), PathBuf::from("/nonexistent"),
        dest.clone(), &f, tx, None, Arc::clone(&cancel), None);
    let line = match rx.recv_timeout(std::time::Duration::from_secs(15)).unwrap() {
        OpMsg::Meta { line } => line,
        other => panic!("a compress answers Meta, got {:?}", std::mem::discriminant(&other)),
    };
    assert!(began.elapsed() < std::time::Duration::from_secs(drain_secs()),
        "a pre-cancelled compress waited out the drain bound");
    assert!(!crate::json::field_bool(&line, "ok"), "a cancelled compress must not report ok: {}", line);
    assert!(crate::json::field_str(&line, "err").unwrap_or_default().contains("cancelled"),
        "a quit cancel must reach the running compress: {}", line);
    assert!(!dest.exists(), "a cancelled compress published a destination");
    let litter = std::fs::read_dir(d.path()).unwrap()
        .filter(|e| e.as_ref().map(|x| x.file_name().to_string_lossy().starts_with(WORK_PREFIX)).unwrap_or(false))
        .count();
    assert_eq!(litter, 0, "a cancelled compress left its staging directory behind");
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
    let line = match rx.recv_timeout(std::time::Duration::from_secs(15)).unwrap() {
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
    rx.recv_timeout(std::time::Duration::from_secs(15)).unwrap();
    assert!(tracked.is_empty(), "a finished compress kept its quit flag behind");
    tracked.cancel_all();
    assert!(!flag.load(Ordering::Relaxed));
}

// A quit through the drain sets the flag and returns only after the job's archivedone.
#[test]
fn a_quit_drain_waits_for_a_held_open_job_and_leaves_no_work_folder() {
    let (op_tx, _op_rx) = std::sync::mpsc::channel();
    let (ev_tx, ev_rx) = std::sync::mpsc::channel();
    let mut ops = Ops::new(op_tx);
    let d = TestDir::new("archquitdrain");
    let work = Work::new(d.path(), "arc").expect("work");
    assert!(work.dir.is_dir());
    let flag = Arc::new(AtomicBool::new(false));
    ops.detached.insert(77, &flag);
    let waiter = Arc::clone(&flag);
    let jobs = Arc::clone(&ops.detached);
    let answer = ev_tx.clone();
    std::thread::spawn(move || {
        while !waiter.load(Ordering::Relaxed) { std::thread::sleep(std::time::Duration::from_millis(10)); }
        drop(work);
        jobs.remove(77);
        let _ = answer.send(Event::Op(OpMsg::Meta { line: archivedone_line(77, false, true, "cancelled") }));
    });
    let mut out = Vec::new();
    let began = std::time::Instant::now();
    drain_detached(&mut out, &mut ops, &ev_rx, began + DETACHED_WAIT);
    assert!(began.elapsed() < DETACHED_WAIT, "drain returned past its own bound");
    assert!(ops.detached.is_empty(), "drain returned with a job still tracked");
    let text = String::from_utf8(out).unwrap();
    assert!(text.contains(r#""id":77"#) && text.contains("cancelled"), "drain returned before the job's archivedone: {}", text);
    let litter = std::fs::read_dir(d.path()).unwrap()
        .filter(|e| e.as_ref().map(|x| x.file_name().to_string_lossy().starts_with(WORK_PREFIX)).unwrap_or(false))
        .count();
    assert_eq!(litter, 0, "a quit drain left the job's staging directory behind");
}

// The quit wait covers the cancel drain bound, so a cancelled job always finishes first.
#[test]
fn the_quit_wait_covers_the_cancel_drain_bound() {
    set_drain_secs(3);
    assert!(DETACHED_WAIT.as_secs() >= drain_secs(), "the quit wait must cover the cancel drain bound");
    set_drain_secs(CANCEL_DRAIN_SECS);
}

// Sample wire line: {"t":"convertdone","id":51,"requestId":9,"source":"/x/a.png","ok":false,"path":"/x/a.jpg","err":"cancelled","collision":false}
#[test]
fn a_pre_cancelled_convert_answers_cancelled_and_leaves_no_work_folder() {
    let d = TestDir::new("archquitconvert");
    let input = d.file("a.png", "pixels");
    let dest = d.join("a.jpg");
    let (tx, rx) = std::sync::mpsc::channel();
    run_convert(51, 9, input, dest.clone(), false, tx, None, Arc::new(AtomicBool::new(true)), None);
    let line = match rx.recv_timeout(std::time::Duration::from_secs(15)).unwrap() {
        OpMsg::Meta { line } => line,
        other => panic!("a convert answers Meta, got {:?}", std::mem::discriminant(&other)),
    };
    assert!(!crate::json::field_bool(&line, "ok"), "a cancelled convert must not report ok: {}", line);
    assert!(crate::json::field_str(&line, "err").unwrap_or_default().contains("cancelled"),
        "a quit cancel must reach the running convert: {}", line);
    assert!(!dest.exists(), "a cancelled convert published a destination");
    let litter = std::fs::read_dir(d.path()).unwrap()
        .filter(|e| e.as_ref().map(|x| x.file_name().to_string_lossy().starts_with(WORK_PREFIX)).unwrap_or(false))
        .count();
    assert_eq!(litter, 0, "a cancelled convert left its staging directory behind");
}

// A convert nobody cancelled answers its own error, never the quit one.
#[test]
fn a_convert_without_a_cancel_is_never_answered_cancelled() {
    let d = TestDir::new("archquitconvertclean");
    let input = d.file("a.png", "pixels");
    let dest = d.file("a.jpg", "taken");
    let (tx, rx) = std::sync::mpsc::channel();
    run_convert(52, 9, input, dest, false, tx, None, Arc::new(AtomicBool::new(false)), None);
    let line = match rx.recv_timeout(std::time::Duration::from_secs(15)).unwrap() {
        OpMsg::Meta { line } => line,
        other => panic!("a convert answers Meta, got {:?}", std::mem::discriminant(&other)),
    };
    assert!(!crate::json::field_bool(&line, "ok"));
    assert!(!crate::json::field_str(&line, "err").unwrap_or_default().contains("cancelled"),
        "a convert nobody cancelled must not read as cancelled: {}", line);
}
