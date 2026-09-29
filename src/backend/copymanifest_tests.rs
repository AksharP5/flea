use super::*;
use crate::backend::testdir::TestDir;

fn recorded(d: &TestDir, names: &[&str]) -> Handle {
    let root = d.dir("root");
    let mut writer = Writer::create(&root).expect("anonymous manifest");
    // The root first, the way copy_dir_at records its own creation before any child.
    writer.record(&root, &root.symlink_metadata().unwrap());
    for name in names {
        let p = root.join(name);
        if name.ends_with('/') {
            std::fs::create_dir_all(&p).unwrap();
        } else {
            if let Some(parent) = p.parent() {
                std::fs::create_dir_all(parent).unwrap();
            }
            std::fs::write(&p, format!("body of {name}")).unwrap();
        }
        writer.record(&p, &p.symlink_metadata().unwrap());
    }
    writer.finish().expect("no I/O").expect("records went")
}

#[test]
fn records_encode_and_decode_with_their_identity() {
    let d = TestDir::new("manifestroundtrip");
    let p = d.file("a.bin", "body");
    // Non-UTF8 names ride as bytes, never through a lossy string.
    use std::os::unix::ffi::OsStrExt;
    let raw = d.path().join(std::ffi::OsStr::from_bytes(b"raw-\xff.bin"));
    std::fs::write(&raw, "raw").unwrap();
    for path in [&p, &raw] {
        let meta = std::fs::symlink_metadata(path).unwrap();
        let bytes = encode(&meta, path.as_os_str().as_bytes());
        let back = decode(&bytes).expect("decodes");
        assert_eq!((back.dev, back.ino, back.kind), (meta.dev(), meta.ino(), meta.mode() & 0o170000));
        assert_eq!((back.len, back.mtime), (meta.len(), (meta.mtime(), meta.mtime_nsec())));
        assert_eq!(back.rel, PathBuf::from(path.as_os_str()));
    }
    assert!(decode(&[0u8; 10]).is_none(), "a short frame is not a record");
}

#[test]
fn containment_never_leaves_the_root() {
    let root = Path::new("/scratch/tmp/flea-test-x/root");
    assert!(contained(root, Path::new("")).is_some(), "the empty rel is the root itself");
    assert!(contained(root, Path::new("a/b.bin")).is_some());
    assert!(contained(root, Path::new("/abs")).is_none(), "absolute smuggles nothing in");
    assert!(contained(root, Path::new("../out")).is_none(), "parent climbs nothing out");
    assert!(contained(root, Path::new("a/../../out")).is_none(), "interior climbs nothing out");
}

#[test]
fn a_garbage_stream_falls_back_with_the_tree_untouched() {
    let d = TestDir::new("manifestgarbage");
    let root = d.dir("root");
    std::fs::write(root.join("own.bin"), "own").unwrap();
    let mut inner = Manifest::new(d.path()).expect("anonymous manifest");
    inner.append(b"framing without a record inside").unwrap();
    let handle = Handle { records: inner.records(), root: root.clone(), count: 1 };
    assert!(matches!(remove_owned(&handle), Outcome::Fallback), "nothing verified, so today decides");
    assert!(root.join("own.bin").exists(), "and the fallback deleted nothing itself");
}

#[test]
fn a_replaced_root_deletes_nothing() {
    let d = TestDir::new("manifestreplaced");
    let handle = recorded(&d, &["a.bin", "sub/b.bin"]);
    let root = handle.root.clone();
    // Same name, another inode: every record mismatches, starting with the root.
    std::fs::remove_dir_all(&root).unwrap();
    std::fs::create_dir(&root).unwrap();
    std::fs::write(root.join("squatter.txt"), "not ours").unwrap();
    let report = match remove_owned(&handle) {
        Outcome::Done(report) => report,
        Outcome::Fallback => panic!("the stream is intact, so the manifest decides"),
    };
    assert!(!report.kept.is_empty(), "the root no longer matches its record");
    assert!(root.join("squatter.txt").exists(), "a stranger's file stands");
    assert_eq!(report.removed, 0, "nothing verified, nothing removed");
}

#[test]
fn an_overflowed_writer_finishes_without_a_manifest() {
    let d = TestDir::new("manifestoverflow");
    let root = d.dir("root");
    let mut writer = Writer::create(&root).expect("anonymous manifest");
    writer.overflow();
    assert!(writer.finish().expect("no I/O").is_none(), "an unfinished record journals today's step instead");
    let writer = Writer::create(&root).expect("anonymous manifest");
    assert!(writer.finish().expect("no I/O").is_none(), "and so does a copy that recorded nothing");
}

#[test]
fn a_directory_move_always_opens_a_manifest() {
    let d = TestDir::new("manifestskipmove");
    let src = d.dir("src");
    let dst = d.join("dst");
    assert!(writer_for_move(&src, &dst).is_some(), "even a same-device rename is manifested, since EXDEV through a symlinked parent defeats a device check");
    assert!(writer_for(&src, &dst).is_some(), "copy still records");
}

#[test]
fn two_thousand_records_stream_there_and_back() {
    let d = TestDir::new("manifeststream");
    let root = d.dir("root");
    let mut writer = Writer::create(&root).expect("anonymous manifest");
    writer.record(&root, &root.symlink_metadata().unwrap());
    for i in 0..2000 {
        let p = root.join(format!("f{i:05}.bin"));
        std::fs::write(&p, "x").unwrap();
        writer.record(&p, &p.symlink_metadata().unwrap());
    }
    let handle = writer.finish().expect("no I/O").expect("bounded well under the cap");
    assert_eq!(handle.count, 2001);
    let report = match remove_owned(&handle) {
        Outcome::Done(report) => report,
        Outcome::Fallback => panic!("an intact stream never falls back"),
    };
    assert!(report.kept.is_empty(), "every recorded path verified: {:?}", report.kept.first().map(|k| &k.path));
    assert_eq!(report.removed, 2001, "two thousand files and the root that held them");
    assert!(!root.exists(), "deepest first ends with the root itself");
}

#[test]
fn framed_bytes_never_pass_the_cap() {
    let d = TestDir::new("manifestcap");
    let root = d.dir("root");
    let meta = d.file("probe.bin", "x").symlink_metadata().unwrap();
    // 168-byte names frame to 228 B: 147,168 reach 33,554,304, one 68-byte name lands exactly on the 32 MiB cap, and the next record overflows.
    let mut writer = Writer::create(&root).expect("anonymous manifest");
    for i in 0..147168 {
        writer.record(&root.join(format!("f{i:0163}.bin")), &meta);
    }
    assert!(!writer.overflow, "the cap-fitting records all went");
    writer.record(&root.join("x".repeat(68)), &meta);
    assert!(!writer.overflow, "landing exactly on the cap is allowed");
    assert_eq!(writer.inner.len() + writer.buf.len() as u64 + writer.ends.len() as u64 * FRAMING, MAX_BYTES);
    assert!(!writer.ends.is_empty(), "records are still buffered, so buffered framing is in play");
    writer.record(&root.join("one-more"), &meta);
    assert!(writer.overflow, "one record past the cap overflows");
    assert!(writer.finish().expect("no I/O").is_none(), "an overfull manifest journals today's step instead");
}

// A tree copy records every path it creates exactly once, so undo walks the same set the copy made.
#[test]
fn a_tree_copy_records_each_file_once_and_each_directory_once() {
    use crate::backend::copyfile::{copy_any, Progress};
    use std::sync::atomic::AtomicBool;
    let d = TestDir::new("manifesttreecount");
    let src = d.dir("tree");
    std::fs::write(src.join("a.bin"), "a").unwrap();
    std::fs::write(src.join("b.bin"), "b").unwrap();
    std::fs::create_dir(src.join("sub")).unwrap();
    std::fs::write(src.join("sub/c.bin"), "c").unwrap();
    std::os::unix::fs::symlink("a.bin", src.join("link")).unwrap();
    let dst = d.join("clone");
    let flag = AtomicBool::new(false);
    let mut sink = |_: u64, _: u64| {};
    let writer = Writer::create(&dst).expect("anonymous manifest");
    let mut p = Progress { cancel: &flag, on_bytes: &mut sink, tree: None, partial: None, manifest: Some(writer), durability: None };
    copy_any(&src, &dst, &mut p).expect("copy");
    let writer = p.manifest.take().expect("the writer back");
    let handle = writer.finish().expect("no I/O").expect("records went");
    // Three files, one symlink and two directories: the root and its one subdirectory.
    assert_eq!(handle.count, 6, "each created path is recorded exactly once");
    assert_eq!(std::fs::read_to_string(dst.join("sub/c.bin")).unwrap(), "c");
}

#[test]
fn a_directory_filled_after_the_copy_is_kept_with_its_reason() {
    let d = TestDir::new("manifestfilled");
    let handle = recorded(&d, &["sub/"]);
    let root = handle.root.clone();
    let filled = root.join("sub");
    std::fs::write(filled.join("stray.txt"), "someone else put this here").unwrap();
    assert_eq!(std::fs::remove_dir(&filled).unwrap_err().raw_os_error(), Some(39), "a filled remove_dir is ENOTEMPTY on this kernel");
    let report = match remove_owned(&handle) {
        Outcome::Done(report) => report,
        Outcome::Fallback => panic!("the stream is intact, so the manifest decides"),
    };
    assert_eq!(report.removed, 0, "nothing leaves while a stranger's file stands");
    assert!(report.kept.iter().any(|k| k.reason == "is not empty"), "the filled directory is kept: {:?}", report.kept.first().map(|k| &k.path));
    assert!(filled.join("stray.txt").exists(), "a stranger's file stands");
}
