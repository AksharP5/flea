//@ pragma ShellId flea-columnclip-empty-test

import QtQuick
import Quickshell
import "flea" as Flea
// The same resolved URL ui/ColumnPane.qml imports, so this is the column's own library instance and not a copy.
import "flea/js/ClipMarks.js" as ClipMarks

// w56 columnclip-empty: a real ui/ColumnPane over a stub pane proves the empty-clipboard
// short-circuit; tests/columnclip-empty.sh drives it offscreen.
ShellRoot {
    id: root

    property var failures: []
    property int markedCalls: 0
    property int cutCalls: -1
    property int clearedCalls: -1

    property var sampleRows: [
        { n: "a.txt", d: false, i: "text-x-generic", p: 420, s: 13 },
        { n: "b.txt", d: false, i: "text-x-generic", p: 420, s: 13 },
        { n: "c.txt", d: false, i: "text-x-generic", p: 420, s: 13 },
        { n: "d.txt", d: false, i: "text-x-generic", p: 420, s: 13 },
        { n: "e.txt", d: false, i: "text-x-generic", p: 420, s: 13 },
        { n: "f.txt", d: false, i: "text-x-generic", p: 420, s: 13 },
        { n: "g.txt", d: false, i: "text-x-generic", p: 420, s: 13 },
        { n: "h.txt", d: false, i: "text-x-generic", p: 420, s: 13 },
        { n: "i.txt", d: false, i: "text-x-generic", p: 420, s: 13 },
        { n: "j.txt", d: false, i: "text-x-generic", p: 420, s: 13 }
    ]
    property int copiedIndex: 1
    property var copiedBoard: ({ paths: ["/probe/b.txt"], moving: false })
    property var cutBoard: ({ paths: ["/probe/b.txt"], moving: true })
    property var emptyBoard: ({ paths: [], moving: false })

    Component {
        id: backendStub
        QtObject {
            property int dirDev: 0
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 10
            property int total: 10
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property bool storageKnown: false
            property string storageClass: ""
            property int previewIndex: -1
            property var trash: ({ opened: false })
            property string searchMode: ""
            property var selectionBand: null
            property bool listInFlight: false
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
            function thumbFor(index) { return "" }
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: root.sampleRows })

    Flea.ColumnPane {
        id: column
        width: 400
        height: 185
        pane: root.stubPane
        selectedIndex: 0
    }

    // Delegates are built on the polish pass, so the read waits one turn like mount-listing.qml.
    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.measureEmpty()
    }

    Timer {
        id: copiedTimer
        interval: 600
        repeat: false
        onTriggered: root.measureCopied()
    }
    Timer {
        id: cutTimer
        interval: 600
        repeat: false
        onTriggered: root.measureCut()
    }
    Timer {
        id: clearedTimer
        interval: 600
        repeat: false
        onTriggered: root.measureCleared()
    }
    Timer {
        id: movedTimer
        interval: 600
        repeat: false
        onTriggered: root.measureMoved()
    }
    Timer {
        id: controlTimer
        interval: 600
        repeat: false
        onTriggered: root.measureControl()
    }

    function fail(text) { root.failures.push(text) }

    function delegateAt(i) { return column.itemAtIndex(i) }

    // Delegates outside the viewport are never built, so only built ones are asserted.
    function builtCount() {
        var n = 0
        for (var i = 0; i < root.sampleRows.length; i++)
            if (root.delegateAt(i) !== null) n += 1
        return n
    }

    function checkBlank(label) {
        for (var i = 0; i < root.sampleRows.length; i++) {
            var d = root.delegateAt(i)
            if (d === null) continue
            if (d.clipMark !== "")
                root.fail(label + " draws " + d.clipMark + " on " + root.sampleRows[i].n + ", want no mark")
        }
    }

    function measureEmpty() {
        var n = root.builtCount()
        if (n === 0) root.fail("empty builds no delegate at all")
        root.checkBlank("empty")
        if (ClipMarks.markCalls !== 0)
            root.fail("empty costs " + ClipMarks.markCalls + " library calls over " + n + " delegates, want 0")
        if (ClipMarks._cached !== null)
            root.fail("empty holds a cached clipboard before any copy")
        if (root.failures.length > 0) { root.report(); return }
        root.markedCalls = ClipMarks.markCalls
        root.stubPane.clipboard = root.copiedBoard
        copiedTimer.start()
    }

    function measureCopied() {
        var n = root.builtCount()
        var d = root.delegateAt(root.copiedIndex)
        if (d === null)
            root.fail("copied builds no delegate at " + root.copiedIndex)
        else if (d.clipMark !== "copy")
            root.fail("copied draws " + d.clipMark + " on b.txt, want copy")
        for (var i = 0; i < root.sampleRows.length; i++) {
            if (i === root.copiedIndex) continue
            var o = root.delegateAt(i)
            if (o !== null && o.clipMark !== "")
                root.fail("copied draws " + o.clipMark + " on " + root.sampleRows[i].n + ", want no mark")
        }
        if (ClipMarks.markCalls - root.markedCalls < n)
            root.fail("copied costs " + (ClipMarks.markCalls - root.markedCalls) + " calls over " + n + " delegates, want at least one a row")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.clipboard = root.cutBoard
        cutTimer.start()
    }

    function measureCut() {
        var d = root.delegateAt(root.copiedIndex)
        if (d === null)
            root.fail("cut builds no delegate at " + root.copiedIndex)
        else {
            if (d.clipMark !== "scissors")
                root.fail("cut draws " + d.clipMark + " on b.txt, want scissors")
            if (d.clipCut !== true)
                root.fail("cut reads no cut")
            if (Math.abs(d.dimOpacity - Flea.Theme.disabledOpacity) > 0.01)
                root.fail("cut dims at " + d.dimOpacity + ", want the board opacity")
        }
        if (root.failures.length > 0) { root.report(); return }
        // The cut board re-runs the lookup per row, so clearing is measured from here and not from the copy.
        root.cutCalls = ClipMarks.markCalls
        root.stubPane.clipboard = root.emptyBoard
        clearedTimer.start()
    }

    function measureCleared() {
        var n = root.builtCount()
        root.checkBlank("cleared")
        // Empty short-circuits before the library, so clearing frees the cache with no per-row call.
        if (ClipMarks.markCalls !== root.cutCalls)
            root.fail("cleared costs " + (ClipMarks.markCalls - root.cutCalls) + " library calls over " + n + " delegates, want 0")
        if (ClipMarks._cached !== null)
            root.fail("cleared keeps its cached clipboard instead of releasing it")
        if (root.failures.length > 0) { root.report(); return }
        root.clearedCalls = ClipMarks.markCalls
        column.positionViewAtIndex(root.sampleRows.length - 1, ListView.Contain)
        movedTimer.start()
    }

    function measureMoved() {
        var n = root.builtCount()
        root.checkBlank("moved")
        if (ClipMarks.markCalls !== root.clearedCalls)
            root.fail("moved costs " + (ClipMarks.markCalls - root.clearedCalls) + " library calls over " + n + " delegates, want 0")
        if (root.failures.length > 0) { root.report(); return }
        controlTimer.start()
    }

    function measureControl() {
        var before = ClipMarks.markCalls
        for (var i = 0; i < root.sampleRows.length; i++)
            ClipMarks.markForRow(root.stubPane, root.sampleRows[i].n, root.stubPane.clipboard)
        var delta = ClipMarks.markCalls - before
        // The old unconditional delegate paid one library call a row even while empty.
        if (delta !== root.sampleRows.length)
            root.fail("control costs " + delta + " calls over " + root.sampleRows.length + " rows, want one a row")
        if (root.failures.length === 0)
            console.log("COLUMNCLIPEMPTY PASS delegates=" + root.sampleRows.length + " built=" + root.builtCount() + " calls=" + ClipMarks.markCalls)
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNCLIPEMPTY FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
