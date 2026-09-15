use super::*;
use crate::backend::testdir::TestDir;
use crate::shelf::Shelf;

fn shelf(tag: &str) -> (TestDir, Shelf) {
    let dir = TestDir::new(tag);
    let shelf = Shelf::at(dir.path());
    (dir, shelf)
}

fn file(dir: &TestDir, name: &str) -> String {
    dir.file(name, "payload").to_string_lossy().to_string()
}

#[test]
fn a_token_names_the_entries_and_the_intent_the_lift_fixed() {
    let (dir, shelf) = shelf("shelfdrag");
    let one = file(&dir, "one.txt");
    let token = shelf.drag_begin(true, &[one.clone()], 1_000).unwrap();
    assert_eq!(token.len(), TOKEN_BYTES * 2, "sixteen bytes of randomness, hex encoded");
    let redeemed = shelf.redeem(&token, 1_500).unwrap();
    assert!(redeemed.moving, "a plain shelf drag asks for a move");
    assert_eq!(redeemed.paths, vec![one]);
}

#[test]
fn a_token_is_spent_the_first_time_it_is_redeemed() {
    let (dir, shelf) = shelf("shelfonce");
    let token = shelf.drag_begin(false, &[file(&dir, "one.txt")], 1_000).unwrap();
    assert!(shelf.redeem(&token, 1_100).is_ok());
    let again = shelf.redeem(&token, 1_200);
    assert!(again.is_err(), "a replayed token finds nothing: {:?}", again.map(|r| r.paths));
}

#[test]
fn a_token_older_than_a_gesture_is_refused() {
    let (dir, shelf) = shelf("shelfstale");
    let token = shelf.drag_begin(true, &[file(&dir, "one.txt")], 1_000).unwrap();
    assert!(shelf.redeem(&token, 1_000 + TOKEN_LIFE_MS).is_err(), "a drag does not outlive its own gesture");
}

#[test]
fn a_token_nobody_minted_is_refused() {
    let (_dir, shelf) = shelf("shelfforged");
    assert!(shelf.redeem("deadbeefdeadbeefdeadbeefdeadbeef", 1_000).is_err());
}

#[test]
fn an_entry_that_is_not_the_file_it_was_is_refused() {
    let (dir, shelf) = shelf("shelfswapped");
    let one = file(&dir, "one.txt");
    let token = shelf.drag_begin(true, &[one.clone()], 1_000).unwrap();
    // The same name, another inode: what the shelf was holding is gone and the drag is not it.
    std::fs::remove_file(&one).unwrap();
    std::fs::write(&one, "another file entirely").unwrap();
    let refused = shelf.redeem(&token, 1_100);
    assert!(refused.is_err(), "a path that now names another inode is not what was lifted");
}

#[test]
fn a_drag_of_nothing_is_refused_before_a_token_exists() {
    let (_dir, shelf) = shelf("shelfempty");
    assert!(shelf.drag_begin(true, &[], 1_000).is_err());
}

#[test]
fn a_drag_records_the_absolute_path_the_pile_holds() {
    let (dir, shelf) = shelf("shelfrelative");
    let one = file(&dir, "one.txt");
    let token = shelf.drag_begin(true, &[one.clone()], 1_000).unwrap();
    assert_eq!(shelf.redeem(&token, 1_100).unwrap().paths, vec![one]);
}
