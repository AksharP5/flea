//@ pragma ShellId flea-columnscost-test

import QtQuick
import Quickshell
import "flea" as Flea

// e6 columnscost: a ColumnsArea at the shipped default limit (3) builds no
// great-grandparent or grandparent pane, and one ColumnRow holds its ceiling.
// tests/columnscost.sh drives it offscreen; the controller pins the counts.
ShellRoot {
    id: root

        // One ColumnPane signature: drawsEmpty, lockedMode and liftedName with itemAtIndex.
    // Nothing else in the area carries all four, so the count is the built panes.
    function isColumnPane(o) {
        return o !== null && o.drawsEmpty !== undefined && o.lockedMode !== undefined
            && o.liftedName !== undefined && typeof o.itemAtIndex === "function"
    }

    // Children and resources, recursively; transforms ride their item and are not walked.
    function countUnder(item) {
        var n = 0
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            n += 1
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
            var res = (o !== null && o.resources !== undefined) ? o.resources : []
            for (var j = 0; j < res.length; j++) stack.push(res[j])
        }
        return n - 1
    }

    function countPanes(item) {
        var n = 0
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (root.isColumnPane(o)) n += 1
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
            var res = (o !== null && o.resources !== undefined) ? o.resources : []
            for (var j = 0; j < res.length; j++) stack.push(res[j])
        }
        return n
    }

    // The backend ColumnsArea peeks through; every answer is a no-op, so nothing lands.
    Component {
        id: backendStub
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
            property int dirDev: 0
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
        }
    }

    // An empty listing: total 0 builds no delegates, so the count is the panes alone.
    // rowFor answers null, so the cursor names no row and the third column stays idle.
    Component {
        id: paneStub
        QtObject {
            property string path: "/probe/studio"
            property var rows: []
            property var shown: []
            property int shownTotal: 0
            property int total: 0
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property bool showHidden: false
            property int windowSize: 35
            property bool listInFlight: false
            property string listingState: "ready"
            property string searchMode: ""
            property var trash: ({ opened: false })
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property bool storageKnown: false
            property string storageClass: ""
            property int previewIndex: -1
            property string pendingSelect: ""
            property bool pendingMenu: false
            property var selectionBand: null
            property string focusView: "list"
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { return null }
            function isSelected(index) { return false }
            function selectedIndices() { return [] }
            function selectionCount() { return 0 }
            function thumbFor(index) { return "" }
            function open(path) {}
            function openFile(path) {}
            function focusRequested() {}
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
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend })

    // 900 px at the shipped default limit draws 3 columns: parent, active, child.
    Flea.ColumnsArea {
        id: area
        width: 900
        height: 600
        pane: root.stubPane
        menu: menuStub.createObject(root)
    }

    property var sampleRow: ({ n: "columnscost.txt", d: false, i: "text-x-generic", p: 420, s: 13 })

    Flea.ColumnRow {
        id: probeRow
        width: 300
        row: root.sampleRow
        thumb: ""
        clipMark: ""
        showSize: false
    }

    // Measured by the controller offscreen; one more object per delegate is a regression.
    readonly property int columnRowMax: 20

    // Delegates are built on the polish pass, so the read waits one turn like mount-listing.qml.
    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.measure()
    }

    function measure() {
        var failures = []
        var count = area.columnCount
        if (count !== 3)
            failures.push("at 900 px the default limit draws " + count + " columns, want 3")
        var panes = root.countPanes(area)
        if (panes !== 3)
            failures.push("at 3 columns holds " + panes + " ColumnPanes, want 3: no great-grandparent or grandparent pane exists below 4 and 5")
        var rowCount = root.countUnder(probeRow)
        if (rowCount > root.columnRowMax)
            failures.push("a column row holds " + rowCount + " objects over the " + root.columnRowMax + " ceiling")
        if (probeRow.clipCut !== false)
            failures.push("an unmarked row reads cut")
        if (probeRow.dimOpacity !== 1)
            failures.push("an unmarked row dims at " + probeRow.dimOpacity)
        if (failures.length === 0)
            console.log("COLUMNCOST PASS panes=" + panes + " row=" + rowCount + " columns=" + count)
        for (var f = 0; f < failures.length; f++)
            console.log("COLUMNCOST FAIL " + failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
