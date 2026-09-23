import QtQuick
import "js/Collide.js" as Collide
import "js/Ops.js" as Ops

// A pane's question before a transfer lands on names that exist: the transfer waits here, so Cancel sends nothing.
Loader {
    id: root
    required property var pane
    anchors.fill: parent
    z: 2
    // Built by the first question that collides, see AGENTS.md rule 6: a hidden card is not a free one.
    active: false
    source: "CollideConfirm.qml"
    readonly property bool opened: item !== null && item.opened
    // The transfer waiting on the answer, or null, and whether sending it spends a cut clipboard.
    property var pending: null
    property bool spendsCut: false
    property int askId: 0

    // A cut is spent when its transfer goes out, so a Cancel leaves it on the clipboard to paste elsewhere.
    function ask(request, probe, cut) {
        var refused = Collide.refusal(root.opened, root.pending)
        if (refused.length > 0) {
            root.pane.message(refused, false)
            return false
        }
        root.askId += 1
        // Its rows keep the numbering they were read in, so a listing landing before the answer gets the transfer refused, not resolved anew.
        root.pending = Collide.waiting(request, root.pane.backend.heldListing)
        root.spendsCut = cut === true
        root.pane.backend.send(Collide.question(root.pending, probe, root.askId))
        return true
    }

    // Nothing collided: the transfer goes out as it would have, carrying the refusal for any late name.
    function answered(id, total, names) {
        if (id !== root.askId || root.pending === null)
            return
        if (total === 0) {
            root.decide(Collide.NONE)
            return
        }
        root.active = true
        root.item.open(Collide.title(names, total, root.pending.dest), names, Collide.more(total, names.length))
    }

    // The transfer is written before pending lets go of it: clearing pending is what frees ui/PaneWire.qml's watched re-read.
    function decide(choice) {
        var request = root.pending
        if (request && choice !== "cancel") {
            root.pane.backend.send(Collide.transfer(request, choice, root.askId))
            if (root.spendsCut)
                root.pane.clipboard = Ops.emptyClipboard()
        }
        root.pending = null
    }

    Connections {
        target: root.pane.backend
        function onCollisions(id, total, names) { root.answered(id, total, names) }
        // A dead backend answers nothing and takes nothing, so the transfer goes; a choice on a card still open then sends nothing and keeps the cut.
        // A refused question never opens the card either, so the wait ends here or the next paste is refused behind it.
        function onFailed(where, input) {
            if (where === "backend" || Collide.droppedPending(where, input))
                root.pending = null
        }
    }
    Connections {
        target: root.item
        function onChosen(choice) {
            root.decide(choice)
            root.pane.listArea.forceActiveFocus()
        }
    }
}
