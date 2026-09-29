//@ pragma ShellId flea-columnrow-geom-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Names.js" as Names

// Column-row geometry through a real ColumnPane: the handed budget fits, a clip fits, and a short name draws whole.
ShellRoot {
    id: root

    property var failures: []
    property string longName: "a-very-long-filename-that-must-elide-in-the-middle-to-keep-its-extension-visible-0123456789abcdef0123456789abcdef0123456789abcdef.png"
    property string shortName: "columnrow-geom.txt"
    property var activeRows: [{ n: root.longName, d: false, i: "text-x-generic", p: 420, s: 13 }, { n: root.shortName, d: false, i: "text-x-generic", p: 420, s: 13 }, { n: root.longName, d: true, i: "folder", p: 493, s: 0 }]
    property var peekRows: [{ n: root.longName, d: false, i: "text-x-generic", p: 420, s: 13 }, { n: root.shortName, d: false, i: "text-x-generic", p: 420, s: 13 }, { n: root.longName, d: true, i: "folder", p: 493, s: 0 }]

    // A ColumnPane-like parent: a fixed column width, the way the delegate is built.
    Item {
        id: columnLike
        width: 280
        height: 200

        Flea.ColumnRow {
            id: probeFile
            width: parent.width
            row: ({ n: "columnrow-geom.txt", d: false, i: "text-x-generic", p: 420, s: 13 })
            thumb: ""
            clipMark: ""
            showSize: true
            nameBudget: 40
        }

        Flea.ColumnRow {
            id: probeDir
            y: 40
            width: parent.width
            row: ({ n: "full", d: true, i: "folder", p: 493, s: 0 })
            thumb: ""
            clipMark: ""
            showSize: true
            cursor: true
            nameBudget: 40
        }

        Flea.ColumnRow {
            id: probeScissors
            y: 80
            width: parent.width
            row: ({ n: "columnrow-geom.txt", d: false, i: "text-x-generic", p: 420, s: 13 })
            thumb: ""
            clipMark: "scissors"
            showSize: true
            nameBudget: 40
        }

        Flea.ColumnRow {
            id: probePlainClip
            y: 120
            width: parent.width
            row: ({ n: "columnrow-geom.txt", d: false, i: "text-x-generic", p: 420, s: 13 })
            thumb: ""
            clipMark: ""
            showSize: true
            nameBudget: 40
        }
    }

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
        id: paneComponent
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 3
            property int total: 3
            property int held: 0
            property int cursorIndex: -1
            property int renamingIndex: -1
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property bool storageKnown: false
            property bool listInFlight: false
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            property var trash: ({ opened: false })
            property string searchMode: ""
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
            function thumbFor(index) { return "" }
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubPanePlain: paneComponent.createObject(root, { backend: root.stubBackend, rows: root.activeRows })
    property var stubPaneClipped: paneComponent.createObject(root, { backend: root.stubBackend, rows: root.activeRows, clipboard: ({ paths: ["/probe/" + root.longName], moving: false }) })

    // Realistic column widths: 366 is an 1100 px window at 3 columns, 853 a 2560 px window at 3 columns.
    Flea.ColumnPane {
        id: activeNarrow
        y: 200
        width: 366
        height: 200
        pane: root.stubPanePlain
        selectedIndex: 2
    }

    Flea.ColumnPane {
        id: activeWide
        y: 410
        width: 853
        height: 200
        pane: root.stubPanePlain
        selectedIndex: 2
    }

    Flea.ColumnPane {
        id: clippedNarrow
        y: 620
        width: 366
        height: 200
        pane: root.stubPaneClipped
    }

    Flea.ColumnPane {
        id: peekNarrow
        y: 830
        width: 366
        height: 200
        rows: root.peekRows
        selectedIndex: 2
    }

    Flea.ColumnPane {
        id: peekWide
        y: 1040
        width: 853
        height: 200
        rows: root.peekRows
        selectedIndex: 2
    }

    // Same font as ColumnRow.nameText, so a budget+1 probe measures the drawn slot.
    Text {
        id: budgetProbe
        visible: false
        font.family: Flea.Theme.font.family
        font.pixelSize: Flea.Theme.font.body
        textFormat: Text.PlainText
    }

    Item {
        id: dynamicContainer
        y: 1250
        width: 366
        height: 40
    }

    Component {
        id: dynamicRowComponent
        Flea.ColumnRow {
            thumb: ""
            clipMark: ""
            showSize: true
        }
    }

    property var dynamicRow: null
    property int dynamicTextChanges: 0
    Connections {
        id: dynamicConn
        target: null
        function onTextChanged() { root.dynamicTextChanges += 1 }
    }

    // Delegates are built on the polish pass, so the read waits one turn like mount-listing.qml.
    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.measure()
    }

    Timer {
        id: dynamicTimer
        interval: 600
        repeat: false
        onTriggered: root.measureDynamic()
    }

    function fail(text) { root.failures.push(text) }

    // One row's drawn boxes: the name holds text between the mark and the size.
    function checkRow(probe, label, wantName) {
        var ng = probe.nameGeom()
        var sg = probe.sizeGeom()
        var cg = probe.chevronGeom()
        var markR = probe.markRight()
        if (ng[1] <= 0)
            root.fail(label + " draws its name " + ng[1] + " wide, want > 0")
        if (String(probe.displayText()).indexOf(wantName) < 0)
            root.fail(label + " draws " + probe.displayText() + ", want " + wantName)
        if (ng[0] + ng[1] > sg[0] + 0.5)
            root.fail(label + " ends its name at " + (ng[0] + ng[1]) + " over the size at " + sg[0])
        if (sg[0] + sg[1] > cg[0] + 0.5)
            root.fail(label + " ends its size at " + (sg[0] + sg[1]) + " over the chevron at " + cg[0])
        if (sg[0] <= markR)
            root.fail(label + " starts its size at " + sg[0] + " at or left of the mark edge " + markR)
    }

    // A row built by a real ColumnPane fits its handed text: no second elision by Qt.
    function checkPaneRow(pane, label, index, name, clipped, budget) {
        var delegate = pane.itemAtIndex(index)
        if (!delegate) {
            root.fail(label + " builds no delegate at " + index)
            return
        }
        if (!(budget >= 0)) {
            root.fail(label + " hands no budget, got " + budget)
            return
        }
        var adjust = 0
        if (clipped) {
            if (!delegate.clipMark || delegate.clipMark.length === 0) {
                root.fail(label + " carries no clip mark, want one")
                return
            }
            adjust = Math.ceil((Flea.Theme.spacing.gap + delegate.clipPx) / Flea.Theme.bodyAdvance)
        }
        var want = Names.middleElide(name, Math.max(0, budget - adjust))
        var got = delegate.displayText()
        if (got !== want)
            root.fail(label + " draws " + got + ", want " + want)
        var ni = delegate.nameItem()
        if (ni.implicitWidth > ni.width)
            root.fail(label + " overflows its slot: implicit " + ni.implicitWidth + " over " + ni.width)
        if (ni.truncated === true)
            root.fail(label + " is truncated by Qt after Names elided it")
    }

    // The budget is the largest that fits: one more cell would overflow the slot.
    function checkTight(pane, label, name, budget, index) {
        if (budget + 1 >= name.length) {
            root.fail(label + " fixture name too short for width " + budget)
            return
        }
        var delegate = null
        try { delegate = pane.itemAtIndex(index) } catch (e) {
            root.fail(label + " delegate read threw " + e)
            return
        }
        if (!delegate) {
            root.fail(label + " builds no delegate for the tight check")
            return
        }
        var ni = null
        try { ni = delegate.nameItem() } catch (e) {
            root.fail(label + " name read threw " + e)
            return
        }
        if (!ni) {
            root.fail(label + " has no drawn name for the tight check")
            return
        }
        budgetProbe.text = Names.middleElide(name, budget + 1)
        if (!(budgetProbe.implicitWidth > ni.width))
            root.fail(label + " budget " + budget + " is not tight: budget+1 still fits at " + budgetProbe.implicitWidth + " over " + ni.width)
    }

    // The dim lives on the content item, so read the drawn opacity and not the role.
    function checkDim() {
        if (probeScissors.dimOpacity !== Flea.Theme.disabledOpacity)
            root.fail("a scissors row dims at " + probeScissors.dimOpacity + ", want " + Flea.Theme.disabledOpacity)
        if (probePlainClip.dimOpacity !== 1)
            root.fail("an unmarked row dims at " + probePlainClip.dimOpacity + ", want 1")
        if (probeScissors.nameItem().opacity !== 1)
            root.fail("a scissors name carries its own opacity, want the content item's alone")
        var sc = probeScissors.nameItem()
        var pl = probePlainClip.nameItem()
        if (!sc || !sc.parent)
            root.fail("a scissors row has no drawn name to read dim from")
        else if (sc.parent.opacity !== Flea.Theme.disabledOpacity)
            root.fail("a scissors row draws at " + sc.parent.opacity + ", want " + Flea.Theme.disabledOpacity)
        if (!pl || !pl.parent)
            root.fail("an unmarked row has no drawn name to read dim from")
        else if (pl.parent.opacity !== 1)
            root.fail("an unmarked row draws at " + pl.parent.opacity + ", want 1")
        if (sc && sc.parent && sc.opacity * sc.parent.opacity !== Flea.Theme.disabledOpacity)
            root.fail("a scissors name shows effective " + (sc.opacity * sc.parent.opacity) + ", want " + Flea.Theme.disabledOpacity)
        if (pl && pl.parent && pl.opacity * pl.parent.opacity !== 1)
            root.fail("an unmarked name shows effective " + (pl.opacity * pl.parent.opacity) + ", want 1")
    }

    // Every delegate read is guarded, so a missing row fails loud instead of hanging.
    function measure() {
        try {
            root.checkRow(probeFile, "a file row", "columnrow-geom.txt")
            root.checkRow(probeDir, "a directory row", "full")
            root.checkDim()
            root.checkPaneRow(activeNarrow, "an active column at 366", 0, root.longName, false, activeNarrow.nameBudgetPlain)
            root.checkPaneRow(activeWide, "an active column at 853", 0, root.longName, false, activeWide.nameBudgetPlain)
            root.checkPaneRow(clippedNarrow, "a clipped row at 366", 0, root.longName, true, clippedNarrow.nameBudgetPlain)
            root.checkPaneRow(peekNarrow, "a peek column at 366", 0, root.longName, false, peekNarrow.nameBudgetPlain)
            root.checkPaneRow(peekWide, "a peek column at 853", 0, root.longName, false, peekWide.nameBudgetPlain)
            root.checkPaneRow(activeNarrow, "a short name at 366", 1, root.shortName, false, activeNarrow.nameBudgetPlain)
            root.checkPaneRow(peekNarrow, "a short peek name at 366", 1, root.shortName, false, peekNarrow.nameBudgetPlain)
            root.checkTight(activeNarrow, "an active column at 366", root.longName, activeNarrow.nameBudgetPlain, 0)
            root.checkTight(activeWide, "an active column at 853", root.longName, activeWide.nameBudgetPlain, 0)
            root.checkTight(peekNarrow, "a peek column at 366", root.longName, peekNarrow.nameBudgetPlain, 0)
            root.checkTight(peekWide, "a peek column at 853", root.longName, peekWide.nameBudgetPlain, 0)
            var chev = [[activeNarrow, "a chevron row at 366"], [activeWide, "a chevron row at 853"], [peekNarrow, "a chevron peek at 366"], [peekWide, "a chevron peek at 853"]]
            for (var c = 0; c < chev.length; c++) { root.checkPaneRow(chev[c][0], chev[c][1], 2, root.longName, false, chev[c][0].nameBudgetChevron); root.checkTight(chev[c][0], chev[c][1], root.longName, chev[c][0].nameBudgetChevron, 2) }
            // Only a cursor or lifted directory takes the chevron: a file under it and a directory off it keep the full width.
            activeNarrow.selectedIndex = 0
            root.checkPaneRow(activeNarrow, "a file under the cursor at 366", 0, root.longName, false, activeNarrow.nameBudgetPlain)
            root.checkTight(activeNarrow, "a file under the cursor at 366", root.longName, activeNarrow.nameBudgetPlain, 0)
            activeNarrow.selectedIndex = 1
            root.checkPaneRow(activeNarrow, "a directory off the cursor at 366", 2, root.longName, false, activeNarrow.nameBudgetPlain)
            root.checkTight(activeNarrow, "a directory off the cursor at 366", root.longName, activeNarrow.nameBudgetPlain, 2)
            activeNarrow.liftedName = root.longName
            root.checkPaneRow(activeNarrow, "a lifted directory at 366", 2, root.longName, false, activeNarrow.nameBudgetChevron)
            root.checkTight(activeNarrow, "a lifted directory at 366", root.longName, activeNarrow.nameBudgetChevron, 2)
            var shortDelegate = null
            try { shortDelegate = activeNarrow.itemAtIndex(1) } catch (e) {
                root.fail("a short name delegate read threw " + e)
            }
            if (!shortDelegate)
                root.fail("a short name at 366 builds no delegate at 1")
            else if (String(shortDelegate.displayText()).indexOf("…") >= 0)
                root.fail("a short name draws elided at 366")
            if (root.failures.length > 0) { root.report(); return }
            // Built raw at budget -1, so the counter arms before any handed text is set.
            root.dynamicTextChanges = 0
            root.dynamicRow = dynamicRowComponent.createObject(dynamicContainer, { width: 366, row: ({ n: root.longName, d: false, i: "text-x-generic", p: 420, s: 13 }), showSize: true, nameBudget: -1 })
            if (!root.dynamicRow) {
                root.fail("a dynamic row never builds")
                root.report()
                return
            }
            var dynamicName = null
            try { dynamicName = root.dynamicRow.nameItem() } catch (e) {
                root.fail("a dynamic row name read threw " + e)
                root.report()
                return
            }
            if (!dynamicName) {
                root.fail("a dynamic row has no drawn name to count")
                root.report()
                return
            }
            dynamicConn.target = dynamicName
            root.dynamicRow.nameBudget = activeNarrow.nameBudgetPlain
            dynamicTimer.start()
        } catch (e) {
            root.fail("measure threw " + e)
            root.report()
        }
    }

    function measureDynamic() {
        try {
            if (!root.dynamicRow) {
                root.fail("a dynamic row never builds")
            } else {
                if (root.dynamicTextChanges !== 1)
                    root.fail("a handed-budget row re-sets its text " + root.dynamicTextChanges + " times, want 1")
                var want = Names.middleElide(root.longName, activeNarrow.nameBudgetPlain)
                var got = null
                try { got = root.dynamicRow.displayText() } catch (e) {
                    root.fail("a dynamic row text read threw " + e)
                    got = null
                }
                if (got !== null && got !== want)
                    root.fail("a dynamic row draws " + got + ", want " + want)
            }
            if (root.failures.length === 0)
                console.log("COLUMNROWGEOM PASS file=columnrow-geom.txt dir=full")
            root.report()
        } catch (e) {
            root.fail("measureDynamic threw " + e)
            root.report()
        }
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNROWGEOM FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
