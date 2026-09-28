.pragma library

// A row on the clipboard carries a mark after its name: copy for copied, scissors for cut.
// The mark follows the pane's own clipboard, so spending a cut clears every mark at once.

// Sample input: { paths: ["/home/gm/Pictures/phone/IMG_4121.jpg"], moving: true }
var _cached = null
var _marks = {}

// One keyed lookup per clipboard, rebuilt when the clipboard object changes; every row after that is a single key read.
function setFor(clipboard) {
    if (clipboard === _cached)
        return _marks
    _cached = clipboard
    _marks = {}
    var paths = (clipboard && clipboard.paths) || []
    for (var i = 0; i < paths.length; i++)
        _marks[paths[i]] = true
    return _marks
}

function markFor(path, clipboard) {
    if (!clipboard || !clipboard.paths || clipboard.paths.length === 0) {
        return ""
    }
    return setFor(clipboard)[path] === true ? (clipboard.moving ? "scissors" : "copy") : ""
}

// One lookup per visible row, and an empty clipboard costs nothing: the
// paths are never joined and never searched when there is nothing to find.
function markForRow(pane, name, clipboard) {
    if (!clipboard || !clipboard.paths || clipboard.paths.length === 0 || !name) {
        return ""
    }
    return markFor(rowPath(pane, name), clipboard)
}

// The pane's own join, so a search result resolves against the scope the
// pane is standing on, which Search.run made its path. Sample input:
// pane { path: "/home/gm/Pictures/phone" }, name "IMG_4121.jpg".
function rowPath(pane, name) {
    if (!name) {
        return ""
    }
    return pane.join(pane.path, name)
}

// A paste that spends a cut empties the clipboard, so the marks go with it;
// a copy paste keeps it. ui/CollideHost.qml decides through this.
function spent(clipboard, spendsCut) {
    if (spendsCut === true) {
        return { paths: [], moving: false }
    }
    return clipboard
}
