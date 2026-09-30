//@ pragma ShellId flea-scrollfill-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Scroll.js" as Scroll

// e52 scroll-fill: state fills paint under the reserved lane while delegates keep contentWidth.
ShellRoot {
    id: root

    property var failures: []
    function fail(text) { root.failures.push(text) }

    property var sampleRows: [
        { n: "a.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "b.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "adir", d: true, i: "folder", p: 493, s: 4096, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "c.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 }
    ]

    Component {
        id: backendStub
        QtObject {
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
        }
    }

    Component {
        id: statusBarStub
        QtObject {
            property var activities: []
            property var dragFeedbackOwner: null
            function setActivity(owner, text, transfer) {}
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 4
            property int total: 4
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property string searchMode: ""
            property string searchQuery: ""
            property string filterQuery: ""
            property var selectionBand: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property int visibleRows: 8
            property int cacheRows: 0
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            property var statusBar: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return index === 1 }
            function commitRename(newName) {}
        }
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    Component {
        id: pickerStub
        QtObject {
            property string path: "/probe"
            property int shownTotal: 3
            property int total: 3
            property int held: 0
            property var rows: []
            property int cursorIndex: 0
            property var marks: [{ path: "/probe/b.txt", bytes: 1 }]
            property var kindNames: []
            property bool recent: false
            property bool folderMode: false
            property int windowSize: 35
            property bool backendUnavailable: true
            property int pendingListings: 0
            function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
            function toggleMark(index) {}
            function doubleActivate(index, rowPath, firstPath) {}
            function activate(index) {}
            function goUp() {}
            function goBack() {}
            function requestSort(order) {}
            function cancel() {}
            function stepFocus(item, back) {}
            function openWithoutHistory(path) {}
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubStatusBar: statusBarStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, statusBar: root.stubStatusBar, rows: root.sampleRows })
    property var stubPicker: pickerStub.createObject(root, { rows: root.sampleRows.slice(0, 3) })

    Flea.List {
        id: list
        width: 700
        height: 300
        pane: root.stubPane
        menu: menuStub.createObject(root)
    }

    Flea.ColumnPane {
        id: col
        x: 0
        y: 310
        width: 400
        height: 200
        rows: root.sampleRows
        selectedIndex: 2
        liftedName: "adir"
    }

    Flea.PickerList {
        id: pick
        x: 0
        y: 520
        width: 700
        height: 200
        picker: root.stubPicker
        backend: root.stubBackend
    }

    // Standalone drop probes: the wash shares the state fill's own extent object.
    Flea.Row {
        id: dropRow
        x: 0
        y: 730
        width: 600
        paintWidth: 700
        row: root.sampleRows[0]
        kindNames: []
        hiddenCols: []
        dropTarget: true
    }

    Flea.ColumnRow {
        id: dropCol
        x: 0
        y: 770
        width: 300
        paintWidth: 400
        row: root.sampleRows[2]
        dropTarget: true
    }

    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.phaseWide12()
    }
    Timer { id: t14; interval: 400; repeat: false; onTriggered: root.phaseWide14() }
    Timer { id: tNarrow; interval: 400; repeat: false; onTriggered: root.phaseNarrow() }
    Timer { id: tDrop; interval: 400; repeat: false; onTriggered: root.phaseDrop() }

    // Half-pixel tolerance matching the 0.5 below: lanes round to whole pixels, so exact equality would flake.
    function near(a, b) { return Math.abs(Number(a) - Number(b)) <= 0.5 }

    function checkList(label) {
        if (list.count !== 4) { root.fail(label + " lists " + list.count + ", want 4"); return }
        if (!list.clip) root.fail(label + " loses viewport clipping")
        var lane = Flea.Theme.spacing.rowPaddingX
        var wantContent = Scroll.contentWidth(list.width, lane)
        if (!root.near(list.rowWidth, wantContent))
            root.fail(label + " rowWidth " + list.rowWidth + ", want content " + wantContent)
        for (var i = 0; i < 4; i++) {
            var d = list.itemAtIndex(i)
            if (d === null) { root.fail(label + " builds no delegate at " + i); continue }
            if (d.clip === true) root.fail(label + " clips row " + i + ", hiding the lane fill")
            if (!root.near(d.width, wantContent))
                root.fail(label + " delegate " + i + " width " + d.width + ", want " + wantContent)
            var fill = d.children.length > 0 ? d.children[0].width : -1
            if (!root.near(fill, list.width))
                root.fail(label + " row " + i + " paints " + fill + ", want viewport " + list.width)
            if (d.assignedNameBudget !== list.nameBudgetPlain)
                root.fail(label + " row " + i + " budgets " + d.assignedNameBudget + ", want shared " + list.nameBudgetPlain)
        }
        // Cursor and selected share the one fill object, so geometry covers hover too.
        var c0 = list.itemAtIndex(0)
        var c1 = list.itemAtIndex(1)
        if (c0 !== null && c0.cursor !== true) root.fail(label + " misses cursor on 0")
        if (c1 !== null && c1.selected !== true) root.fail(label + " misses selection on 1")
    }

    function checkCol(label) {
        var lane = Flea.Theme.spacing.rowPaddingX
        var wantContent = Scroll.contentWidth(col.width, lane)
        var d = null
        try { d = col.itemAtIndex(2) } catch (e) { d = null }
        if (d === null) { root.fail(label + " builds no column delegate"); return }
        if (d.clip === true) root.fail(label + " clips column row, hiding the lane fill")
        if (!root.near(d.width, wantContent))
            root.fail(label + " column width " + d.width + ", want " + wantContent)
        var fill = d.children.length > 0 ? d.children[0].width : -1
        var viewW = col.width
        if (!root.near(fill, viewW))
            root.fail(label + " column paints " + fill + ", want viewport " + viewW)
    }

    function checkPicker(label) {
        if (pick.count !== 3) { root.fail(label + " picks " + pick.count + ", want 3"); return }
        if (!pick.clip) root.fail(label + " picker loses viewport clipping")
        var lane = Flea.Theme.spacing.rowPaddingX
        var wantContent = Scroll.contentWidth(pick.width, lane)
        for (var i = 0; i < 3; i++) {
            var cell = pick.itemAtIndex(i)
            if (cell === null) { root.fail(label + " builds no picker cell at " + i); continue }
            if (!root.near(cell.width, wantContent))
                root.fail(label + " picker cell " + i + " width " + cell.width + ", want " + wantContent)
            var markFill = cell.children.length > 0 ? cell.children[0].width : -1
            // Only the marked row builds its fill; the rest prove the lane by the embedded Row below.
            if (i === 1 && !root.near(markFill, pick.width))
                root.fail(label + " picker mark paints " + markFill + ", want viewport " + pick.width)
            if (cell.children.length < 3) { root.fail(label + " picker cell " + i + " builds no Row"); continue }
            var row = cell.children[2]
            if (row.clip === true) root.fail(label + " picker clips Row " + i)
            var rowFill = row.children.length > 0 ? row.children[0].width : -1
            if (i === 0 && !root.near(rowFill, pick.width))
                root.fail(label + " picker cursor paints " + rowFill + ", want viewport " + pick.width)
        }
    }

    function checkDrop(label, viewW) {
        var wash = dropRow.children.length > 2 && dropRow.children[2].item
            ? dropRow.children[2].item.children[0].width : -1
        if (!root.near(wash, viewW))
            root.fail(label + " drop wash paints " + wash + ", want viewport " + viewW)
        if (!(dropRow.nameRight() < dropRow.dropLabelLeft()))
            root.fail(label + " drop label moved over the name")
        var cw = dropCol.children.length > 2 && dropCol.children[2].item ? dropCol.children[2].item.width : -1
        if (!root.near(cw, 400))
            root.fail(label + " column wash paints " + cw + ", want viewport 400")
    }

    function phaseWide12() {
        Flea.ViewState.state = { display: { textSize: { mode: 12 } } }
        root.checkList("wide12")
        root.checkCol("wide12")
        root.checkPicker("wide12")
        if (root.failures.length > 0) { root.report(); return }
        t14.start()
    }

    function phaseWide14() {
        Flea.ViewState.state = { display: { textSize: { mode: 14 } } }
        root.checkList("wide14")
        root.checkCol("wide14")
        root.checkPicker("wide14")
        if (root.failures.length > 0) { root.report(); return }
        list.width = 240
        col.width = 200
        pick.width = 240
        tNarrow.start()
    }

    function phaseNarrow() {
        root.checkList("narrow")
        root.checkCol("narrow")
        root.checkPicker("narrow")
        if (root.failures.length > 0) { root.report(); return }
        list.width = 700
        col.width = 400
        pick.width = 700
        root.stubPane.paneFocused = false
        tDrop.start()
    }

    function phaseDrop() {
        root.checkList("inactive")
        root.checkDrop("drop", 700)
        if (root.failures.length > 0) { root.report(); return }
        Flea.ViewState.state = {}
        console.log("SCROLLFILL PASS list=" + list.width + " col=" + col.width + " pick=" + pick.width)
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("SCROLLFILL FAIL " + root.failures[f])
        console.log("SCROLLFILL DONE failures=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
