const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

// Sample input: "    function renameEditor() {\n    }".
function injectPane(fixture, source) {
    const methods = ["renameEditor", "commitOpenRename"].map(name => {
        const match = source.match(new RegExp(`^    function ${name}\\(\\) \\{[\\s\\S]*?^    \\}`, "m"));
        assert.ok(match, `Pane.${name} source is missing`);
        return match[0];
    }).join("\n");
    const wire = fs.readFileSync(path.join(__dirname, "../ui/PaneWire.qml"), "utf8");
    // Sample input: "        function onFailed(where, input, message, mode) {\n        }".
    const failed = wire.match(/^        function onFailed\(where, input, message, mode\) \{[\s\S]*?^        \}/m);
    assert.ok(failed, "PaneWire.onFailed source is missing");
    return fixture.replace('import "flea/js/Ops.js" as Ops', 'import "flea/js/Ops.js" as Ops\nimport "flea/js/Tap.js" as Tap\nimport "flea/js/Errors.js" as Errors')
        .replace("    property int step: 0", `    property Item oldTile: null
    property Item oldField: null
    property Item currentTile: null
    property Item currentField: null
    property int pointerSelections: 0
    property int step: 0`)
        .replace("        property int shownTotal: 1202", `        property var root: editPane
        property var pane: editPane
        property string viewMode: "grid"
        property var listArea: view
        property var observedTile: null
        property var routeItem: null
        property var columnsArea: backend
        property int visibleLookups: 0
        property int columnLookups: 0
        property int submissions: 0
        property var submitted: null
        property int selectionsAtSubmit: -1
        property bool renameKeepsPointerRow: false
        property string searchMode: ""
        function visibleItemFor(index) {
            visibleLookups++
            return observedTile || view.itemAtIndex(Filter.viewOf(shown, index))
        }
        function selectOnly(index) { probe.pointerSelections++; cursorIndex = index }
${methods}
${failed[0].replace("function onFailed(", "function failRename(")}
        property int shownTotal: 1202`)
        .replace("property var backend: QtObject { function window(start, count) {} }", `property var backend: QtObject {
            function window(start, count) {}
            function activeColumn() { editPane.columnLookups++; return editPane.routeItem }
            function rename(source, name, menuId) {
                editPane.submissions++
                editPane.submitted = {source: source, name: name, menuId: menuId}
                editPane.selectionsAtSubmit = probe.pointerSelections
            }
        }`)
        .replace("function commitRename(name) {}", "function commitRename(name) { Ops.commitRename(editPane, name) }");
}

function ownerStep(turn) {
    function visibleOwner(field) {
        if (!field || field !== view.renameEditor || field.editorHost !== view.currentItem) return false
        var point = field.mapToItem(view, field.width / 2, field.fieldHeight / 2)
        return point.y >= 0 && point.y < view.height
            && view.itemAt(point.x + view.contentX, point.y + view.contentY) === field.editorHost
            && view.indexAt(point.x + view.contentX, point.y + view.contentY) === view.currentIndex
    }
    if (turn === 0) {
        view.height = 646
        editPane.setCursor(1201)
        probe.check(view.currentIndex === 1201, "idle End tracks actual cursor in Qt currentIndex")
        editPane.setCursor(0)
        probe.check(view.currentIndex === 0, "idle Home tracks actual cursor in Qt currentIndex")
        editPane.shown = [0, 1201]
        editPane.shownTotal = 2
        editPane.setCursor(1201)
        probe.check(view.currentIndex === 1, "idle filtered cursor uses its actual view position")
        editPane.shown = null
        editPane.shownTotal = 1202
        editPane.setCursor(1201)
    }
    if (turn === 1) {
        Ops.startRename(editPane)
        var field = probe.editor()
        probe.check(field && field.ownsEdit() && field.inputItem.activeFocus,
            "owner fixture begins with actual focused bottom Loader")
        probe.check(view.currentIndex === 1201 && visibleOwner(field),
            "normal bottom F2 registered host is Qt current item at visible editor position")
        editPane.renameError = "A refusal expands the predecessor editor across several caption lines."
    }
    if (turn === 2) {
        probe.check(view.cellHeight > probe.plainHeight && probe.contained(),
            "owner fixture expands and contains actual error editor")
        probe.check(visibleOwner(view.renameEditor), "expanded error keeps registered host in actual current layout slot")
        view.contentY = 0
    }
    if (turn === 3) {
        probe.check(editPane.renamingIndex === -1 && editPane.renameError === "",
            "actual scroll cancels expanded editor before Home and End")
        editPane.setCursor(0)
        editPane.setCursor(1201)
    }
    if (turn === 4) {
        Ops.startRename(editPane)
        probe.oldTile = view.itemAtIndex(1201)
        probe.oldField = probe.oldTile ? probe.oldTile.editorField : null
        probe.check(probe.oldField && probe.oldField.ownsEdit() && probe.oldField.inputItem.activeFocus,
            "F2 after error cancellation begins real last-tile editor")
        if (!probe.oldField) { probe.finish(); return }
        probe.check(view.currentIndex === 1201 && visibleOwner(probe.oldField),
            "error contraction Home End F2 registers actual visible current tile")
        probe.oldField.inputItem.text = "b-existing.md"
    }
    if (turn === 5) {
        Tap.tapped(0, 1, 0, editPane)
        probe.check(editPane.cursorIndex === 0 && editPane.renamePending && view.currentIndex === 1201
            && probe.oldField.inputItem.activeFocus && probe.oldField.current === "b-existing.md"
            && visibleOwner(probe.oldField), "pending click-away holds edit current item focus and draft as logical cursor moves")
    }
    if (turn === 6) {
        probe.check(editPane.cursorIndex === 0 && editPane.renamePending && view.currentIndex === 1201
            && probe.oldField.inputItem.activeFocus && probe.oldField.current === "b-existing.md"
            && visibleOwner(probe.oldField), "pending click-away retains actual visible draft on a later turn before reply")
        editPane.failRename("rename", "/fixture/f1199.txt", "File exists", 0)
    }
    if (turn === 7) {
        var refused = view.renameEditor
        probe.check(!editPane.renamePending && editPane.renamingIndex === 1201
            && editPane.renameError === "b-existing.md already exists." && refused
            && refused.current === "b-existing.md" && !refused.inputItem.readOnly && refused.inputItem.activeFocus
            && visibleOwner(refused), "actual backend refusal keeps draft editable focused in actual visible current tile")
        editPane.renamingIndex = -1
        editPane.submissions = 0
        probe.pointerSelections = 0
        Ops.startRename(editPane)
        probe.oldTile = view.itemAtIndex(1201)
        probe.oldField = probe.oldTile ? probe.oldTile.editorField : null
        if (!probe.oldField) { probe.check(false, "fresh superseded-object control has live editor"); probe.finish(); return }
        // Actual same-row pooling leaves two live Loaders. Qt 6.8 need not return the old one itself.
        view.currentIndex = 0
        view.contentY = 0
        editPane.setCursor(1201)
        probe.currentField = view.renameEditor
        probe.currentTile = probe.currentField ? probe.currentField.parent.parent : null
        probe.check(probe.currentField && probe.currentField !== probe.oldField
            && probe.currentTile && probe.currentTile !== probe.oldTile,
            "real Grid pooling produces distinct live same-row tiles and fields")
        if (!probe.currentField || probe.currentField === probe.oldField) { probe.finish(); return }
        probe.check(probe.oldTile.editorField === probe.oldField
            && probe.currentTile.editorField === probe.currentField,
            "both captured fields still belong to actual live GridTile Loaders")
        probe.check(probe.oldTile.listingIndex === 1201 && probe.currentTile.listingIndex === 1201
            && probe.oldField.editIndex === 1201 && probe.currentField.editIndex === 1201
            && probe.oldTile.row.n === "f1199.txt" && probe.currentTile.row.n === "f1199.txt",
            "both live objects retain identical listing row and filename identity")
        probe.check(!probe.oldField.ownsEdit() && probe.currentField.ownsEdit()
            && view.renameEditor === probe.currentField,
            "only registered replacement owns the edit")
        probe.check(probe.oldField.begun && !probe.oldTile.visible && !probe.oldField.visible
            && !probe.oldField.inputItem.visible,
            "superseded begun live tile and its input are effectively invisible")
        probe.check(probe.currentTile.visible && probe.currentField.visible && probe.currentField.inputItem.visible,
            "registered current host and its editor remain effectively visible")
        var ordinary = view.itemAtIndex(1200)
        probe.check(ordinary && !ordinary.renaming && ordinary.visible,
            "ordinary live neighboring tile remains visible beside superseded host")
        probe.check(probe.currentField.inputItem.activeFocus && probe.currentField.visible
            && probe.currentField.inputItem.selectedText === "f1199",
            "registered replacement retains real focus visibility and stem selection")
        probe.oldField.inputItem.text = "superseded-draft.md"
        probe.currentField.inputItem.text = "click-away-current.md"
        editPane.observedTile = probe.oldTile
        probe.check(editPane.visibleItemFor(1201) === probe.oldTile,
            "lookup control routes to captured real superseded same-row tile")
        editPane.visibleLookups = 0
        var row = editPane.renameEditor()
        probe.check(row === probe.currentTile && row.editorField === view.renameEditor,
            "actual Pane.renameEditor returns current registered owner's GridTile")
        probe.check(row && row.editorText === "click-away-current.md" && row.height === view.cellHeight
            && typeof row.commitEditor === "function",
            "actual Pane lookup retains row API and current draft")
        probe.check(editPane.visibleLookups === 0, "Grid owner lookup never asks stale itemAtIndex route")
        probe.check(!probe.oldField.commit() && editPane.submissions === 0,
            "superseded real editor cannot submit a draft")
        Tap.tapped(0, 1, 0, editPane)
        probe.check(editPane.submissions === 1 && editPane.submitted
            && editPane.submitted.source === "/fixture/f1199.txt"
            && editPane.submitted.name === "click-away-current.md",
            "actual click-away commits current draft once through Pane.commitOpenRename")
        probe.check(editPane.selectionsAtSubmit === 0 && probe.pointerSelections === 1
            && editPane.cursorIndex === 0 && editPane.renameKeepsPointerRow,
            "current-owner draft submits before click-away selects its new row")
        editPane.commitOpenRename()
        probe.check(editPane.submissions === 1 && editPane.renamePending,
            "pending click-away cannot resubmit current draft")
        editPane.viewMode = "list"
        editPane.visibleLookups = 0
        probe.check(editPane.renameEditor() === probe.oldTile && editPane.visibleLookups === 1,
            "List retains existing visibleItemFor route")
        editPane.viewMode = "columns"
        editPane.routeItem = probe.oldTile
        probe.check(editPane.renameEditor() === probe.oldTile && editPane.columnLookups === 2
            && editPane.visibleLookups === 1, "Columns retains existing activeColumn route")
        editPane.routeItem = view.itemAtIndex(1200)
        probe.check(editPane.routeItem && !editPane.routeItem.renaming && editPane.renameEditor() === null,
            "Columns existing route rejects nonrenaming active column")
        var columns = editPane.columnsArea
        editPane.columnsArea = null
        probe.check(editPane.renameEditor() === null, "unloaded Columns retains existing null guard")
        editPane.columnsArea = columns
        editPane.viewMode = "grid"
    }
    if (turn === 8) {
        probe.check(probe.oldTile.editorField === probe.oldField && probe.oldField.begun
            && !probe.oldTile.visible && !probe.oldField.visible,
            "superseded live Loader stays hidden after its queued lifecycle runs")
        probe.check(probe.currentField.ownsEdit() && probe.currentTile.visible
            && probe.currentField.inputItem.activeFocus && probe.currentField.current === "click-away-current.md"
            && editPane.renamePending && editPane.submissions === 1,
            "stale tile hiding cannot cancel or refocus the registered pending draft")
        probe.oldField.parent.active = false
        probe.check(view.renameEditor === probe.currentField && editPane.renameEditor() === probe.currentTile,
            "superseded Loader teardown cannot replace current lookup")
        probe.currentField.visible = false
        probe.check(editPane.renameEditor() === null, "hidden registered field returns null")
        probe.currentField.visible = true
        view.hiddenHeld = true
        probe.check(editPane.renameEditor() === null, "held-hidden Grid returns null")
        view.hiddenHeld = false
        probe.currentField.pane = {renameError: "", renamePending: true, renamingIndex: 1201}
        probe.check(editPane.renameEditor() === null, "foreign editor pane returns null")
        probe.currentField.pane = editPane
        probe.currentField.viewport = null
        probe.check(editPane.renameEditor() === null, "foreign editor viewport returns null")
        probe.currentField.viewport = view
        probe.currentField.name = "another-name.txt"
        probe.check(editPane.renameEditor() === null, "stale edit name returns null")
        probe.currentField.name = "f1199.txt"
        if (probe.currentField.editorHost !== undefined) probe.currentField.editorHost = probe.oldTile
        probe.check(editPane.renameEditor() === null, "superseded tile cannot serve as current field host")
        if (probe.currentField.editorHost !== undefined) probe.currentField.editorHost = probe.currentTile
        probe.check(editPane.renameEditor() === probe.currentTile && probe.currentField.ownsEdit(),
            "restored exact owner identity returns current tile")
        view.visible = false
        probe.check(editPane.renameEditor() === null, "hidden Grid returns null")
        view.visible = true
    }
    if (turn === 9) {
        probe.currentField = view.renameEditor
        probe.currentTile = probe.currentField ? probe.currentField.parent.parent : null
        probe.check(!view.hiddenHeld && probe.currentField && probe.currentField.ownsEdit()
            && editPane.renameEditor() === probe.currentTile,
            "actual Grid restore returns its registered current tile after hidden hold settles")
        if (!probe.currentField) { probe.finish(); return }
        probe.currentField.parent.active = false
        probe.check(view.renameEditor === null && editPane.renameEditor() === null,
            "destroyed current Loader returns null despite stale same-row lookup")
        editPane.listArea = null
        probe.check(editPane.renameEditor() === null, "unloaded Grid returns null")
        editPane.listArea = view
        editPane.renamingIndex = -1
        probe.check(editPane.renameEditor() === null, "closed edit retains existing null guard")
        probe.check(view.renameEditor === null && view.renameRetirement === null,
            "teardown clears registered owner and copied retirement")
        probe.finish()
    }
}

module.exports = {injectPane, ownerStep, checks: 49};
