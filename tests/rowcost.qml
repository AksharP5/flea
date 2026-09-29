//@ pragma ShellId flea-rowcost-test

import QtQuick
import Quickshell
import "flea" as Flea

// Rowcost: one Row and one GridTile, built as ui/List.qml and ui/GridArea.qml build them, are counted against the measured objects.
ShellRoot {
    id: root

    property var sampleRow: ({ n: "rowcost.txt", i: "text-x-generic", p: 420, d: false, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
    property var failures: []
    // Measured in flea-ci at 89115b45 (ROWCOST PASS row=19 grid=14); one more object per delegate is a regression.
    readonly property int rowMax: 19
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

    // A cut row dims and builds its mark over idle, a copy builds undimmed, clearing returns to idle.
    function measureClip() {
        if (root.clipPhase === 0) {
            if (probeRow.dimOpacity === 1)
                failures.push("a cut row shares no dim with its mark")
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
        if (failures.length === 0)
            console.log("ROWCOST PASS row=" + root.rowIdleCount + " grid=" + root.gridIdleCount)
        for (var f = 0; f < failures.length; f++)
            console.log("ROWCOST FAIL " + failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
