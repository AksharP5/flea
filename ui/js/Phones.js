.pragma library

// Sample input, "gio mount -li" under the C locale ui/MountListing.qml pins, captured live on this
// box with a Samsung phone on USB (2026-09-11), the udisks noise around it cut:
// Volume(0): SAMSUNG Android
//   Type: GProxyVolume (GProxyVolumeMonitorMTP)
//   activation_root=mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/
//   can_mount=1
//   Mount(0): SAMSUNG Android -> mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/
// And with GM's iPhone on USB (iOS 26.6.2, 2026-09-14), which answers on two monitors at once,
// then once its root is mounted, at column zero and outside the block that offered it:
// Volume(0): iPhone
//   Type: GProxyVolume (GProxyVolumeMonitorGPhoto2)
//   activation_root=gphoto2://Apple_Inc._iPhone_00008130001641411883401C/
//   can_mount=1
// Volume(1): Documents on GM's iPhone
//   Type: GProxyVolume (GProxyVolumeMonitorAfc)
//   uuid=00008130-001641411883401C
//   activation_root=afc://00008130-001641411883401C:3/
//   can_mount=1
// Mount(2): GM's iPhone -> afc://00008130-001641411883401C/
// The root is that column-zero line; the share answers can_mount=0 with its own indented Mount when gvfs automounts it.
// Only a COLUMN-ZERO Volume() block can be a phone: a udisks volume prints indented under its own
// Drive() block, and the Type line is required anyway, so only the three gvfs monitors with no block
// device behind them qualify, MTP for Android, AFC for an iPhone's files and GPhoto2 for cameras.
// lsblk can never list these, which is why ui/DeviceMounts.qml's enumeration misses a plugged phone.
// The indented Mount() inside the block is what says an MTP or GPhoto2 volume is live; an AFC root
// mounts outside the block that offered it, so a column-zero Mount() naming the row's own uri says
// the same thing. Either way that line is ui/js/Mounts.js parseMounts's to skip as a NETWORK row.
function parsePhones(output) {
    var blocks = []
    var mounted = {}
    var lines = String(output || "").split("\n")
    var v = null
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        var head = line.match(/^Volume\(\d+\):\s*(.+?)\s*$/)
        if (head) {
            v = { label: head[1], uri: "", uuid: "", mounted: false, inBlock: false, monitor: "", canMount: false }
            blocks.push(v)
            continue
        }
        // An AFC root mounts outside the block that offered it, so these are collected first.
        var top = line.match(/^Mount\(\d+\):\s*.+?\s*->\s*(\S+)\s*$/)
        if (top) mounted[top[1]] = true
        // Any other column-zero line ends the block, the next Drive() or Mount() included.
        if (!/^\s/.test(line)) { v = null; continue }
        if (!v) continue
        // Rule 1: the mark names the transport, MTP and AFC the phone and GPhoto2 the camera.
        var monitor = line.match(/^\s+Type: GProxyVolume \(GProxyVolumeMonitor(MTP|GPhoto2|Afc)\)\s*$/)
        if (monitor) v.monitor = monitor[1]
        // The block's own uuid line, not the deeper one under ids: that carries the same digits.
        var uuid = line.match(/^\s+uuid=(\S+)\s*$/)
        if (uuid) v.uuid = uuid[1]
        var root = line.match(/^\s+activation_root=(\S+)\s*$/)
        if (root) v.uri = root[1]
        if (/^\s+can_mount=1\s*$/.test(line)) v.canMount = true
        if (/^\s+Mount\(\d+\):/.test(line)) v.inBlock = true
    }
    for (var a = 0; a < blocks.length; a++) {
        if (blocks[a].monitor !== "Afc")
            continue
        // gvfs-afc advertises afc://<uuid>:3/, the documents share; the phone's files are at the root.
        blocks[a].uri = blocks[a].uuid.length > 0 ? "afc://" + blocks[a].uuid + "/" : ""
    }
    var kept = []
    var serials = []
    var seen = {}
    for (var b = 0; b < blocks.length; b++) {
        var p = blocks[b]
        // An Afc block's own Mount is that documents share, so only the root's column-zero line counts.
        p.mounted = p.monitor === "Afc" ? mounted[p.uri] === true : (p.inBlock || mounted[p.uri] === true)
        // An Afc volume's can_mount is that share's too, so its row stands on the root it names.
        var live = p.monitor === "Afc" || p.canMount || p.mounted
        // gvfs answers can_mount=0 for a volume it has already mounted, measured on this box's own USB
        if (p.monitor.length === 0 || p.uri.length === 0 || !live)
            continue
        // Two AFC volumes can carry one uuid, and they rebuild to one root, which is one row.
        if (seen[p.uri])
            continue
        seen[p.uri] = true
        if (p.monitor === "Afc")
            serials.push(p.uuid.replace(/-/g, "").toUpperCase())
        kept.push(p)
    }
    // Folded against rows that survived, so a dropped AFC volume cannot take the phone off the rail.
    var out = []
    for (var c = 0; c < kept.length; c++) {
        // One phone, one row: the serial the two monitors share is what says they are one device.
        if (kept[c].monitor === "GPhoto2" && carriesOneOf(kept[c].uri, serials))
            continue
        out.push(entry(kept[c]))
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
