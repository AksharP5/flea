use super::*;
use crate::backend::copyfile::Progress;
use crate::backend::testdir::TestDir;

fn quiet<'a>(flag: &'a std::sync::atomic::AtomicBool, sink: &'a mut dyn FnMut(u64, u64), durability: &'a mut Durability) -> Progress<'a> {
    Progress { cancel: flag, on_bytes: sink, partial: None, tree: None, manifest: None, durability: Some(durability) }
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
    assert!(fat_name_is_durable("ntfs3"), "the in-kernel ntfs3 driver names itself");
    assert!(!fat_name_is_durable("ext4"));
    assert!(!fat_name_is_durable("btrfs"));
    assert!(fat_magic_is_durable(MSDOS_SUPER_MAGIC));
    assert!(fat_magic_is_durable(EXFAT_SUPER_MAGIC));
    assert!(fat_magic_is_durable(NTFS_SUPER_MAGIC));
    assert!(fat_magic_is_durable(NTFS3_SUPER_MAGIC));
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
    let mut durability = Durability::begin(&out);
    assert!(durability.durable, "the marked target is durable");
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = quiet(&flag, &mut sink, &mut durability);
    crate::backend::copyfile::copy_any(&src.join("a.txt"), &out.join("a.txt"), &mut p).expect("copy");
    crate::backend::copyfile::copy_any(&src.join("b.txt"), &out.join("b.txt"), &mut p).expect("copy");
    drop(p);
    assert_eq!(test_counts().0, 2, "one fsync per file, got {:?}", test_counts());
    durability.flush_dirs().expect("real dirs flush");
    assert_eq!(test_counts(), (2, 1), "one parent flush for two files, got {:?}", test_counts());
}

#[test]
fn touched_dirs_are_recorded_once_and_ordered_deepest_first() {
    test_reset();
    let d = TestDir::new("durable-order");
    test_mark_durable(d.path());
    let mut durability = Durability::begin(d.path());
    let (a, b) = (d.join("a"), d.join("a/b"));
    durability.touch(&a);
    durability.touch(&a);
    durability.touch(&b);
    durability.touch(&a);
    assert_eq!(durability.ordered(), vec![b, a]);
}

#[test]
fn a_local_copy_fsyncs_nothing() {
    test_reset();
    let d = TestDir::new("durable-local");
    let src = d.file("a.txt", "body");
    let out = d.dir("out");
    let mut durability = Durability::begin(&out);
    assert!(!durability.durable, "an unmarked TestDir is local");
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = quiet(&flag, &mut sink, &mut durability);
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
    let mut durability = Durability::begin(&out);
    assert!(durability.durable);
    test_set_fail(true);
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = quiet(&flag, &mut sink, &mut durability);
    let err = crate::backend::copyfile::copy_any(&src, &out.join("a.txt"), &mut p).expect_err("a failed fsync is a failed copy");
    assert_eq!(err.where_, "copy");
    assert!(p.partial.is_some(), "the partial is journalled for undo: {:?}", p.partial);
    assert_eq!(test_counts().0, 1, "the failed flush still counts as called");
}

#[test]
fn the_writing_line_carries_the_phase_the_protocol_documents() {
    let line = writing_line(12, "128GB");
    assert!(line.contains(r#""t":"transferprogress""#));
    assert!(line.contains(r#""phase":"writing""#), "the final phase rides a progress line: {}", line);
}

#[test]
fn the_writing_line_names_the_drive_it_is_flushing() {
    let line = writing_line(12, "128GB");
    assert!(line.contains(r#""drive":"128GB""#), "the card names the drive: {}", line);
    let quoted = writing_line(12, "128\"GB");
    assert!(quoted.contains(r#""drive":"128\"GB""#), "the drive is JSON-escaped: {}", quoted);
}

#[test]
fn finish_names_the_destination_it_flushes() {
    use std::sync::mpsc::channel;
    test_reset();
    let d = TestDir::new("durable-finish-drive");
    let out = d.dir("out");
    test_mark_durable(&out);
    let durability = Durability::begin(&out);
    assert!(durability.durable);
    let (tx, rx) = channel();
    finish(7, &tx, &durability, &out, 1);
    let mut drive = None;
    for msg in rx.try_iter() {
        if let crate::backend::opsreq::OpMsg::Meta { line } = msg {
            if line.contains(r#""phase":"writing""#) {
                drive = Some(line);
            }
        }
    }
    let line = drive.expect("the final phase emits one writing line");
    let want = drive_name(&out);
    assert!(line.contains(&format!(r#""drive":"{}""#, want)), "the drive is the mount's own name: {}", line);
}

#[test]
fn drive_name_answers_the_mount_not_the_folder() {
    let body = "1 0 8:1 / / rw - ext4 /dev/a rw\n30 1 8:17 / /media/stick rw - vfat /dev/sdb1 rw\n";
    assert_eq!(drive_name_in(std::path::Path::new("/media/stick/DCIM"), body), "stick");
    assert_eq!(drive_name_in(std::path::Path::new("/media/stick/photos"), body), "stick");
}

#[test]
fn drive_name_answers_the_share_for_a_gvfs_path() {
    let body = "";
    assert_eq!(drive_name_in(std::path::Path::new("/run/user/1000/gvfs/smb-share:server=nas,share=media/photos"), body), "media");
    assert_eq!(drive_name_in(std::path::Path::new("/run/user/1000/gvfs/smb-share:server=nas,share=media"), body), "media");
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
    test_set_fail_files(true);
    let (tx, rx) = channel();
    run_transfer(9, false, vec![src.to_string_lossy().to_string()], out.clone(), Arc::new(std::sync::atomic::AtomicBool::new(false)), tx);
    let mut item_err = String::new();
    let mut entry_steps = 0;
    let mut done = None;
    for msg in rx.iter() {
        match msg {
            OpMsg::Item { ok: false, err, .. } => item_err = err,
            OpMsg::TransferDone { entry, durable: done_durable, ok, failed, note, .. } => {
                entry_steps = entry.steps.len();
                done = Some((done_durable, ok, failed, note));
            }
            _ => {}
        }
    }
    assert!(!item_err.is_empty(), "the file's name rides a copy error");
    assert_eq!(entry_steps, 1, "the partial is journalled for undo");
    assert_eq!(done, Some((false, 0, 1, String::new())), "a failed file flush is not durable with no note: {:?}", done);
    test_set_fail_files(false);
}

#[test]
fn a_file_fsync_failure_beside_a_landed_file_is_not_durable() {
    use std::sync::mpsc::channel;
    test_reset();
    let d = TestDir::new("durable-wire-filefail");
    let first = d.file("a.txt", "body");
    let second = d.file("b.txt", "body");
    let out = d.dir("out");
    test_mark_durable(&out);
    let mut durability = Durability::begin(&out);
    assert!(durability.durable);
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = quiet(&flag, &mut sink, &mut durability);
    crate::backend::copyfile::copy_any(&first, &out.join("a.txt"), &mut p).expect("first file lands");
    drop(p);
    test_set_fail_files(true);
    let mut p = quiet(&flag, &mut sink, &mut durability);
    let err = crate::backend::copyfile::copy_any(&second, &out.join("b.txt"), &mut p).expect_err("a failed file fsync is a failed copy");
    assert_eq!(err.where_, "copy");
    drop(p);
    test_set_fail_files(false);
    let (tx, rx) = channel();
    let done = finish(16, &tx, &durability, &out, 1);
    assert!(!done.ok, "a failed file flush is not durable");
    assert!(done.note.is_empty(), "a failed file flush carries no note: {:?}", done.note);
    assert!(rx.try_iter().any(|m| matches!(m, crate::backend::opsreq::OpMsg::Meta { line } if line.contains(r#""phase":"writing""#))), "the writing line still runs beside a landed file");
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

#[test]
fn an_rclone_fstype_counts_and_nothing_else_does() {
    assert!(fstype_is_rclone("fuse.rclone"));
    assert!(fstype_is_rclone("FUSE.RCLONE"), "the mount table never promises a case");
    assert!(!fstype_is_rclone("fuse.sshfs"));
    assert!(!fstype_is_rclone("fuse.gvfsd-fuse"));
    assert!(!fstype_is_rclone("ext4"));
    assert!(!fstype_is_rclone(""));
}

#[test]
fn a_copy_onto_rclone_says_it_uploads_in_the_background_and_never_claims_the_drive() {
    use std::sync::mpsc::channel;
    test_reset();
    let d = TestDir::new("durable-rclone-note");
    let out = d.dir("out");
    let durability = Durability { durable: false, rclone: true, file_failed: false,
        touched: std::collections::HashSet::new(), last: None };
    let (tx, rx) = channel();
    let done = finish(9, &tx, &durability, &out, 1);
    assert!(!done.ok, "an rclone copy never claims the drive confirmed it");
    assert_eq!(done.note, RCLONE_NOTE, "the verdict names the background upload: {:?}", done.note);
    assert!(rx.try_iter().next().is_none(), "no writing phase on an rclone target");
}

#[test]
fn a_move_confirms_only_the_folders_its_destination_filled() {
    test_reset();
    let d = TestDir::new("flushfor");
    std::fs::create_dir_all(d.join("src")).unwrap();
    std::fs::create_dir_all(d.join("dst/tree")).unwrap();
    test_mark_durable(d.path());
    let mut durability = Durability::begin(&d.join("dst/tree"));
    durability.touch(&d.join("src"));
    durability.touch(&d.join("dst/tree"));
    durability.touch(&d.join("dst"));
    test_reset_counts();
    durability.flush_dirs_for(&d.join("dst/tree")).unwrap();
    assert_eq!(test_counts().1, 2, "the tree and its parent, never the source's folder");
    test_reset();
}

#[test]
fn finish_with_nothing_landed_sends_no_writing_line_and_claims_nothing() {
    use std::sync::mpsc::channel;
    test_reset();
    let d = TestDir::new("durable-finish-empty");
    let out = d.dir("out");
    test_mark_durable(&out);
    let durability = Durability::begin(&out);
    let (tx, rx) = channel();
    let done = finish(11, &tx, &durability, &out, 0);
    assert!(!done.ok, "nothing landed, so nothing is durable");
    assert!(done.note.is_empty(), "nothing landed, so no note: {:?}", done.note);
    assert!(rx.try_iter().next().is_none(), "nothing landed, so no writing line");
}

#[test]
fn finish_with_nothing_landed_on_rclone_says_nothing() {
    use std::sync::mpsc::channel;
    test_reset();
    let d = TestDir::new("durable-rclone-empty");
    let out = d.dir("out");
    let durability = Durability { durable: false, rclone: true, file_failed: false,
        touched: std::collections::HashSet::new(), last: None };
    let (tx, rx) = channel();
    let done = finish(12, &tx, &durability, &out, 0);
    assert!(!done.ok, "nothing landed, so nothing is durable");
    assert!(done.note.is_empty(), "nothing landed, so no rclone note: {:?}", done.note);
    assert!(rx.try_iter().next().is_none(), "nothing landed, so no writing line");
}

#[test]
fn a_failed_batch_lands_nothing_and_sends_no_writing_line() {
    use crate::backend::opsreq::{run_transfer, OpMsg};
    use std::sync::mpsc::channel;
    use std::sync::Arc;
    test_reset();
    let d = TestDir::new("durable-wire-failall");
    let missing = d.join("gone.txt");
    let out = d.dir("out");
    test_mark_durable(&out);
    let (tx, rx) = channel();
    run_transfer(14, false, vec![missing.to_string_lossy().to_string()], out.clone(), Arc::new(std::sync::atomic::AtomicBool::new(false)), tx);
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
    assert!(!saw_writing, "nothing landed, so no writing line");
    assert_eq!(done, Some((false, 0, 1, String::new())), "a failed batch claims nothing: {:?}", done);
}

#[test]
fn a_cancelled_batch_lands_nothing_and_sends_no_writing_line() {
    use crate::backend::opsreq::{run_transfer, OpMsg};
    use std::sync::mpsc::channel;
    use std::sync::Arc;
    use std::sync::atomic::AtomicBool;
    test_reset();
    let d = TestDir::new("durable-wire-skipall");
    let src = d.file("a.txt", "body");
    let out = d.dir("out");
    test_mark_durable(&out);
    let (tx, rx) = channel();
    run_transfer(15, false, vec![src.to_string_lossy().to_string()], out.clone(), Arc::new(AtomicBool::new(true)), tx);
    let mut saw_writing = false;
    let mut done = None;
    for msg in rx.iter() {
        match msg {
            OpMsg::Meta { line } if line.contains(r#""phase":"writing""#) => saw_writing = true,
            OpMsg::TransferDone { durable: done_durable, ok, failed, skipped, note, .. } => {
                done = Some((done_durable, ok, failed, skipped, note));
            }
            _ => {}
        }
    }
    assert!(!saw_writing, "nothing landed, so no writing line");
    assert_eq!(done, Some((false, 0, 0, 1, String::new())), "a skipped batch claims nothing: {:?}", done);
}

#[test]
fn a_cancelled_folder_copy_forgets_the_tree_it_removed() {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::mpsc::channel;
    test_reset();
    let d = TestDir::new("durable-cancel-forget");
    let first = d.file("first.txt", "body");
    let src = d.dir("src");
    std::fs::write(src.join("a.txt"), "a").unwrap();
    std::fs::create_dir(src.join("sub")).unwrap();
    std::fs::write(src.join("sub/b.txt"), "b").unwrap();
    let out = d.dir("out");
    test_mark_durable(&out);
    let mut durability = Durability::begin(&out);
    let idle = AtomicBool::new(false);
    let mut quiet_sink = |_: u64, _: u64| {};
    let mut p = quiet(&idle, &mut quiet_sink, &mut durability);
    crate::backend::copyfile::copy_any(&first, &out.join("first.txt"), &mut p).expect("one file lands first");
    drop(p);
    let dst = out.join("clone");
    d.assert_contains(&dst);
    // The first bytes of the tree raise the cancel, so the folder exists and was touched before it goes.
    let flag = AtomicBool::new(false);
    let mut cancelling = |_: u64, _: u64| flag.store(true, Ordering::Relaxed);
    let mut p = quiet(&flag, &mut cancelling, &mut durability);
    let err = crate::backend::copyfile::copy_any(&src, &dst, &mut p).expect_err("cancelled mid-tree");
    drop(p);
    assert_eq!(err.msg, "cancelled");
    assert!(!dst.exists(), "the cancelled tree goes with the cancel");
    let (tx, _rx) = channel();
    let done = finish(13, &tx, &durability, &out, 1);
    assert!(done.note.is_empty(), "a removed tree is not a confirmation failure: {:?}", done.note);
    assert!(done.ok, "the file that landed is confirmed");
}

#[test]
fn duplicate_classifies_the_existing_parent_not_the_missing_name() {
    test_reset();
    let d = TestDir::new("durable-dup-parent");
    let src = d.file("a.txt", "body");
    // Only the missing name is marked, so probing it answers durable and probing its parent does not.
    test_mark_durable(&d.join("a copy.txt"));
    test_set_fail_dirs(true);
    let (outcome, _) = crate::backend::ops::duplicate(&src);
    test_set_fail_dirs(false);
    test_reset();
    assert_eq!(outcome.map_err(|e| e.msg), Ok(d.join("a copy.txt")), "the marked name is the copy's, and the parent was classified, so no folder flush ran to fail");
}

// A durable copy confirms slices while it writes, so the card counts confirmed bytes mid-file.
#[test]
fn a_durable_copy_confirms_slices_while_it_writes() {
    test_reset();
    let d = TestDir::new("durable-slices");
    let out = d.dir("out");
    test_mark_durable(&out);
    // Three confirm slices plus a tail: pipelined writeback reports through k-1, so two mids plus the final.
    let confirm = crate::backend::copyfile::CONFIRM_BYTES as usize;
    let total: usize = confirm * 3 + 1024 * 1024;
    let src = d.join("big.bin");
    std::fs::write(&src, vec![b'a'; total]).expect("test sandbox file");
    let mut durability = Durability::begin(&out);
    assert!(durability.durable, "the marked target is durable");
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut seen: Vec<(u64, u64)> = Vec::new();
    let mut sink = |done: u64, against: u64| seen.push((done, against));
    let mut p = quiet(&flag, &mut sink, &mut durability);
    crate::backend::copyfile::copy_any(&src, &out.join("big.bin"), &mut p).expect("copy");
    drop(p);
    assert_eq!(seen.len(), 3, "two pipelined mids plus the final, got {:?}", seen);
    assert!(seen.windows(2).all(|w| w[1].0 > w[0].0), "confirmed counts only ever rise, got {:?}", seen);
    assert_eq!(seen.last().copied(), Some((total as u64, total as u64)), "the last report is the whole file, got {:?}", seen.last());
    test_reset();
}

#[test]
fn a_filesystem_without_range_writeback_is_not_a_failed_copy() {
    // EINVAL is what some FUSE mounts answer sync_file_range with; EIO is a drive refusing bytes.
    let einval = std::io::Error::from_raw_os_error(crate::backend::durable::EINVAL);
    let eio = std::io::Error::from_raw_os_error(crate::backend::durable::EIO);
    assert!(crate::backend::durable::range_unsupported(&einval));
    assert!(!crate::backend::durable::range_unsupported(&eio));
}

// A write seam answering EINVAL falls back to the final fsync: the copy still lands whole.
#[test]
fn a_range_einval_still_copies_and_reports_only_the_final_count() {
    test_reset();
    let d = TestDir::new("durable-range-einval");
    let out = d.dir("out");
    test_mark_durable(&out);
    let confirm = crate::backend::copyfile::CONFIRM_BYTES as usize;
    let total: usize = confirm * 2 + 1024 * 1024;
    let src = d.join("big.bin");
    std::fs::write(&src, vec![b'a'; total]).expect("test sandbox file");
    let mut durability = Durability::begin(&out);
    assert!(durability.durable, "the marked target is durable");
    crate::backend::durable::test_set_fail_range_write(true);
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut seen: Vec<(u64, u64)> = Vec::new();
    let mut sink = |done: u64, against: u64| seen.push((done, against));
    let mut p = quiet(&flag, &mut sink, &mut durability);
    crate::backend::copyfile::copy_any(&src, &out.join("big.bin"), &mut p).expect("a range EINVAL is a fallback, not a failure");
    drop(p);
    crate::backend::durable::test_set_fail_range_write(false);
    assert_eq!(seen, vec![(total as u64, total as u64)], "only the final whole-file count, got {:?}", seen);
    assert_eq!(crate::backend::durable::test_range_waits(), 0, "no slice wait ran");
    assert_eq!(test_counts().0, 1, "the final fsync still ran, got {:?}", test_counts());
    assert_eq!(std::fs::metadata(out.join("big.bin")).unwrap().len(), total as u64);
    test_reset();
}

// A slice flush failure fails the copy, marks the file and journals the partial.
#[test]
fn a_slice_flush_failure_fails_the_copy_and_journals_the_partial() {
    test_reset();
    let d = TestDir::new("durable-slice-fail");
    let out = d.dir("out");
    test_mark_durable(&out);
    let confirm = crate::backend::copyfile::CONFIRM_BYTES as usize;
    let total: usize = confirm * 2;
    let src = d.join("big.bin");
    std::fs::write(&src, vec![b'a'; total]).expect("test sandbox file");
    let mut durability = Durability::begin(&out);
    assert!(durability.durable, "the marked target is durable");
    crate::backend::durable::test_set_fail_files(true);
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = quiet(&flag, &mut sink, &mut durability);
    let err = crate::backend::copyfile::copy_any(&src, &out.join("big.bin"), &mut p).expect_err("a failed slice flush is a failed copy");
    assert_eq!(err.where_, "copy");
    assert!(p.partial.is_some(), "the partial is journalled for undo: {:?}", p.partial);
    drop(p);
    crate::backend::durable::test_set_fail_files(false);
    assert!(durability.file_failed, "the file failure is noted for the verdict");
    assert_eq!(test_counts().0, 1, "the failed slice never reaches the final fsync, got {:?}", test_counts());
    test_reset();
}

// Every mid-file report follows a completed wait, so the card counts confirmed bytes only.
#[test]
fn every_mid_file_report_follows_a_completed_wait() {
    test_reset();
    let d = TestDir::new("durable-reports-waits");
    let out = d.dir("out");
    test_mark_durable(&out);
    let confirm = crate::backend::copyfile::CONFIRM_BYTES as u64;
    let total: usize = confirm as usize * 3 + 1024 * 1024;
    let src = d.join("big.bin");
    std::fs::write(&src, vec![b'a'; total]).expect("test sandbox file");
    let mut durability = Durability::begin(&out);
    assert!(durability.durable, "the marked target is durable");
    let flag = std::sync::atomic::AtomicBool::new(false);
    // The waits seen at each report, so a report moved above its wait reddens.
    let mut seen: Vec<(u64, u64, usize)> = Vec::new();
    let mut sink = |done: u64, against: u64| seen.push((done, against, crate::backend::durable::test_range_waits()));
    let mut p = quiet(&flag, &mut sink, &mut durability);
    crate::backend::copyfile::copy_any(&src, &out.join("big.bin"), &mut p).expect("copy");
    drop(p);
    let waits = crate::backend::durable::test_range_waits();
    assert_eq!(waits, 2, "two pipelined waits for three slices, got {}", waits);
    assert_eq!(seen.len(), waits + 1, "mids plus the final, got {:?}", seen);
    assert_eq!((seen[0].0, seen[0].2), (confirm, 1), "the first mid follows one wait, got {:?}", seen);
    assert_eq!((seen[1].0, seen[1].2), (confirm * 2, 2), "the second mid follows two waits, got {:?}", seen);
    assert_eq!(seen[2].2, 2, "the final fsync adds no wait, got {:?}", seen);
    assert_eq!(seen.last().map(|s| (s.0, s.1)), Some((total as u64, total as u64)));
    test_reset();
}

// The wait leg answering EINVAL stops slicing and reports only the final count.
#[test]
fn a_wait_einval_stops_slicing_and_reports_only_the_final_count() {
    test_reset();
    let d = TestDir::new("durable-wait-einval");
    let out = d.dir("out");
    test_mark_durable(&out);
    let confirm = crate::backend::copyfile::CONFIRM_BYTES as usize;
    let total: usize = confirm * 2 + 1024 * 1024;
    let src = d.join("big.bin");
    std::fs::write(&src, vec![b'a'; total]).expect("test sandbox file");
    let mut durability = Durability::begin(&out);
    assert!(durability.durable, "the marked target is durable");
    crate::backend::durable::test_set_fail_range_wait(crate::backend::durable::EINVAL);
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut seen: Vec<(u64, u64)> = Vec::new();
    let mut sink = |done: u64, against: u64| seen.push((done, against));
    let mut p = quiet(&flag, &mut sink, &mut durability);
    crate::backend::copyfile::copy_any(&src, &out.join("big.bin"), &mut p).expect("a wait EINVAL is a fallback, not a failure");
    drop(p);
    crate::backend::durable::test_set_fail_range_wait(0);
    assert_eq!(seen, vec![(total as u64, total as u64)], "only the final whole-file count, got {:?}", seen);
    assert_eq!(crate::backend::durable::test_range_waits(), 0, "no wait completed");
    assert_eq!(test_counts().0, 3, "two writes plus the final fsync, got {:?}", test_counts());
    assert_eq!(std::fs::metadata(out.join("big.bin")).unwrap().len(), total as u64);
    test_reset();
}

// The wait leg answering EIO fails the copy, notes the file and journals the partial.
#[test]
fn a_wait_eio_fails_the_copy_and_journals_the_partial() {
    test_reset();
    let d = TestDir::new("durable-wait-eio");
    let out = d.dir("out");
    test_mark_durable(&out);
    let confirm = crate::backend::copyfile::CONFIRM_BYTES as usize;
    let total: usize = confirm * 2;
    let src = d.join("big.bin");
    std::fs::write(&src, vec![b'a'; total]).expect("test sandbox file");
    let mut durability = Durability::begin(&out);
    assert!(durability.durable, "the marked target is durable");
    crate::backend::durable::test_set_fail_range_wait(crate::backend::durable::EIO);
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = quiet(&flag, &mut sink, &mut durability);
    let err = crate::backend::copyfile::copy_any(&src, &out.join("big.bin"), &mut p).expect_err("a failed wait is a failed copy");
    assert_eq!(err.where_, "copy");
    assert!(p.partial.is_some(), "the partial is journalled for undo: {:?}", p.partial);
    drop(p);
    crate::backend::durable::test_set_fail_range_wait(0);
    assert!(durability.file_failed, "the file failure is noted for the verdict");
    assert_eq!(crate::backend::durable::test_range_waits(), 0, "no wait completed");
    test_reset();
}

// Slice k starts with WRITE alone before slice k-1 waits, so the next slice writes while it flies.
#[test]
fn slices_start_with_write_alone_before_the_previous_waits() {
    test_reset();
    let d = TestDir::new("durable-pipeline-order");
    let out = d.dir("out");
    test_mark_durable(&out);
    let confirm = crate::backend::copyfile::CONFIRM_BYTES;
    let total: usize = confirm as usize * 3 + 1024 * 1024;
    let src = d.join("big.bin");
    std::fs::write(&src, vec![b'a'; total]).expect("test sandbox file");
    let mut durability = Durability::begin(&out);
    assert!(durability.durable, "the marked target is durable");
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = quiet(&flag, &mut sink, &mut durability);
    crate::backend::copyfile::copy_any(&src, &out.join("big.bin"), &mut p).expect("copy");
    drop(p);
    assert_eq!(crate::backend::durable::test_range_log(), vec![
        format!("write 0"),
        format!("write {confirm}"),
        "wait 0".to_string(),
        format!("write {}", confirm * 2),
        format!("wait {confirm}"),
        "fsync".to_string(),
    ], "pipelined writes before waits, got {:?}", crate::backend::durable::test_range_log());
    test_reset();
}
