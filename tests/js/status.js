.import "../../ui/js/Status.js" as Status
.import "../../ui/js/Trash.js" as Trash
.import "../../ui/js/Ops.js" as Ops

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

// ui/TrashView.qml's dd prompt, read from its source; sample: else statusReported("Press d again to review permanent deletion, or Delete on its own.", false)
function trashViewPrompt() {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../../ui/TrashView.qml"), false)
    request.send()
    var found = String(request.responseText || "").match(/statusReported\("(Press [^"]*)"/)
    return found ? found[1] : ""
}

// ui/TrashView.qml's armDelete stamps before it reports; sample: trashArmedAt = paired ? 0 : now ... statusReported("Press d again ...", false)
function trashViewStampsFirst() {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../../ui/TrashView.qml"), false)
    request.send()
    var body = String(request.responseText || "")
    var from = body.indexOf("function armDelete()")
    var stamp = body.indexOf("trashArmedAt = paired ? 0 : now", from)
    var say = body.indexOf("statusReported(\"Press ", from)
    return from >= 0 && stamp > from && say > stamp
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

    // The precedence with an empty sticky, which is what the strip hands in while a transfer runs.
    var errorOverSearch = slot({ transient: "Copy failed: c.txt · already exists", transientIsError: true,
                                 searching: true, searchLine: "3 found in 1.6 s" })
    check("an error beats a search that is still reporting",
          Status.centreText(errorOverSearch), "Copy failed: c.txt · already exists")
    check("and keeps the error role while it does",
          Status.centreRole(errorOverSearch), "error")

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

    // An arm's prompt stands over errors, search and activity only while the arm lives: its text alone ranks nothing.
    var p = { trashArmedAt: 0, cursorIndex: 3, shown: null, trashedIdx: [], said: "", stampAtSay: -1, selectedIndices: function () { return [] } }
    p.message = function (text) { p.said = text; p.stampAtSay = p.trashArmedAt }
    p.backend = { trash: function (idx) { p.trashedIdx = idx } }
    Trash.arm(p)
    var prompt = p.said
    check("the listing's dd prompt reads as a prompt", Status.isPrompt(prompt), true)
    check("and so does the Trash view's own", trashViewPrompt().length > 0 && Status.isPrompt(trashViewPrompt()), true)
    check("while a result is not one", Status.isPrompt("Moved 4 items to Trash · z undoes"), false)
    // ui/StatusBar.qml watches the stamp its owner holds when the prompt is said, so each owner stamps first.
    check("Trash.arm stamps before it says its prompt", p.stampAtSay > 0 && p.stampAtSay === p.trashArmedAt, true)
    check("and ui/TrashView.qml's armDelete does too", trashViewStampsFirst(), true)
    var older = [{ text: "Copy failed: photo.heic · disk full", detail: "No space left on device", place: "" }]
    check("a prompt's text with no live arm does not stand over an error", Status.transientOf(older, prompt).isError, true)
    check("nor over a search that is still reporting",
          Status.centreText(slot({ transient: prompt, searching: true, searchLine: "3 found in 1.6 s" })), "3 found in 1.6 s")
    var arm = Status.armOf(p, p.trashArmedAt)
    check("a live arm's prompt stands over an older error", JSON.stringify(Status.transientOf(older, "", prompt,
          Status.armLive(arm, p))), JSON.stringify({ text: prompt, isError: false, detail: "" }))
    check("and over a search and an activity",
          Status.centreText(slot({ transient: prompt, armLive: true, searching: true, searchLine: "3 found" })) + "|"
          + Status.centreText(slot({ transient: prompt, armLive: true, stickyHere: true, sticky: "Copy 1 item to dest" })),
          prompt + "|" + prompt)
    check("while a plain result still waits behind the error",
          Status.transientOf(older, "Copied 1 item · p pastes", "", false).text, older[0].text)
    check("the arm is dead to a bar that has lost its owner", Status.armLive(arm, { trashArmedAt: p.trashArmedAt }), false)
    // dd where the trash fails: the second d spends the arm, so the failure it raises shows at once.
    Trash.arm(p)
    check("the second d trashes the row and spends the arm", p.trashedIdx.join(",") + "|" + p.trashArmedAt, "3|0")
    var trashFailed = Status.withError([], "Could not move locked to the Trash · Permission denied", "", "/d")
    check("so the failed trash shows at once, not behind a dead prompt",
          Status.transientOf(trashFailed, "", prompt, Status.armLive(arm, p)).text, trashFailed[0].text)
    check("and an older error shows again, detail and all", Status.transientOf(older, "", prompt, Status.armLive(arm, p)).detail,
          "No space left on device")
    p.trashArmedAt = arm.stamp + 1
    check("a fresh arm's new stamp leaves the old record dead", Status.armLive(arm, p), false)
    // The Trash view is an owner like the pane, watched the same way, with no unwatched kind left.
    var view = { trashArmedAt: 2000 }
    var viewArm = Status.armOf(view, 2000)
    check("the Trash view's arm lives while its stamp stands", Status.armLive(viewArm, view), true)
    view.trashArmedAt = 0
    check("and ends when the view zeroes it, on any other key or the second d", Status.armLive(viewArm, view), false)
    check("a prompt said before its owner armed is no arm at all", Status.armLive(Status.armOf(view, 0), view), false)
    var said = Status.armOf(view, 1000)
    check("the arm ends on its owner's clock, the stamp, never on when the bar heard of it",
          Status.armLeft(said, 1000 + Trash.ARM_MS - 1, Trash.ARM_MS) + "|" + Status.armLeft(said, 1000 + Trash.ARM_MS, Trash.ARM_MS)
          + "|" + Status.armLeft(said, 1500, Trash.ARM_MS), "1|0|" + (Trash.ARM_MS - 500))
    check("a live prompt is not the notice the strip times out", Status.noticeShown(slot({ transient: prompt, armLive: true })), false)
    check("while a plain notice with nothing over it is", Status.noticeShown(slot({ transient: "Renamed to notes.txt" })), true)
    check("and one behind the search is not",
          Status.noticeShown(slot({ transient: "Renamed to notes.txt", searching: true, searchLine: "3 found" })), false)
    // The refusal belongs to the place that has no Trash: leaving it drops it, and another d there replaces it where it stands.
    var share = "/run/user/1000/gvfs/mtp:host=SAMSUNG_Android"
    var refused = Status.withError(Status.withError(older, Status.noTrashLine(), "", share), Status.noTrashLine(), "", share)
    check("a second refusal in the same place replaces the first", refused.length, 2)
    check("and names that place", refused[1].place, share)
    var queued = Status.withError(Status.withError([], Status.noTrashLine(), "", share), "Copy failed: a.txt · disk full", "", share)
    check("in its own slot, so a newer error never moves ahead of it",
          Status.withError(queued, Status.noTrashLine(), "", share).map(function (e) { return e.text }).join("|"),
          Status.noTrashLine() + "|Copy failed: a.txt · disk full")
    check("while any other error names none", Status.withError([], "Copy failed", "", share)[0].place, "")
    check("staying in the place keeps the refusal", Status.errorsAt(refused, share), refused)
    var away = Status.errorsAt(refused, "/run/user/1000/gvfs")
    check("leaving it drops the refusal and keeps every other error", JSON.stringify(away), JSON.stringify(older))
    check("so the folder above carries nothing of it", Status.transientOf(Status.errorsAt(
        Status.withError([], Status.noTrashLine(), "", share), "/run/user/1000/gvfs"), "").text, "")

    // V7: the clipboard's own hint joins the undo hint on the secondary, so no sentence here ends
    // in advice. ui/js/Ops.js builds both into its result lines and this is what takes them apart.
    check("an undoable result carries the undo hint", Status.hintOf("Moved 4 items to Trash · z undoes"), " · z undoes")
    check("a clipboard result carries the paste hint", Status.hintOf("Copied 1 item · p pastes"), " · p pastes")
    check("a plain result carries neither", Status.hintOf("Renamed to notes.txt"), "")
    // A refusal where gio has no Trash carries its key hint the same way, so the strip draws the
    // place in the primary and the key beside it, and a failure without one carries neither.
    check("a trash refusal carries its key hint", Status.hintOf("This location has no Trash · shift-delete deletes"), " · shift-delete deletes")
    check("and the secondary is handed the key alone", Status.hintKey(Status.trashHint()), "shift-delete deletes")
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

    // Durability callout 6: "z undoes" takes a click, the same as z, on every line that carries it.
    check("the undo segment lifts out of a plain hint", Status.withoutUndoKey("z undoes"), "")
    check("and out of an error hint beside esc",
          Status.withoutUndoKey("esc dismisses · z undoes"), "esc dismisses")
    check("while a hint with no undo stays whole", Status.withoutUndoKey("esc dismisses"), "esc dismisses")
    check("and an empty hint stays empty", Status.withoutUndoKey(""), "")
    check("the secondary draws the hint the way it always did",
          Status.secondaryText("z undoes", false, false, "", [], false, "", ""), " · z undoes")
    check("the rest without it draws the same line minus the segment",
          Status.secondaryText("", false, false, "", [], false, "", ""), "")
    check("an error keeps esc beside the undo it carries",
          Status.secondaryText("esc dismisses · z undoes", true, false, "", [], false, "", ""),
          " · esc dismisses · z undoes")
    check("a live activity still stands over an error in the secondary",
          Status.secondaryText("esc dismisses", true, true, "Converting 1 of 3", [], false, "", ""),
          " · esc dismisses · Converting 1 of 3")
    check("a search still reports beside a live activity",
          Status.secondaryText("", false, true, "", [], true, "3 found", ""), " · 3 found")
    check("and a retry line still reports",
          Status.secondaryText("", false, false, "", [], false, "", "c.txt selected for retry"),
          " · c.txt selected for retry")

    // The click is the key: both reach the backend through Ops.undo on the strip's own pane.
    var undone = []
    Ops.undo({ backend: { undo: function () { undone.push("undo") } } })
    check("a click on z undoes sends the backend's undo", undone.join(","), "undo")
    check("the z key routes through Ops.undo",
          sourceText("../../ui/js/Focus.js").indexOf('case "undo": Ops.undo(root);') >= 0, true)
    check("a click on z undoes routes through the same Ops.undo",
          sourceText("../../ui/StatusBar.qml").indexOf("Ops.undo(root.pane)") >= 0, true)
}

function sourceText(url) {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl(url), false)
    request.send()
    return String(request.responseText || "")
}
