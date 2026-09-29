.pragma library

// The mark follows the pane's own clipboard, so spending a cut clears every mark at once.

// Sample input: { paths: ["/home/gm/Pictures/phone/IMG_4121.jpg"], moving: true }
var _cached = null
var _marks = {}
// Counts rows reaching the library; production ignores it, tests/listcost.qml asserts on it.
var markCalls = 0

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

// An emptied clipboard drops its lookup once, so a cut of a large directory frees it and later rows allocate nothing.
function release() {
    if (_cached === null) return
    _cached = null
    _marks = {}
}

// Sample input: { paths: [], moving: false } is empty, null is empty.
function isEmpty(clipboard) {
    return !clipboard || !clipboard.paths || clipboard.paths.length === 0
}

function markFor(path, clipboard) {
    if (isEmpty(clipboard)) {
        release()
        return ""
    }
    return setFor(clipboard)[path] === true ? (clipboard.moving ? "scissors" : "copy") : ""
}

// An empty clipboard costs nothing: its paths are never joined or searched.
function markForRow(pane, name, clipboard) {
    markCalls += 1
    if (isEmpty(clipboard)) {
        release()
        return ""
    }
    if (!name) {
        return ""
    }
    return markFor(rowPath(pane, name), clipboard)
}

// The pane's own join, so a search result resolves against the scope Search.run made its path.
// Sample input: pane { path: "/home/gm/Pictures/phone" }, name "IMG_4121.jpg".
function rowPath(pane, name) {
    if (!name) {
        return ""
    }
    return pane.join(pane.path, name)
}

// A sent cut empties a cut clipboard, so the marks go with it; anything else keeps it. ui/CollideHost.qml decides through this.
function spent(clipboard, spendsCut) {
    if (spendsCut === true && clipboard && clipboard.moving === true) {
        return { paths: [], moving: false }
    }
    return clipboard
}
