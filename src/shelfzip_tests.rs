use super::*;
use crate::backend::testdir::TestDir;

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
    let first = free_name(dir.path(), "2026-09-14").expect("a first name");
    assert!(first.ends_with("shelf-2026-09-14.zip"));
    std::fs::write(&first, "an archive").unwrap();
    let second = free_name(dir.path(), "2026-09-14").expect("a second name");
    assert!(second.ends_with("shelf-2026-09-14-2.zip"), "got {}", second.display());
}

#[test]
fn the_days_hundredth_archive_is_refused() {
    let dir = TestDir::new("shelfzipfull");
    for n in 0..100 {
        let name = if n == 0 { "shelf-2026-09-14.zip".to_string() } else { format!("shelf-2026-09-14-{}.zip", n + 1) };
        std::fs::write(dir.path().join(name), "an archive").unwrap();
    }
    assert!(free_name(dir.path(), "2026-09-14").is_none());
}
