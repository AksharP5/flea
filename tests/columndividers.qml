//@ pragma ShellId flea-columndividers-test

import QtQuick
import Quickshell
import "flea" as Flea

// e21 column dividers: the active pane draws its edge only while the third column draws.
ShellRoot {
    id: root

    // A ColumnPane is the only item carrying drawsEmpty, lockedMode, liftedName and itemAtIndex.
    function isColumnPane(o) {
        return o !== null && o.drawsEmpty !== undefined && o.lockedMode !== undefined
            && o.liftedName !== undefined && typeof o.itemAtIndex === "function"
    }

    // One shared Divider per column edge; a row delegate carries none.
    function isDivider(o) {
        return o !== null && o.isDivider === true
    }

    // False on any hidden ancestor, so a divider under an unbuilt Loader counts as drawn none.
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

    function findActive() {
        var stack = [area]
        while (stack.length > 0) {
            var o = stack.pop()
            if (root.isActivePane(o) && root.effectivelyVisible(o)) return o
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return null
    }

    // The true arm of the active edge: false stays green when showDivider is forced false.
    function checkActive(want, label) {
        var act = root.findActive()
        if (act === null) {
            root.fail(label + " finds no active pane")
            return
        }
        if (act.showDivider !== want)
            root.fail(label + " active showDivider is " + act.showDivider + ", want " + want)
        var div = root.dividerOf(act)
        if (div === null)
            root.fail(label + " active pane draws no divider")
        else if (div.visible !== want)
            root.fail(label + " active divider visible is " + div.visible + ", want " + want)
    }

    // N panes shown draw N-1, the rightmost none; this pins the grandparent arms too.
    function checkWide(label) {
        var panes = root.countVisiblePanes(area)
        var dividers = root.countVisibleDividers(area)
        if (dividers !== panes - 1)
            root.fail(label + " draws " + dividers + " dividers over " + panes + " panes, want " + (panes - 1))
        var stack = [area]
        while (stack.length > 0) {
            var o = stack.pop()
            if (root.isColumnPane(o) && root.effectivelyVisible(o)) {
                var div = root.dividerOf(o)
                if (div === null)
                    root.fail(label + " a shown pane draws no divider")
                else if (root.isActivePane(o) && div.visible !== false)
                    root.fail(label + " the rightmost pane draws a divider")
                else if (!root.isActivePane(o) && div.visible !== true)
                    root.fail(label + " a shown non-rightmost pane hides its divider")
            }
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
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

    // An empty listing: rowFor answers null, so the cursor names no row and shown* is driven by hand.
    Component {
        id: paneStub
        QtObject {
            property string path: "/a/b/c"
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

    Flea.ColumnsArea {
        id: area
        width: 900
        height: 600
        pane: root.stubPane
        menu: menuStub.createObject(root)
    }

    property var ancestorRows: [{ n: "ancestor.txt", d: false, i: "text-x-generic" }]
    property var childRows: [{ n: "kid.txt", d: false, i: "text-x-generic" }]

    function populateAncestors() {
        var next = {}
        next[area.peekKey(area.parentPath)] = root.ancestorRows
        next[area.peekKey(area.grandparentPath)] = root.ancestorRows
        next[area.peekKey(area.greatGrandparentPath)] = root.ancestorRows
        area.peeked = next
        area.peekVersion += 1
    }

    function populateChild() {
        var key = area.peekKey("/a/b/c/sub")
        var next = {}
        next[key] = root.childRows
        area.peeked = next
        area.peekVersion += 1
    }

    // Delegates are built on the polish pass, so the read waits one turn like mount-listing.qml.
    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.measureEmpty()
    }

    Timer {
        id: dirTimer
        interval: 600
        repeat: false
        onTriggered: root.measureDir()
    }

    Timer {
        id: fileTimer
        interval: 600
        repeat: false
        onTriggered: root.measureFileOn()
    }

    Timer {
        id: offTimer
        interval: 600
        repeat: false
        onTriggered: root.measureFileOff()
    }

    Timer {
        id: wideTimer
        interval: 600
        repeat: false
        onTriggered: root.measureWide5()
    }

    Timer {
        id: midTimer
        interval: 600
        repeat: false
        onTriggered: root.measureWide4()
    }

    function fail(text) { root.failures.push(text) }

    // A throw inside a Timer handler fails loud, so a TypeError never hangs to timeout.
    function measureEmpty() {
        try {
            if (area.columnCount !== 3)
                root.fail("at 900 px the default limit draws " + area.columnCount + " columns, want 3")
            if (root.countVisiblePanes(area) !== 2)
                root.fail("at 900 px with an empty third shows " + root.countVisiblePanes(area) + " panes, want 2")
            if (area.thirdShown !== false)
                root.fail("an empty third shows thirdShown true, want false")
            root.checkActive(false, "empty third")
            if (root.failures.length > 0) { root.report(); return }
            Flea.ViewState.state = {}
            area.shownHasRow = true
            area.shownIsDir = true
            area.shownChildPath = "/a/b/c/sub"
            root.populateChild()
            dirTimer.start()
        } catch (e) {
            root.fail("measureEmpty threw " + e)
            root.report()
        }
    }

    function measureDir() {
        try {
            if (area.thirdShown !== true)
                root.fail("a child folder with rows leaves thirdShown false, want true")
            if (root.countVisiblePanes(area) !== 3)
                root.fail("a child folder with rows shows " + root.countVisiblePanes(area) + " panes, want 3")
            if (root.countVisibleDividers(area) !== 2)
                root.fail("a child folder with rows draws " + root.countVisibleDividers(area) + " dividers, want 2")
            root.checkActive(true, "child folder with rows")
            if (root.failures.length > 0) { root.report(); return }
            area.shownHasRow = true
            area.shownIsDir = false
            area.shownChildPath = ""
            Flea.ViewState.state = {}
            fileTimer.start()
        } catch (e) {
            root.fail("measureDir threw " + e)
            root.report()
        }
    }

    function measureFileOn() {
        try {
            if (area.thirdShown !== true)
                root.fail("a file preview with the preview column on leaves thirdShown false, want true")
            root.checkActive(true, "file preview with the preview column on")
            if (root.failures.length > 0) { root.report(); return }
            Flea.ViewState.state = { preview: { column: false } }
            offTimer.start()
        } catch (e) {
            root.fail("measureFileOn threw " + e)
            root.report()
        }
    }

    function measureFileOff() {
        try {
            if (area.thirdShown !== false)
                root.fail("with the preview column off a file keeps thirdShown true, want false")
            root.checkActive(false, "preview column off")
            if (root.failures.length > 0) { root.report(); return }
            Flea.ViewState.state = { columnsLimit: 5 }
            root.stubPane.path = "/a/b/c/d"
            area.shownHasRow = false
            area.shownIsDir = false
            area.shownChildPath = ""
            area.width = 2400
            root.populateAncestors()
            wideTimer.start()
        } catch (e) {
            root.fail("measureFileOff threw " + e)
            root.report()
        }
    }

    function measureWide5() {
        try {
            if (area.columnCount !== 5)
                root.fail("at 2400 px with limit 5 draws " + area.columnCount + " columns, want 5")
            if (root.countVisiblePanes(area) !== 4)
                root.fail("at 5 columns with an empty third shows " + root.countVisiblePanes(area) + " panes, want 4")
            root.checkWide("at 2400 px with limit 5")
            if (root.failures.length > 0) { root.report(); return }
            area.width = 1800
            root.populateAncestors()
            midTimer.start()
        } catch (e) {
            root.fail("measureWide5 threw " + e)
            root.report()
        }
    }

    function measureWide4() {
        try {
            if (area.columnCount !== 4)
                root.fail("at 1800 px with limit 5 draws " + area.columnCount + " columns, want 4")
            if (root.countVisiblePanes(area) !== 3)
                root.fail("at 4 columns with an empty third shows " + root.countVisiblePanes(area) + " panes, want 3")
            root.checkWide("at 1800 px with limit 5")
            if (root.failures.length === 0)
                console.log("COLUMNDIVIDERS PASS panes=" + root.countVisiblePanes(area) + " dividers=" + root.countVisibleDividers(area))
            root.reportFailures()
        } catch (e) {
            root.fail("measureWide4 threw " + e)
            root.report()
        }
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNDIVIDERS FAIL " + root.failures[f])
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
