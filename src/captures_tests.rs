use super::*;
use crate::backend::testdir::TestDir;

fn touch(dir: &TestDir, name: &str) -> PathBuf {
    dir.file(name, "capture")
}

#[test]
fn only_the_names_the_capture_scripts_write_are_listed() {
    let dir = TestDir::new("captures-names");
    touch(&dir, "screenshot-2026-09-14_19-02-11.png");
    touch(&dir, "holiday.png");
    touch(&dir, "screenshot-2026-09-14_18-41-02.txt");
    let mut found = Vec::new();
    collect(dir.path(), SCREENSHOT_PREFIX, SCREENSHOT_SUFFIX, &mut found);
    assert_eq!(found.len(), 1, "a pictures directory is not a tray: {:?}", found.iter().map(|c| &c.path).collect::<Vec<_>>());
    assert!(found[0].path.ends_with("screenshot-2026-09-14_19-02-11.png"));
}

#[test]
fn a_directory_that_is_not_there_is_an_empty_tray_rather_than_an_error() {
    let mut found = Vec::new();
    collect(Path::new("/definitely/not/here/flea-captures"), SCREENSHOT_PREFIX, SCREENSHOT_SUFFIX, &mut found);
    assert!(found.is_empty());
}

#[test]
fn the_newest_come_first_across_both_directories_and_the_count_caps_them() {
    let made = |path: &str, at: u64| Capture { path: path.to_string(), mtime_ms: at };
    let found = vec![
        made("/p/screenshot-old.png", 1_000),
        made("/v/screenrecording-newest.mp4", 3_000),
        made("/p/screenshot-middle.png", 2_000),
    ];
    let newest = newest_of(found, 2);
    assert_eq!(newest.len(), 2, "the count is the cut");
    assert_eq!(newest[0].path, "/v/screenrecording-newest.mp4", "a recording sorts with the screenshots");
    assert_eq!(newest[1].path, "/p/screenshot-middle.png");
}

#[test]
fn the_tray_can_never_ask_for_more_than_the_settings_own_ceiling() {
    let found: Vec<Capture> = (0..10)
        .map(|i| Capture { path: format!("/p/screenshot-{}.png", i), mtime_ms: i })
        .collect();
    assert_eq!(newest_of(found, 99).len(), MAX_CAPTURES);
}

#[test]
fn a_user_dirs_line_is_read_the_way_the_capture_scripts_source_it() {
    let text = "# a comment\nXDG_DESKTOP_DIR=\"$HOME/\"\nXDG_PICTURES_DIR=\"$HOME/Media/Shots\"\n";
    assert_eq!(user_dirs_entry(text, "XDG_PICTURES_DIR", "/home/gm"), Some("/home/gm/Media/Shots".to_string()));
    assert_eq!(user_dirs_entry(text, "XDG_VIDEOS_DIR", "/home/gm"), None, "a key the file does not carry falls through to the default");
    // A commented-out key is not a value, or the tray would list a directory the scripts never write to.
    assert_eq!(user_dirs_entry("#XDG_PICTURES_DIR=\"$HOME/Nope\"\n", "XDG_PICTURES_DIR", "/home/gm"), None);
}

#[test]
fn the_kinds_the_settings_checked_are_the_kinds_that_are_listed() {
    let shots = TestDir::new("captures-kinds-shots");
    let clips = TestDir::new("captures-kinds-clips");
    touch(&shots, "screenshot-2026-09-14_19-02-11.png");
    touch(&clips, "screenrecording-2026-09-14_18-41-02.mp4");
    // The gate itself, driven the way Settings drives it, rather than two collect calls that would
    // pass whatever the gate did.
    let both = newest_in(shots.path(), clips.path(), 6, true, true);
    assert_eq!(both.len(), 2, "with both kinds checked the tray holds both");
    let only_shots = newest_in(shots.path(), clips.path(), 6, true, false);
    assert_eq!(only_shots.len(), 1, "a recording is not listed for a tray that asked for shots");
    assert!(only_shots[0].path.ends_with(".png"));
    let only_clips = newest_in(shots.path(), clips.path(), 6, false, true);
    assert_eq!(only_clips.len(), 1, "and a screenshot is not listed for a tray that asked for clips");
    assert!(only_clips[0].path.ends_with(".mp4"));
    assert!(newest_in(shots.path(), clips.path(), 6, false, false).is_empty(),
            "with neither checked the tray is empty rather than full");
}
