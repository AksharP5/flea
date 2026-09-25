use super::*;
use crate::backend::copyfile::Progress;
use crate::backend::testdir::TestDir;

fn quiet<'a>(flag: &'a std::sync::atomic::AtomicBool, sink: &'a mut dyn FnMut(u64, u64), ctx: &'a mut Ctx) -> Progress<'a> {
    Progress { cancel: flag, on_bytes: sink, partial: None, tree: None, manifest: None, durability: Some(ctx) }
}

#[test]
fn a_marked_testdir_target_counts_as_usb_without_real_hardware() {
    test_reset();
    let d = TestDir::new("durable-class");
    let out = d.dir("out");
    test_mark_durable(&out);
    assert!(dest_is_durable(&out), "a test-marked target is usb");
    assert!(!dest_is_durable(d.path()), "its sibling stays local");
}

#[test]
fn fat_names_and_magics_count_as_durable() {
    assert!(fat_name_is_durable("vfat"));
    assert!(fat_name_is_durable("exfat"));
    assert!(fat_name_is_durable("ntfs"));
    assert!(fat_name_is_durable("VFAT"), "the mount table never promises a case");
    assert!(!fat_name_is_durable("ext4"));
    assert!(!fat_name_is_durable("btrfs"));
    assert!(fat_magic_is_durable(0x4D44));
    assert!(fat_magic_is_durable(0x2011BAB0));
    assert!(fat_magic_is_durable(0x5346544E));
    assert!(!fat_magic_is_durable(0xEF53));
}

#[test]
fn a_durable_copy_fsyncs_each_file_and_confirms_its_parent_once() {
    test_reset();
    let d = TestDir::new("durable-counts");
    let src = d.dir("src");
    std::fs::write(src.join("a.txt"), "a").unwrap();
    std::fs::write(src.join("b.txt"), "b").unwrap();
    let out = d.dir("out");
    test_mark_durable(&out);
    let mut ctx = Ctx::begin(&out);
    assert!(ctx.durable, "the marked target is durable");
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = quiet(&flag, &mut sink, &mut ctx);
    crate::backend::copyfile::copy_any(&src.join("a.txt"), &out.join("a.txt"), &mut p).expect("copy");
    crate::backend::copyfile::copy_any(&src.join("b.txt"), &out.join("b.txt"), &mut p).expect("copy");
    drop(p);
    assert_eq!(test_counts().0, 2, "one fsync per file, got {:?}", test_counts());
    ctx.flush_dirs().expect("real dirs flush");
    assert_eq!(test_counts(), (2, 1), "one parent flush for two files, got {:?}", test_counts());
}

#[test]
fn touched_dirs_are_recorded_once_and_ordered_deepest_first() {
    test_reset();
    let d = TestDir::new("durable-order");
    test_mark_durable(d.path());
    let mut ctx = Ctx::begin(d.path());
    let (a, b) = (d.join("a"), d.join("a/b"));
    ctx.touch(&a);
    ctx.touch(&a);
    ctx.touch(&b);
    ctx.touch(&a);
    assert_eq!(ctx.ordered(), vec![b, a]);
}

#[test]
fn a_local_copy_fsyncs_nothing() {
    test_reset();
    let d = TestDir::new("durable-local");
    let src = d.file("a.txt", "body");
    let out = d.dir("out");
    let mut ctx = Ctx::begin(&out);
    assert!(!ctx.durable, "an unmarked TestDir is local");
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = quiet(&flag, &mut sink, &mut ctx);
    crate::backend::copyfile::copy_any(&src, &out.join("a.txt"), &mut p).expect("copy");
    drop(p);
    assert_eq!(test_counts(), (0, 0), "no flush on a local target");
}

#[test]
fn a_failed_fsync_fails_the_copy_like_any_other_write_error() {
    test_reset();
    let d = TestDir::new("durable-fail");
    let src = d.file("a.txt", "body");
    let out = d.dir("out");
    test_mark_durable(&out);
    let mut ctx = Ctx::begin(&out);
    assert!(ctx.durable);
    test_set_fail(true);
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = quiet(&flag, &mut sink, &mut ctx);
    let err = crate::backend::copyfile::copy_any(&src, &out.join("a.txt"), &mut p).expect_err("a failed fsync is a failed copy");
    assert_eq!(err.where_, "copy");
    assert!(p.partial.is_some(), "the partial is journalled for undo: {:?}", p.partial);
    assert_eq!(test_counts().0, 1, "the failed flush still counts as called");
}

#[test]
fn the_writing_line_carries_the_phase_the_protocol_documents() {
    let line = writing_line(12);
    assert!(line.contains(r#""t":"transferprogress""#));
    assert!(line.contains(r#""phase":"writing""#), "the final phase rides a progress line: {}", line);
}

#[test]
fn a_durable_transfer_reports_writing_and_durable_true() {
    use crate::backend::opsreq::{run_transfer, OpMsg};
    use std::sync::mpsc::channel;
    use std::sync::Arc;
    test_reset();
    let d = TestDir::new("durable-wire");
    let src = d.file("a.txt", "body");
    let out = d.dir("out");
    test_mark_durable(&out);
    let (tx, rx) = channel();
    run_transfer(7, false, vec![src.to_string_lossy().to_string()], out.clone(), Arc::new(std::sync::atomic::AtomicBool::new(false)), tx);
    let mut saw_writing = false;
    let mut durable = None;
    for msg in rx.iter() {
        match msg {
            OpMsg::Meta { line } if line.contains(r#""phase":"writing""#) => saw_writing = true,
            OpMsg::TransferDone { durable: done_durable, ok, failed, .. } => {
                durable = Some((done_durable, ok, failed));
            }
            _ => {}
        }
    }
    assert!(saw_writing, "the final phase emits one writing line");
    assert_eq!(durable, Some((true, 1, 0)), "every flush succeeded: {:?}", durable);
    let (files, dirs) = test_counts();
    assert_eq!(files, 1, "one file fsync");
    assert!(dirs >= 1, "at least the dest dir, got {:?}", test_counts());
}

#[test]
fn a_local_transfer_reports_durable_false_and_no_writing() {
    use crate::backend::opsreq::{run_transfer, OpMsg};
    use std::sync::mpsc::channel;
    use std::sync::Arc;
    test_reset();
    let d = TestDir::new("durable-wire-local");
    let src = d.file("a.txt", "body");
    let out = d.dir("out");
    let (tx, rx) = channel();
    run_transfer(8, false, vec![src.to_string_lossy().to_string()], out.clone(), Arc::new(std::sync::atomic::AtomicBool::new(false)), tx);
    let mut saw_writing = false;
    let mut durable = None;
    for msg in rx.iter() {
        match msg {
            OpMsg::Meta { line } if line.contains("writing") => saw_writing = true,
            OpMsg::TransferDone { durable: done_durable, .. } => durable = Some(done_durable),
            _ => {}
        }
    }
    assert!(!saw_writing, "no final phase on a local target");
    assert_eq!(durable, Some(false));
    assert_eq!(test_counts(), (0, 0), "no flush on a local target");
}

#[test]
fn a_failed_file_fsync_fails_the_item_and_journals_the_partial() {
    use crate::backend::opsreq::{run_transfer, OpMsg};
    use std::sync::mpsc::channel;
    use std::sync::Arc;
    test_reset();
    let d = TestDir::new("durable-wire-fail");
    let src = d.file("a.txt", "body");
    let out = d.dir("out");
    test_mark_durable(&out);
    test_set_fail(true);
    let (tx, rx) = channel();
    run_transfer(9, false, vec![src.to_string_lossy().to_string()], out.clone(), Arc::new(std::sync::atomic::AtomicBool::new(false)), tx);
    let mut item_err = String::new();
    let mut entry_steps = 0;
    let mut durable = None;
    for msg in rx.iter() {
        match msg {
            OpMsg::Item { ok: false, err, .. } => item_err = err,
            OpMsg::TransferDone { entry, durable: done_durable, ok, failed, .. } => {
                entry_steps = entry.steps.len();
                durable = Some((done_durable, ok, failed));
            }
            _ => {}
        }
    }
    assert!(!item_err.is_empty(), "the file's name rides a copy error");
    assert_eq!(entry_steps, 1, "the partial is journalled for undo");
    assert_eq!(durable, Some((false, 0, 1)), "a failed flush is not durable: {:?}", durable);
    test_set_fail(false);
}

#[test]
fn a_directory_flush_failure_keeps_durable_false_and_says_so() {
    use crate::backend::opsreq::{run_transfer, OpMsg};
    use std::sync::mpsc::channel;
    use std::sync::Arc;
    test_reset();
    let d = TestDir::new("durable-dirfail");
    let src = d.file("a.txt", "body");
    let out = d.dir("out");
    test_mark_durable(&out);
    test_set_fail_dirs(true);
    let (tx, rx) = channel();
    run_transfer(10, false, vec![src.to_string_lossy().to_string()], out.clone(), Arc::new(std::sync::atomic::AtomicBool::new(false)), tx);
    let mut saw_writing = false;
    let mut done = None;
    for msg in rx.iter() {
        match msg {
            OpMsg::Meta { line } if line.contains(r#""phase":"writing""#) => saw_writing = true,
            OpMsg::TransferDone { durable: done_durable, ok, failed, note, .. } => {
                done = Some((done_durable, ok, failed, note));
            }
            _ => {}
        }
    }
    assert!(saw_writing, "the writing phase still runs");
    assert_eq!(done, Some((false, 1, 0, DIR_UNCONFIRMED.to_string())), "the file landed but the folder is unconfirmed: {:?}", done);
    test_set_fail_dirs(false);
}

#[test]
fn duplicate_on_a_durable_target_confirms_the_new_file() {
    test_reset();
    let d = TestDir::new("durable-dup");
    let src = d.file("a.txt", "body");
    test_mark_durable(d.path());
    let (outcome, _steps) = crate::backend::ops::duplicate(&src);
    assert!(outcome.is_ok());
    assert_eq!(test_counts().0, 1, "duplicate fsyncs its file on a durable target");
}

#[test]
fn rename_on_a_durable_target_confirms_the_directory() {
    test_reset();
    let d = TestDir::new("durable-rename");
    let src = d.file("a.txt", "body");
    test_mark_durable(d.path());
    let (to, _steps) = crate::backend::ops::rename(&src, "b.txt").expect("rename");
    assert!(to.exists());
    assert!(test_counts().1 >= 1, "rename fsyncs its directory on a durable target");
}

#[test]
fn redo_of_a_copy_confirms_the_file_again() {
    use crate::backend::undo::{Entry, Journal};
    test_reset();
    let d = TestDir::new("durable-redo");
    let src = d.file("a.txt", "body");
    test_mark_durable(d.path());
    let (outcome, steps) = crate::backend::ops::duplicate(&src);
    let copy = outcome.expect("duplicate");
    let mut journal = Journal::new();
    journal.push(Entry { op: "copy".into(), steps });
    journal.undo().expect("undo removes the copy");
    assert!(!copy.exists());
    test_reset_counts();
    let (tx, _rx) = std::sync::mpsc::channel();
    journal.redo(1, &std::sync::atomic::AtomicBool::new(false), &tx).expect("redo");
    assert!(copy.exists(), "redo put the copy back");
    assert_eq!(test_counts().0, 1, "redo fsyncs its file on a durable target: {:?}", test_counts());
}
