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
    let first = free_name(dir.path(), "2026-09-14");
    assert!(first.ends_with("shelf-2026-09-14.zip"));
    std::fs::write(&first, "an archive").unwrap();
    let second = free_name(dir.path(), "2026-09-14");
    assert!(second.ends_with("shelf-2026-09-14-2.zip"), "got {}", second.display());
}

#[test]
fn a_peer_is_named_the_way_the_send_command_resolves_it() {
    let status = r#"{"Peer":{"nodekey:aa":{"DNSName":"macbookair.tail1234.ts.net.","HostName":"macbookair","Online":true},
                             "nodekey:bb":{"DNSName":"","HostName":"iphone"},
                             "nodekey:cc":{"DNSName":"se-mma-wg-001.mullvad.ts.net.","HostName":"se-mma"}}}"#;
    assert_eq!(peer_names(status), vec!["iphone".to_string(), "macbookair.tail1234.ts.net".to_string()],
               "an exit-node relay is never a send target");
    assert!(peer_names("not json at all").is_empty());
    assert!(peer_names(r#"{"Self":{"HostName":"minipc"}}"#).is_empty(), "a tailnet of one has no peer to send to");
}
