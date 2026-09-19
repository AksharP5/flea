.pragma library

.import "DirSizes.js" as DirSizes

// A finished operation names its own reversal and the clipboard names the key that spends it. The
// strip draws either in its secondary, so no sentence it shows ends in advice of its own.
var UNDO_HINT = " \u00b7 z undoes"
var PASTE_HINT = " \u00b7 p pastes"

// Which hint a result carries, if any.
function hintOf(notice) {
    if (notice.indexOf(UNDO_HINT) >= 0) {
        return UNDO_HINT
    }
    return notice.indexOf(PASTE_HINT) >= 0 ? PASTE_HINT : ""
}

// The key it names. ui/StatusBar.qml draws the separator itself, so the key arrives without one.
function hintKey(hint) {
    return hint.replace(" \u00b7 ", "")
}

// Sample input: { transient: "Copy failed", transientIsError: true, searching: true, searchLine: "3 found in 1.6 s", stickyHere: true, sticky: "Copying 2 of 5" }
function errorHere(slot) {
    return slot.transient.length > 0 && slot.transientIsError
}

// The centre zone is what just happened, and nothing else. The disk facts have a zone of their own,
// so this no longer falls back to them: an idle bar's centre is empty. StatusBar board rule 1.
// GM's ordering: acknowledged errors leave the slot; activity cannot displace them.
function centreText(slot) {
    if (errorHere(slot))
        return slot.transient
    if (slot.stickyHere)
        return slot.sticky
    if (slot.searching)
        return slot.searchLine
    return slot.transient
}

function centreRole(slot) {
    return errorHere(slot) ? "error" : "foreground"
}

// The selection's byte total, or -1 when the bar may not claim one. StatusBar board rule 3: every
// selected row has to be held and every size known and complete, and nothing here starts a sweep.
// A file carries its own bytes; a directory has them only from a finished DirSizes answer.
function selectionBytes(pane) {
    var count = pane.selection.count()
    // More rows selected than the window holds means at least one of them is not here to measure.
    if (count === 0 || count > pane.rows.length) {
        return -1
    }
    var indices = pane.selection.indices()
    var bytes = 0
    for (var i = 0; i < indices.length; i++) {
        var row = pane.rows[indices[i] - pane.held]
        if (!row) {
            return -1
        }
        if (row.d) {
            var walked = DirSizes.sizeFor(pane.dirSizeState, indices[i])
            if (!walked || walked.partial) {
                return -1
            }
            bytes += walked.bytes
            continue
        }
        bytes += row.s
    }
    return bytes
}

// Each backend numbers its own transfers, so an id is meaningful only with its pane owner.
function activityChanged(activities, owner, text, transfer) {
    var next = activities.slice()
    var at = next.findIndex(function (activity) { return activity.owner === owner })
    if (!text) {
        if (at >= 0) next.splice(at, 1)
        return next
    }
    var previous = at >= 0 ? next[at] : null
    var activity = { owner: owner, text: text, transfer: transfer,
                     cancelling: !!(previous && previous.transfer.id === transfer.id && previous.cancelling) }
    if (at >= 0) next[at] = activity
    else next.push(activity)
    return next
}

function cancelActivity(activities) {
    if (!activities.length || !activities[0].transfer.running || activities[0].cancelling)
        return activities
    var next = activities.slice()
    next[0] = Object.assign({}, next[0], { cancelling: true })
    return next
}
