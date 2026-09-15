use super::*;

#[test]
fn the_user_dirs_file_is_read_the_way_the_rail_reads_it() {
    let text = "# written by xdg-user-dirs-update\nXDG_DESKTOP_DIR=\"$HOME/\"\nXDG_DOWNLOAD_DIR=\"$HOME/Downloads\"\nXDG_PICTURES_DIR=\"$HOME/Pictures/\"\n";
    assert_eq!(user_dirs(text, "/home/gm"), vec!["/home/gm/Downloads", "/home/gm/Pictures"],
               "a directory that is home itself is not a place of its own");
}

#[test]
fn a_bookmark_is_a_folder_only_when_it_names_one() {
    let text = "file:///home/gm/Work%20notes Work\nsmb://nas/share Share\nfile:///tmp\n";
    assert_eq!(bookmarks(text), vec!["/home/gm/Work notes", "/tmp"],
               "a share is a location and its escapes are part of the path");
}

#[test]
fn a_destination_used_again_moves_to_the_front_rather_than_appearing_twice() {
    let dir = crate::backend::testdir::TestDir::new("shelfdests");
    // The recents live beside the pile, so the test points the whole state home at its own sandbox.
    std::env::set_var("XDG_STATE_HOME", dir.path());
    remember("/tmp/one").unwrap();
    remember("/tmp/two").unwrap();
    remember("/tmp/one").unwrap();
    assert_eq!(recents(), vec!["/tmp/one", "/tmp/two"]);
    for i in 0..6 {
        remember(&format!("/tmp/{}", i)).unwrap();
    }
    assert_eq!(recents().len(), KEPT, "a list, not a log");
    std::env::remove_var("XDG_STATE_HOME");
}
