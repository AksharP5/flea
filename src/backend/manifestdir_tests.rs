use super::*;
use crate::backend::testdir::TestDir;
use std::os::unix::fs::PermissionsExt;

fn owned_seven_hundred(path: &Path) {
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700)).unwrap();
}

#[test]
fn a_candidate_on_the_copy_filesystem_is_skipped() {
    let d = TestDir::new("manifestdirskip");
    let same = d.dir("same");
    owned_seven_hundred(&same);
    let dev: u64 = same.symlink_metadata().unwrap().dev();
    assert!(
        pick(&[same.clone()], &[dev], current_uid()).is_err(),
        "same-device candidate pins the drive being copied to"
    );
    assert_eq!(
        pick(&[same.clone()], &[], current_uid()).unwrap(),
        same,
        "the same directory qualifies once no copy forbids its filesystem"
    );
}

#[test]
fn a_candidate_with_the_wrong_mode_is_never_reused() {
    let d = TestDir::new("manifestdirmode");
    let loose = d.dir("loose");
    std::fs::set_permissions(&loose, std::fs::Permissions::from_mode(0o755)).unwrap();
    let good = d.dir("good");
    owned_seven_hundred(&good);
    assert_eq!(
        pick(&[loose.clone(), good.clone()], &[], current_uid()).unwrap(),
        good,
        "a 0755 directory is skipped, never chmodded into service"
    );
    assert_eq!(
        loose.symlink_metadata().unwrap().permissions().mode() & 0o777,
        0o755,
        "the skipped directory keeps its own mode"
    );
}

#[test]
fn a_symlink_candidate_is_skipped() {
    let d = TestDir::new("manifestdirlink");
    let target = d.dir("target");
    let link = d.join("link");
    std::os::unix::fs::symlink(&target, &link).unwrap();
    let good = d.dir("good");
    owned_seven_hundred(&good);
    assert_eq!(
        pick(&[link.clone(), good.clone()], &[], current_uid()).unwrap(),
        good,
        "a planted symlink never becomes the manifest directory"
    );
}

#[test]
fn no_qualifying_candidate_is_a_loud_error() {
    let d = TestDir::new("manifestdirnone");
    let only = d.dir("only");
    owned_seven_hundred(&only);
    let dev: u64 = only.symlink_metadata().unwrap().dev();
    assert!(
        pick(&[only], &[dev], current_uid()).is_err(),
        "no off-copy filesystem means no manifest, said out loud"
    );
}

#[test]
fn an_owned_0700_directory_is_reused() {
    let d = TestDir::new("manifestdirreuse");
    let good = d.dir("good");
    owned_seven_hundred(&good);
    assert_eq!(pick(&[good.clone()], &[], current_uid()).unwrap(), good);
}

#[test]
fn a_missing_candidate_is_created_owner_only() {
    let d = TestDir::new("manifestdirmake");
    let fresh = d.join("fresh");
    let picked = pick(&[fresh.clone()], &[], current_uid()).unwrap();
    assert_eq!(picked, fresh);
    assert_eq!(fresh.symlink_metadata().unwrap().permissions().mode() & 0o777, 0o700);
}
