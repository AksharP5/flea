//@ pragma ShellId flea-rowcost-test

import QtQuick
import Quickshell
import "flea" as Flea

// Rowcost: each list row and grid tile builds no more than it needs. One Row and one
// GridTile are built the way ui/List.qml and ui/GridArea.qml build them, then each
// delegate's tree (children and resources, recursively) is counted. ROW_MAX 32 and
// GRID_MAX 24 are the 0.3.6 shape plus the clip mark's own clipLoader: a fixed tile
// holds about 18 objects against about 26 with the eager editor's 8-object subtree,
// and a Row holds about 24 either way, its win being bindings rather than objects.
ShellRoot {
    id: root

    property var sampleRow: ({ n: "rowcost.txt", i: "text-x-generic", p: 420, d: false, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
    property var failures: []

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

    function measureIdle() {
        var rowCount = root.countUnder(probeRow)
        var gridCount = root.countUnder(probeTile)
        if (rowCount > 32)
            failures.push("row holds " + rowCount + " objects over the 32 ceiling")
        if (gridCount > 24)
            failures.push("tile holds " + gridCount + " objects over the 24 ceiling")
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
        if (failures.length === 0)
            console.log("ROWCOST PASS row=" + root.rowIdleCount + " grid=" + root.gridIdleCount)
        for (var f = 0; f < failures.length; f++)
            console.log("ROWCOST FAIL " + failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
