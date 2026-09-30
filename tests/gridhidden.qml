//@ pragma ShellId flea-gridhidden-test

import QtQuick
import Quickshell
import "flea" as Flea

// A real hidden Grid has no delegates or work; return preserves cursor, selection and pending rename.
ShellRoot {
    id: root

    property var failures: []
    property int cursorRow: 45
    property int rowCount: 60
    property int stage: 0
    property var copyBoard: ({ paths: ["/probe/item07.txt"], moving: false })
    property var cutBoard: ({ paths: ["/probe/item45.txt"], moving: true })

    property int baseWindow: -1
    property int baseMenu: -1
    property int baseCancel: -1
    property int baseThumb: -1

    // Built by call: initializers run before onCompleted and would hand it the empty array.
    function buildRows() {
        var rows = []
        for (var i = 0; i < root.rowCount; i++) {
            var n = "item" + (i < 10 ? "0" + i : i) + ".txt"
            var photo = i % 5 === 0
            rows.push({ n: n, d: i % 3 === 0, i: photo ? "image-x-generic" : "text-x-generic",
                p: 420, s: 13, m: 1758835200, t: photo, k: 0, v: 0 })
        }
        return rows
    }

    Component {
        id: backendStub
        QtObject {
            property int windowCalls: 0
            property int thumbCalls: 0
            property int dirsizescancelCalls: 0
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) { thumbCalls += 1 }
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() { dirsizescancelCalls += 1 }
            function window(start, count) { windowCalls += 1 }
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 60
            property int total: 60
            property int held: 0
            property int cursorIndex: 45
            property int renamingIndex: -1
            property string renameError: ""
            property bool renamePending: false
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: ["/probe/item07.txt"], moving: false })
            property var selected: ({ 44: true })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property string searchMode: ""
            property string searchQuery: ""
            property string filterQuery: ""
            property var selectionBand: null
            property var sidebar: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property var statusBar: null
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return selected[index] === true }
            function commitRename(newName) {}
        }
    }

    Component {
        id: menuStub
        QtObject {
            property int closeCalls: 0
            function close() { closeCalls += 1 }
            function openBackground(point) {}
        }
    }

    Component {
        id: statusStub
        QtObject { property var activities: [] }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubMenu: menuStub.createObject(root)
    property var stubStatus: statusStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: root.buildRows(), statusBar: root.stubStatus })

    // The grid lives in a real window, the pane the product parents; visibility there is effective.
    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 500
        color: Flea.Theme.color.background

        Flea.GridArea {
            id: grid
            width: 700
            height: 300
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            pane: root.stubPane
            menu: root.stubMenu
        }
    }

    Timer { interval: 800; running: true; repeat: false; onTriggered: root.measureShown() }
    Timer { id: scrolledTimer; interval: 500; repeat: false; onTriggered: root.measureScrolled() }
    Timer { id: hiddenTimer; interval: 600; repeat: false; onTriggered: root.measureHiddenStage() }
    Timer { id: returnedTimer; interval: 900; repeat: false; onTriggered: root.measureReturnedStage() }
    Timer { id: renameTimer; interval: 400; repeat: false; onTriggered: root.measureRenameStage() }

    function fail(text) { root.failures.push(text) }
    function delegateAt(i) { return grid.itemAtIndex(i) }

    // Shown with a deep cursor: delegates exist and a copied tile draws its copy mark.
    function measureShown() {
        if (grid.count !== root.rowCount)
            root.fail("shown grids " + grid.count + " rows, want " + root.rowCount)
        var mark = root.delegateAt(7)
        if (mark === null || mark.clipMark !== "copy")
            root.fail("shown draws no copy mark on item07")
        if (root.failures.length > 0) { root.report(); return }
        grid.positionViewAtIndex(root.cursorRow, GridView.Contain)
        root.stage = 1
        scrolledTimer.start()
    }

    // Edge contact is offscreen: exact touches miss, one-pixel overlaps hit, via real coversCursor.
    function checkBoundaries() {
        var h = grid.cellHeightPx, H = grid.height, cols = Math.max(1, grid.columns)
        var r = Math.ceil(H / h), view = r * cols, top = r * h, y = grid.contentY
        if (view >= root.rowCount) { root.fail("boundary row out of range"); grid.contentY = y; return }
        grid.contentY = top + h; var topTouch = grid.coversCursor(view)
        grid.contentY = top - H; var bottomTouch = grid.coversCursor(view)
        grid.contentY = top + h - 1; var topPixel = grid.coversCursor(view)
        grid.contentY = top - H + 1; var bottomPixel = grid.coversCursor(view)
        grid.contentY = y
        if (grid.restoreMaxTurns !== 60) root.fail("restore bound is " + grid.restoreMaxTurns + ", want 60")
        if (topTouch !== false) root.fail("top touch covers, want false")
        if (bottomTouch !== false) root.fail("bottom touch covers, want false")
        if (topPixel !== true) root.fail("top pixel misses, want true")
        if (bottomPixel !== true) root.fail("bottom pixel misses, want true")
    }

    // Scrolled to the cursor, then hidden with drift queued and a dirsize pending.
    function measureScrolled() {
        var at = root.delegateAt(root.cursorRow)
        if (at === null)
            root.fail("scrolled builds no delegate at the cursor " + root.cursorRow)
        else if (at.cursor !== true)
            root.fail("scrolled draws cursor false on " + root.cursorRow)
        if (root.failures.length > 0) { root.report(); return }
        root.checkBoundaries()
        root.baseWindow = root.stubBackend.windowCalls
        root.baseMenu = root.stubMenu.closeCalls
        root.baseCancel = root.stubBackend.dirsizescancelCalls
        root.baseThumb = root.stubBackend.thumbCalls
        root.stubPane.dirSizeState = ({ file: ({ 40: null }), order: [40] })
        grid.restartCoalesce()
        grid.visible = false
        root.stage = 2
        hiddenTimer.start()
    }

    function measureHiddenStage() {
        if (root.stage === 2) root.measureHidden()
        else if (root.stage === 5) root.measureRenameHidden()
        else if (root.stage === 8) root.measureEmptyHidden()
        else if (root.stage === 10) root.measureFilteredHidden()
        else { root.fail("hidden reached at stage " + root.stage); root.report() }
    }

    function measureReturnedStage() {
        if (root.stage === 3) root.measureReturned()
        else if (root.stage === 7) root.measureAbandonedReturn()
        else if (root.stage === 9) root.measureEmptyReturn()
        else if (root.stage === 11) root.measureFilteredReturn()
        else { root.fail("returned reached at stage " + root.stage); root.report() }
    }

    function measureRenameStage() {
        if (root.stage === 4) root.measureRenameReady()
        else if (root.stage === 6) root.measureAbandonedHidden()
        else { root.fail("rename reached at stage " + root.stage); root.report() }
    }

    // Hidden ordinary: zero delegates, zero backend work, shared values untouched.
    function measureHidden() {
        if (grid.count !== 0)
            root.fail("hidden grids " + grid.count + " rows, want 0")
        if (root.delegateAt(0) !== null || root.delegateAt(root.cursorRow) !== null)
            root.fail("hidden builds delegates while holding no model")
        if (root.stubBackend.windowCalls !== root.baseWindow)
            root.fail("hidden sent " + (root.stubBackend.windowCalls - root.baseWindow) + " queued backend.window, want 0")
        if (root.stubBackend.thumbCalls !== root.baseThumb)
            root.fail("hidden sent " + (root.stubBackend.thumbCalls - root.baseThumb) + " queued backend.thumb, want 0")
        if (root.stubBackend.dirsizescancelCalls !== root.baseCancel)
            root.fail("hidden cancelled dirsize work no visible scroll asked for")
        if (root.stubMenu.closeCalls !== root.baseMenu)
            root.fail("hidden closed the menu another view owns")
        if (root.stubPane.cursorIndex !== root.cursorRow)
            root.fail("hidden moved the shared cursor to " + root.stubPane.cursorIndex + ", want " + root.cursorRow)
        if (root.stubPane.selected[44] !== true)
            root.fail("hidden dropped the shared selection")
        if (root.stubPane.held !== 0)
            root.fail("hidden moved the held offset to " + root.stubPane.held)
        grid.contentY = 0
        grid.requestIfDrifted()
        if (root.stubBackend.windowCalls !== root.baseWindow)
            root.fail("hidden geometry sent backend.window, want no window while hidden")
        if (root.stubPane.cursorIndex !== root.cursorRow)
            root.fail("hidden geometry reached the shared cursor")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.clipboard = root.cutBoard
        grid.visible = true
        root.stage = 3
        returnedTimer.start()
    }

    // Returned: the model is back and the untouched cursor draws at its held offset.
    function measureReturned() {
        if (grid.count !== root.rowCount)
            root.fail("returned grids " + grid.count + " rows, want " + root.rowCount)
        if (root.stubPane.cursorIndex !== root.cursorRow)
            root.fail("returned moved the shared cursor to " + root.stubPane.cursorIndex + ", want " + root.cursorRow)
        if (grid.hiddenHeld !== false)
            root.fail("returned left the held restore pending after the rows landed")
        var at = root.delegateAt(root.cursorRow)
        if (at === null || at.cursor !== true || at.clipMark !== "scissors")
            root.fail("returned draws no cut cursor on " + root.cursorRow)
        var near = root.delegateAt(44)
        if (near === null || near.selected !== true)
            root.fail("returned draws selected false on row 44")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.renamingIndex = root.cursorRow
        root.stage = 4
        renameTimer.start()
    }

    // Rename open on the cursor tile, then hide pending: the edit keeps its model, its editor and its draft.
    function measureRenameReady() {
        var at = root.delegateAt(root.cursorRow)
        if (at === null || at.renaming !== true || at.editorField === null)
            root.fail("rename builds no real editor on the cursor tile before the hide")
        else {
            at.editorField.inputItem.text = "item45-draft.txt"
            if (at.editorText !== "item45-draft.txt")
                root.fail("rename takes no draft on the real editor")
        }
        if (root.failures.length > 0) { root.report(); return }
        // An in-flight commit: RenameField preserves a pending hide and abandons an ordinary one.
        root.stubPane.renamePending = true
        root.baseWindow = root.stubBackend.windowCalls
        root.baseCancel = root.stubBackend.dirsizescancelCalls
        grid.restartCoalesce()
        grid.visible = false
        root.stage = 5
        hiddenTimer.start()
    }

    // Hidden pending: the model stands, the real editor stands with its draft, drift is dropped.
    function measureRenameHidden() {
        if (grid.count !== root.rowCount)
            root.fail("rename hidden grids " + grid.count + " rows, want the kept " + root.rowCount)
        var at = root.delegateAt(root.cursorRow)
        if (at === null || at.renaming !== true || at.editorField === null)
            root.fail("rename hidden destroyed the in-flight editor")
        else if (at.editorText !== "item45-draft.txt")
            root.fail("rename hidden lost the draft, keeps " + at.editorText)
        if (root.stubBackend.windowCalls !== root.baseWindow)
            root.fail("rename hidden sent queued backend.window, want 0")
        if (root.stubBackend.dirsizescancelCalls !== root.baseCancel)
            root.fail("rename hidden cancelled dirsize work no visible scroll asked for")
        if (root.stubPane.cursorIndex !== root.cursorRow)
            root.fail("rename hidden reached the shared cursor")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.renamePending = false
        root.stubPane.renamingIndex = -1
        root.stage = 6
        renameTimer.start()
    }

    // Abandoned while hidden: the model zeroes under the same guard as an ordinary hide.
    function measureAbandonedHidden() {
        if (grid.count !== 0)
            root.fail("abandoned hidden grids " + grid.count + " rows, want 0")
        if (root.stubPane.cursorIndex !== root.cursorRow)
            root.fail("abandoned hidden moved the shared cursor to " + root.stubPane.cursorIndex)
        if (root.failures.length > 0) { root.report(); return }
        grid.visible = true
        root.stage = 7
        returnedTimer.start()
    }

    // Returned past the abandon: the listing is whole and the editor is gone.
    function measureAbandonedReturn() {
        if (grid.count !== root.rowCount)
            root.fail("abandoned return grids " + grid.count + " rows, want " + root.rowCount)
        if (grid.hiddenHeld !== false)
            root.fail("abandoned return left the held restore pending")
        var at = root.delegateAt(root.cursorRow)
        if (at === null || at.cursor !== true || at.renaming !== false)
            root.fail("abandoned return draws no plain cursor on " + root.cursorRow)
        if (root.failures.length > 0) { root.report(); return }
        grid.visible = false
        root.stage = 10
        hiddenTimer.start()
    }

    // Hidden filtered: the filter lands on the zeroed model, moving no geometry.
    function measureFilteredHidden() {
        if (grid.count !== 0)
            root.fail("filtered hidden grids " + grid.count + " rows, want 0")
        root.stubPane.shown = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        root.stubPane.shownTotal = 10
        if (grid.count !== 0)
            root.fail("filtered hidden builds rows for a hidden grid")
        if (root.stubPane.cursorIndex !== root.cursorRow)
            root.fail("filtered hidden moved the shared cursor")
        if (root.failures.length > 0) { root.report(); return }
        grid.visible = true
        root.stage = 11
        returnedTimer.start()
    }

    // Returned filtered: the hold is released on the filtered-away cursor, which still stands.
    function measureFilteredReturn() {
        if (grid.count !== 10)
            root.fail("filtered return grids " + grid.count + " rows, want 10")
        if (grid.hiddenHeld !== false)
            root.fail("filtered return left the hold pending on a filtered-away cursor")
        if (root.stubPane.cursorIndex !== root.cursorRow)
            root.fail("filtered return moved the shared cursor to " + root.stubPane.cursorIndex)
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.shown = null
        root.stubPane.rows = []
        root.stubPane.total = 0
        root.stubPane.shownTotal = 0
        grid.visible = false
        root.stage = 8
        hiddenTimer.start()
    }

    // Hidden empty: nothing to park and nothing to clamp.
    function measureEmptyHidden() {
        if (grid.count !== 0)
            root.fail("empty hidden grids " + grid.count + " rows, want 0")
        if (root.stubPane.cursorIndex !== root.cursorRow)
            root.fail("empty hidden moved the shared cursor")
        if (root.failures.length > 0) { root.report(); return }
        grid.visible = true
        root.stage = 9
        returnedTimer.start()
    }

    // Returned empty: the hold is cleared, and a visible scroll is handled, not suppressed.
    function measureEmptyReturn() {
        if (grid.hiddenHeld !== false)
            root.fail("empty return left the held restore pending with no rows to land")
        var closes = root.stubMenu.closeCalls
        grid.contentY = 50
        if (root.stubMenu.closeCalls !== closes + 1)
            root.fail("empty return suppresses visible geometry after the hold ended")
        if (root.failures.length === 0)
            console.log("GRIDHIDDEN PASS rows=" + root.rowCount + " cursor=" + root.cursorRow)
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("GRIDHIDDEN FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
