.pragma library

.import "DirSizes.js" as DirSizes
.import "Keymap.js" as Keymap

// A finished operation names its own reversal and the clipboard names the key that spends it. The
// strip draws either in its secondary, so no sentence it shows ends in advice of its own.
var UNDO_HINT = " · z undoes"
var PASTE_HINT = " · p pastes"

// The key that still removes the rows where there is no Trash, drawn in the secondary lane.
function trashHint() {
    var key = Keymap.hintFor("deletePermanently")
    return key.length > 0 ? " · " + key + " deletes" : ""
}

// Refusal where gio has no Trash: the place in the primary, the key that still works in the secondary.
var NO_TRASH = "This location has no Trash"
function noTrashLine() { return NO_TRASH + trashHint() }

// Which notice starts an arm; only the arm's life ranks it. Sample input: "Press d again to trash, or Delete on its own." (ui/js/Trash.js)
function isPrompt(text) {
    return text.indexOf("Press ") === 0 && text.indexOf(" again ") > 0
}

// An arm's record: its owner (the pane, or the Trash view while it is open) and the stamp that owner set before the prompt.
function armOf(owner, stamp) { return { owner: owner, stamp: stamp } }

// Live while the bar still has that owner and the owner still holds that stamp; its second press, any other key and a new listing zero it.
function armLive(arm, owner) { return arm !== null && arm.stamp > 0 && arm.owner === owner && owner.trashArmedAt === arm.stamp }

// What the arm has left by its owner's clock, the stamp, so a Qt timer that fires early never ends it while the key still acts.
function armLeft(arm, now, armMs) { return arm === null ? 0 : armMs - (now - arm.stamp) }

// A live arm's prompt, else the oldest unacknowledged error, else the notice: a hidden live prompt's second press acts unannounced.
function transientOf(errors, notice, prompt, live) {
    if (live === true) return { text: prompt, isError: false, detail: "" }
    if (errors.length) return { text: errors[0].text, isError: true, detail: errors[0].detail }
    return { text: notice, isError: false, detail: "" }
}

// The no-Trash refusal names its place and replaces its own copy there, where it stands; other errors name none.
function withError(errors, text, detail, place) {
    var entry = { text: text, detail: detail || "", place: text === noTrashLine() ? place : "" }
    var at = entry.place.length === 0 ? -1
        : errors.findIndex(function (e) { return e.text === text && e.place === entry.place })
    if (at < 0) return errors.concat([entry])
    var next = errors.slice()
    next[at] = entry
    return next
}

// Leaving a place drops its refusals; other errors wait for dismissal, and an unchanged queue is the same array.
function errorsAt(errors, place) {
    var kept = errors.filter(function (entry) { return entry.place.length === 0 || entry.place === place })
    return kept.length === errors.length ? errors : kept
}

// Which hint a result carries, if any.
function hintOf(notice) {
    if (notice.indexOf(UNDO_HINT) >= 0) {
        return UNDO_HINT
    }
    if (notice.indexOf(PASTE_HINT) >= 0) {
        return PASTE_HINT
    }
    var trash = trashHint()
    if (trash.length > 0 && notice.indexOf(trash) >= 0) {
        return trash
    }
    return ""
}

// The key it names. ui/StatusBar.qml draws the separator itself, so the key arrives without one.
function hintKey(hint) {
    return hint.replace(" \u00b7 ", "")
}

// Sample input: { transient: "Copy failed", transientIsError: true, searching: true, searchLine: "3 found in 1.6 s", stickyHere: true, sticky: "Copying 2 of 5" }
function errorHere(slot) {
    return slot.transient.length > 0 && slot.transientIsError
}

function promptHere(slot) {
    return slot.armLive === true
}

// The centre zone is what just happened, and nothing else. The disk facts have a zone of their own,
// so this no longer falls back to them: an idle bar's centre is empty. StatusBar board rule 1.
// GM's ordering: acknowledged errors leave the slot; activity cannot displace them.
function centreText(slot) {
    // A prompt stands over activity and search as well, for the reason transientOf gives.
    if (errorHere(slot) || promptHere(slot))
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

// Whether the centre draws the notice, whose display time is the one ui/StatusBar.qml's timer ends.
function noticeShown(slot) {
    return !promptHere(slot) && slot.transient.length > 0 && !slot.transientIsError && !slot.stickyHere && !slot.searching
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
