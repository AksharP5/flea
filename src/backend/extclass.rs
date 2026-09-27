// The directory's own class for the thumbnail gate: network, phone, usb or local ("").
// Computed once per directory change beside the fsinfo line, never per row.
use super::mountinfo::MountEntry;
use std::path::{Path, PathBuf};

// statfs magics that name a network filesystem even when the mount table spells it "fuse".
const NETWORK_MAGICS: [i64; 5] = [0x6969, 0xFF534D42, 0xFE534D42, 0x01021997, 0x00C36400];

// Sample input: 0xFE534D42 trues, 0xEF53 falses.
pub fn magic_is_network(magic: i64) -> bool {
    NETWORK_MAGICS.contains(&magic)
}

// Sample input: "fuse.sshfs" trues, "ext4" falses, "NFS4" trues.
pub fn fstype_is_network(fstype: &str) -> bool {
    let lower = fstype.to_ascii_lowercase();
    lower == "cifs"
        || lower.starts_with("nfs")
        || lower.contains("sshfs")
        || lower.contains("rclone")
        || lower == "9p"
        || lower.contains("ceph")
}

// Sample input: "/run/user/1000/gvfs/mtp:host=X/" answers Some("phone").
pub fn gvfs_class(path: &Path) -> Option<&'static str> {
    if !path.to_string_lossy().starts_with("/run/user/") {
        return None;
    }
    let text = path.to_string_lossy().into_owned();
    let mark = text.find("/gvfs/")?;
    let rest = text[mark + "/gvfs/".len()..].to_ascii_lowercase();
    if rest.starts_with("mtp:") || rest.starts_with("gphoto2:") || rest.starts_with("afc:") {
        Some("phone")
    } else {
        Some("network")
    }
}

// Sample input: "/run/user/1000/gvfs/smb-share:server=n,share=x/dir" answers "/run/user/1000/gvfs/smb-share:server=n,share=x".
pub fn gvfs_root(path: &Path) -> Option<PathBuf> {
    gvfs_class(path)?;
    let mut root = PathBuf::new();
    let mut after_gvfs = false;
    for part in path.components() {
        root.push(part);
        if after_gvfs {
            return Some(root);
        }
        after_gvfs = part.as_os_str() == "gvfs";
    }
    None
}

// Sample sysfs target: "../../devices/pci0000:00/0000:00:14.0/usb2/2-1/host0/block/sdb/sdb1" trues.
pub fn link_is_usb(target: &str) -> bool {
    target.split('/').any(|seg| seg == "usb" || usb_bus(seg))
}

// A bus segment is "usb" plus its number, so a block device literally named "usbstick" never matches.
fn usb_bus(seg: &str) -> bool {
    seg.len() > 3 && seg.starts_with("usb") && seg.as_bytes()[3..].iter().all(|b| b.is_ascii_digit())
}

// Sample: removable "1\n" trues with no link at all.
pub fn is_usb(link_target: Option<&str>, removable: Option<&str>) -> bool {
    if removable.is_some_and(|v| v.trim() == "1") {
        return true;
    }
    link_target.is_some_and(link_is_usb)
}

// Sample target: "../../devices/pci/host0/block/sdb/sdb1" answers Some("sdb").
fn disk_of_link(target: &str) -> Option<&str> {
    let parts: Vec<&str> = target.split('/').collect();
    let disk = parts.iter().position(|seg| *seg == "block").and_then(|at| parts.get(at + 1))?;
    if disk.is_empty() || *disk == "." || *disk == ".." {
        return None;
    }
    Some(disk)
}

// Sample: (None, Some(0xFF534D42), false) answers "network"; (Some("ext4"), Some(0xEF53), false) answers "".
pub fn classify_parts(path: &Path, fstype: Option<&str>, magic: Option<i64>, usb: bool) -> &'static str {
    if let Some(class) = gvfs_class(path) {
        return class;
    }
    if fstype.is_some_and(fstype_is_network) {
        return "network";
    }
    if magic.is_some_and(magic_is_network) {
        return "network";
    }
    if usb {
        return "usb";
    }
    ""
}

// One statfs, one mountinfo read and two sysfs reads at most, once per directory change.
pub fn classify(path: &Path) -> &'static str {
    if let Some(class) = gvfs_class(path) {
        return class;
    }
    let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    classify_entry(path, super::mountinfo::mount_entry_in(path, &body).as_ref())
}

// The class from a mount entry the caller already read, so fsinfo pays one mountinfo read.
pub fn classify_entry(path: &Path, entry: Option<&MountEntry>) -> &'static str {
    let usb = usb_for(entry.map(|e| e.majmin.as_str()));
    classify_parts(path, entry.map(|e| e.fstype.as_str()), super::fsinfo::magic_of(path), usb)
}

// A mount that names no block device answers false without touching sysfs.
fn usb_for(majmin: Option<&str>) -> bool {
    let majmin = match majmin {
        Some(m) if !m.is_empty() && m.bytes().all(|b| b.is_ascii_digit() || b == b':') => m,
        _ => return false,
    };
    let target =
        std::fs::read_link(Path::new("/sys/dev/block").join(majmin)).map(|p| p.to_string_lossy().into_owned()).ok();
    let removable = target
        .as_deref()
        .and_then(disk_of_link)
        .and_then(|disk| std::fs::read_to_string(Path::new("/sys/block").join(disk).join("removable")).ok());
    is_usb(target.as_deref(), removable.as_deref())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn network_magics_are_the_five_this_tree_mounts() {
        for magic in [0x6969, 0xFF534D42, 0xFE534D42, 0x01021997, 0x00C36400] {
            assert!(magic_is_network(magic), "0x{:x} is a network filesystem", magic);
        }
        for magic in [0xEF53, 0x9123683E, 0x2011BAB0, 0x01021994, 0x65735546] {
            assert!(!magic_is_network(magic), "0x{:x} is local or decided elsewhere", magic);
        }
    }

    #[test]
    fn fuse_subtypes_name_their_network() {
        for fstype in ["cifs", "nfs", "nfs4", "NFS", "fuse.sshfs", "sshfs", "fuse.rclone", "9p", "ceph"] {
            assert!(fstype_is_network(fstype), "{} reaches the network class", fstype);
        }
        for fstype in ["ext4", "btrfs", "xfs", "vfat", "exfat", "ntfs", "tmpfs", "overlay", "fuse.gvfsd-fuse", ""] {
            assert!(!fstype_is_network(fstype), "{} stays out of the network class", fstype);
        }
    }

    #[test]
    fn a_gvfs_phone_scheme_is_a_phone_and_any_other_gvfs_path_is_network() {
        for path in [
            "/run/user/1000/gvfs/mtp:host=SAMSUNG/DCIM",
            "/run/user/1000/gvfs/gphoto2:host=usb%3A001%2C014/store",
            "/run/user/1000/gvfs/afc:host=abc/Documents",
        ] {
            assert_eq!(gvfs_class(Path::new(path)), Some("phone"), "{} is a phone", path);
        }
        for path in [
            "/run/user/1000/gvfs/smb-share:server=nas,share=media",
            "/run/user/1000/gvfs/sftp:host=nas/home/tom",
            "/run/user/1000/gvfs/dav:host=slot,ssl=true/notes.txt",
            "/run/user/1000/gvfs/",
        ] {
            assert_eq!(gvfs_class(Path::new(path)), Some("network"), "{} is network", path);
        }
        for path in ["/home/gm", "/run/user/1000/doc/x", "/tmp/gvfs/mtp:host=X", "/run/user/1000/gvfs"] {
            assert_eq!(gvfs_class(Path::new(path)), None, "{} is not a gvfs share", path);
        }
    }

    #[test]
    fn the_decision_prefers_phone_then_network_then_usb_then_local() {
        assert_eq!(classify_parts(Path::new("/media/nas"), Some("cifs"), Some(0xFF534D42), false), "network");
        assert_eq!(classify_parts(Path::new("/media/nas"), None, Some(0xFE534D42), false), "network");
        assert_eq!(classify_parts(Path::new("/run/user/1000/gvfs/mtp:host=X"), Some("ext4"), Some(0xEF53), true), "phone");
        assert_eq!(classify_parts(Path::new("/run/user/1000/gvfs/smb-share:server=n"), None, None, false), "network");
        assert_eq!(classify_parts(Path::new("/media/stick"), Some("vfat"), Some(0x4D44), true), "usb");
        assert_eq!(classify_parts(Path::new("/home/gm"), Some("ext4"), Some(0xEF53), false), "");
        assert_eq!(classify_parts(Path::new("/home/gm"), None, None, false), "");
    }

    #[test]
    fn a_gvfs_root_is_the_share_directory_whatever_the_depth() {
        let share = Path::new("/run/user/1000/gvfs/smb-share:server=nas,share=media");
        assert_eq!(gvfs_root(&share.join("photos/2026")).as_deref(), Some(share));
        assert_eq!(gvfs_root(share).as_deref(), Some(share), "the share itself is its own root");
        assert_eq!(gvfs_root(Path::new("/run/user/1000/gvfs")), None, "the gvfs mount alone names no share");
        assert_eq!(gvfs_root(Path::new("/home/gm/gvfs/x")), None, "a local folder named gvfs is not a share");
    }

    #[test]
    fn only_a_usb_bus_segment_or_a_removable_disk_is_usb() {
        assert!(link_is_usb("../../devices/pci0000:00/0000:00:14.0/usb2/2-1/host0/block/sdb/sdb1"));
        assert!(link_is_usb("../../devices/usb/1-1/block/sda/sda1"));
        assert!(!link_is_usb("../../devices/pci0000:00/0000:00:1f.2/ata1/host0/block/sda/sda1"));
        assert!(!link_is_usb("../../devices/virtual/block/dm-0"));
        assert!(is_usb(None, Some("1\n")));
        assert!(is_usb(None, Some("1")));
        assert!(!is_usb(None, Some("0\n")));
        assert!(!is_usb(None, None));
        assert!(is_usb(Some("../../devices/usb/x/block/sdb/sdb1"), Some("0")));
    }

    #[test]
    fn the_disk_is_the_name_below_block() {
        assert_eq!(disk_of_link("../../devices/pci/host0/block/sdb/sdb1"), Some("sdb"));
        assert_eq!(disk_of_link("../../devices/pci/host0/block/nvme0n1/nvme0n1p2"), Some("nvme0n1"));
        assert_eq!(disk_of_link("../../devices/virtual/block/dm-0"), Some("dm-0"));
        assert_eq!(disk_of_link("/no/block/here"), Some("here"));
        assert_eq!(disk_of_link("plain/path"), None);
        assert_eq!(disk_of_link("../../devices/pci/block/"), None);
    }
}
