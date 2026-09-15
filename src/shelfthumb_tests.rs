use super::line;

#[test]
fn answers_name_the_path_they_belong_to() {
    assert_eq!(
        line(Some("/home/gm/.cache/thumbnails/large/714c.png"), "/home/gm/Pictures/shot.png"),
        "/home/gm/.cache/thumbnails/large/714c.png\t/home/gm/Pictures/shot.png"
    );
}

#[test]
fn a_path_with_no_thumbnail_answers_none() {
    assert_eq!(line(None, "/home/gm/notes.md"), "none\t/home/gm/notes.md");
}

// A path with a space still answers on one line, because the tab is the only separator.
#[test]
fn a_space_in_a_path_is_not_a_separator() {
    assert_eq!(line(None, "/home/gm/two words.txt"), "none\t/home/gm/two words.txt");
}
