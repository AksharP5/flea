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
    // The ordering is the whole of the rule and it is a pure list edit, so no state home is
    // touched: this binary's tests share one process and one environment.
    assert_eq!(ordered(&["/tmp/two".to_string(), "/tmp/one".to_string()], "/tmp/one"),
               vec!["/tmp/one", "/tmp/two"]);
    let many: Vec<String> = (0..6).map(|n| format!("/tmp/{}", n)).collect();
    assert_eq!(ordered(&many, "/tmp/new").len(), KEPT, "a list, not a log");
    assert_eq!(ordered(&many, "/tmp/new")[0], "/tmp/new", "the newest is the one at the front");
}

#[test]
fn a_percent_escape_decodes_without_splitting_a_character_in_half() {
    assert_eq!(decode("/home/gm/Work%20notes"), "/home/gm/Work notes");
    // A percent, one hex digit, then a two byte character: read as a string slice this panics.
    let accented = "/home/gm/100%a\u{00e9}";
    assert_eq!(decode(accented), accented);
    assert_eq!(decode("/home/gm/half%2"), "/home/gm/half%2", "a truncated escape is not an escape");
}

#[test]
fn the_chooser_answers_a_directory_or_nothing_at_all() {
    assert_eq!(chosen_dir(r#"{"response":0,"uris":["file:///home/gm/Work%20notes"]}"#),
               Some("/home/gm/Work notes".to_string()));
    // esc in the chooser is response 1, and a cancelled chooser has chosen nothing.
    assert_eq!(chosen_dir(r#"{"response":1}"#), None);
    assert_eq!(chosen_dir(""), None);
}
