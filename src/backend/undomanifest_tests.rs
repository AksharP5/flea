// Undo of a failed tree copy removes exactly what the copy created, keeping strays.
use crate::backend::copymanifest;
use crate::backend::copyfile::Progress;
use crate::backend::ops;
use crate::backend::testdir::TestDir;
use crate::backend::undo::{copied_partial, Entry, ItemIdentity, Journal, Step};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

fn journal(op: &str, steps: Vec<Step>) -> Journal {
    let mut j = Journal::new();
    j.push(Entry { op: op.to_string(), steps });
    j
}

fn check_root(d: &TestDir, path: &Path) {
    d.assert_contains(path);
    assert!(path.is_absolute() && path.starts_with(d.path()));
}

// Runs a tree copy with its manifest attached, failing after three files whatever order readdir returns.

fn partial_with_manifest(src: &Path, dst: &Path, hook: &mut dyn FnMut(u32, &Path, &Path)) -> copymanifest::Handle {
    let flag = AtomicBool::new(false);
    let mut reports = 0u32;
    let mut sink = |_: u64, _: u64| {
        reports += 1;
        hook(reports, src, dst);
    };
    let mut p = Progress {
        cancel: &flag,
        on_bytes: &mut sink,
        tree: None,
        partial: None,
        manifest: copymanifest::writer_for(src, dst),
    };
    let outcome = crate::backend::copyfile::copy_any(src, dst, &mut p);
    let finished = p.partial.take();
    let manifest = p.manifest.take().map(|writer| writer.finish().expect("no I/O")).unwrap_or(None);
    drop(p);
    std::fs::set_permissions(src, std::fs::Permissions::from_mode(0o755)).unwrap();
    let _ = std::fs::set_permissions(src.join("nested"), std::fs::Permissions::from_mode(0o755));
    outcome.expect_err("the hook must fail the tree copy");
    assert_eq!(finished, Some(dst.to_path_buf()));
    assert!(reports >= 3, "three files went before the failure");
    manifest.expect("the failed copy is manifested")
}

fn fail_after_three(reports: u32, src: &Path, _dst: &Path) {
    if reports == 3 {
        std::thread::sleep(std::time::Duration::from_millis(20));
        std::fs::set_permissions(src, std::fs::Permissions::from_mode(0o000)).unwrap();
    }
}

fn flat_source(d: &TestDir, name: &str) -> PathBuf {
    let src = d.dir(name);
    for i in 0..10 {
        std::fs::write(src.join(format!("f{i}.bin")), "x".repeat(64)).unwrap();
    }
    src
}

#[test]
fn a_failed_tree_copy_is_fully_removed_by_undo() {
    let d = TestDir::new("undopartialmanifest");
    let src = flat_source(&d, "source");
    let partial = d.join("clone");
    let handle = partial_with_manifest(&src, &partial, &mut fail_after_three);
    check_root(&d, &partial);
    let step = copied_partial(&src, &partial, ItemIdentity::inspect(&src).unwrap(), Some(handle)).unwrap();
    let mut j = journal("copy", vec![step]);
    assert_eq!(j.undo().expect("a failed copy's own files must go"), "copy");
    assert!(!partial.exists(), "the partial tree is gone and nothing else was touched");
    assert!(src.join("f0.bin").exists(), "the source is untouched");
}

#[test]
fn a_file_modified_after_the_copy_survives_while_the_copys_own_files_go() {
    let d = TestDir::new("undopartialforeign2");
    let src = flat_source(&d, "source");
    let partial = d.join("clone");
    let handle = partial_with_manifest(&src, &partial, &mut fail_after_three);
    check_root(&d, &partial);
    // After the copy, so the manifest holds the as-copied identity for certain.

    std::thread::sleep(std::time::Duration::from_millis(20));
    let edited = std::fs::read_dir(&partial).unwrap().flatten().find_map(|entry| {
        let p = entry.path();
        (p.extension().and_then(|e| e.to_str()) == Some("bin")).then_some(p)
    }).expect("a copied file to modify");
    std::fs::write(&edited, "the user's own work").unwrap();
    check_root(&d, &edited);
    let step = copied_partial(&src, &partial, ItemIdentity::inspect(&src).unwrap(), Some(handle)).unwrap();
    let mut j = journal("copy", vec![step]);
    let err = j.undo().expect_err("one kept file must be reported, not silent");
    assert_eq!(err.where_, "undo");
    assert!(err.msg.contains("kept") && err.msg.contains("was modified after the copy"), "honest count and cause: {}", err.msg);
    assert_eq!(std::fs::read_to_string(&edited).unwrap(), "the user's own work");
    assert_eq!(std::fs::read_dir(&partial).unwrap().count(), 1, "only the edited file is left");
}

#[test]
fn a_file_added_mid_copy_survives_inside_a_kept_directory() {
    let d = TestDir::new("undopartialstray");
    let src = d.dir("source");
    for i in 0..10 {
        std::fs::write(src.join(format!("t{i}.bin")), "x".repeat(64)).unwrap();
    }
    let nested = src.join("nested");
    std::fs::create_dir(&nested).unwrap();
    for i in 0..3 {
        std::fs::write(nested.join(format!("n{i}.bin")), "y".repeat(64)).unwrap();
    }
    let partial = d.join("clone");
    // The stray lands in the nested directory, so only that directory is kept.

    let mut planted = false;
    let mut hook = |reports: u32, src: &Path, dst: &Path| {
        if !planted && reports >= 3 && dst.join("nested").is_dir() {
            planted = true;
            std::thread::sleep(std::time::Duration::from_millis(20));
            std::fs::write(dst.join("nested/stray.txt"), "stray").unwrap();
            // Both levels refuse later opens whatever order readdir returns.
            std::fs::set_permissions(src, std::fs::Permissions::from_mode(0o000)).unwrap();
            let _ = std::fs::set_permissions(src.join("nested"), std::fs::Permissions::from_mode(0o000));
        }
    };
    let handle = partial_with_manifest(&src, &partial, &mut hook);
    check_root(&d, &partial);
    assert_eq!(std::fs::read_to_string(partial.join("nested/stray.txt")).unwrap(), "stray");
    let step = copied_partial(&src, &partial, ItemIdentity::inspect(&src).unwrap(), Some(handle)).unwrap();
    let mut j = journal("copy", vec![step]);
    let err = j.undo().expect_err("the stray keeps its directories");
    assert!(err.msg.contains("kept") && err.msg.contains("is not empty"), "honest count and cause: {}", err.msg);
    assert_eq!(std::fs::read_to_string(partial.join("nested/stray.txt")).unwrap(), "stray");
    assert!(walk_bins(&partial).is_empty(), "every file the copy made is gone");
    assert!(partial.join("nested").is_dir() && partial.is_dir(), "only the stray's directories stand");
}

#[test]
fn a_file_replaced_by_another_inode_is_kept() {
    let d = TestDir::new("undopartialreplaced");
    let src = flat_source(&d, "source");
    let partial = d.join("clone");
    let handle = partial_with_manifest(&src, &partial, &mut fail_after_three);
    check_root(&d, &partial);
    let victim = std::fs::read_dir(&partial).unwrap().flatten().find_map(|entry| {
        let p = entry.path();
        (p.extension().and_then(|e| e.to_str()) == Some("bin")).then_some(p)
    }).expect("a copied file to replace");
    std::fs::remove_file(&victim).unwrap();
    std::fs::write(&victim, "a different file at the same name").unwrap();
    let step = copied_partial(&src, &partial, ItemIdentity::inspect(&src).unwrap(), Some(handle)).unwrap();
    let mut j = journal("copy", vec![step]);
    let err = j.undo().expect_err("the replacement must be reported, not removed");
    assert!(err.msg.contains("was replaced after the copy"), "honest cause: {}", err.msg);
    assert_eq!(std::fs::read_to_string(&victim).unwrap(), "a different file at the same name");
}

#[test]
fn a_file_edited_or_replaced_mid_copy_survives_undo() {
    let d = TestDir::new("undopartialmidcopy");
    let src = flat_source(&d, "source");
    let partial = d.join("clone");
    // Snapshotted at 3 and tampered at 5 on the copy's own thread, so both are recorded by then and the manifest holds the as-created identity, so undo keeps both.
    let (mut edited, mut replaced) = (PathBuf::new(), PathBuf::new());
    let mut hook = |reports: u32, src: &Path, dst: &Path| {
        if reports == 3 {
            let mut bins = std::fs::read_dir(dst).unwrap().flatten().map(|entry| entry.path()).filter(|p| p.extension().and_then(|e| e.to_str()) == Some("bin"));
            edited = bins.next().expect("a copied file to edit");
            replaced = bins.next().expect("a copied file to replace");
        } else if reports == 5 {
            std::fs::write(&edited, "the user's own longer work").unwrap();
            let swap = dst.join("swap.bin");
            std::fs::write(&swap, "another writer's file").unwrap();
            std::fs::rename(&swap, &replaced).unwrap();
            std::fs::set_permissions(src, std::fs::Permissions::from_mode(0o000)).unwrap();
        }
    };
    let handle = partial_with_manifest(&src, &partial, &mut hook);
    let step = copied_partial(&src, &partial, ItemIdentity::inspect(&src).unwrap(), Some(handle)).unwrap();
    let mut j = journal("copy", vec![step]);
    let err = j.undo().expect_err("both tampered files must be reported, not removed");
    assert!(err.msg.contains("kept"), "honest count: {}", err.msg);
    assert_eq!(std::fs::read_to_string(&edited).unwrap(), "the user's own longer work");
    assert_eq!(std::fs::read_to_string(&replaced).unwrap(), "another writer's file");
    assert_eq!(std::fs::read_dir(&partial).unwrap().count(), 2, "exactly the two tampered files stand");
}

#[test]
fn a_missing_manifest_falls_back_to_todays_behaviour() {
    let d = TestDir::new("undopartialfallback");
    // Newer inside: today's refusal, word for word.
    let src = flat_source(&d, "source");
    let partial = d.join("clone");
    let handle = partial_with_manifest(&src, &partial, &mut fail_after_three);
    check_root(&d, &partial);
    // An edit bumps only the file it touches, so today's check refuses the tree.

    std::thread::sleep(std::time::Duration::from_millis(20));
    let touched = std::fs::read_dir(&partial).unwrap().flatten().find_map(|entry| {
        let p = entry.path();
        (p.extension().and_then(|e| e.to_str()) == Some("bin")).then_some(p)
    }).expect("a copied file to touch");
    std::fs::write(&touched, "changed after").unwrap();
    let step = copied_partial(&src, &partial, ItemIdentity::inspect(&src).unwrap(), None).unwrap();
    let mut j = journal("copy", vec![step]);
    let err = j.undo().expect_err("no manifest means today's check decides");
    assert!(err.msg.contains("something inside the copied folder changed"), "today's sentence: {}", err.msg);
    assert!(partial.is_dir(), "and today's refusal keeps the tree");
    drop(handle);
}

#[test]
fn a_symlink_the_copy_made_goes_without_touching_its_target() {
    let d = TestDir::new("undopartiallink");
    let src = d.dir("source");
    let target = d.file("target.txt", "do not follow me");
    std::os::unix::fs::symlink(&target, src.join("link")).unwrap();
    for i in 0..10 {
        std::fs::write(src.join(format!("f{i}.bin")), "x".repeat(64)).unwrap();
    }
    // A whole successful copy, manifested with no failure hook to strand it.

    let partial = d.join("clone");
    let flag = AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let mut p = Progress {
        cancel: &flag,
        on_bytes: &mut sink,
        tree: None,
        partial: None,
        manifest: copymanifest::writer_for(&src, &partial),
    };
    crate::backend::copyfile::copy_any(&src, &partial, &mut p).expect("the copy");
    let handle = p.manifest.take().map(|writer| writer.finish().expect("no I/O")).unwrap_or(None).expect("manifest");
    drop(p);
    check_root(&d, &partial);
    assert!(partial.join("link").symlink_metadata().unwrap().file_type().is_symlink());
    let step = copied_partial(&src, &partial, ItemIdentity::inspect(&src).unwrap(), Some(handle)).unwrap();
    let mut j = journal("copy", vec![step]);
    assert_eq!(j.undo().expect("undo"), "copy");
    assert!(!partial.exists(), "the link went with the tree");
    assert_eq!(std::fs::read_to_string(&target).unwrap(), "do not follow me", "its target stands");
}

#[test]
fn a_successful_copy_journals_no_manifest() {
    let d = TestDir::new("undocopysuccess");
    let file = d.file("photo.jpg", "pixels");
    let (outcome, steps) = ops::duplicate(&file);
    assert!(outcome.is_ok());
    assert!(matches!(&steps[..], [Step::Copied { manifest: None, .. }]), "a success keeps today's step: {:?}", steps);
    let src = d.dir("tree");
    std::fs::write(src.join("inside.txt"), "body").unwrap();
    let (outcome, steps) = ops::duplicate(&src);
    assert!(outcome.is_ok());
    assert!(matches!(&steps[..], [Step::Copied { manifest: None, .. }]), "a successful tree too: {:?}", steps);
}

fn walk_bins(root: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();
    let mut dirs = vec![root.to_path_buf()];
    while let Some(dir) = dirs.pop() {
        for entry in std::fs::read_dir(&dir).unwrap().flatten() {
            let p = entry.path();
            if p.is_dir() && !p.symlink_metadata().unwrap().file_type().is_symlink() {
                dirs.push(p);
            } else if p.extension().and_then(|e| e.to_str()) == Some("bin") {
                found.push(p);
            }
        }
    }
    found
}

#[test]
fn a_failed_copy_holds_no_descriptor_on_the_destination_filesystem() {
    let d = TestDir::new("undofdnodest");
    let src = flat_source(&d, "source");
    let partial = d.join("clone");
    let handle = partial_with_manifest(&src, &partial, &mut fail_after_three);
    check_root(&d, &partial);
    let fd = handle.fd_raw();
    let target = std::fs::read_link(format!("/proc/self/fd/{fd}")).expect("manifest fd target");
    let dest = partial.to_string_lossy().to_string();
    assert!(!target.to_string_lossy().starts_with(d.path().to_string_lossy().as_ref()), "manifest fd {fd} targets {target:?}, dest {dest}");
    let fd_dev = std::fs::metadata(format!("/proc/self/fd/{fd}")).expect("manifest fd stat").dev();
    let dest_dev = std::fs::metadata(d.path()).expect("dest stat").dev();
    assert_ne!(fd_dev, dest_dev, "manifest lives off the destination filesystem");
    drop(handle);
}
