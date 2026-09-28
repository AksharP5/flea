use super::*;
use crate::backend::testdir::TestDir;
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

// Cancel before the confirm removes what the batch copied and keeps every source whole.
#[test]
fn a_cancelled_batch_keeps_sources_and_removes_its_copies() {
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
    assert_eq!((counts.ok, counts.failed, counts.skipped), (0, 0, 2));
    assert!(retry.is_empty(), "a cancel is skipped, never retried");
    assert!(steps.is_empty(), "removed copies journal nothing");
    drop(tx);
    let lines = items(rx);
    assert_eq!(lines.len(), 2);
    assert!(lines.iter().all(|(_, ok, err)| !ok && err == CANCELLED));
    for n in 0..2 {
        assert_eq!(std::fs::read_to_string(srcdir.join(format!("f{n}.txt"))).unwrap(), "body");
        assert!(!out.join(format!("f{n}.txt")).exists(), "the unconfirmed copy goes with the cancel");
    }
    durable::test_reset();
}

// The batch holds one destination folder: a move elsewhere closes it first.
#[test]
fn a_second_folder_closes_the_first_batch() {
    use crate::backend::durable;
    durable::test_reset();
    let d = TestDir::new("movebatch-folder");
    let srcdir = d.dir("src");
    let first = d.dir("first");
    let second = d.dir("second");
    durable::test_mark_durable(d.path());
    let mut durability = durable::Durability::begin(d.path());
    let flag = AtomicBool::new(false);
    let settled = AtomicU64::new(0);
    let mut batch = MoveBatch::new();
    let (tx, _rx) = channel();
    let mut steps = Vec::new();
    assert!(!batch.folder_changed(&first.join("a.txt")), "an empty batch changes no folder");
    let src = srcdir.join("a.txt");
    std::fs::write(&src, "body").unwrap();
    staged(1, &mut batch, &mut durability, &flag, &tx, &settled, &mut steps, 0, &src, &first.join("a.txt"));
    assert!(!batch.folder_changed(&first.join("b.txt")), "the same folder joins");
    assert!(batch.folder_changed(&second.join("a.txt")), "another folder closes");
    let (counts, _) = close_normal(&mut batch, 1, &tx, &mut steps, &mut durability);
    assert_eq!(counts.ok, 1);
    let src = srcdir.join("b.txt");
    std::fs::write(&src, "body").unwrap();
    staged(1, &mut batch, &mut durability, &flag, &tx, &settled, &mut steps, 1, &src, &second.join("b.txt"));
    let (counts, _) = close_normal(&mut batch, 1, &tx, &mut steps, &mut durability);
    assert_eq!(counts.ok, 1);
    assert_eq!(durable::test_counts().1, 2, "one confirm per folder: {:?}", durable::test_counts());
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

// A tree staged in a batch carries its manifest when the confirm fails, as a single tree move does.
#[test]
fn a_failed_tree_confirm_journals_its_manifest_for_undo() {
    use crate::backend::{durable, undo::Journal};
    durable::test_reset();
    let d = TestDir::new("movebatch-tree-fail");
    let tree = d.dir("tree");
    std::fs::write(tree.join("a.txt"), "body").unwrap();
    let out = d.dir("out");
    durable::test_mark_durable(&out);
    let mut durability = durable::Durability::begin(&out);
    let flag = AtomicBool::new(false);
    let settled = AtomicU64::new(0);
    let mut batch = MoveBatch::new();
    let (tx, _rx) = channel();
    let mut steps = Vec::new();
    staged(1, &mut batch, &mut durability, &flag, &tx, &settled, &mut steps, 0, &tree, &out.join("tree"));
    durable::test_set_fail_dirs(true);
    let (counts, retry) = close_normal(&mut batch, 1, &tx, &mut steps, &mut durability);
    durable::test_set_fail_dirs(false);
    assert_eq!((counts.ok, counts.failed), (0, 1));
    assert_eq!(retry.len(), 1);
    assert!(matches!(&steps[..], [Step::Copied { manifest: Some(_), .. }]), "the tree's manifest rides its partial");
    assert!(tree.join("a.txt").exists(), "the source tree stays whole");
    let mut journal = Journal::new();
    journal.push(crate::backend::undo::Entry { op: "move".to_string(), steps });
    assert_eq!(journal.undo().unwrap(), "move");
    assert!(!out.join("tree").exists(), "undo took the unconfirmed tree back");
    assert!(tree.join("a.txt").exists(), "and never touched the source");
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
