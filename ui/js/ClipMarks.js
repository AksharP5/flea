.pragma library

// A row on the clipboard carries a mark after its name: copy for copied,
// scissors for cut, in the muted role. The mark is derived from the pane's
// own clipboard, so a paste that spends a cut, a new copy or a new cut
// clears the old marks at once with no second signal.

// Sample input: { paths: ["/home/gm/Pictures/phone/IMG_4121.jpg"], moving: true }
function markFor(path, clipboard) {
    if (!clipboard || !clipboard.paths || clipboard.paths.indexOf(path) < 0) {
        return ""
    }
    return clipboard.moving ? "scissors" : "copy"
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
