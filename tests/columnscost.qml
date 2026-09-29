//@ pragma ShellId flea-columnscost-test

import QtQuick
import Quickshell
import "flea" as Flea

// e6 columnscost: a ColumnsArea at the shipped default limit (3) builds no
// great-grandparent or grandparent pane, and one ColumnRow holds its ceiling.
// tests/columnscost.sh drives it offscreen; the controller pins the counts.
ShellRoot {
    id: root

    // A ColumnPane is the only item carrying drawsEmpty, lockedMode, liftedName and itemAtIndex, so this counts built panes.
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

    // One shared Divider per column edge; a row delegate carries none.
    function isDivider(o) {
        return o !== null && o.isDivider === true
    }

    // False on any hidden ancestor, so a divider under an unbuilt Loader or a hidden pane counts as drawn none.
    function effectivelyVisible(o) {
        var cur = o
        while (cur !== null) {
            if (cur.visible === false) return false
            cur = cur.parent
        }
        return true
    }

    function countVisiblePanes(item) {
        var n = 0
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (root.isColumnPane(o) && root.effectivelyVisible(o)) n += 1
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return n
    }

    function countVisibleDividers(item) {
        var n = 0
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (root.isDivider(o) && root.effectivelyVisible(o) && o.visible) n += 1
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return n
    }

    // The divider built directly under a pane, or null when the pane draws none.
    function dividerOf(pane) {
        var kids = pane.children || []
        for (var i = 0; i < kids.length; i++) if (root.isDivider(kids[i])) return kids[i]
        return null
    }

    // The active pane owns the listing; every other ColumnPane is a peek.
    function isActivePane(o) {
        return root.isColumnPane(o) && o.pane !== undefined && o.pane !== null
    }

    function checkDividers() {
        var panes = root.countVisiblePanes(area)
        if (panes !== 2)
            root.fail("at 900 px with an empty third shows " + panes + " panes, want 2")
        var dividers = root.countVisibleDividers(area)
        if (dividers !== panes - 1)
            root.fail("at 900 px draws " + dividers + " dividers over " + panes + " panes, want " + (panes - 1))
        var stack = [area]
        while (stack.length > 0) {
            var o = stack.pop()
            if (root.isColumnPane(o) && root.effectivelyVisible(o)) {
                var div = root.dividerOf(o)
                if (div === null) {
                    root.fail("a shown pane draws no divider")
                } else {
                    if (root.isActivePane(o) && div.visible !== false)
                        root.fail("the rightmost pane draws a divider")
                    if (!root.isActivePane(o) && div.visible !== true)
                        root.fail("a shown pane hides its divider")
                    if (div.width !== Flea.Theme.spacing.hairline)
                        root.fail("a column divider is " + div.width + " wide, want the rail hairline")
                    if (String(div.color) !== String(Flea.Theme.color.foreground))
                        root.fail("a column divider inks " + div.color + ", want the rail ink")
                    if (div.opacity !== 0.12)
                        root.fail("a column divider opacifies at " + div.opacity + ", want 0.12")
                }
            }
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return dividers
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
    property var failures: []

    // 900 px at the shipped default limit draws 3 columns: parent, active, child.
    Flea.ColumnsArea {
        id: area
        width: 900
        height: 600
        pane: root.stubPane
        menu: menuStub.createObject(root)
    }

    property var sampleRow: ({ n: "columnscost.txt", d: false, i: "text-x-generic", p: 420, s: 13 })
    property var ancestorRows: [{ n: "ancestor.txt", d: false, i: "text-x-generic", p: 420, s: 1 }]

    Flea.ColumnRow {
        id: probeRow
        width: 300
        row: root.sampleRow
        thumb: ""
        clipMark: ""
        showSize: false
    }

    Flea.ColumnRow {
        id: probeMarked
        width: 300
        row: root.sampleRow
        thumb: ""
        clipMark: "copy"
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

    Timer {
        id: wideTimer
        interval: 600
        repeat: false
        onTriggered: root.measureWide()
    }

    Timer {
        id: midTimer
        interval: 600
        repeat: false
        onTriggered: root.measureMid()
    }

    Timer {
        id: narrowTimer
        interval: 600
        repeat: false
        onTriggered: root.measureNarrow()
    }

    function fail(text) { root.failures.push(text) }

    function checkRowBudget() {
        var rowCount = root.countUnder(probeRow)
        if (rowCount > root.columnRowMax)
            root.fail("a column row holds " + rowCount + " objects over the " + root.columnRowMax + " ceiling")
        return rowCount
    }

    function checkClip() {
        if (probeRow.clipCut !== false)
            root.fail("an unmarked row reads cut")
        if (probeRow.dimOpacity !== 1)
            root.fail("an unmarked row dims at " + probeRow.dimOpacity)
        if (probeRow.clipX() !== 0)
            root.fail("an unmarked row moves its mark to " + probeRow.clipX() + ", want 0")
        if (Math.abs(probeMarked.clipX() - probeMarked.clipExpectedX()) > 0.01)
            root.fail("a marked row holds its mark at " + probeMarked.clipX() + ", want " + probeMarked.clipExpectedX())
    }

    function populateAncestors() {
        var next = {}
        next[area.peekKey(area.parentPath)] = root.ancestorRows
        next[area.peekKey(area.grandparentPath)] = root.ancestorRows
        next[area.peekKey(area.greatGrandparentPath)] = root.ancestorRows
        area.peeked = next
        area.peekVersion += 1
    }

    function measure() {
        var count = area.columnCount
        if (count !== 3)
            root.fail("at 900 px the default limit draws " + count + " columns, want 3")
        var panes = root.countPanes(area)
        if (panes !== 3)
            root.fail("at 3 columns holds " + panes + " ColumnPanes, want 3")
        root.checkRowBudget()
        root.checkClip()
        root.checkDividers()
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.path = "/a/b/c/d"
        Flea.ViewState.state = { columnsLimit: 5 }
        area.width = 2400
        root.populateAncestors()
        wideTimer.start()
    }

    function measureWide() {
        var count = area.columnCount
        if (count !== 5)
            root.fail("at 2400 px with limit 5 draws " + count + " columns, want 5")
        var panes = root.countPanes(area)
        if (panes !== 5)
            root.fail("at 5 columns holds " + panes + " ColumnPanes, want 5")
        if (area.rowsFor(area.grandparentPath).length !== 1)
            root.fail("the grandparent pane is not bound to its rows")
        if (area.rowsFor(area.greatGrandparentPath).length !== 1)
            root.fail("the great-grandparent pane is not bound to its rows")
        if (area.grandparentItemAt(0) === null)
            root.fail("grandparentItemAt(0) answers null with 5 columns")
        if (area.greatGrandparentItemAt(0) === null)
            root.fail("greatGrandparentItemAt(0) answers null with 5 columns")
        if (root.failures.length > 0) { root.report(); return }
        area.width = 1800
        midTimer.start()
    }

    function measureMid() {
        var count = area.columnCount
        if (count !== 4)
            root.fail("at 1800 px with limit 5 draws " + count + " columns, want 4")
        var panes = root.countPanes(area)
        if (panes !== 4)
            root.fail("at 4 columns holds " + panes + " ColumnPanes, want 4")
        if (area.grandparentItemAt(0) === null)
            root.fail("grandparentItemAt(0) answers null with 4 columns")
        if (area.greatGrandparentItemAt(0) !== null)
            root.fail("greatGrandparentItemAt(0) answers non-null with 4 columns")
        if (root.failures.length > 0) { root.report(); return }
        Flea.ViewState.state = {}
        area.width = 900
        narrowTimer.start()
    }

    function measureNarrow() {
        var count = area.columnCount
        if (count !== 3)
            root.fail("narrowed back draws " + count + " columns, want 3")
        var panes = root.countPanes(area)
        if (panes !== 3)
            root.fail("narrowed back holds " + panes + " ColumnPanes, want 3")
        if (area.grandparentItemAt(0) !== null)
            root.fail("grandparentItemAt(0) answers non-null after narrowing to 3")
        if (area.greatGrandparentItemAt(0) !== null)
            root.fail("greatGrandparentItemAt(0) answers non-null after narrowing to 3")
        var rowCount = root.checkRowBudget()
        root.checkClip()
        if (root.failures.length === 0)
            console.log("COLUMNCOST PASS panes=" + panes + " row=" + rowCount + " columns=" + count)
        root.reportFailures()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNCOST FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    function reportFailures() {
        if (root.failures.length === 0) {
            Quickshell.execDetached(["kill", String(Quickshell.processId)])
            return
        }
        root.report()
    }
}
