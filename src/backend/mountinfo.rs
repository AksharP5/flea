// The /proc/self/mountinfo parser: the filesystem type of the mount that owns a path, from a body the caller has read.
use std::ffi::OsString;
use std::os::unix::ffi::OsStringExt;
use std::path::{Path, PathBuf};

// Sample: `2 1 0:9 / /home/pi/My\040Drive rw - fuse.rclone remote: rw`; longest enclosing mount wins after octal unescaping.
pub(crate) fn mount_type_in(path: &Path, body: &str) -> Option<String> {
    mount_entry_in(path, body).map(|entry| entry.fstype)
}

// Sample dev: makedev(8,17) is 0x811 and answers "8:17"; the glibc major/minor packing, see sys/sysmacros.h.
fn dev_majmin(dev: u64) -> String {
    let major = ((dev >> 8) & 0xfff) | ((dev >> 32) & 0xffff_f000);
    let minor = (dev & 0xff) | ((dev >> 12) & 0xffff_ff00);
    format!("{major}:{minor}")
}

// Sample input: dev 0x811 against a line carrying "8:17 ... - vfat ..." answers Some("vfat").
pub(crate) fn fstype_for_dev(dev: u64, body: &str) -> Option<String> {
    let want = dev_majmin(dev);
    body.lines().filter_map(parse_line).find(|(_, _, majmin)| *majmin == want).map(|(_, fstype, _)| fstype)
}

// The mount that owns a path: its mount point, its filesystem type and its device numbers.
pub(crate) struct MountEntry {
    pub mount: PathBuf,
    pub fstype: String,
    pub majmin: String,
}

// Sample: the line above answers mount "/home/pi/My Drive", fstype "fuse.rclone" and majmin "0:9".
pub(crate) fn mount_entry_in(path: &Path, body: &str) -> Option<MountEntry> {
    let mut best: Option<(usize, MountEntry)> = None;
    for (mount, fstype, majmin) in body.lines().filter_map(parse_line) {
        if !path.starts_with(&mount) {
            continue;
        }
        let depth = mount.components().count();
        if best.as_ref().map(|(old, _)| depth >= *old).unwrap_or(true) {
            best = Some((depth, MountEntry { mount, fstype, majmin }));
        }
    }
    best.map(|(_, entry)| entry)
}

// Every mount point and its filesystem type, in file order, read once for a caller that asks about many paths.
pub(crate) fn mounts_in(body: &str) -> Vec<(PathBuf, String)> {
    body.lines().filter_map(parse_line).map(|(mount, fstype, _)| (mount, fstype)).collect()
}

// The deepest mount holding path, the later line winning a tie as the kernel's own stacking order does.
pub(crate) fn enclosing<'a>(path: &Path, mounts: &'a [(PathBuf, String)]) -> Option<&'a (PathBuf, String)> {
    let mut best: Option<(usize, &(PathBuf, String))> = None;
    for mount in mounts {
        if !path.starts_with(&mount.0) {
            continue;
        }
        let depth = mount.0.components().count();
        if best.map(|(old, _)| depth >= old).unwrap_or(true) {
            best = Some((depth, mount));
        }
    }
    best.map(|(_, mount)| mount)
}

// Sample line as above: mount point, fstype and major:minor, or None for a line with no "-" or too few fields.
fn parse_line(line: &str) -> Option<(PathBuf, String, String)> {
    let fields: Vec<&str> = line.split_whitespace().collect();
    let split = fields.iter().position(|field| *field == "-")?;
    if fields.len() <= split + 1 || fields.len() < 5 {
        return None;
    }
    Some((PathBuf::from(OsString::from_vec(unescape(fields[4]))), fields[split + 1].to_string(), fields[2].to_string()))
}

fn unescape(field: &str) -> Vec<u8> {
    let bytes = field.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match octal_byte(bytes, i) {
            Some(byte) => {
                out.push(byte);
                i += 4;
            }
            None => {
                out.push(bytes[i]);
                i += 1;
            }
        }
    }
    out
}

// Sample: `\040` is a space. Summed wide and refused above 255, because `\400` overflows a u8 mid-sum.
fn octal_byte(bytes: &[u8], i: usize) -> Option<u8> {
    if bytes[i] != b'\\' || i + 3 >= bytes.len() {
        return None;
    }
    let digits = &bytes[i + 1..=i + 3];
    if !digits.iter().all(|b| (b'0'..=b'7').contains(b)) {
        return None;
    }
    u8::try_from(digits.iter().fold(0u32, |value, b| value * 8 + u32::from(b - b'0'))).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deepest_mount_identifies_rclone_and_decodes_its_path() {
        let info = "1 0 8:1 / / rw - ext4 /dev/a rw\n\
                    2 1 0:9 / /home/pi/My\\040Drive rw - fuse.rclone remote: rw\n\
                    3 2 0:10 / /home/pi/My\\040Drive/nested rw - tmpfs tmpfs rw\n";
        assert_eq!(
            mount_type_in(Path::new("/home/pi/My Drive/file"), info).as_deref(),
            Some("fuse.rclone")
        );
        assert_eq!(
            mount_type_in(Path::new("/home/pi/My Drive/nested/file"), info).as_deref(),
            Some("tmpfs")
        );
        assert_eq!(
            mount_type_in(Path::new("/elsewhere"), info).as_deref(),
            Some("ext4")
        );
    }

    #[test]
    fn a_device_lookup_names_the_fstype_for_the_slow_pass_gate() {
        let info = "1 0 8:1 / / rw - ext4 /dev/a rw\n\
                    30 1 8:17 / /media/stick rw - vfat /dev/sdb1 rw\n\
                    31 1 0:45 / /media/nas rw - nfs nas:/share rw\n\
                    32 1 0:46 / /media/cloud rw - fuse.rclone remote: rw\n";
        // Sample dev numbers: makedev(8,17) is 0x811, makedev(0,45) is 45.
        assert_eq!(fstype_for_dev(0x811, info).as_deref(), Some("vfat"));
        assert_eq!(fstype_for_dev(45, info).as_deref(), Some("nfs"));
        assert_eq!(fstype_for_dev(46, info).as_deref(), Some("fuse.rclone"));
        assert_eq!(fstype_for_dev(0x812, info), None);
    }

    #[test]
    fn malformed_mountinfo_is_ignored() {
        assert_eq!(mount_type_in(Path::new("/home/pi"), "junk\n"), None);
    }

    #[test]
    fn the_entry_names_the_fstype_the_device_and_the_source() {
        let info = "1 0 8:1 / / rw - ext4 /dev/a rw\n\
                    30 1 8:17 / /media/stick rw - vfat /dev/sdb1 rw\n";
        let entry = mount_entry_in(Path::new("/media/stick/photo.jpg"), info).expect("the stick owns its files");
        assert_eq!(entry.fstype, "vfat");
        assert_eq!(entry.majmin, "8:17");
        let root = mount_entry_in(Path::new("/elsewhere"), info).expect("the root owns the rest");
        assert_eq!((root.fstype.as_str(), root.majmin.as_str()), ("ext4", "8:1"));
        assert!(mount_entry_in(Path::new("/home/pi"), "junk\n").is_none());
    }

    // The kernel escapes only \040, \011, \012 and \134, but this is a parser at a trust boundary.
    #[test]
    fn an_octal_escape_above_255_is_refused_rather_than_overflowing() {
        assert_eq!(unescape("\\040"), b" ".to_vec());
        assert_eq!(unescape("\\134"), b"\\".to_vec());
        assert_eq!(unescape("\\400"), b"\\400".to_vec());
        assert_eq!(unescape("\\777"), b"\\777".to_vec());
    }
}
