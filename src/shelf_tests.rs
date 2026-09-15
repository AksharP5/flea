use super::*;
use crate::backend::testdir::TestDir;

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
fn only_what_moved_leaves_the_pile() {
    let (dir, shelf) = shelf("shelfsettle");
    let one = file(&dir, "one.txt");
    let two = file(&dir, "two.txt");
    std::fs::create_dir_all(shelf.pile_file().parent().unwrap()).unwrap();
    std::fs::write(
        shelf.pile_file(),
        format!(r#"{{"items":[{{"path":"{}"}},{{"path":"{}"}}]}}"#, one, two),
    )
    .unwrap();
    shelf.settle(&[one.clone()]).unwrap();
    assert_eq!(shelf.pile(), vec![two.clone()], "the moved reference leaves and the other stays");
    // Rule 3: a copy reports nothing moved, so the pile is not touched at all.
    shelf.settle(&[]).unwrap();
    assert_eq!(shelf.pile(), vec![two]);
}

#[test]
fn a_pile_that_cannot_be_read_is_an_empty_one_rather_than_an_error() {
    let (dir, shelf) = shelf("shelfbroken");
    std::fs::create_dir_all(shelf.pile_file().parent().unwrap()).unwrap();
    std::fs::write(shelf.pile_file(), "{\"items\":[{\"pa").unwrap();
    assert!(shelf.pile().is_empty());
    let _ = dir;
}

#[test]
fn a_file_answers_its_own_bytes_and_a_directory_its_walk() {
    let (dir, _shelf) = shelf("shelfsize");
    let one = file(&dir, "one.txt");
    let (bytes, partial) = size_of(&one).unwrap();
    assert_eq!(bytes, "payload".len() as u64, "a plain file is its own entry, not a walk");
    assert!(!partial);
    let tree = dir.dir("tree");
    std::fs::write(tree.join("inner.bin"), vec![0u8; 4096]).unwrap();
    let (walked, _) = size_of(&tree.to_string_lossy()).unwrap();
    assert!(walked > 4096, "a directory answers the walk, which counts what is under it: {}", walked);
}

#[test]
fn a_path_that_is_not_there_answers_a_sentence_rather_than_a_zero() {
    let (dir, _shelf) = shelf("shelfsizegone");
    let gone = dir.path().join("never-written").to_string_lossy().to_string();
    assert!(size_of(&gone).is_err(), "a zero would draw as a real size on the card");
}

#[test]
fn the_row_x_takes_the_reference_off_and_leaves_the_file() {
    let (dir, shelf) = shelf("shelfforget");
    let one = file(&dir, "one.txt");
    let two = file(&dir, "two.txt");
    std::fs::create_dir_all(shelf.pile_file().parent().unwrap()).unwrap();
    std::fs::write(
        shelf.pile_file(),
        format!(r#"{{"items":[{{"path":"{}"}},{{"path":"{}"}}]}}"#, one, two),
    )
    .unwrap();
    shelf.settle(&[one.clone()]).unwrap();
    assert_eq!(shelf.pile(), vec![two], "the reference leaves the pile");
    assert!(std::fs::metadata(&one).is_ok(), "and the file it named is still there");
}

#[test]
fn a_reference_is_added_once_and_a_folder_says_it_is_one() {
    let (dir, shelf) = shelf("shelfadd");
    let one = file(&dir, "one.txt");
    let tree = dir.dir("tree").to_string_lossy().to_string();
    shelf.add(&[one.clone()]).unwrap();
    shelf.add(&[one.clone(), tree.clone()]).unwrap();
    assert_eq!(shelf.pile(), vec![one, tree.clone()], "the second add of a held path changes nothing");
    let text = std::fs::read_to_string(shelf.pile_file()).unwrap();
    assert!(text.contains("\"folder\": true"), "the card draws a folder from the entry, so it is recorded: {}", text);
}

#[test]
fn a_path_that_is_not_there_is_not_added_at_all() {
    let (dir, shelf) = shelf("shelfaddgone");
    let one = file(&dir, "one.txt");
    let gone = dir.path().join("never-written").to_string_lossy().to_string();
    assert!(shelf.add(&[one, gone]).is_err());
    assert!(shelf.pile().is_empty(), "one bad path adds none of them, rather than half a batch");
}

#[test]
fn a_pin_rides_the_pile_entry_and_a_pinned_row_survives_its_own_move() {
    let (dir, shelf) = shelf("shelfpin");
    let one = file(&dir, "one.txt");
    let two = file(&dir, "two.txt");
    shelf.add(&[one.clone(), two.clone()]).unwrap();
    shelf.pin(&[two.clone()], true).unwrap();
    let text = std::fs::read_to_string(shelf.pile_file()).unwrap();
    assert!(text.contains("\"pinned\": true"), "the flag rides the entry: {}", text);
    assert_eq!(shelf.pinned_among(&[one.clone(), two.clone()]), vec![two.clone()]);
    // A move takes both: the loose one leaves the pile and the pinned one stays to be re-pointed.
    shelf.settle(&[one.clone(), two.clone()]).unwrap();
    assert_eq!(shelf.pile(), vec![two.clone()], "a pinned row is never consumed");
    shelf.repoint(&[(two.clone(), "/moved/two.txt".to_string())]).unwrap();
    assert_eq!(shelf.pile(), vec!["/moved/two.txt".to_string()], "and the pin follows the file");
    let moved = std::fs::read_to_string(shelf.pile_file()).unwrap();
    assert!(moved.contains("\"pinned\": true"), "the pin is still a pin after the move: {}", moved);
}

#[test]
fn pinning_a_path_the_shelf_is_not_holding_puts_it_on_the_shelf() {
    let (dir, shelf) = shelf("shelfpinnew");
    let one = file(&dir, "one.txt");
    shelf.pin(&[one.clone()], true).unwrap();
    assert_eq!(shelf.pile(), vec![one.clone()], "Flea's own menu row pins a path the shelf never held");
    shelf.pin(&[one.clone()], false).unwrap();
    assert_eq!(shelf.pile(), vec![one], "unpinning leaves the row on the shelf, loose");
    let text = std::fs::read_to_string(shelf.pile_file()).unwrap();
    assert!(text.contains("\"pinned\": false"), "{}", text);
}
