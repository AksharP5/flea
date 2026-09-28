use super::*;
use crate::backend::collide::CANCELLED;
use crate::backend::testdir::TestDir;
use std::os::unix::fs::MetadataExt;
use std::sync::mpsc::channel;

fn staged(
    id: usize,
    batch: &mut MoveBatch,
    durability: &mut Durability,
    flag: &AtomicBool,
    tx: &std::sync::mpsc::Sender<OpMsg>,
    settled: &AtomicU64,
    steps: &mut Vec<Step>,
    index: usize,
    src: &Path,
    dst: &Path,
) {
    let source = ItemIdentity::inspect(src).expect("source recorded before its copy");
    let name = src.file_name().unwrap().to_string_lossy().to_string();
    match stage_copy(id, index, &name, src, dst, source, flag, tx, settled, steps, durability, batch) {
        MoveOutcome::Deferred => {}
        MoveOutcome::Done(r) => panic!("staging copies, got {}", r.map(|_| "ok").unwrap_err().msg),
    }
}

fn items(rx: std::sync::mpsc::Receiver<OpMsg>) -> Vec<(usize, bool, String)> {
    let mut out = Vec::new();
    for msg in rx.iter() {
        if let OpMsg::Item { index, ok, err, .. } = msg {
            out.push((index, ok, err));
        }
    }
    out
}

// 64 items into one folder confirm it once, not 64 times; the file fsyncs stay per file.
#[test]
fn a_batch_of_sixty_four_confirms_its_folder_once() {
    use crate::backend::durable;
    durable::test_reset();
    let d = TestDir::new("movebatch-once");
    let srcdir = d.dir("src");
    let out = d.dir("out");
    durable::test_mark_durable(&out);
    let mut durability = durable::Durability::begin(&out);
    assert!(durability.durable, "the marked target is durable");
    let flag = AtomicBool::new(false);
    let settled = AtomicU64::new(0);
    let mut batch = MoveBatch::new();
    let (tx, rx) = channel();
    let mut steps = Vec::new();
    for n in 0..64 {
        let src = srcdir.join(format!("f{n}.txt"));
        std::fs::write(&src, "body").unwrap();
        staged(1, &mut batch, &mut durability, &flag, &tx, &settled, &mut steps, n, &src, &out.join(format!("f{n}.txt")));
    }
    assert!(batch.full(), "64 staged items fill the batch");
    let (counts, retry) = close_normal(&mut batch, 1, &tx, &mut steps, &mut durability);
    assert_eq!((counts.ok, counts.failed, counts.skipped), (64, 0, 0));
    assert!(retry.is_empty());
    assert_eq!(steps.len(), 64, "one Moved step per item, the journal redo already reads");
    assert_eq!(durable::test_counts(), (64, 1), "one file fsync per file, one folder confirm: {:?}", durable::test_counts());
    drop(tx);
    let lines = items(rx);
    assert_eq!(lines.len(), 64);
    assert!(lines.iter().enumerate().all(|(n, (index, ok, _))| *index == n && *ok));
    for n in 0..64 {
        assert!(!srcdir.join(format!("f{n}.txt")).exists(), "no source survives its batch's confirm");
        assert_eq!(std::fs::read_to_string(out.join(format!("f{n}.txt"))).unwrap(), "body");
    }
    durable::test_reset();
}

// A failed confirm keeps every source of the batch whole and journals each copy as a partial.
#[test]
fn a_failed_batch_confirm_keeps_every_source_and_journals_partials() {
    use crate::backend::durable;
    durable::test_reset();
    let d = TestDir::new("movebatch-confirm-fail");
    let srcdir = d.dir("src");
    let out = d.dir("out");
    durable::test_mark_durable(&out);
    let mut durability = durable::Durability::begin(&out);
    let flag = AtomicBool::new(false);
    let settled = AtomicU64::new(0);
    let mut batch = MoveBatch::new();
    let (tx, rx) = channel();
    let mut steps = Vec::new();
    for (n, body) in ["first", "second"].iter().enumerate() {
        let src = srcdir.join(format!("f{n}.txt"));
        std::fs::write(&src, body).unwrap();
        staged(1, &mut batch, &mut durability, &flag, &tx, &settled, &mut steps, n, &src, &out.join(format!("f{n}.txt")));
    }
    durable::test_set_fail_dirs(true);
    let (counts, retry) = close_normal(&mut batch, 1, &tx, &mut steps, &mut durability);
    durable::test_set_fail_dirs(false);
    assert_eq!((counts.ok, counts.failed), (0, 2));
    assert_eq!(retry.len(), 2, "every unconfirmed source is offered again");
    assert!(matches!(&steps[..], [Step::Copied { .. }, Step::Copied { .. }]), "partials, as the single-item failure journals: {:?}", steps.len());
    drop(tx);
    let lines = items(rx);
    assert_eq!(lines.len(), 2);
    for (n, body) in ["first", "second"].iter().enumerate() {
        assert!(lines.iter().any(|(index, ok, err)| *index == n && !ok && err == durable::DIR_UNCONFIRMED));
        assert_eq!(std::fs::read_to_string(srcdir.join(format!("f{n}.txt"))).unwrap(), *body, "the source stays whole");
        assert_eq!(std::fs::read_to_string(out.join(format!("f{n}.txt"))).unwrap(), *body, "the landed copy stays beside it");
        d.assert_contains(&srcdir.join(format!("f{n}.txt")));
    }
    durable::test_reset();
}

// Cancel completes what already copied instead of deleting it: sources go, copies stay.
#[test]
fn a_cancelled_batch_completes_its_landed_moves() {
    use crate::backend::durable;
    durable::test_reset();
    let d = TestDir::new("movebatch-cancel");
    let srcdir = d.dir("src");
    let out = d.dir("out");
    durable::test_mark_durable(&out);
    let mut durability = durable::Durability::begin(&out);
    let flag = AtomicBool::new(false);
    let settled = AtomicU64::new(0);
    let mut batch = MoveBatch::new();
    let (tx, rx) = channel();
    let mut steps = Vec::new();
    for n in 0..2 {
        let src = srcdir.join(format!("f{n}.txt"));
        std::fs::write(&src, "body").unwrap();
        staged(1, &mut batch, &mut durability, &flag, &tx, &settled, &mut steps, n, &src, &out.join(format!("f{n}.txt")));
    }
    let (counts, retry) = close_cancelled(&mut batch, 1, &tx, &mut steps, &mut durability);
    assert!(counts.cancelled);
    assert_eq!((counts.ok, counts.failed, counts.skipped), (2, 0, 0));
    assert!(retry.is_empty(), "a completed move is never retried");
    assert!(matches!(&steps[..], [Step::Moved { .. }, Step::Moved { .. }]), "redo sees moved steps only");
    drop(tx);
    let lines = items(rx);
    assert_eq!(lines.len(), 2);
    assert!(lines.iter().all(|(_, ok, _)| *ok), "landed items complete, so every line is ok");
    for n in 0..2 {
        assert!(!srcdir.join(format!("f{n}.txt")).exists(), "no source survives its batch's confirm");
        assert_eq!(std::fs::read_to_string(out.join(format!("f{n}.txt"))).unwrap(), "body");
    }
    durable::test_reset();
}

// Batched Moved steps undo exactly like single-item ones: sources come back, copies go.
#[test]
fn batched_moves_undo_like_single_item_moves() {
    use crate::backend::{durable, undo::Journal};
    durable::test_reset();
    let d = TestDir::new("movebatch-undo");
    let srcdir = d.dir("src");
    let out = d.dir("out");
    durable::test_mark_durable(&out);
    let mut durability = durable::Durability::begin(&out);
    let flag = AtomicBool::new(false);
    let settled = AtomicU64::new(0);
    let mut batch = MoveBatch::new();
    let (tx, _rx) = channel();
    let mut steps = Vec::new();
    for n in 0..2 {
        let src = srcdir.join(format!("f{n}.txt"));
        std::fs::write(&src, "body").unwrap();
        staged(1, &mut batch, &mut durability, &flag, &tx, &settled, &mut steps, n, &src, &out.join(format!("f{n}.txt")));
    }
    let (counts, _) = close_normal(&mut batch, 1, &tx, &mut steps, &mut durability);
    assert_eq!(counts.ok, 2);
    let mut journal = Journal::new();
    journal.push(crate::backend::undo::Entry { op: "move".to_string(), steps });
    assert_eq!(journal.undo().unwrap(), "move");
    for n in 0..2 {
        assert_eq!(std::fs::read_to_string(srcdir.join(format!("f{n}.txt"))).unwrap(), "body");
        assert!(!out.join(format!("f{n}.txt")).exists());
    }
    durable::test_reset();
}

// A source replaced after its copy landed is never removed: both copies stay and undo loses neither.
#[test]
fn a_replaced_batch_source_survives_close_with_both_copies_kept() {
    use crate::backend::{durable, undo::Journal};
    durable::test_reset();
    let d = TestDir::new("movebatch-changed-source");
    let srcdir = d.dir("src");
    let out = d.dir("out");
    durable::test_mark_durable(&out);
    let mut durability = durable::Durability::begin(&out);
    let flag = AtomicBool::new(false);
    let settled = AtomicU64::new(0);
    let mut batch = MoveBatch::new();
    let (tx, rx) = channel();
    let mut steps = Vec::new();
    let first = srcdir.join("f0.txt");
    std::fs::write(&first, "old").unwrap();
    staged(1, &mut batch, &mut durability, &flag, &tx, &settled, &mut steps, 0, &first, &out.join("f0.txt"));
    let second = srcdir.join("f1.txt");
    std::fs::write(&second, "body").unwrap();
    staged(1, &mut batch, &mut durability, &flag, &tx, &settled, &mut steps, 1, &second, &out.join("f1.txt"));
    // Atomically replaced after its copy landed, so a new inode sits at the staged name.
    let repl = srcdir.join("replacement.txt");
    std::fs::write(&repl, "new").unwrap();
    std::fs::rename(&repl, &first).unwrap();
    let (counts, retry) = close_normal(&mut batch, 1, &tx, &mut steps, &mut durability);
    assert_eq!((counts.ok, counts.failed, counts.skipped), (1, 1, 0));
    assert_eq!(retry.len(), 1, "the changed source is offered again");
    drop(tx);
    let lines = items(rx);
    assert_eq!(lines.len(), 2);
    assert!(lines.iter().any(|(index, ok, _)| *index == 1 && *ok));
    let reported = lines.iter().find(|(index, ok, _)| *index == 0 && !ok).expect("the changed item reports its own line");
    assert!(reported.2.contains("changed during the move; both kept"), "one line names the file: {}", reported.2);
    assert!(first.exists(), "the replacement survives");
    assert_eq!(std::fs::read_to_string(&first).unwrap(), "new", "the replacement survives");
    assert_eq!(std::fs::read_to_string(out.join("f0.txt")).unwrap(), "old", "beside the stale copy");
    assert!(!second.exists() && std::fs::read_to_string(out.join("f1.txt")).unwrap() == "body");
    assert!(matches!(&steps[..], [Step::Copied { .. }, Step::Moved { .. }]), "the kept copy journals a Copied step");
    let mut journal = Journal::new();
    journal.push(crate::backend::undo::Entry { op: "move".to_string(), steps });
    journal.undo().unwrap();
    assert_eq!(std::fs::read_to_string(&first).unwrap(), "new", "undo never touches the replacement");
    assert_eq!(std::fs::read_to_string(&second).unwrap(), "body", "and the clean move comes back");
    assert!(!out.join("f0.txt").exists() && !out.join("f1.txt").exists());
    durable::test_reset();
}

// A same-filesystem move never stages: the rename answers at once with no batch behind it.
#[test]
fn same_filesystem_moves_answer_at_once_and_never_stage() {
    use crate::backend::durable;
    durable::test_reset();
    let d = TestDir::new("movebatch-rename");
    let out = d.dir("out");
    let mut durability = durable::Durability::begin(&out);
    let flag = AtomicBool::new(false);
    let settled = AtomicU64::new(0);
    let (tx, _rx) = channel();
    let mut steps = Vec::new();
    let mut batch = MoveBatch::new();
    let src = d.file("a.txt", "body");
    let source = ItemIdentity::inspect(&src).unwrap();
    let dst = out.join("a.txt");
    match land_move(1, 0, "a.txt", &src, &dst, source, &flag, &tx, &settled, &mut steps, &mut durability, &mut batch) {
        MoveOutcome::Done(Ok(())) => {}
        other => panic!("a rename answers at once, got {}", if matches!(other, MoveOutcome::Deferred) { "deferred" } else { "an error" }),
    }
    assert!(batch.is_empty(), "no batch behind a rename");
    assert!(!src.exists() && std::fs::read_to_string(&dst).unwrap() == "body");
    assert!(matches!(&steps[..], [Step::Moved { .. }]));
    // A move onto an existing name refuses with the rename's own error, still with no batch.
    let src = d.file("b.txt", "source");
    std::fs::write(&dst, "taken").unwrap();
    let source = ItemIdentity::inspect(&src).unwrap();
    let err = match land_move(1, 1, "b.txt", &src, &dst, source, &flag, &tx, &settled, &mut steps, &mut durability, &mut batch) {
        MoveOutcome::Done(Err(e)) => e,
        _ => panic!("a clobbering move must refuse"),
    };
    assert_eq!(err.where_, "rename");
    assert!(batch.is_empty());
    assert_eq!(std::fs::read_to_string(&dst).unwrap(), "taken");
    durable::test_reset();
}

// One drain for transfer-level cases: every item line plus the done counts, steps and retry.
struct Collected {
    lines: Vec<(usize, bool, String)>,
    ok: usize,
    failed: usize,
    skipped: usize,
    cancelled: bool,
    steps: Vec<Step>,
    retry: Vec<(PathBuf, ItemIdentity)>,
}

fn collect(rx: std::sync::mpsc::Receiver<OpMsg>) -> Collected {
    let mut out = Collected { lines: Vec::new(), ok: 0, failed: 0, skipped: 0, cancelled: false, steps: Vec::new(), retry: Vec::new() };
    for msg in rx.iter() {
        match msg {
            OpMsg::Item { index, ok, err, .. } => out.lines.push((index, ok, err)),
            OpMsg::TransferDone { ok, failed, skipped, cancelled, entry, retry, .. } => {
                out.ok = ok;
                out.failed = failed;
                out.skipped = skipped;
                out.cancelled = cancelled;
                out.steps = entry.steps;
                out.retry = retry;
            }
            _ => {}
        }
    }
    out
}

// A cancel landing mid-batch completes what already copied and still reports cancelled.
#[test]
fn a_cancelled_move_transfer_reports_cancelled_with_landed_complete() {
    use std::sync::Arc;
    use std::time::Duration;
    let _force = ForceCopyGuard::hold();
    let d = TestDir::new("movebatch-cancel-transfer");
    let srcdir = d.dir("src");
    let out = d.dir("out");
    // Small files stage before the watcher fires; large ones keep a copy in flight for the cancel.
    for n in 0..5 {
        std::fs::write(srcdir.join(format!("s{n}.txt")), "small").unwrap();
    }
    for n in 0..10 {
        std::fs::write(srcdir.join(format!("l{n}.txt")), vec![b'l'; 8 * 1024 * 1024]).unwrap();
    }
    let names: Vec<String> = (0..5).map(|n| format!("s{n}.txt")).chain((0..10).map(|n| format!("l{n}.txt"))).collect();
    let paths: Vec<String> = names.iter().map(|n| srcdir.join(n).to_string_lossy().into_owned()).collect();
    let cancel = Arc::new(AtomicBool::new(false));
    let probe = Arc::clone(&cancel);
    let dest_probe = out.clone();
    let watcher = std::thread::spawn(move || {
        for _ in 0..30_000 {
            if probe.load(Ordering::Relaxed) {
                return;
            }
            if std::fs::read_dir(&dest_probe).is_ok_and(|e| e.count() >= 5) {
                probe.store(true, Ordering::Relaxed);
                return;
            }
            std::thread::sleep(Duration::from_millis(1));
        }
    });
    let (tx, rx) = channel();
    crate::backend::opsreq::run_transfer_checked(1, true, paths, out.clone(), Arc::clone(&cancel), tx,
        None, None, crate::backend::collide::Policy::default());
    watcher.join().unwrap();
    let got = collect(rx);
    assert!(got.cancelled, "a pressed cancel answers cancelled whatever the last item hit");
    assert_eq!(got.failed, 0);
    assert!(got.ok >= 1, "at least one landed copy completed as a move");
    assert_eq!(got.ok + got.skipped, 15);
    assert!(got.lines.iter().all(|(_, ok, err)| *ok || err == CANCELLED), "no landed copy is ever removed by a cancel");
    assert_eq!(got.lines.iter().filter(|(_, ok, _)| *ok).count(), got.ok);
    assert!(got.steps.iter().all(|s| matches!(s, Step::Moved { .. })), "redo sees moved steps only");
    assert_eq!(got.steps.len(), got.ok);
    for name in &names {
        let src = srcdir.join(name);
        let dst = out.join(name);
        if dst.exists() {
            assert!(!src.exists(), "a completed move leaves nothing at its source: {name}");
        } else {
            assert!(src.exists(), "an unstarted item keeps its source whole: {name}");
        }
    }
    let mut journal = crate::backend::undo::Journal::new();
    journal.push(crate::backend::undo::Entry { op: "move".to_string(), steps: got.steps });
    journal.undo().unwrap();
    for name in &names {
        assert!(srcdir.join(name).exists(), "undo brings every source back: {name}");
        assert!(!out.join(name).exists(), "and takes every landed copy: {name}");
    }
}

// Directories and symlinks never stage: they move alone by rename, keeping their inode.
#[test]
fn non_regular_items_close_the_batch_and_move_alone() {
    let _force = ForceCopyGuard::hold();
    let d = TestDir::new("movebatch-nonregular");
    let srcdir = d.dir("src");
    let out = d.dir("out");
    let a = srcdir.join("a.txt");
    std::fs::write(&a, "a").unwrap();
    let b = srcdir.join("b.txt");
    std::fs::write(&b, "b").unwrap();
    let tree = srcdir.join("tree");
    std::fs::create_dir(&tree).unwrap();
    std::fs::write(tree.join("inner.txt"), "inner").unwrap();
    let target = srcdir.join("target.txt");
    std::fs::write(&target, "target").unwrap();
    let link = srcdir.join("link.txt");
    std::os::unix::fs::symlink(&target, &link).unwrap();
    let tree_ino = tree.symlink_metadata().unwrap().ino();
    let link_ino = link.symlink_metadata().unwrap().ino();
    let paths = [a, tree, link, b].iter().map(|p| p.to_string_lossy().into_owned()).collect::<Vec<_>>();
    let (tx, rx) = channel();
    crate::backend::opsreq::run_transfer_checked(1, true, paths, out.clone(),
        std::sync::Arc::new(AtomicBool::new(false)), tx, None, None, crate::backend::collide::Policy::default());
    let got = collect(rx);
    assert_eq!((got.ok, got.failed, got.skipped, got.cancelled), (4, 0, 0, false));
    assert_eq!(out.join("tree").symlink_metadata().unwrap().ino(), tree_ino, "a directory moves by rename, not by copy");
    assert_eq!(out.join("link.txt").symlink_metadata().unwrap().ino(), link_ino, "and so does a symlink");
    assert_eq!(std::fs::read_to_string(out.join("tree/inner.txt")).unwrap(), "inner");
    assert_eq!(std::fs::read_to_string(out.join("a.txt")).unwrap(), "a");
    assert_eq!(std::fs::read_to_string(out.join("b.txt")).unwrap(), "b");
    assert!(got.steps.iter().all(|s| matches!(s, Step::Moved { .. })));
    assert_eq!(got.steps.len(), 4);
}
