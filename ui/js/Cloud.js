.pragma library

// The NETWORK half's cloud rows: FUSE mounts inside the home folder (rclone, Proton Drive
// clients, other cloud mounts), read out of /proc/self/mountinfo on the rail's own five
// second poll, so no new process runs. Split out of ui/js/Mounts.js, which keeps gio's own
// mounts and the saved places; a kernel mount table and a gio listing share nothing but the
// rail they land in.

// Sample input, /proc/self/mountinfo lines (id parent maj:min root mountpoint options,
// then fstype source superoptions):
// 23 1 8:1 / /home/u/gdrive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000
// 24 1 8:1 / /home/u/My\040Drive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000
// 31 1 0:27 / /home/u/ProtonDrive rw,nosuid,nodev - fuse.protondrive proton: rw,user_id=1000
// 18 1 8:1 / /home/u rw,nosuid,nodev - btrfs /dev/sda1 rw
// 40 1 0:40 / /run/user/1000/gvfs rw,nosuid,nodev - fuse.gvfsd-fuse gvfsd-fuse rw,user_id=1000
// The first three name FUSE mounts inside the home folder and become rows; the home
// directory itself is not a cloud mount, and the gvfs FUSE mount is not inside home.
// A stacked mountpoint names one row: the later line wins, the way the kernel stacks it.
function parseCloudMounts(body, home) {
    var root = String(home || "")
    if (root.length === 0)
        return []
    var prefix = root.charAt(root.length - 1) === "/" ? root : root + "/"
    var out = []
    var at = {}
    var lines = String(body || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var parsed = parseMountinfoLine(lines[i])
        if (!parsed || !isCloudFstype(parsed.fstype))
            continue
        // Strictly inside: the home directory itself mounts whatever the box is made of.
        if (parsed.path.length <= root.length || parsed.path.indexOf(prefix) !== 0)
            continue
        if (at[parsed.path] === undefined)
            at[parsed.path] = out.length
        out[at[parsed.path]] = parsed
    }
    return out
}

// Any FUSE mount is a cloud candidate; the home-folder containment above is what keeps
// gvfs, portals and the box's own mounts out, because none of them lives under it.
function isCloudFstype(fstype) {
    var lower = String(fstype || "").toLowerCase()
    return lower === "fuse" || lower.indexOf("fuse.") === 0
}

// One mountinfo line into its mountpoint and fstype, or null: the mountpoint is field five
// of the left half and the fstype is the first field of the right half, split on " - ".
function parseMountinfoLine(line) {
    var halves = String(line || "").split(" - ")
    if (halves.length < 2)
        return null
    var left = halves[0].split(/\s+/)
    var right = halves[1].split(/\s+/)
    if (left.length < 5 || right.length < 1 || left[4].length === 0 || right[0].length === 0)
        return null
    return { path: unescapeOctal(left[4]), fstype: right[0] }
}

// Sample input: "/home/u/My\040Drive" answers "/home/u/My Drive". A mountinfo escape is a
// backslash and three octal digits, and anything else is kept literally.
function unescapeOctal(field) {
    return String(field).replace(/\\([0-7]{3})/g, function (match, digits) {
        return String.fromCharCode(parseInt(digits, 8))
    })
}
