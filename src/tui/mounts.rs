// Issue 133, the TUI's half of ui/js/Mounts.js "trashable": what a folder's path says about its Trash.
use std::path::Path;

// The status line's refusal: what failed, then the key that still removes the rows.
pub const NO_TRASH: &str = "This location has no Trash; Shift+Delete deletes permanently";

// No GVFS backend implements trash, so gio trash refuses every path under its FUSE folder.
// Sample input: /run/user/1000/gvfs/smb-share:server=192.168.21.25,share=data/photos, where "smb-share:" names the mount.
pub fn trashable(path: &Path) -> bool {
    let mut after_gvfs = false;
    for part in path.components() {
        let name = part.as_os_str().to_string_lossy();
        if after_gvfs && names_a_mount(&name) {
            return false;
        }
        after_gvfs = name.eq_ignore_ascii_case("gvfs");
    }
    true
}

// Sample input: "mtp:host=SAMSUNG_Android", a type of letters, digits and hyphens before the first colon.
fn names_a_mount(name: &str) -> bool {
    match name.find(':') {
        Some(end) if end > 0 => name[..end].chars().all(|c| c.is_ascii_alphanumeric() || c == '-'),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::trashable;
    use std::path::Path;

    #[test]
    fn every_gvfs_mount_refuses_and_every_ordinary_folder_keeps_its_trash() {
        for refused in [
            "/run/user/1000/gvfs/smb-share:server=192.168.21.25,share=data",
            "/run/user/1000/gvfs/sftp:host=box,user=gm/home/gm",
            "/run/user/1000/gvfs/mtp:host=SAMSUNG_RQGL705T0NR/DCIM",
            "/run/user/1000/gvfs/gphoto2:host=usb%3A001%2C014/store",
            "/run/user/1000/gvfs/afc:host=00008130-001641411883401C/DCIM",
            "/run/user/1000/GVFS/dav:host=slot,ssl=true/notes",
        ] {
            assert!(!trashable(Path::new(refused)), "{refused} has no Trash");
        }
        for kept in ["/home/gm/Downloads", "/home/gm/src/gvfs/daemon", "/run/user/1000/gvfs", "/"] {
            assert!(trashable(Path::new(kept)), "{kept} keeps its Trash");
        }
    }
}
