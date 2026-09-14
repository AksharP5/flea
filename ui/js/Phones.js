.pragma library

// Sample input, "gio mount -li" under the C locale ui/MountListing.qml pins, captured live on this
// box with a Samsung phone on USB (2026-09-11), the udisks noise around it cut:
// Volume(0): SAMSUNG Android
//   Type: GProxyVolume (GProxyVolumeMonitorMTP)
//   activation_root=mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/
//   can_mount=1
//   Mount(0): SAMSUNG Android -> mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/
// Only a COLUMN-ZERO Volume() block can be a phone: a udisks volume prints indented under its own
// Drive() block, and the Type line is required anyway, so only the two gvfs monitors with no block
// device behind them qualify, MTP for Android and GPhoto2 for cameras and iPhones. lsblk can never
// list these, which is why ui/DeviceMounts.qml's enumeration misses a plugged phone entirely.
// The indented Mount() inside the block is what says the phone is live; the shadow top-level
// Mount() gio prints beside it is ui/js/Mounts.js parseMounts's to skip.
function parsePhones(output) {
    var blocks = []
    var lines = String(output || "").split("\n")
    var v = null
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        var head = line.match(/^Volume\(\d+\):\s*(.+?)\s*$/)
        if (head) {
            v = { label: head[1], uri: "", mounted: false, monitor: "", canMount: false }
            blocks.push(v)
            continue
        }
        // Any other column-zero line ends the block, the next Drive() or Mount() included.
        if (!/^\s/.test(line)) { v = null; continue }
        if (!v) continue
        // The monitor is also the mark: PhoneMark rule 1 gives MTP the phone and GPhoto2 the camera,
        // which is what the transport exposes the device as rather than what brand made it.
        var monitor = line.match(/^\s+Type: GProxyVolume \(GProxyVolumeMonitor(MTP|GPhoto2)\)\s*$/)
        if (monitor) v.monitor = monitor[1]
        var root = line.match(/^\s+activation_root=(\S+)\s*$/)
        if (root) v.uri = root[1]
        if (/^\s+can_mount=1\s*$/.test(line)) v.canMount = true
        if (/^\s+Mount\(\d+\):/.test(line)) v.mounted = true
    }
    var out = []
    for (var b = 0; b < blocks.length; b++) {
        var p = blocks[b]
        // gvfs answers can_mount=0 for a volume that is already mounted, measured on this box's own
        // USB volume, so only a volume that can neither be mounted nor is mounted is not a row.
        if (p.monitor.length === 0 || p.uri.length === 0 || (!p.canMount && !p.mounted))
            continue
        out.push(entry(p))
    }
    return out
}

// path is "" until "gio info" resolves the FUSE folder, and size is null because ui/SidebarRow.qml reads a device row's detail off "size !== null".
function entry(v) {
    return { path: "", label: v.label, group: "device", kind: "phone", uri: v.uri, size: null,
             mounted: v.mounted, glyph: v.monitor === "GPhoto2" ? "camera" : "smartphone" }
}
