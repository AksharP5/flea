import QtQuick
import "flea"
import "flea" as Flea
import "@UI@/js/Filter.js" as Filter
import "@UI@/js/Thumbs.js" as Thumbs
import "@UI@/js/DirSizes.js" as DirSizes

// rename-lifecycle-check.js inserts the unchanged List geometry, Row Loader and Pane.showRow. Real Qt discards an expanded delegate, shifts originY, then runs the Home action once.
Window {
    id: probe
    width: 1000
    height: 700
    visible: true
    property int step: 0
    property int failures: 0

    function check(ok, label) {
        if (!ok) {
            failures++
            console.log("RENAME_SCROLL FAIL origin " + label)
        }
    }
    function geometry(label) {
        console.log("RENAME_ORIGIN " + label + " contentY=" + view.contentY + " originY=" + view.originY
            + " first=" + view.visibleRange().first + " cursor=" + editPane.cursorIndex
            + " row0=" + (view.itemAtIndex(0) ? view.itemAtIndex(0).y : "discarded"))
    }

    component ProbePane: QtObject {
        id: root
        property var listArea: null
        property int shownTotal: 1202
        property int total: shownTotal
        property var shown: null
        property int cursorIndex: 0
        property int renamingIndex: -1
        property string renameError: ""
        property bool renamePending: false
        property var selectionBand: null
        property int visibleRows: Math.ceil(listArea.height / Theme.fileRowHeight)
        property var dirSizeState: ({file: {}, order: []})
        property var rows: []
        property int held: 0
        property int refetchMargin: 0
        property int buffer: 0
        property int windowSize: 25
        property bool listInFlight: false
        property var backend: QtObject {
            property int asked: -1
            function window(start, count) { asked = start }
            function dirsizecancel() {}
        }
        onRenamingIndexChanged: if (renamingIndex < 0) renameError = ""
        function setCursor(index) { Filter.setCursor(root, index) }
        /* PANE_SHOW_ROW */
    }

    component ProbeList: ListView {
        id: root
        property var pane: null
        property var menu: QtObject { function close() {} }
        property bool hiddenHeld: false
        model: (visible || pane.renamingIndex >= 0) ? pane.shownTotal : 0
        clip: true
        focus: true
        reuseItems: true
        cacheBuffer: 0
        boundsBehavior: Flickable.StopAtBounds
        signal cursorClamped(int first, int last)
        signal dirSizesCancelled()
        onCursorClamped: function(first, last) { Filter.clampCursor(pane, first, last) }
        Timer { id: coalesce; interval: 16; onTriggered: root.requestIfDrifted() }
        Timer { id: settle; interval: 10000 }
        /* LIST_GEOMETRY */
        delegate: Item {
            id: root
            required property int index
            property var renamePane: editPane
            property string displayName: index === 0 ? "a-original.md" : "b-existing.md"
            property bool modeShown: false
            property bool renaming: index === editPane.renamingIndex
            property var editor: renameLoader.item
            width: view.width
            height: renaming && editor ? Math.max(Theme.rowHeight, editor.implicitHeight + 8) : Theme.rowHeight
            signal renameCommitted(string name)
            signal renameAbandoned()
            onRenameAbandoned: editPane.renamingIndex = -1
            Item { id: icon; width: 16 }
            Item { id: mode; x: root.width }
            /* ROW_LOADER */
        }
    }

    ProbePane { id: editPane; listArea: view }
    ProbeList { id: view; width: 1000; height: 619; pane: editPane }
    Timer {
        interval: 80
        running: true
        repeat: true
        onTriggered: {
            var cell = view.currentItem
            if (probe.step === 0) {
                probe.geometry("plain")
                probe.check(view.visibleRange().first === 0 && view.coversCursor(0), "plain origin covers first row")
                editPane.renamingIndex = 0
            }
            if (probe.step === 1) {
                probe.check(cell && cell.editor && cell.editor.begun, "field began")
                cell.editor.inputItem.text = "b-existing.md"
                editPane.renameError = "b-existing.md already exists."
            }
            if (probe.step === 2) {
                probe.check(cell.height > Theme.rowHeight, "error expanded row")
                probe.geometry("expanded")
                view.contentY = Math.max(view.originY, view.originY + view.contentHeight - view.height)
            }
            if (probe.step === 3) {
                probe.check(editPane.renamingIndex === -1 && editPane.renameError === "", "offscreen edit released")
                probe.geometry("discarded")
                // This is the Home action from Focus.js, through unchanged Filter and Pane.showRow.
                Filter.setCursorView(editPane, 0)
            }
            if (probe.step === 4) {
                probe.geometry("home")
                probe.check(view.originY !== 0, "control produced shifted Qt origin")
                probe.check(editPane.cursorIndex === 0 && view.itemAtIndex(0) && view.itemAtIndex(0).height > 0, "one Home restores first cursor row")
                probe.check(view.coversCursor(0), "restore coverage includes shifted first row")
                probe.check(view.visibleRange().first === 0, "visible work starts at first row")
                view.requestIfDrifted()
                probe.check(editPane.backend.asked === 0, "held-window request starts at first row")
                view.contentY = view.originY + Theme.rowHeight + 1
            }
            if (probe.step === 5) {
                probe.check(editPane.cursorIndex === 1 && view.visibleRange().first === 1, "ordinary scroll follows relative row offset")
                view.requestIfDrifted()
                probe.check(editPane.backend.asked === 1 && view.coversCursor(1), "scroll keeps held work and restore coverage aligned")
                Filter.setCursorView(editPane, editPane.shownTotal - 1)
            }
            if (probe.step === 6) {
                probe.geometry("end")
                probe.check(editPane.cursorIndex === 1201 && view.itemAtIndex(1201), "one End restores last cursor row")
                console.log("RENAME_SCROLL DONE origin failures=" + probe.failures)
                Qt.quit()
            }
            probe.step++
        }
    }
}
