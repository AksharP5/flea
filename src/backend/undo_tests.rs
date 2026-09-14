use super::*;
use crate::backend::testdir::TestDir;

fn entry(op: &str, steps: Vec<Step>) -> Entry {
    Entry { op: op.to_string(), steps }
}

#[test]
fn an_empty_journal_answers_an_error_rather_than_claiming_it_undid_something() {
    let mut j = Journal::new();
    let e = j.undo().expect_err("nothing to undo");
    assert_eq!(e.where_, "undo");
    assert!(e.msg.contains("nothing to undo"));
}

#[test]
fn an_operation_that_changed_nothing_is_not_recorded() {
    let mut j = Journal::new();
    j.push(entry("rename", Vec::new()));
    assert!(j.is_empty(), "an empty step list would undo as a no-op reported as work");
}

#[test]
fn the_ring_is_bounded_at_fifty_and_drops_its_oldest() {
    let mut j = Journal::new();
    for i in 0..DEPTH + 10 {
        j.push(entry(&format!("op {}", i), vec![Step::Created { path: PathBuf::from("/x") }]));
    }
    assert_eq!(j.len(), DEPTH);
}

#[test]
fn undoing_a_rename_puts_the_old_name_back() {
    let d = TestDir::new("undorename");
    let from = d.join("before.txt");
    let to = d.file("after.txt", "body");
    let mut j = Journal::new();
    j.push(entry("rename", vec![moved(&from, &to, ItemIdentity::inspect(&to).unwrap()).unwrap()]));
    assert_eq!(j.undo().expect("undo"), "rename");
    assert!(from.exists(), "the original name is back");
    assert!(!to.exists(), "the new name is gone");
    assert_eq!(std::fs::read_to_string(&from).unwrap(), "body");
}

#[test]
fn undoing_a_rename_refuses_to_clobber_a_file_that_took_the_old_name_since() {
    let d = TestDir::new("undoclobber");
    let from = d.file("before.txt", "something else wrote this");
    let to = d.file("after.txt", "body");
    let mut j = Journal::new();
    j.push(entry("rename", vec![moved(&from, &to, ItemIdentity::inspect(&to).unwrap()).unwrap()]));
    let e = j.undo().expect_err("must refuse rather than destroy the newer file");
    assert_eq!(e.where_, "rename");
    assert_eq!(std::fs::read_to_string(&from).unwrap(), "something else wrote this");
}

// Issue 111: the copied root keeps its own ctime while a file inside it is edited or a new one is
// added, so undo removed a tree the user had gone on working in, permanently and not to the trash.
#[test]
fn undoing_a_copied_folder_refuses_once_anything_inside_it_has_changed() {
    for change in ["edit", "add"] {
        let d = TestDir::new(&format!("undotree{change}"));
        let source = d.dir("source");
        std::fs::create_dir(source.join("nested")).unwrap();
        std::fs::write(source.join("nested/document.txt"), "as copied").unwrap();
        let copy = d.join("copy");
        let flag = std::sync::atomic::AtomicBool::new(false);
        let mut sink = |_: u64, _: u64| {};
        let mut p = crate::backend::copyfile::Progress { cancel: &flag, on_bytes: &mut sink, tree: None, partial: None };
        crate::backend::copyfile::copy_any(&source, &copy, &mut p).expect("the copy this undo reverses");
        let step = copied(&source, &copy, ItemIdentity::inspect(&source).unwrap()).unwrap();
        // Measured: /tmp is tmpfs, whose timestamps are coarser than this test is fast, so the copy and
        // the edit landed on the same nanosecond and the change was indistinguishable from the copy.
        std::thread::sleep(std::time::Duration::from_millis(20));
        // A later edit and a later create both leave the root's own ctime exactly where the copy left it.
        match change {
            "edit" => std::fs::write(copy.join("nested/document.txt"), "the user's own work").unwrap(),
            _ => std::fs::write(copy.join("nested/new-work.txt"), "the user's own work").unwrap(),
        }
        let mut j = Journal::new();
        j.push(entry("copy", vec![step]));
        let e = j.undo().expect_err("must refuse rather than delete work done since the copy");
        assert_eq!(e.where_, "undo");
        assert!(e.msg.contains("changed since this operation"), "{}", e.msg);
        assert!(copy.join("nested").exists(), "the tree the user was working in is still there");
        match change {
            "edit" => assert_eq!(std::fs::read_to_string(copy.join("nested/document.txt")).unwrap(), "the user's own work"),
            _ => assert!(copy.join("nested/new-work.txt").exists(), "the new file survives the refusal"),
        }
    }
}

// The control: a tree nobody touched is still the copy's own, so undo removes it the way it always did.
#[test]
fn undoing_a_copied_folder_nobody_touched_still_removes_it() {
    let d = TestDir::new("undotreeclean");
    let source = d.dir("source");
    std::fs::create_dir(source.join("nested")).unwrap();
    std::fs::write(source.join("nested/document.txt"), "as copied").unwrap();
    let copy = d.join("copy");
    let flag = std::sync::atomic::AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = crate::backend::copyfile::Progress { cancel: &flag, on_bytes: &mut sink, tree: None, partial: None };
    crate::backend::copyfile::copy_any(&source, &copy, &mut p).expect("copy");
    let step = copied(&source, &copy, ItemIdentity::inspect(&source).unwrap()).unwrap();
    let mut j = Journal::new();
    j.push(entry("copy", vec![step]));
    j.undo().expect("an untouched copy is still this operation's to remove");
    assert!(!copy.exists(), "the copy is gone and the source is untouched");
    assert!(source.join("nested/document.txt").exists());
}

#[test]
fn undoing_a_duplicate_removes_only_the_copy_it_created() {
    let d = TestDir::new("undodup");
    let original = d.file("doc.txt", "original");
    let copy = d.file("doc copy.txt", "original");
    let mut j = Journal::new();
    j.push(entry("duplicate", vec![Step::Created { path: copy.clone() }]));
    d.assert_contains(&copy);
    j.undo().expect("undo");
    assert!(!copy.exists(), "the copy is gone");
    assert!(original.exists(), "the file it was copied from is untouched");
}

#[test]
fn undoing_a_created_directory_takes_its_contents_with_it() {
    let d = TestDir::new("undodir");
    let made = d.dir("copied-tree");
    std::fs::write(made.join("inside.txt"), "body").unwrap();
    let mut j = Journal::new();
    j.push(entry("copy", vec![Step::Created { path: made.clone() }]));
    d.assert_contains(&made);
    j.undo().expect("undo");
    assert!(!made.exists());
}

#[test]
fn the_steps_of_one_operation_reverse_newest_first() {
    let d = TestDir::new("undoorder");
    // A move recorded as two steps: undoing them out of order would leave b.txt where a.txt belongs.
    let a = d.file("a.txt", "a");
    let mut j = Journal::new();
    j.push(entry(
        "move",
        vec![
            moved(&d.join("first.txt"), &a, ItemIdentity::inspect(&a).unwrap()).unwrap(),
            Step::Created { path: d.file("second.txt", "s") },
        ],
    ));
    d.assert_contains(&d.join("second.txt"));
    j.undo().expect("undo");
    assert!(!d.join("second.txt").exists(), "the newest step reversed");
    assert!(d.join("first.txt").exists(), "the oldest step reversed too");
}

#[test]
fn a_step_that_fails_stops_the_rest_rather_than_half_reversing() {
    let d = TestDir::new("undofail");
    let mut j = Journal::new();
    j.push(entry(
        "copy",
        vec![
            Step::Created { path: d.file("keeper.txt", "k") },
            // Reversed first, and it cannot be: nothing is at this path to remove.
            Step::Created { path: d.join("never-existed.txt") },
        ],
    ));
    d.assert_contains(&d.join("keeper.txt"));
    d.assert_contains(&d.join("never-existed.txt"));
    let e = j.undo().expect_err("the missing path must fail");
    assert_eq!(e.where_, "undo");
    assert!(d.join("keeper.txt").exists(), "the step behind the failure was not reversed");
}

#[test]
fn undoing_a_new_folder_removes_it_while_it_is_still_empty() {
    let d = TestDir::new("undomkdir");
    let made = d.dir("fresh");
    let mut j = Journal::new();
    j.push(entry("mkdir", vec![Step::MadeDir { path: made.clone(), identity: ItemIdentity::inspect(&made).unwrap() }]));
    d.assert_contains(&made);
    assert_eq!(j.undo().expect("undo"), "mkdir");
    assert!(!made.exists());
}

#[test]
fn undoing_a_new_folder_the_user_has_filled_refuses_and_keeps_what_is_inside() {
    let d = TestDir::new("undomkdirfilled");
    let made = d.dir("fresh");
    std::fs::write(made.join("theirs.txt"), "not ours to remove").unwrap();
    let mut j = Journal::new();
    j.push(entry("mkdir", vec![Step::MadeDir { path: made.clone(), identity: ItemIdentity::inspect(&made).unwrap() }]));
    d.assert_contains(&made);
    let e = j.undo().expect_err("must refuse rather than delete what the operation did not put there");
    assert_eq!(e.where_, "undo");
    assert_eq!(e.msg, "the new folder has been filled since, so undo left it in place");
    assert_eq!(std::fs::read_to_string(made.join("theirs.txt")).unwrap(), "not ours to remove");
    // Spent like every failed reversal, so the next undo reaches the operation before this one.
    assert!(j.is_empty());
}
