.pragma library

// Sample input, "gio mount -li" under the C locale ui/MountListing.qml pins, captured live on this
// box with a Samsung phone on USB (2026-09-11), the udisks noise around it cut:
// Volume(0): SAMSUNG Android
//   Type: GProxyVolume (GProxyVolumeMonitorMTP)
//   activation_root=mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/
//   can_mount=1
//   Mount(0): SAMSUNG Android -> mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/
// And with GM's iPhone on USB (iOS 26.6.2, 2026-09-14), which answers on two monitors at once:
// Volume(0): iPhone
//   Type: GProxyVolume (GProxyVolumeMonitorGPhoto2)
//   activation_root=gphoto2://Apple_Inc._iPhone_00008130001641411883401C/
// Volume(1): Documents on GM's iPhone
//   Type: GProxyVolume (GProxyVolumeMonitorAfc)
//   uuid=00008130-001641411883401C
//   activation_root=afc://00008130-001641411883401C:3/
// Only a COLUMN-ZERO Volume() block can be a phone: a udisks volume prints indented under its own
// Drive() block, and the Type line is required anyway, so only the three gvfs monitors with no block
// device behind them qualify, MTP for Android, AFC for an iPhone's files and GPhoto2 for cameras.
// lsblk can never list these, which is why ui/DeviceMounts.qml's enumeration misses a plugged phone.
// The indented Mount() inside the block is what says the phone is live; the shadow top-level
// Mount() gio prints beside it is ui/js/Mounts.js parseMounts's to skip.
function parsePhones(output) {
    var blocks = []
    var mounted = {}
    var lines = String(output || "").split("\n")
    var v = null
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        var head = line.match(/^Volume\(\d+\):\s*(.+?)\s*$/)
        if (head) {
            v = { label: head[1], uri: "", uuid: "", mounted: false, monitor: "", canMount: false }
            blocks.push(v)
            continue
        }
        // An AFC root mount prints at column zero rather than inside the volume block it belongs to,
        // so these are collected before the same line ends the block below.
        var top = line.match(/^Mount\(\d+\):\s*.+?\s*->\s*(\S+)\s*$/)
        if (top) mounted[top[1]] = true
        // Any other column-zero line ends the block, the next Drive() or Mount() included.
        if (!/^\s/.test(line)) { v = null; continue }
        if (!v) continue
        // The monitor is also the mark: PhoneMark rule 1 gives MTP the phone and GPhoto2 the camera,
        // which is what the transport exposes the device as rather than what brand made it.
        var monitor = line.match(/^\s+Type: GProxyVolume \(GProxyVolumeMonitor(MTP|GPhoto2|Afc)\)\s*$/)
        if (monitor) v.monitor = monitor[1]
        // The block's own uuid line, not the deeper one under ids:, and the only place the root uri is.
        var uuid = line.match(/^\s+uuid=(\S+)\s*$/)
        if (uuid) v.uuid = uuid[1]
        var root = line.match(/^\s+activation_root=(\S+)\s*$/)
        if (root) v.uri = root[1]
        if (/^\s+can_mount=1\s*$/.test(line)) v.canMount = true
        if (/^\s+Mount\(\d+\):/.test(line)) v.mounted = true
    }
    var out = []
    var serials = []
    for (var a = 0; a < blocks.length; a++) {
        // gvfs-afc advertises the app documents volume, afc://<uuid>:3/, and the rail never mounts
        // that one: the phone's own files are at the root, which mounts on request.
        if (blocks[a].monitor === "Afc" && blocks[a].uuid.length > 0) {
            blocks[a].uri = "afc://" + blocks[a].uuid + "/"
            serials.push(blocks[a].uuid.replace(/-/g, "").toUpperCase())
        }
    }
    for (var b = 0; b < blocks.length; b++) {
        var p = blocks[b]
        // Before the guard below, because an AFC volume answers can_mount=0 once its root is mounted
        // and that mount is the column-zero line rather than one inside its block: asking in the other
        // order loses the row at the moment the rail needs its Unmount.
        if (mounted[p.uri])
            p.mounted = true
        // gvfs answers can_mount=0 for a volume that is already mounted, measured on this box's own
        // USB volume, so only a volume that can neither be mounted nor is mounted is not a row.
        if (p.monitor.length === 0 || p.uri.length === 0 || (!p.canMount && !p.mounted))
            continue
        // One phone, one row: an iPhone's GPhoto2 volume is the camera store that lists nothing on
        // this iOS, and the serial it shares with the AFC uuid is what says they are one device.
        if (p.monitor === "GPhoto2" && carriesOneOf(p.uri, serials))
            continue
        out.push(entry(p))
    }
    return out
}

// The serial both monitors spell: AFC hyphenates it in its uuid, GPhoto2 buries it in the host name.
function carriesOneOf(uri, serials) {
    var up = String(uri).toUpperCase()
    for (var i = 0; i < serials.length; i++)
        if (up.indexOf(serials[i]) >= 0)
            return true
    return false
}

// path is "" until "gio info" resolves the FUSE folder, and size is null because ui/SidebarRow.qml reads a device row's detail off "size !== null".
function entry(v) {
    // AFC names its volume for the documents share it advertises, and the row is the phone, not that.
    var label = v.monitor === "Afc" ? v.label.replace(/^Documents on /, "") : v.label
    return { path: "", label: label, group: "device", kind: "phone", uri: v.uri, size: null,
             mounted: v.mounted, glyph: v.monitor === "GPhoto2" ? "camera" : "smartphone" }
}
