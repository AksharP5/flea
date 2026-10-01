import QtQuick
import "flea"
import "flea" as Flea
import "flea/js/Filter.js" as Filter

// The real GridArea and GridTile must retain and contain a bottom editor through global cell reflow.
Window {
    id: probe
    width: 1000
    height: 700
    visible: true
    property int step: 0
    property int checks: 0
    property int failures: 0
    property int plainHeight: 0
    property int heightChanges: 0
    property int replacementChanges: 0
    property var pendingRequest: ({source: "/fixture/f1199.txt", destination: "/fixture/pending.md"})
    function check(ok, label) {
        checks++
        if (!ok) {
            failures++
            console.log("RENAME_GRID_BOTTOM FAIL " + label)
        }
    }
    function editor() {
        var tile = view.itemAtIndex(editPane.renamingIndex)
        return tile ? tile.editorField : null
    }
    function geometry(label) {
        var field = probe.editor()
        var top = field ? field.mapToItem(view, 0, 0).y : -1
        console.log("RENAME_GRID_BOTTOM " + label + " index=" + editPane.renamingIndex
            + " cellHeight=" + view.cellHeight + " contentY=" + view.contentY
            + " top=" + top + " bottom=" + (field ? top + field.height : -1))
    }
    function contained() {
        var field = probe.editor()
        if (!field) return false
        var top = field.mapToItem(view, 0, 0).y
        return top >= 0 && top + field.height <= view.height
    }

    QtObject {
        id: editPane
        property int shownTotal: 1202
        property int total: shownTotal
        property var shown: null
        property int cursorIndex: 0
        property int renamingIndex: -1
        property string renameError: ""
        property var renameRequest: null
        readonly property bool renamePending: renameRequest !== null
        property var selectionBand: null
        property var clipboard: null
        property var thumbState: ({file: {}, order: []})
        property var dirSizeState: ({file: {}, order: []})
        property var rows: []
        property int held: 0
        property int refetchMargin: 0
        property int buffer: 0
        property int windowSize: 350
        property bool listInFlight: false
        property bool storageKnown: false
        property string storageClass: "local"
        property int previewIndex: -1
        property string filterQuery: ""
        property int coalesceMs: 16
        property int settleMs: 10000
        property int firstSettleMs: 10000
        property var backend: QtObject { function window(start, count) {} }
        onRenamingIndexChanged: if (renamingIndex < 0) renameError = ""
        function rowFor(index) { return {n: "f" + ("0000" + (index - 2)).slice(-4) + ".txt", d: false, i: "file", p: 0} }
        function isSelected(index) { return false }
        function setCursor(index) { Filter.setCursor(editPane, index) }
        function showRow(index) { view.positionViewAtIndex(index, ListView.Contain); view.restartCoalesce() }
        function commitRename(name) {}
    }
    Flea.GridArea {
        id: view
        width: 1000
        height: 619
        pane: editPane
        onCellHeightChanged: probe.heightChanges++
        menu: QtObject { function close() {} }
    }
    Item { id: menuFocus }
    Item { id: railFocus }
    // A retired context cannot run its methods. Count attempts without hiding QML warnings.
    Item {
        id: retired
        property var editPane: null
        property var editViewport: null
        property int editIndex: -1
        property string editName: ""
        property real extraHeight: 0
        property int methodCalls: 0
        function ownsEdit() { methodCalls++; return false }
    }
    function rejectRetiredPredecessors(field) {
        var identities = ["pane", "viewport", "index", "name"]
        for (var i = 0; i < identities.length; i++) {
            retired.editPane = i === 0 ? menuFocus : editPane
            retired.editViewport = i === 1 ? railFocus : view
            retired.editIndex = i === 2 ? -2 : editPane.renamingIndex
            retired.editName = i === 3 ? "retired.txt" : field.name
            retired.methodCalls = 0
            view.renameEditor = retired
            field.begun = false
            field.begin()
            probe.check(retired.methodCalls === 0 && view.renameEditor === field && field.ownsEdit(),
                "retired " + identities[i] + " identity is rejected before calling its method")
        }
    }
    Timer {
        interval: 80
        running: true
        repeat: true
        onTriggered: {
            if (probe.step === 0) {
                probe.plainHeight = view.cellHeight
                editPane.setCursor(1201)
            }
            if (probe.step === 1) {
                probe.check(view.itemAtIndex(1201) !== null, "End draws actual last tile")
                probe.geometry("before")
                editPane.renamingIndex = 1201
            }
            if (probe.step === 2) {
                probe.geometry("begun")
                var field = probe.editor()
                probe.check(editPane.renamingIndex === 1201 && field && field.begun && field.inputItem.activeFocus,
                    "bottom begin retains editor ownership and focus")
                probe.check(field && field.current === "f1199.txt", "bottom editor holds actual last filename")
                probe.check(probe.contained(), "bottom begin contains complete editor")
                if (!field) {
                    console.log("RENAME_GRID_BOTTOM DONE failures=" + probe.failures)
                    Qt.quit()
                    return
                }
                // Real GridView pooling recreates the same row while its old focused field still lives. Returning in this turn leaves the row visible, so neither delegate may cancel the edit.
                field.inputItem.text = "b-existing.md"
                field.inputItem.select(9, 2)
                probe.check(field.inputItem.selectionStart === 2 && field.inputItem.selectionEnd === 9
                    && field.inputItem.cursorPosition === 2, "draft starts with a reversed selection before replacement")
                var oldField = field
                view.contentY = 0
                editPane.setCursor(1201)
                field = probe.editor()
                probe.check(field && field !== oldField, "real Grid layout creates a replacement same-row editor")
                probe.check(editPane.renamingIndex === 1201 && field && field.inputItem.activeFocus,
                    "stale same-row focus loss cannot release the replacement")
                if (!field) { probe.finish(); return }
                probe.check(field.current === "b-existing.md", "same-row replacement preserves unfinished draft")
                probe.check(field.inputItem.selectionStart === 2 && field.inputItem.selectionEnd === 9
                    && field.inputItem.cursorPosition === 2, "same-row replacement preserves selection and caret direction")
                oldField.queueContainment()
                oldField.visible = false
                oldField.visible = true
                probe.check(field.inputItem.activeFocus, "stale duplicate visibility cannot retake focus")
                // Destroy the old Loader with containment and focus checks still queued in its field.
                oldField.parent.active = false
                probe.check(view.renameEditor === field, "predecessor destruction preserves newer same-row owner")
                editPane.renameError = "b-existing.md already exists. Choose another name to preserve both files."
            }
            if (probe.step === 3) {
                probe.geometry("expanded")
                var failedField = probe.editor()
                probe.check(view.cellHeight > probe.plainHeight, "error expands real Grid cell height")
                probe.check(editPane.renamingIndex === 1201 && failedField && failedField.current === "b-existing.md"
                    && failedField.inputItem.activeFocus, "error reflow retains draft and focus")
                probe.check(probe.contained(), "error reflow contains complete editor")
                if (!failedField) { probe.finish(); return }
                // FastScrollHandler writes contentY directly. Stop with one pixel of the editor visible.
                view.contentY = view.contentY + failedField.mapToItem(view, 0, 0).y + failedField.height - 1
            }
            if (probe.step === 4) {
                var partial = probe.editor()
                probe.check(editPane.renamingIndex === 1201 && partial && partial.current === "b-existing.md"
                    && partial.inputItem.activeFocus, "partially visible draft remains editable")
                view.contentY = 0
            }
            if (probe.step === 5) {
                probe.check(editPane.renamingIndex === -1 && editPane.renameError === "", "scroll departure releases draft and error")
                probe.check(view.cellHeight === probe.plainHeight && view.activeFocus, "scroll release restores geometry and listing focus")
                editPane.setCursor(1201)
                editPane.renamingIndex = 1201
            }
            if (probe.step === 6) {
                var pending = probe.editor()
                if (!pending) { probe.check(false, "pending field exists"); probe.finish(); return }
                pending.inputItem.text = "pending.md"
                editPane.renameRequest = probe.pendingRequest
                pending.inputItem.select(4, 4)
                probe.check(pending.inputItem.readOnly && !pending.commit(), "pending submit is guarded before scroll")
                var pendingPredecessor = pending
                view.contentY = 0
                editPane.setCursor(1201)
                pending = probe.editor()
                console.log("RENAME_GRID_BOTTOM pending-replacement predecessor=" + pendingPredecessor
                    + " replacement=" + pending + " changed=" + (pending !== pendingPredecessor))
                probe.check(pending && pending !== pendingPredecessor && editPane.renameRequest === probe.pendingRequest,
                    "real Grid layout replaces same-row editor while write is pending")
                probe.check(pending && pending.current === "pending.md", "pending replacement preserves submitted draft")
                probe.check(pending && pending.inputItem.cursorPosition === 4
                    && pending.inputItem.selectionStart === 4 && pending.inputItem.selectionEnd === 4,
                    "pending replacement preserves collapsed caret")
                probe.check(pending && pending.inputItem.readOnly && !pending.commit(), "pending replacement keeps submit guarded")
                view.contentY = 0
            }
            if (probe.step === 7) {
                // Grid can retain a focused delegate outside itemAtIndex's held window.
                probe.check(editPane.renamingIndex === 1201 && editPane.renameRequest === probe.pendingRequest,
                    "pending scroll never releases backend write ownership")
                editPane.setCursor(1201)
            }
            if (probe.step === 8) {
                var retained = probe.editor()
                probe.check(retained && retained.inputItem.readOnly && !retained.commit(), "pending submit guard survives real Grid scroll")
                probe.check(retained && retained.current === "pending.md", "pending scroll retains submitted draft")
                probe.check(retained && retained.inputItem.cursorPosition === 4
                    && retained.inputItem.selectionStart === 4 && retained.inputItem.selectionEnd === 4,
                    "pending scroll retains collapsed caret")
                view.visible = false
                view.contentY = 0
            }
            if (probe.step === 9) {
                probe.check(editPane.renamingIndex === 1201 && editPane.renameRequest === probe.pendingRequest,
                    "hidden Grid geometry retains pending ownership")
                editPane.renameRequest = null
                editPane.renamingIndex = -1
                view.visible = true
                editPane.setCursor(1201)
            }
            if (probe.step === 10) {
                // Exercise begin-time cell growth as well as the native 134 px normal-cell case.
                Theme.rowHeight = 111
                editPane.renamingIndex = 1201
            }
            if (probe.step === 11) {
                probe.geometry("tall-begun")
                var tall = probe.editor()
                probe.check(view.cellHeight > probe.plainHeight, "begin changes real Grid cell height")
                probe.check(editPane.renamingIndex === 1201 && tall && tall.inputItem.activeFocus,
                    "begin reflow never synchronously abandons bottom editor")
                probe.check(probe.contained(), "begin reflow contains complete bottom editor")
                if (!tall) { probe.finish(); return }
                tall.inputItem.text = "unrelated-row-draft.md"
                tall.inputItem.select(3, 12)
                // Queue departure, then replace that editor in the same turn. The queued check is stale.
                probe.replacementChanges = probe.heightChanges
                view.contentY = 0
                editPane.renamingIndex = -1
                editPane.setCursor(0)
                editPane.renamingIndex = 0
            }
            if (probe.step === 12) {
                probe.check(probe.heightChanges === probe.replacementChanges, "same-height row replacement never collapses global cells")
                var replacement = probe.editor()
                probe.check(editPane.renamingIndex === 0 && replacement && replacement.begun
                    && replacement.inputItem.activeFocus, "old queued departure cannot abandon replacement editor")
                probe.check(replacement && replacement.current === editPane.rowFor(0).n
                    && replacement.inputItem.selectionStart === 0 && replacement.inputItem.selectionEnd === replacement.stemEnd
                    && replacement.inputItem.cursorPosition === replacement.stemEnd,
                    "different-row owner cannot pass its draft or selection to a fresh edit")
                probe.check(probe.contained(), "replacement editor remains contained")
                if (!replacement) { probe.finish(); return }
                probe.rejectRetiredPredecessors(replacement)
                view.hiddenHeld = true
                view.contentY = view.contentHeight - view.height
            }
            if (probe.step === 13) {
                probe.check(editPane.renamingIndex === 0, "hiddenHeld blocks departure judgment")
                view.hiddenHeld = false
                editPane.setCursor(0)
            }
            if (probe.step === 14) {
                view.contentY = view.contentHeight - view.height
                editPane.renameRequest = probe.pendingRequest
            }
            if (probe.step === 15) {
                probe.check(editPane.renamingIndex === 0 && editPane.renameRequest === probe.pendingRequest,
                    "queued departure rechecks a write that became pending")
                editPane.setCursor(0)
                editPane.renameRequest = null
            }
            if (probe.step === 16) {
                probe.replacementChanges = probe.heightChanges
                var replacementHeight = view.cellHeight
                editPane.renameError = "A refusal queued for the old editor."
                editPane.renamingIndex = -1
                probe.check(view.renameEditor === null && view.cellHeight === replacementHeight,
                    "old destruction clears identity without synchronous global height reflow")
                editPane.setCursor(1)
                editPane.renamingIndex = 1
            }
            if (probe.step === 17) {
                probe.check(probe.heightChanges === probe.replacementChanges, "later editor waits for measurement without intermediate cell reflow")
                var newest = probe.editor()
                probe.check(editPane.renamingIndex === 1 && newest && newest.inputItem.activeFocus,
                    "stale containment cannot move focus or release a later editor")
                probe.check(probe.contained(), "later editor owns its containment")
                view.visible = false
            }
            if (probe.step === 18) {
                probe.check(editPane.renamingIndex === -1 && editPane.renameError === "", "nonpending hide still abandons")
                view.visible = true
                editPane.setCursor(1201)
                editPane.renamingIndex = 1201
            }
            if (probe.step === 19) {
                probe.check(probe.editor() && probe.editor().inputItem.activeFocus, "fresh editor begins before menu focus loss")
                var menuPredecessor = probe.editor()
                menuFocus.forceActiveFocus()
                view.contentY = 0
                editPane.setCursor(1201)
                probe.check(probe.editor() && probe.editor() !== menuPredecessor, "Grid replaces same-row editor after menu takes focus")
                probe.check(menuFocus.activeFocus, "same-row replacement cannot steal menu focus")
            }
            if (probe.step === 20) {
                probe.check(editPane.renamingIndex === -1 && menuFocus.activeFocus, "real menu focus loss cancels without reclaiming focus")
                editPane.renamingIndex = 1201
            }
            if (probe.step === 21) {
                var railPredecessor = probe.editor()
                railFocus.forceActiveFocus()
                view.contentY = 0
                editPane.setCursor(1201)
                probe.check(probe.editor() && probe.editor() !== railPredecessor, "Grid replaces same-row editor after rail takes focus")
                probe.check(railFocus.activeFocus, "same-row replacement cannot steal rail focus")
            }
            if (probe.step === 22) {
                probe.check(editPane.renamingIndex === -1 && railFocus.activeFocus, "real rail focus loss cancels without reclaiming focus")
                editPane.renamingIndex = 1201
            }
            if (probe.step === 23) {
                var doomed = probe.editor()
                probe.check(doomed && doomed.inputItem.activeFocus, "owned editor exists before Loader destruction")
                if (!doomed) { probe.finish(); return }
                var doomedLoader = doomed.parent, retiringHeight = view.cellHeight
                doomed.inputItem.text = "retirement-draft.md"
                doomed.inputItem.select(12, 3)
                doomed.queueContainment()
                doomedLoader.active = false
                probe.check(view.renameEditor === null, "owned destruction clears viewport reference in the same turn")
                probe.check(view.cellHeight === retiringHeight && editPane.renamingIndex === 1201,
                    "current destruction defers height reflow and ownership judgment")
                doomedLoader.active = true
                var reborn = probe.editor()
                probe.check(reborn && reborn !== doomed && reborn.ownsEdit() && reborn.inputItem.activeFocus,
                    "real Loader recreation takes ownership after its predecessor is dead")
                probe.check(reborn && reborn.current === "retirement-draft.md",
                    "dead predecessor passes only copied unfinished draft to same-row replacement")
                probe.check(reborn && reborn.inputItem.selectionStart === 3 && reborn.inputItem.selectionEnd === 12
                    && reborn.inputItem.cursorPosition === 3, "dead predecessor preserves reversed selection and caret")
                probe.check(view.renameRetirement === null && view.cellHeight === retiringHeight,
                    "newer owner consumes retirement without reentering global layout")
                doomedLoader.active = false
                probe.check(view.renameEditor === null, "replacement destruction also clears callable identity immediately")
            }
            if (probe.step === 24) {
                probe.check(editPane.renamingIndex === -1 && view.activeFocus, "owned destruction releases edit and queued work")
                probe.check(view.renameRetirement === null && view.cellHeight === probe.plainHeight,
                    "viewport settles unclaimed retirement and restores plain height")
                editPane.setCursor(0)
                editPane.renamingIndex = 0
            }
            if (probe.step === 25) {
                var pendingDoomed = probe.editor()
                probe.check(pendingDoomed && pendingDoomed.begun && view.renameEditor === pendingDoomed,
                    "pending destruction starts with an owned editor")
                if (!pendingDoomed) { probe.finish(); return }
                editPane.renameRequest = probe.pendingRequest
                var pendingHeight = view.cellHeight
                pendingDoomed.queueContainment()
                pendingDoomed.parent.active = false
                probe.check(view.renameEditor === null, "pending destruction clears viewport reference in the same turn")
                probe.check(view.cellHeight === pendingHeight && editPane.renameRequest === probe.pendingRequest,
                    "pending retirement changes neither global height nor submitted write synchronously")
            }
            if (probe.step === 26) {
                probe.check(editPane.renamingIndex === 0 && editPane.renameRequest === probe.pendingRequest,
                    "pending destruction cannot emit abandonment or release backend write")
                editPane.renameRequest = null
                editPane.renamingIndex = -1
                probe.finish()
            }
            probe.step++
        }
    }
    function finish() {
        console.log("RENAME_GRID_BOTTOM CHECKS=" + probe.checks)
        console.log("RENAME_GRID_BOTTOM DONE failures=" + probe.failures)
        Qt.quit()
    }
}
