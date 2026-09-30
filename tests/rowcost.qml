//@ pragma ShellId flea-rowcost-test

import QtQuick
import Quickshell
import "flea" as Flea

// Rowcost: one Row and one GridTile, built as ui/List.qml and ui/GridArea.qml build them, are counted against the measured objects.
ShellRoot {
    id: root

    property var sampleRow: ({ n: "rowcost.txt", i: "text-x-generic", p: 420, d: false, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
    property var failures: []
    // One Loader fewer than 0.3.6 98404bc7 (row=18 grid=14); one more object per delegate is a regression.
    readonly property int rowMax: 17
    readonly property int gridMax: 14

    Flea.Row {
        id: probeRow
        width: 800
        row: root.sampleRow
        kindNames: []
        hiddenCols: []
        clipMark: ""
    }

    Flea.GridTile {
        id: probeTile
        width: 160
        height: 120
        row: root.sampleRow
        clipMark: ""
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

    function editorsUnder(item) {
        var n = 0
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (String(o).indexOf("RenameField") === 0) n += 1
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
            var res = (o !== null && o.resources !== undefined) ? o.resources : []
            for (var j = 0; j < res.length; j++) stack.push(res[j])
        }
        return n
    }

    // Delegates are built on the polish pass, so the read waits one turn like mount-listing.qml.
    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.measureIdle()
    }

    Timer {
        id: renameProbe
        interval: 300
        repeat: false
        onTriggered: root.measureRename()
    }

    Timer {
        id: clipProbe
        interval: 300
        repeat: false
        onTriggered: root.measureClip()
    }

    Timer {
        id: dropProbe
        interval: 300
        repeat: false
        onTriggered: root.measureDrop()
    }

    Timer {
        id: dateProbe
        interval: 300
        repeat: false
        onTriggered: root.measureDate()
    }

    property int dropPhase: -1
    property double fitBefore: -1
    property double todayFixture: 0
    property int datePhase: -1

    property int clipPhase: -1
    property int clipBuiltCount: -1

    function measureIdle() {
        var rowCount = root.countUnder(probeRow)
        var gridCount = root.countUnder(probeTile)
        if (rowCount > root.rowMax)
            failures.push("row holds " + rowCount + " objects over the " + root.rowMax + " ceiling")
        if (gridCount > root.gridMax)
            failures.push("tile holds " + gridCount + " objects over the " + root.gridMax + " ceiling")
        if (root.editorsUnder(probeRow) !== 0)
            failures.push("row builds a RenameField while not renaming")
        if (root.editorsUnder(probeTile) !== 0)
            failures.push("tile builds a RenameField while not renaming")
        if (probeTile.editorField !== null)
            failures.push("tile editorField is live while not renaming")
        if (probeRow.cellInk === undefined)
            failures.push("row shares no cellInk across its four cells")
        if (probeRow.dimOpacity === undefined || probeTile.dimOpacity === undefined)
            failures.push("delegates share no dimOpacity for the clip dim")
        if (probeRow.cell("mode") === null || probeRow.cell("size") === null
                || probeRow.cell("date") === null || probeRow.cell("kind") === null)
            failures.push("row cell() no longer answers all four cells")
        if (probeRow.dropBuilt())
            failures.push("a row at rest builds its drop frame")
        root.rowIdleCount = rowCount
        root.gridIdleCount = gridCount
        probeTile.renaming = true
        renameProbe.start()
    }

    property int rowIdleCount: -1
    property int gridIdleCount: -1

    function measureRename() {
        if (root.editorsUnder(probeTile) !== 1)
            failures.push("tile builds no RenameField while renaming")
        if (probeTile.editorText !== "rowcost.txt")
            failures.push("tile editor opened on " + probeTile.editorText)
        probeTile.renaming = false
        if (root.editorsUnder(probeTile) !== 0)
            failures.push("tile keeps its RenameField after the rename closed")
        // Rare states build only while their state is on; the clip mark is next.
        probeRow.clipMark = "scissors"
        root.clipPhase = 0
        clipProbe.start()
    }

    // Effective ink, so an added opacity double-dims instead of passing on color.a alone.
    function effectiveAlpha(item) {
        var a = item.color.a
        var cur = item
        while (cur !== null) { if (cur.opacity !== undefined) a *= cur.opacity; if (cur === root) break; cur = cur.parent }
        return a
    }

    // The drawn mark is the one direct Glyph matching the row's own name and color contract.
    function markGlyph() {
        var found = null, n = 0
        var kids = probeRow.children || []
        for (var i = 0; i < kids.length; i++) { var o = kids[i]; if (o && o.name !== undefined && o.color !== undefined && o.name === probeRow.glyphName && String(o.color) === String(probeRow.markColor())) { found = o; n += 1 } }
        if (n !== 1) failures.push("a row draws " + n + " mark glyphs, want 1")
        return found
    }

    // Cut dims drawn colours, copy stays bright, and clearing restores idle objects and ink.
    function checkDrawnDim(wantDim) {
        var want = wantDim ? Flea.Theme.disabledOpacity : 1
        // A trivial token makes every dim check vacuous, so the baseline must stay a real dim.
        if (Flea.Theme.disabledOpacity <= 0.05 || Flea.Theme.disabledOpacity >= 0.95)
            failures.push("disabledOpacity reads " + Flea.Theme.disabledOpacity + ", want a real dim")
        var nameA = root.effectiveAlpha(probeRow.nameItem())
        if (Math.abs(nameA - want) > 0.01)
            failures.push("a row draws its name at " + nameA + ", want " + want)
        var sizeA = root.effectiveAlpha(probeRow.cell("size"))
        if (Math.abs(sizeA - want) > 0.01)
            failures.push("a row draws its size at " + sizeA + ", want " + want)
        var markA = -1, glyph = root.markGlyph()
        if (glyph === null) failures.push("a row draws no mark glyph, want one")
        else { markA = root.effectiveAlpha(glyph); if (Math.abs(markA - want) > 0.01) failures.push("a row draws its mark at " + markA + ", want " + want) }
    }

    function measureClip() {
        if (root.clipPhase === 0) {
            if (probeRow.dimOpacity === 1)
                failures.push("a cut row shares no dim with its mark")
            root.checkDrawnDim(true)
            root.clipBuiltCount = root.countUnder(probeRow)
            if (root.clipBuiltCount <= root.rowIdleCount)
                failures.push("a clipboard row builds no mark over the idle count")
            probeRow.clipMark = "copy"
            root.clipPhase = 1
            clipProbe.start()
            return
        }
        if (root.clipPhase === 1) {
            if (probeRow.dimOpacity !== 1)
                failures.push("a copied row keeps the cut dim")
            root.checkDrawnDim(false)
            if (root.countUnder(probeRow) <= root.rowIdleCount)
                failures.push("a copy mark builds nothing over the idle count")
            probeRow.clipMark = ""
            root.clipPhase = 2
            clipProbe.start()
            return
        }
        if (root.countUnder(probeRow) !== root.rowIdleCount)
            failures.push("a cleared clipboard row keeps its mark objects")
        if (probeRow.dimOpacity !== 1)
            failures.push("a cleared clipboard row keeps the cut dim")
        root.checkDrawnDim(false)
        // A drop-target row with only the name column and a long name: the name must end before the label starts.
        probeRow.hiddenCols = ["mode", "size", "date", "kind"]
        probeRow.row = ({ n: "averylongfilenamethatgoesonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandonandon.txt", i: "text-x-generic", p: 493, d: true, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
        probeRow.dropCopying = false
        probeRow.dropTarget = true
        root.dropPhase = 0
        dropProbe.start()
    }

    // The drop frame and label build only on the row under a drag, and a long name never overprints them.
    function measureDrop() {
        if (root.dropPhase === 0) {
            if (!probeRow.dropBuilt())
                failures.push("a drop-target row builds no drop frame")
            if (probeRow.dropLabelText() !== "move here")
                failures.push("a drop-target row labels no move, got " + probeRow.dropLabelText())
            if (!(probeRow.nameRight() < probeRow.dropLabelLeft()))
                failures.push("a long name overprints the drop label")
            probeRow.dropCopying = true
            root.dropPhase = 1
            dropProbe.start()
            return
        }
        if (root.dropPhase === 1) {
            if (probeRow.dropLabelText() !== "copy here")
                failures.push("a copy drop labels no copy, got " + probeRow.dropLabelText())
            if (!(probeRow.nameRight() < probeRow.dropLabelLeft()))
                failures.push("a long name overprints the copy label")
            probeRow.clipMark = "copy"
            root.dropPhase = 5
            dropProbe.start()
            return
        }
        if (root.dropPhase === 5) {
            if (!probeRow.dropBuilt())
                failures.push("a clipboard drop target builds no drop frame")
            if (probeRow.dropLabelText() !== "copy here")
                failures.push("a clipboard drop labels no copy, got " + probeRow.dropLabelText())
            if (root.countUnder(probeRow) <= root.rowIdleCount)
                failures.push("a clipboard drop target builds no mark over the idle count")
            if (probeRow.clipRight() < 0)
                failures.push("a clipboard drop target draws no clip mark")
            else if (!(probeRow.clipRight() < probeRow.dropLabelLeft()))
                failures.push("a clip mark overprints the drop label")
            probeRow.clipMark = ""
            probeRow.dropTarget = false
            root.dropPhase = 2
            dropProbe.start()
            return
        }
        if (root.dropPhase === 2) {
            if (probeRow.dropBuilt())
                failures.push("a cleared drop target keeps its frame objects")
            if (root.countUnder(probeRow) !== root.rowIdleCount)
                failures.push("a cleared drop target keeps its label objects")
            if (failures.length > 0) { root.report(); return }
            probeRow.hiddenCols = []
            probeRow.row = ({ n: "a.txt", i: "text-x-generic", p: 420, d: false, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
            probeRow.dropCopying = false
            probeRow.dropTarget = false
            root.dropPhase = 3
            dropProbe.start()
            return
        }
        if (root.dropPhase === 3) {
            root.fitBefore = probeRow.nameRight()
            probeRow.dropTarget = true
            root.dropPhase = 4
            dropProbe.start()
            return
        }
        if (!(probeRow.nameRight() < probeRow.dropLabelLeft()))
            failures.push("a fitting name overprints the drop label")
        if (probeRow.nameRight() !== root.fitBefore)
            failures.push("a fitting name re-elides on hover")
        probeRow.dropTarget = false
        probeRow.hiddenCols = []
        root.todayFixture = Flea.ViewState.todayStart
        Flea.ViewState.state = {}
        Flea.ViewState.todayStart = root.todayFixture
        probeRow.row = ({ n: "today.txt", i: "text-x-generic", p: 420, d: false, s: 13, m: root.todayFixture / 1000 + 3600, t: false, k: 0, v: 0 })
        root.datePhase = 0
        dateProbe.start()
    }

    // The today lift reads the drawn date cell with the switch off, on, and on with a stale date.
    function measureDate() {
        if (root.datePhase === 0) {
            if (String(probeRow.cellInk) === String(Flea.Theme.color.foreground))
                failures.push("cellInk matches foreground, so the today lift reads nothing")
            if (String(probeRow.cell("date").color) !== String(probeRow.cellInk))
                failures.push("highlight off draws " + probeRow.cell("date").color + " on today, want cellInk")
            Flea.ViewState.state = { highlightToday: true }
            Flea.ViewState.todayStart = root.todayFixture
            root.datePhase = 1
            dateProbe.start()
            return
        }
        if (root.datePhase === 1) {
            if (String(probeRow.cell("date").color) !== String(Flea.Theme.color.foreground))
                failures.push("highlight on draws " + probeRow.cell("date").color + " on today, want foreground")
            probeRow.row = ({ n: "old.txt", i: "text-x-generic", p: 420, d: false, s: 13, m: root.todayFixture / 1000 - 3600, t: false, k: 0, v: 0 })
            root.datePhase = 2
            dateProbe.start()
            return
        }
        if (String(probeRow.cell("date").color) !== String(probeRow.cellInk))
            failures.push("highlight on draws " + probeRow.cell("date").color + " on a stale date, want cellInk")
        Flea.ViewState.state = {}
        root.report()
    }

    function report() {
        if (failures.length === 0)
            console.log("ROWCOST PASS row=" + root.rowIdleCount + " grid=" + root.gridIdleCount)
        for (var f = 0; f < failures.length; f++)
            console.log("ROWCOST FAIL " + failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
