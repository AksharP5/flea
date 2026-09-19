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

// SettingsRest rule 4: the panel orders the pins, and the loose entries keep their own places.
#[test]
fn order_moves_a_pin_among_the_pins_only() {
    let (dir, shelf) = shelf("shelforder");
    shelf.add(&[file(&dir, "loose.txt")]).unwrap();
    shelf.pin(&[file(&dir, "one.txt"), file(&dir, "two.txt")], true).unwrap();
    let two_again = file(&dir, "two.txt");
    shelf.order(&two_again, 0).unwrap();
    let leaves: Vec<String> = shelf
        .pile()
        .iter()
        .map(|path| path.rsplit('/').next().unwrap_or(path).to_string())
        .collect();
    assert_eq!(leaves, vec!["loose.txt", "two.txt", "one.txt"]);
}

#[test]
fn order_ignores_a_path_that_is_not_pinned_and_a_place_that_is_not_there() {
    let (dir, shelf) = shelf("shelforderbad");
    let one = file(&dir, "one.txt");
    shelf.pin(&[one.clone()], true).unwrap();
    shelf.order("/nowhere", 0).unwrap();
    shelf.order(&one, 9).unwrap();
    assert_eq!(shelf.pile().len(), 1);
}

// The advloop's Rust pass: a pile that cannot be parsed is not an empty one, and writing over it
// would take every row with it.
#[test]
fn a_pile_that_cannot_be_parsed_is_never_written_over() {
    let (dir, shelf) = shelf("shelfbadjson");
    let one = file(&dir, "one.txt");
    shelf.add(&[one.clone()]).unwrap();
    std::fs::write(shelf.pile_file(), b"{\"items\": [ truncated").unwrap();
    let refused = shelf.add(&[file(&dir, "two.txt")]);
    assert!(refused.is_err(), "a pile this cannot read is not an empty pile");
    let kept = std::fs::read_to_string(shelf.pile_file()).unwrap();
    assert!(kept.contains("truncated"), "the operator's own file stayed exactly as it was");
}

// A pinned row whose file was deleted outside Flea is exactly the row that has to be unpinnable.
#[test]
fn a_pin_can_be_taken_off_a_file_that_is_gone() {
    let (dir, shelf) = shelf("shelfghostpin");
    let one = file(&dir, "one.txt");
    shelf.pin(&[one.clone()], true).unwrap();
    std::fs::remove_file(&one).unwrap();
    shelf.pin(&[one.clone()], false).unwrap();
    let pinned = shelf.pinned_among(&[one]);
    assert!(pinned.is_empty(), "the pin came off, {:?}", pinned);
}

// The token records the path the pile spells, so a relative argument still names the same row.