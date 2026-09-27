.pragma library

.import "DirSizes.js" as DirSizes
.import "Thumbs.js" as Thumbs

// The PhonePhotos board's rail row and DCIM walk control. The Photos row appears under a
// phone or camera device entry while that device is on the rail, at the same column and
// never indented, and opening it walks that device's DCIM for photos and videos, newest
// first, streamed into the grid the way a search streams into the list. The walk's rows
// are paths relative to DCIM, so join, reveal and every per-row facility keep working
// untouched, and thumbnails and dates ride the same visible-tiles-only machinery.

// The DCIM folder under a mounted phone. Sample input: "/run/user/1000/gvfs/mtp:host=X/"
// answers "/run/user/1000/gvfs/mtp:host=X/DCIM".
function dcimPath(mountPath) {
    var base = String(mountPath || "")
    while (base.length > 1 && base.charAt(base.length - 1) === "/")
        base = base.substring(0, base.length - 1)
    return base + "/DCIM"
}

// A phone or a camera, the only rows a Photos row stands under. Sample input:
// {kind:"phone"} answers true, {kind:"volume"} answers false.
function isPhoneEntry(entry) {
    return !!entry && entry.group === "device" && entry.kind === "phone"
}

// The rail row itself: the board's "Photos" with the image glyph, carrying the device it
// walks. The size stays null because ui/SidebarRow.qml reads a device row's detail off
// "size !== null", and a Photos row draws no number.
function photoEntry(device) {
    return { path: "", label: "Photos", group: "device", kind: "photos", glyph: "image",
             uri: device.uri || "", mounted: device.mounted === true,
             deviceLabel: device.label || "", size: null }
}

// One Photos row directly under each phone or camera entry, and nothing anywhere else: a
// volume, a share and a home row stand alone. Only while the device is present and mounted,
// because the rows are rebuilt from the entries the poll still names; the board's callout 1
// shows it only where a DCIM folder stands, which an unmounted device cannot answer for.
function withPhotoRows(deviceEntries) {
    var out = []
    var list = deviceEntries || []
    for (var i = 0; i < list.length; i++) {
        out.push(list[i])
        if (isPhoneEntry(list[i]) && list[i].mounted === true)
            out.push(photoEntry(list[i]))
    }
    return out
}

// The walk's own mode, beside ui/js/Search.js's: "" off, "results" once asked for.
var RESULTS = "results"

// Opening the rail row: the pane moves to DCIM and the walk starts, in the grid the board
// draws. The grid is the session's, not a saved view: ui/Pane.qml holds the persistence
// while this mode stands and hands the saved view back when it ends. A search owning the
// rows ends first through the shared leave step, so searchRunning never sticks behind.
function run(pane, dcim, deviceLabel) {
    if ((pane.searchMode || "").length > 0 && pane.searchRunning) {
        if (pane.backend) pane.backend.searchcancel()
        pane.searchMode = ""
        pane.searchQuery = ""
        pane.searchRunning = false
        pane.searchScanned = 0
        pane.searchFrom = ""
        var self = pane
        var folder = dcim
        var label = deviceLabel
        Qt.callLater(function () { run(self, folder, label) })
        return
    }
    if ((pane.searchMode || "").length > 0) {
        pane.searchMode = ""
        pane.searchQuery = ""
        pane.searchRunning = false
        pane.searchScanned = 0
        pane.searchFrom = ""
    }
    if (pane.photosFrom.length === 0) {
        pane.photosFrom = pane.path
        pane.photosView = pane.viewMode
    }
    pane.photosDevice = String(deviceLabel || pane.photosDevice || "")
    pane.path = dcim
    pane.photosMode = RESULTS
    pane.photosRunning = true
    pane.photosScanned = 0
    pane.total = 0
    pane.held = 0
    pane.rows = []
    pane.kindNames = []
    pane.cursorIndex = 0
    pane.listingState = "loading"
    pane.clearSelection()
    pane.viewMode = "grid"
    // The walk's scope is a directory too, so its class rides the same line a list's does.
    pane.storageClass = ""
    pane.storageKnown = false
    pane.backend.photos(dcim, pane.showHidden)
    // The walk's scope is a directory too, so its class rides the same line a list's does,
    // which is what makes a phone's roll cache-only at defaults; see ui/js/ExtThumbs.js.
    pane.backend.askFsInfo()
}

// Esc stops a running walk and leaves the roll up; a second Esc is what returns to the listing.
function cancel(pane) {
    if (pane.photosRunning) {
        pane.backend.photoscancel()
        return
    }
    close(pane)
}

// Leaving the roll re-lists the directory it was opened from and hands the saved view back.
// No history entry, because entering and leaving the roll is not a navigation. A view chosen
// during the roll survives: the saved view tracks the choice, so closing keeps it.
function close(pane) {
    var back = pane.photosFrom.length > 0 ? pane.photosFrom : pane.path
    var view = pane.photosView.length > 0 ? pane.photosView : "list"
    if (pane.viewMode !== "grid") view = pane.viewMode
    pane.photosMode = ""
    pane.photosRunning = false
    pane.photosScanned = 0
    pane.photosFrom = ""
    pane.photosView = ""
    pane.photosDevice = ""
    pane.viewMode = view
    pane.openWithoutHistory(back)
}

// A navigation drops the roll without re-listing it first; the navigation lists instead.
function drop(pane) {
    if ((pane.photosMode || "").length === 0) return false
    if (pane.photosRunning && pane.backend) pane.backend.photoscancel()
    pane.photosMode = ""
    pane.photosRunning = false
    pane.photosScanned = 0
    pane.photosFrom = ""
    pane.photosView = ""
    pane.photosDevice = ""
    return true
}

// The terminal searched line: the walk orders its rows newest first in the statement before
// writing it, so every row index the client still holds names another file, exactly as a
// re-sort's do. The five moves are ui/js/Search.js ranked()'s own.
function ranked(pane) {
    pane.thumbState = Thumbs.empty()
    pane.dirSizeState = DirSizes.empty()
    pane.clearSelection()
    // Row 0 is the newest photo once the ordering has run, so the reset lands the cursor on it.
    pane.setCursor(0)
    pane.backend.window(0, pane.windowSize)
}

// A walk with no matches yet is still working, so the grid keeps the crawl rather than
// flashing the empty state at every directory that happens to hold nothing.
function listingState(pane, total) {
    if (total > 0) {
        return "ready"
    }
    return pane.photosRunning ? "loading" : "empty"
}
