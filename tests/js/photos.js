.import "../../ui/js/Photos.js" as Photos
.import "../../ui/js/Mounts.js" as Mounts
.import "../../ui/js/RailKeys.js" as RailKeys

// The PhonePhotos board's rail row and DCIM walk control: the Photos row appears under a
// phone or camera device entry, at the same column and never indented, only while that
// device is on the rail, and opening it walks that device's DCIM for photos and videos.

function phone(uri) {
    return { path: "", label: "iPhone", group: "device", kind: "phone", uri: uri,
             size: null, mounted: true, glyph: "smartphone" }
}

function volume() {
    return { path: "/run/media/gm/128GB", label: "128GB", group: "device", kind: "volume",
             device: "/dev/sda1", size: null, mounted: true, removable: true, glyph: "drive" }
}

function run(check) {
    check("a mount path gains DCIM", Photos.dcimPath("/run/user/1000/gvfs/mtp:host=X"),
          "/run/user/1000/gvfs/mtp:host=X/DCIM")
    check("a trailing slash is trimmed first", Photos.dcimPath("/run/user/1000/gvfs/mtp:host=X/"),
          "/run/user/1000/gvfs/mtp:host=X/DCIM")

    check("a phone entry is a phone", Photos.isPhoneEntry(phone("mtp://x/")), true)
    check("a volume is not", Photos.isPhoneEntry(volume()), false)
    check("a share is not", Photos.isPhoneEntry({ kind: "share", group: "network" }), false)
    check("a photos row is not a phone", Photos.isPhoneEntry({ kind: "photos", group: "device" }), false)
    check("nothing is not a phone", Photos.isPhoneEntry(null), false)

    var entry = Photos.photoEntry(phone("mtp://SAMSUNG/"))
    check("the row is labelled Photos", entry.label, "Photos")
    check("it draws the image glyph", entry.glyph, "image")
    check("it rides the DEVICES group as its own kind", entry.group + "|" + entry.kind, "device|photos")
    check("it carries the device it walks", entry.uri + "|" + entry.deviceLabel + "|" + entry.mounted,
          "mtp://SAMSUNG/|iPhone|true")
    check("it carries a null size rather than none", entry.size, null)

    check("an empty rail stays empty", Photos.withPhotoRows([]).length, 0)
    check("a volume stands alone", Photos.withPhotoRows([volume()]).length, 1)
    var one = Photos.withPhotoRows([phone("mtp://x/")])
    check("a phone gains exactly one row under it", one.length, 2)
    check("the row sits directly under the device", one[0].kind + "|" + one[1].kind, "phone|photos")
    var two = Photos.withPhotoRows([phone("mtp://a/"), volume(), phone("mtp://b/")])
    check("each phone gains its own row and nothing else moves",
          two.map(function (e) { return e.kind }).join(","), "phone,photos,volume,phone,photos")
    check("each photos row names its own device", two[1].uri + "|" + two[4].uri, "mtp://a/|mtp://b/")

    check("a photos row keys apart from its device",
          Mounts.railKey(two[1]) === Mounts.railKey(two[0]), false)
    check("and it resolves back to its own position", Mounts.rowByKey(two, Mounts.railKey(two[1])), 1)
    check("a photos row offers no release", Mounts.railMenu(two[1]).length, 0)
    check("a uriless photos row keys nothing", Mounts.railKey({ group: "device", kind: "photos", uri: "" }), "")

    // The walk control, beside the transitions it drives. Only the members run, close,
    // cancel and ranked touch are stubbed, and sends are recorded so a request can be told.
    function idle(dcim) {
        var sent = []
        return {
            photosMode: "", photosFrom: "", photosView: "", photosRunning: false, photosCancelled: false,
            photosScanned: 0, photosMs: 0, path: "/d", showHidden: false, total: 0, held: 0,
            rows: [], kindNames: [], cursorIndex: 0, listingState: "ready", viewMode: "list",
            relisted: "", sent: sent,
            clearSelection: function () {},
            setCursor: function (i) { this.cursorIndex = i },
            openWithoutHistory: function (path) { this.relisted = path },
            backend: {
                photos: function (path, hidden) { sent.push("photos " + path) },
                photoscancel: function () { sent.push("photoscancel") },
                askFsInfo: function () { sent.push("fsinfo") },
                window: function (start, count) { sent.push("window " + start + "+" + count) }
            },
            windowSize: 350, thumbState: {}, dirSizeState: {}, selectionVersion: 0
        }
    }
    var pane = idle()
    Photos.run(pane, "/run/user/1000/gvfs/mtp:host=X/DCIM")
    check("opening takes the pane to DCIM", pane.path, "/run/user/1000/gvfs/mtp:host=X/DCIM")
    check("a photos walk is a mode of its own, not a search", pane.photosMode, "results")
    check("the walk runs and the count restarts", pane.photosRunning + "|" + pane.total, "true|0")
    check("the roll draws as a grid", pane.viewMode, "grid")
    check("the walk is asked for, then its class", pane.sent.join(","), "photos /run/user/1000/gvfs/mtp:host=X/DCIM,fsinfo")
    check("a running walk with nothing yet is still loading", Photos.listingState(pane, 0), "loading")

    pane.total = 1246
    check("matches make the listing ready", Photos.listingState(pane, 1246), "ready")
    Photos.ranked(pane)
    check("the rank lands the cursor on the newest row", pane.cursorIndex, 0)
    check("and the new order is windowed", pane.sent[pane.sent.length - 1], "window 0+350")

    Photos.cancel(pane)
    check("esc while running stops the walk, not the listing", pane.sent[pane.sent.length - 1], "photoscancel")
    check("the rows stay up behind it", pane.photosMode, "results")
    // The backend's own searched line ends the run; ui/PaneWire.qml writes this half.
    pane.photosRunning = false
    Photos.cancel(pane)
    check("a second esc leaves the roll", pane.photosMode, "")
    check("leaving re-lists where it began", pane.relisted, "/d")
    check("and the view goes back with it", pane.viewMode, "list")

    // The rail's own entrance beside RailKeys.openFrom: no row acts while a listing is out.
    var sidebar = { focusOnOpen: true }
    RailKeys.openPhotosFrom(null, "/dcim/DCIM", sidebar)
    check("no pane drops the focus claim", sidebar.focusOnOpen, false)
    var busy = idle()
    busy.listInFlight = true
    busy.note = ""
    busy.message = function (text) { this.note = text }
    sidebar.focusOnOpen = true
    RailKeys.openPhotosFrom(busy, "/dcim/DCIM", sidebar)
    check("a listing in flight refuses the roll", busy.note, "A directory is already loading.")
    check("and drops the focus claim with it", sidebar.focusOnOpen, false)
    check("nothing was asked for", busy.sent.length, 0)
    var free = idle()
    free.listInFlight = false
    sidebar.focusOnOpen = true
    RailKeys.openPhotosFrom(free, "/dcim/DCIM", sidebar)
    check("an idle pane walks", free.sent[0], "photos /dcim/DCIM")
}
