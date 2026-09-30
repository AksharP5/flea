//@ pragma ShellId flea-listcost-test

import QtQuick
import Quickshell
import "flea" as Flea
// The same resolved URL ui/List.qml imports, so this is the list's own library instance and not a copy.
import "flea/js/ClipMarks.js" as ClipMarks

// e34r2 listcost: a real ui/List.qml over a stub pane hoists its shared values and frees its lookup; tests/listcost.sh drives it offscreen.
ShellRoot {
    id: root

    property var failures: []
    property int markedCalls: 0
    // Snapshot after copied before clear, so the cleared phase proves no per-row library call.
    property int copiedCalls: -1
    // The follow value the hoist probe writes through list.rowWidth, so a per-row recompute stays behind it.
    property real hoistProbe: -1
    // The shared set before the narrowing probe, so followers must redraw from it rather than their own width.
    property var colsBefore: ""

    property var sampleRows: [
        { n: "a.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "b.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "c.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "d.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "e.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "f.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 }
    ]
    property var copiedBoard: ({ paths: ["/probe/c.txt"], moving: false })
    property var emptyBoard: ({ paths: [], moving: false })

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
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 6
            property int total: 6
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
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
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

    property var stubBackend: backendStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: root.sampleRows })

    Flea.List {
        id: list
        width: 700
        height: 300
        pane: root.stubPane
        menu: menuStub.createObject(root)
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
        id: clearedTimer
        interval: 600
        repeat: false
        onTriggered: root.measureCleared()
    }

    Timer {
        id: dualTimer
        interval: 600
        repeat: false
        onTriggered: root.measureDual()
    }

    Timer {
        id: hoistTimer
        interval: 600
        repeat: false
        onTriggered: root.measureHoist()
    }

    Timer {
        id: colsTimer
        interval: 600
        repeat: false
        onTriggered: root.measureCols()
    }

    Timer {
        id: colsFollowTimer
        interval: 600
        repeat: false
        onTriggered: root.measureColsFollow()
    }

    function fail(text) { root.failures.push(text) }

    function delegateAt(i) { return list.itemAtIndex(i) }

    // Every delegate drawn, none missing: the model is small enough to hold them all.
    function checkDelegates(label) {
        if (list.count !== root.sampleRows.length)
            root.fail(label + " lists " + list.count + " rows, want " + root.sampleRows.length)
        var n = 0
        for (var i = 0; i < root.sampleRows.length; i++) {
            if (root.delegateAt(i) === null)
                root.fail(label + " builds no delegate at " + i)
            else
                n += 1
        }
        return n
    }

    function measureEmpty() {
        var n = root.checkDelegates("empty")
        for (var i = 0; i < root.sampleRows.length; i++) {
            var d = root.delegateAt(i)
            if (d === null) continue
            if (d.clipMark !== "")
                root.fail("empty draws " + d.clipMark + " on " + root.sampleRows[i].n + ", want no mark")
            if (d.width !== list.rowWidth)
                root.fail("empty widths " + d.width + ", want the hoisted " + list.rowWidth)
            if (d.hiddenCols !== list.rowHiddenCols)
                root.fail("empty holds its own hidden array instead of the hoisted one")
        }
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
        var n = root.checkDelegates("copied")
        for (var i = 0; i < root.sampleRows.length; i++) {
            var d = root.delegateAt(i)
            if (d === null) continue
            var want = root.sampleRows[i].n === "c.txt" ? "copy" : ""
            if (d.clipMark !== want)
                root.fail("copied draws " + d.clipMark + " on " + root.sampleRows[i].n + ", want " + want)
        }
        if (ClipMarks.markCalls - root.markedCalls < n)
            root.fail("copied costs " + (ClipMarks.markCalls - root.markedCalls) + " calls over " + n + " delegates, want at least one a row")
        if (root.failures.length > 0) { root.report(); return }
        root.copiedCalls = ClipMarks.markCalls
        root.stubPane.clipboard = root.emptyBoard
        clearedTimer.start()
    }

    function measureCleared() {
        var n = root.checkDelegates("cleared")
        // Empty short-circuits before the library, so clearing frees the cache with no per-row call.
        if (ClipMarks.markCalls !== root.copiedCalls)
            root.fail("cleared costs " + (ClipMarks.markCalls - root.copiedCalls) + " library calls over " + n + " delegates, want 0")
        for (var i = 0; i < root.sampleRows.length; i++) {
            var d = root.delegateAt(i)
            if (d === null) { root.fail("cleared builds no delegate at " + i); continue }
            if (d.clipMark !== "")
                root.fail("cleared keeps " + d.clipMark + " on " + root.sampleRows[i].n + ", want no mark")
        }
        if (ClipMarks._cached !== null)
            root.fail("cleared keeps its cached clipboard instead of releasing it")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.dualMode = true
        dualTimer.start()
    }

    function measureDual() {
        root.checkDelegates("dual")
        if (list.rowHiddenCols.indexOf("mode") < 0 || list.rowHiddenCols.indexOf("kind") < 0)
            root.fail("dual hides " + JSON.stringify(list.rowHiddenCols) + ", want mode and kind")
        for (var i = 0; i < root.sampleRows.length; i++) {
            var d = root.delegateAt(i)
            if (d === null) { root.fail("dual builds no delegate at " + i); continue }
            if (d.hiddenCols !== list.rowHiddenCols)
                root.fail("dual builds a hidden array per row instead of sharing one")
            if (d.width !== list.rowWidth)
                root.fail("dual widths " + d.width + ", want the hoisted " + list.rowWidth)
        }
        if (root.failures.length > 0) { root.report(); return }
        // A per-row Scroll.contentWidth matches numerically, so the hoist is proved by following: only a delegate bound to rowWidth moves with it.
        root.hoistProbe = Math.max(1, list.rowWidth - 17)
        list.rowWidth = root.hoistProbe
        hoistTimer.start()
    }

    function measureHoist() {
        root.checkDelegates("hoist")
        for (var i = 0; i < root.sampleRows.length; i++) {
            var d = root.delegateAt(i)
            if (d === null) { root.fail("hoist builds no delegate at " + i); continue }
            if (d.width !== root.hoistProbe)
                root.fail("delegate recomputes its width instead of reading the hoisted rowWidth; got " + d.width + ", want " + root.hoistProbe)
        }
        if (list.rowWidth !== root.hoistProbe)
            root.fail("list lost its hoisted rowWidth")
        if (root.failures.length > 0) { root.report(); return }
        colsTimer.start()
    }

    // Every delegate draws the shared set: identity proves the wire, derived flags prove the cells.
    function sameSet(label) {
        for (var i = 0; i < root.sampleRows.length; i++) {
            var d = root.delegateAt(i)
            if (d === null) { root.fail(label + " builds no delegate at " + i); continue }
            if (d.cols !== list.listCols)
                root.fail(label + " delegate " + i + " holds its own set instead of the shared one")
            if (JSON.stringify(d.cols) !== JSON.stringify(list.listCols))
                root.fail(label + " delegate " + i + " draws " + JSON.stringify(d.cols) + ", want " + JSON.stringify(list.listCols))
            if (d.modeShown !== list.listModeShown || d.sizeShown !== list.listSizeShown
                    || d.dateShown !== list.listDateShown || d.kindShown !== list.listKindShown)
                root.fail(label + " delegate " + i + " cells disagree with the shared set")
        }
    }

    function measureCols() {
        root.checkDelegates("cols")
        root.sameSet("cols")
        if (root.failures.length > 0) { root.report(); return }
        // A real shared input narrows, so followers redraw from it rather than their own width.
        root.colsBefore = JSON.stringify(list.listCols)
        list.rowWidth = 200
        colsFollowTimer.start()
    }

    function measureColsFollow() {
        root.checkDelegates("colsfollow")
        if (JSON.stringify(list.listCols) === root.colsBefore)
            root.fail("a narrowed view keeps " + root.colsBefore + ", want a smaller set")
        root.sameSet("colsfollow")
        if (root.failures.length === 0)
            console.log("LISTCOST PASS delegates=" + root.sampleRows.length + " calls=" + ClipMarks.markCalls)
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("LISTCOST FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
