use super::*;
use crate::backend::testdir::TestDir;

#[test]
fn the_writability_probe_leaves_nothing_behind_and_refuses_a_directory_that_is_not_there() {
    let dir = TestDir::new("shelfzipwritable");
    // A directory that exists takes the probe and gives it back; nothing is left behind.
    writable(dir.path()).expect("a directory of this test's own is writable");
    let left: Vec<String> = std::fs::read_dir(dir.path())
        .unwrap()
        .filter_map(|e| e.ok().map(|e| e.file_name().to_string_lossy().to_string()))
        .filter(|name| !name.starts_with(".flea-test-sandbox"))
        .collect();
    assert!(left.is_empty(), "the probe cleans up after itself, found {:?}", left);
    assert!(writable(&dir.path().join("no-such-directory")).is_err(), "and a directory that is not there is not writable");
}

#[test]
fn a_pile_that_spans_folders_is_archived_from_the_deepest_directory_they_share() {
    let paths = vec![
        "/home/gm/Pictures/raw/one.jpg".to_string(),
        "/home/gm/Documents/notes.md".to_string(),
    ];
    let (parent, names) = relative_to_ancestor(&paths).unwrap();
    assert_eq!(parent, PathBuf::from("/home/gm"));
    assert_eq!(names, vec!["Pictures/raw/one.jpg", "Documents/notes.md"],
               "two files of the same name from two folders have to stay two files");
    // One directory is its own ancestor, which is the pane's own case and must still work.
    let same = vec!["/tmp/a/one".to_string(), "/tmp/a/two".to_string()];
    assert_eq!(relative_to_ancestor(&same).unwrap().0, PathBuf::from("/tmp/a"));
}

#[test]
fn the_days_second_archive_does_not_replace_the_first() {
    let dir = TestDir::new("shelfzipname");
    let first = free_name(dir.path(), "2026-09-14").unwrap().expect("a first name");
    assert!(first.ends_with("shelf-2026-09-14.zip"));
    assert!(first.symlink_metadata().is_ok(), "the name is taken by creating it, not by looking");
    std::fs::write(&first, "an archive").unwrap();
    let second = free_name(dir.path(), "2026-09-14").unwrap().expect("a second name");
    assert!(second.ends_with("shelf-2026-09-14-2.zip"), "got {}", second.display());
    // A reservation nobody keeps goes back when it drops, so the next zip of that date takes it again.
    drop(Reserved { path: second.clone(), kept: false });
    assert!(second.symlink_metadata().is_err(), "the name is free again");
}

#[test]
fn the_cap_is_the_hundred_the_constant_names_and_the_hundred_and_first_is_refused() {
    let dir = TestDir::new("shelfzipfull");
    // Ninety-nine on disk: the unsuffixed one and -2 through -99, so one name is still free.
    std::fs::write(dir.path().join("shelf-2026-09-14.zip"), "an archive").unwrap();
    for n in 2..ARCHIVES_A_DAY {
        std::fs::write(dir.path().join(format!("shelf-2026-09-14-{}.zip", n)), "an archive").unwrap();
    }
    let last = free_name(dir.path(), "2026-09-14").unwrap().expect("the hundredth name");
    assert!(last.ends_with("shelf-2026-09-14-100.zip"), "got {}", last.display());
    assert!(free_name(dir.path(), "2026-09-14").unwrap().is_none(), "the hundred and first is refused");
}
