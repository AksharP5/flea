.import "../../ui/js/Status.js" as Status

// The status slot's precedence, which shipped with no suite of any kind. Operations.html states the
// order as an unacknowledged error, then activity, and draws a failed copy holding the slot while a
// running search keeps a secondary count beside it. These drive the precedence directly, because
// the order is the whole of the policy and none of it needs a window to be true.

function slot(over) {
    var s = {
        transient: "",
        transientIsError: false,
        searching: false,
        searchLine: "",
        stickyHere: false,
        sticky: ""
    }
    for (var k in over) {
        s[k] = over[k]
    }
    return s
}

function run(check) {
    // The disk facts have a zone of their own now, so an idle centre says nothing at all.
    var quiet = slot({})
    check("an idle centre is empty rather than borrowing the disk's zone", Status.centreText(quiet), "")
    check("and an empty centre keeps the board's foreground role", Status.centreRole(quiet), "foreground")

    var searching = slot({ searching: true, searchLine: "3 found · Searching, 12 scanned" })
    check("a search on its own owns the slot", Status.centreText(searching), "3 found · Searching, 12 scanned")
    check("a running search uses foreground text", Status.centreRole(searching), "foreground")

    var working = slot({ stickyHere: true, sticky: "Compressing 2 of 5" })
    check("a running operation owns the slot", Status.centreText(working), "Compressing 2 of 5")
    check("and reads at full contrast", Status.centreRole(working), "foreground")

    // Directive 51: a transfer's own progress never reaches this slot any more, the card draws it, so
    // the activity that can still hold one is a drag's feedback. The precedence itself is unchanged.
    var both = slot({ searching: true, searchLine: "3 found · Searching, 12 scanned", stickyHere: true, sticky: "Copy 1 item to dest" })
    check("an activity precedes search", Status.centreText(both), "Copy 1 item to dest")
    check("and retains foreground during search", Status.centreRole(both), "foreground")

    var failed = slot({ transient: "Copy failed: photo.heic · disk full", transientIsError: true })
    check("a failure owns the slot", Status.centreText(failed), "Copy failed: photo.heic · disk full")
    check("and takes the error role", Status.centreRole(failed), "error")

    // The defect this suite was written for. Operations.html's third specimen draws exactly this
    // pair: the failure holds the slot and the walk is reduced to a secondary count.
    var failedWhileSearching = slot({
        transient: "Copy failed: photo.heic · disk full",
        transientIsError: true,
        searching: true,
        searchLine: "3 found · Searching, 12 scanned"
    })
    check("a search never hides an unacknowledged error",
          Status.centreText(failedWhileSearching), "Copy failed: photo.heic · disk full")
    check("and the error keeps its role rather than painting the search keys red",
          Status.centreRole(failedWhileSearching), "error")

    // The same rule against a running operation, which the board ranks below a failure for the same
    // reason: the operation will end on its own and the error will not.
    var failedWhileWorking = slot({
        transient: "Convert failed: no encoder",
        transientIsError: true,
        stickyHere: true,
        sticky: "Converting 1 of 3"
    })
    check("a running operation never hides an unacknowledged error",
          Status.centreText(failedWhileWorking), "Convert failed: no encoder")
    check("and it is drawn as an error, not as the operation",
          Status.centreRole(failedWhileWorking), "error")

    // An ordinary result is not an error, so it stays behind activity and times out on its own.
    var noticeWhileSearching = slot({
        transient: "Moved 4 items to Trash",
        searching: true,
        searchLine: "3 found · Searching, 12 scanned"
    })
    check("a plain notice still yields to the search",
          Status.centreText(noticeWhileSearching), "3 found · Searching, 12 scanned")

    // V7: the clipboard's own hint joins the undo hint on the secondary, so no sentence here ends
    // in advice. ui/js/Ops.js builds both into its result lines and this is what takes them apart.
    check("an undoable result carries the undo hint", Status.hintOf("Moved 4 items to Trash · z undoes"), " · z undoes")
    check("a clipboard result carries the paste hint", Status.hintOf("Copied 1 item · p pastes"), " · p pastes")
    check("a plain result carries neither", Status.hintOf("Renamed to notes.txt"), "")
    check("and the secondary is handed the key alone, because it draws its own separator",
          Status.hintKey(Status.UNDO_HINT) + "|" + Status.hintKey(Status.PASTE_HINT), "z undoes|p pastes")

    // StatusBar board rule 3: the byte total appears only when every selected row is held and every
    // size is known and complete, and nothing here starts a sweep to fill a gap.
    function pane(over) {
        var p = {
            held: 0,
            rows: [{ s: 1000 }, { s: 2000 }, { d: true }, { s: 4000 }],
            dirSizeState: { file: { 2: { bytes: 8000, partial: false } }, order: [2] },
            picked: [0, 1]
        }
        for (var k in over) { p[k] = over[k] }
        p.selection = { count: function () { return p.picked.length },
                        indices: function () { return p.picked } }
        return p
    }
    check("two held files add up", Status.selectionBytes(pane({})), 3000)
    check("a directory with a finished walk counts too",
          Status.selectionBytes(pane({ picked: [0, 2] })), 9000)
    check("a directory whose walk is still partial removes the total",
          Status.selectionBytes(pane({ picked: [0, 2],
              dirSizeState: { file: { 2: { bytes: 8000, partial: true } }, order: [2] } })), -1)
    check("a directory nothing has walked removes the total",
          Status.selectionBytes(pane({ picked: [0, 2], dirSizeState: { file: {}, order: [] } })), -1)
    check("a directory asked about and still waiting removes the total",
          Status.selectionBytes(pane({ picked: [0, 2],
              dirSizeState: { file: { 2: null }, order: [2] } })), -1)
    check("a selected row outside the held window removes the total",
          Status.selectionBytes(pane({ picked: [0, 9] })), -1)
    check("a selection wider than the window is refused before it is walked",
          Status.selectionBytes(pane({ picked: [0, 1, 2, 3, 4] })), -1)
    check("an empty selection has no total to state", Status.selectionBytes(pane({ picked: [] })), -1)
    // The window is not always at row zero, so the row lookup has to go through held.
    check("a held window further down the listing still resolves its rows",
          Status.selectionBytes(pane({ held: 100, picked: [100, 101] })), 3000)

    check("errorHere is the one test for an unacknowledged failure",
          Status.errorHere(failed), true)
    check("and a plain notice is not one", Status.errorHere(noticeWhileSearching), false)
    check("a completion notice uses the board's running-text role",
          Status.centreRole(slot({transient: "Moved 4 items to Trash"})), "foreground")

    var left = {}, right = {}
    var transfer = { id: 1, running: true }
    var activities = Status.activityChanged([], left, "Copying 1 of 5", transfer)
    activities = Status.cancelActivity(activities)
    check("cancel marks its active owner", activities[0].cancelling, true)
    check("repeated cancel keeps the same state", Status.cancelActivity(activities) === activities, true)
    activities = Status.activityChanged(activities, right, "Moving 1 of 3", transfer)
    check("a second owner cannot replace the running primary", activities[0].owner === left, true)
    check("identical ids from another backend do not inherit cancellation", activities[1].cancelling, false)
    activities = Status.activityChanged(activities, left, "Copying 2 of 5", transfer)
    check("progress cannot re-enable a cancelled transfer", activities[0].cancelling, true)
    activities = Status.activityChanged(activities, right, "", { id: 0, running: false })
    check("foreign completion does not clear the active transfer", activities[0].owner === left, true)
    activities = Status.activityChanged(activities, right, "Moving 1 of 2", { id: 2, running: true })
    activities = Status.activityChanged(activities, left, "", { id: 0, running: false })
    check("completion reveals the other running transfer", activities[0].owner === right, true)
    check("the next owner's cancellation remains available", activities[0].cancelling, false)
    activities = Status.cancelActivity(activities)
    activities = Status.activityChanged(activities, right, "Moving 1 of 1", { id: 3, running: true })
    check("a new transfer id clears that owner's old cancellation", activities[0].cancelling, false)
    activities = Status.activityChanged(activities, right, "", { id: 0, running: false })
    check("completed activities release their owner references", activities.length, 0)
    check("an idle cancel is harmless", Status.cancelActivity(activities).length, 0)
}
