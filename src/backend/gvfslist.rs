// A gvfs FUSE directory lists through one gio child instead of readdir plus per-row
// stats. The daemon answers names with size, type and mtime in one pass, where the FUSE
// path would block in getdents64 and then pay one round trip per row.
use crate::backend::extclass;
use crate::backend::listing::{CachedMeta, Listing};
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::time::{Duration, Instant};

// Sample input: gio list -u -a standard::type,standard::size,time::modified,standard::symlink-target --nofollow-symlinks <path>
const GIO_ATTRS: &str = "standard::type,standard::size,time::modified,standard::symlink-target";
// A 10k NAS folder answers in about 1.1 s; 15 s bounds a hung daemon without cutting one off.
pub const GIO_TIMEOUT: Duration = Duration::from_secs(15);
// Modes matching what the smb FUSE stat reports, so icons and rows agree with the stat path.
const MODE_FILE: u32 = 0o100700;
const MODE_DIR: u32 = 0o40700;
const MODE_LINK: u32 = 0o120777;

pub struct GvfsRow {
    pub name: String,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub size: u64,
    pub mtime: i64,
    pub target: String,
}

// One prefix check, so local and USB paths take exactly today's code past it.
pub fn is_gvfs(path: &Path) -> bool {
    if extclass::gvfs_class(path).is_some() {
        return true;
    }
    // extclass recognises /run/user/*/gvfs; a session with XDG_RUNTIME_DIR elsewhere keeps the same root.
    match std::env::var("XDG_RUNTIME_DIR").ok().filter(|v| !v.is_empty()) {
        Some(root) => path.to_string_lossy().starts_with(&format!("{}/gvfs/", root)),
        None => false,
    }
}

// The test seam for the gio binary: FLEA_GIO_BIN names a fake in tests, "gio" otherwise.
pub fn gio_bin() -> String {
    std::env::var("FLEA_GIO_BIN").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| "gio".to_string())
}

pub fn mode_for(is_dir: bool, is_symlink: bool) -> u32 {
    if is_dir {
        MODE_DIR
    } else if is_symlink {
        MODE_LINK
    } else {
        MODE_FILE
    }
}

// Sample input: "sp%20ace.txt" answers "sp ace.txt"; "%FF" answers lossy rather than failing.
pub fn percent_decode(segment: &str) -> String {
    let bytes = segment.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hi = (bytes[i + 1] as char).to_digit(16);
            let lo = (bytes[i + 2] as char).to_digit(16);
            match (hi, lo) {
                (Some(h), Some(l)) => {
                    out.push((h * 16 + l) as u8);
                    i += 3;
                    continue;
                }
                _ => {}
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

// Sample input: "tab\\x5ctname" answers "tab\\tname"; a plain "sp ace" passes through.
fn unescape_target(raw: &str) -> String {
    let bytes = raw.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\' && i + 3 < bytes.len() && bytes[i + 1] == b'x' {
            let hi = (bytes[i + 2] as char).to_digit(16);
            let lo = (bytes[i + 3] as char).to_digit(16);
            match (hi, lo) {
                (Some(h), Some(l)) => {
                    out.push((h * 16 + l) as u8);
                    i += 4;
                    continue;
                }
                _ => {}
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

// Sample input: "smb://192.168.21.25/isos/flea-b036-nas-1790537810/fix-10k/file-00001.txt\t10\t(regular)\ttime::modified=1790537811"
pub fn parse_line(line: &str, hidden: bool) -> Result<Option<GvfsRow>, String> {
    let mut parts = line.splitn(4, '\t');
    let uri = parts.next().ok_or_else(|| "gio line has no uri".to_string())?;
    let size_str = parts.next().ok_or_else(|| format!("gio line has no size: {}", line))?;
    let type_str = parts.next().ok_or_else(|| format!("gio line has no type: {}", line))?;
    let attrs = parts.next().ok_or_else(|| format!("gio line has no attrs: {}", line))?;
    // The URI is encoded, so a tab or newline in a name cannot split this line; decode only the last segment.
    let slash = uri.rfind('/').ok_or_else(|| format!("gio uri has no slash: {}", uri))?;
    let mut segment = &uri[slash + 1..];
    // A directory URI never carries a trailing slash here, but a stray one must not name an empty row.
    while segment.ends_with('/') && !segment.is_empty() {
        segment = &segment[..segment.len() - 1];
    }
    if segment.is_empty() {
        return Err(format!("gio uri names nothing: {}", uri));
    }
    let name = percent_decode(segment);
    if name.is_empty() {
        return Err(format!("gio uri decodes to nothing: {}", uri));
    }
    // corner: a dot-prefixed name is dropped before any stat, the same rule scan.rs applies.
    if !hidden && name.starts_with('.') {
        return Ok(None);
    }
    let size: u64 = size_str.parse().map_err(|_| format!("gio size is not a number: {}", size_str))?;
    let (is_dir, is_symlink) = match type_str {
        "(directory)" => (true, false),
        "(symlink)" => (false, true),
        "(regular)" | "(special)" | "(shortcut)" | "(mountable)" | "(unknown)" => (false, false),
        _ => return Err(format!("gio type is not known: {}", type_str)),
    };
    let mtime_key = "time::modified=";
    let mtime_at = attrs.find(mtime_key).ok_or_else(|| format!("gio attrs name no mtime: {}", attrs))?;
    let mtime_rest = &attrs[mtime_at + mtime_key.len()..];
    let mtime_end = mtime_rest.find(' ').map(|at| at).unwrap_or(mtime_rest.len());
    let mtime: i64 =
        mtime_rest[..mtime_end].parse().map_err(|_| format!("gio mtime is not a number: {}", mtime_rest))?;
    let mut target = String::new();
    if is_symlink {
        let target_key = "standard::symlink-target=";
        if let Some(at) = attrs.find(target_key) {
            let rest = &attrs[at + target_key.len()..];
            // The target may hold spaces, so it runs until the mtime key or the end, never to the next space.
            let end = rest.find(" time::").unwrap_or(rest.len());
            target = unescape_target(&rest[..end]);
        }
    }
    Ok(Some(GvfsRow { name, is_dir, is_symlink, size, mtime, target }))
}

// One gio child per listing; any failure falls back to readdir and says nothing to the user.
pub fn list_via_gio(path: &str, hidden: bool, gio: &str, timeout: Duration) -> Result<(Listing, f64), String> {
    list_via_gio_at(path, hidden, gio, timeout, Instant::now())
}

fn list_via_gio_at(path: &str, hidden: bool, gio: &str, timeout: Duration, t: Instant) -> Result<(Listing, f64), String> {
    let mut argv = vec!["list".to_string(), "-u".to_string(), "-a".to_string(), GIO_ATTRS.to_string(), "--nofollow-symlinks".to_string()];
    if hidden {
        argv.push("-h".to_string());
    }
    argv.push(path.to_string());
    let mut child = std::process::Command::new(gio)
        .args(&argv)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| format!("gio did not start: {}", e))?;
    // The reader drains stdout beside the wait, so a 10k-row listing cannot block on a full pipe.
    let stdout = child.stdout.take();
    let reader = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        if let Some(mut out) = stdout {
            use std::io::Read;
            let _ = out.read_to_end(&mut bytes);
        }
        bytes
    });
    let deadline = Instant::now() + timeout;
    let status = loop {
        match child.try_wait().map_err(|e| format!("gio wait failed: {}", e))? {
            Some(status) => break status,
            // A hung daemon must not strand the listing: kill on the deadline and reap, never leave a zombie.
            None if Instant::now() >= deadline => {
                let _ = child.kill();
                let _ = child.wait();
                return Err("gio list timed out".to_string());
            }
            None => std::thread::sleep(Duration::from_millis(20)),
        }
    };
    if !status.success() {
        return Err(format!("gio list exited {}", status));
    }
    let bytes = reader.join().map_err(|_| "gio reader failed".to_string())?;
    let text = String::from_utf8(bytes).map_err(|_| "gio output is not UTF-8".to_string())?;
    let base_dev: u64 = std::fs::metadata(path).map(|m| m.dev()).unwrap_or(0);
    let mut l = Listing::new();
    for line in text.lines() {
        if line.is_empty() {
            continue;
        }
        match parse_line(line, hidden)? {
            None => {}
            Some(row) => {
                let mode = mode_for(row.is_dir, row.is_symlink);
                let index = l.len();
                l.push(&row.name, row.is_dir);
                l.spans[index].is_symlink = row.is_symlink;
                l.meta_cache.insert(row.name.clone(), CachedMeta { size: row.size, mtime: row.mtime, mode, target: row.target, dev: base_dev });
            }
        }
    }
    Ok((l, t.elapsed().as_secs_f64() * 1000.0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;
    use std::os::unix::fs::PermissionsExt;

    const NAS: &str = "smb://192.168.21.25/isos/flea-b036-nas-1790537810/fix-10k";

    #[test]
    fn a_regular_row_parses_with_size_and_mtime() {
        let row = parse_line(&format!("{}/file-00001.txt\t10\t(regular)\ttime::modified=1790537811", NAS), false)
            .unwrap().expect("regular row");
        assert_eq!(row.name, "file-00001.txt");
        assert_eq!((row.size, row.mtime), (10, 1790537811));
        assert!(!row.is_dir && !row.is_symlink);
        assert!(row.target.is_empty());
        assert_eq!(mode_for(row.is_dir, row.is_symlink), 0o100700);
    }

    #[test]
    fn a_directory_row_parses_with_its_mode() {
        let row = parse_line(&format!("{}/sub\t4096\t(directory)\ttime::modified=1790537811", NAS), false)
            .unwrap().expect("directory row");
        assert_eq!(row.name, "sub");
        assert!(row.is_dir);
        assert_eq!(mode_for(row.is_dir, row.is_symlink), 0o40700);
    }

    #[test]
    fn a_symlink_row_carries_its_target() {
        let row = parse_line(&format!("{}/link1\t5\t(symlink)\tstandard::is-symlink=TRUE standard::symlink-target=a.txt time::modified=1790537811", NAS), false)
            .unwrap().expect("symlink row");
        assert_eq!((row.name.as_str(), row.target.as_str()), ("link1", "a.txt"));
        assert!(row.is_symlink && !row.is_dir);
        assert_eq!(mode_for(row.is_dir, row.is_symlink), 0o120777);
    }

    #[test]
    fn a_percent_encoded_space_decodes_and_a_tab_round_trips() {
        let row = parse_line(&format!("{}/sp%20ace.txt\t0\t(regular)\ttime::modified=1", NAS), false)
            .unwrap().expect("space row");
        assert_eq!(row.name, "sp ace.txt");
        let row = parse_line(&format!("{}/tab%09name.txt\t1\t(regular)\ttime::modified=1", NAS), false)
            .unwrap().expect("tab row");
        assert_eq!(row.name, "tab\tname.txt");
        let row = parse_line(&format!("{}/new%0Aline.txt\t1\t(regular)\ttime::modified=1", NAS), false)
            .unwrap().expect("newline row");
        assert_eq!(row.name, "new\nline.txt");
    }

    #[test]
    fn a_non_utf8_escape_is_lossy_rather_than_a_failure() {
        let row = parse_line(&format!("{}/bad-%FF-name\t0\t(regular)\ttime::modified=1", NAS), false)
            .unwrap().expect("non-utf8 row");
        assert!(row.name.contains('\u{FFFD}'), "expected a replacement char, got {:?}", row.name);
    }

    #[test]
    fn a_hidden_name_is_dropped_unless_hidden_is_true() {
        let line = format!("{}/.hidden\t0\t(regular)\ttime::modified=1", NAS);
        assert!(parse_line(&line, false).unwrap().is_none());
        assert_eq!(parse_line(&line, true).unwrap().expect("hidden kept").name, ".hidden");
    }

    #[test]
    fn garbage_is_a_parse_error_that_falls_back() {
        for line in ["", "garbage", "a\tb", "smb://h/f\t10\t(regular)", "smb://h/f\tnotnum\t(regular)\ttime::modified=1", "smb://h/f\t1\t(bogus)\ttime::modified=1", "smb://h/f\t1\t(regular)\tno-mtime-here"] {
            assert!(parse_line(line, false).is_err(), "expected an error for {:?}", line);
        }
    }

    fn fake_gio(dir: &TestDir, name: &str, body: &str) -> String {
        let p = dir.join(name);
        std::fs::write(&p, body).unwrap();
        std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
        p.to_string_lossy().into_owned()
    }

    #[test]
    fn a_gio_that_exits_1_falls_back() {
        let d = TestDir::new("gvfs-exit1");
        let fake = fake_gio(&d, "gio", "#!/bin/sh\nexit 1\n");
        let e = list_via_gio("/run/user/1000/gvfs/smb-share:server=x,share=y/dir", false, &fake, Duration::from_secs(5)).unwrap_err();
        assert!(e.contains("exited"), "expected an exit failure, got {}", e);
    }

    #[test]
    fn a_gio_that_hangs_past_the_deadline_falls_back() {
        let d = TestDir::new("gvfs-hang");
        let fake = fake_gio(&d, "gio", "#!/bin/sh\nsleep 30\n");
        let t = Instant::now();
        let e = list_via_gio("/run/user/1000/gvfs/smb-share:server=x,share=y/dir", false, &fake, Duration::from_millis(200)).unwrap_err();
        assert!(e.contains("timed out"), "expected a timeout, got {}", e);
        assert!(t.elapsed() < Duration::from_secs(10), "the deadline must fire, not the sleep");
    }

    #[test]
    fn a_gio_that_prints_garbage_falls_back() {
        let d = TestDir::new("gvfs-garbage");
        let fake = fake_gio(&d, "gio", "#!/bin/sh\necho 'this is not a gio line'\n");
        let e = list_via_gio("/run/user/1000/gvfs/smb-share:server=x,share=y/dir", false, &fake, Duration::from_secs(5)).unwrap_err();
        assert!(!e.is_empty(), "garbage must be a parse error");
    }

    #[test]
    fn a_successful_gio_run_builds_the_listing_and_its_cache() {
        let d = TestDir::new("gvfs-success");
        let fake = fake_gio(&d, "gio", "#!/bin/sh\nprintf '%s\\n' 'smb://h/share/a.txt\t3\t(regular)\ttime::modified=100' 'smb://h/share/sub\t4096\t(directory)\ttime::modified=200' 'smb://h/share/l\t1\t(symlink)\tstandard::is-symlink=TRUE standard::symlink-target=a.txt time::modified=300'\n");
        let (l, _) = list_via_gio(d.path().to_str().unwrap(), false, &fake, Duration::from_secs(5)).unwrap();
        assert_eq!(l.len(), 3);
        assert_eq!((l.name(0), l.name(1), l.name(2)), ("a.txt", "sub", "l"));
        assert!(l.is_dir(1) && !l.is_dir(0) && !l.is_dir(2));
        assert!(l.spans[2].is_symlink, "the symlink bit rides in the span like the readdir path");
        let cached = l.meta_cache.get("l").expect("every row is cached by name");
        assert_eq!((cached.size, cached.mtime, cached.mode), (1, 300, 0o120777));
        assert_eq!(cached.target, "a.txt");
        assert_eq!(l.meta_cache.get("a.txt").expect("file cached").size, 3);
    }

    #[test]
    fn only_a_gvfs_path_takes_the_gio_branch() {
        assert!(is_gvfs(Path::new("/run/user/1000/gvfs/smb-share:server=192.168.21.25,share=isos/dir")));
        assert!(!is_gvfs(Path::new("/home/gm")));
        assert!(!is_gvfs(Path::new("/run/user/1000/doc/x")));
    }
}
