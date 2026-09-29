//@ pragma ShellId flea-columnrow-geom-test

import QtQuick
import Quickshell
import "flea" as Flea

// e20 column-row geometry: a real ColumnRow at a realistic column width draws
// its name between the mark and the size, with the size before the chevron.
ShellRoot {
    id: root

    property var failures: []

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
    }

    // Delegates are built on the polish pass, so the read waits one turn like mount-listing.qml.
    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.measure()
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

    function measure() {
        root.checkRow(probeFile, "a file row", "columnrow-geom.txt")
        root.checkRow(probeDir, "a directory row", "full")
        if (root.failures.length === 0)
            console.log("COLUMNROWGEOM PASS file=columnrow-geom.txt dir=full")
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNROWGEOM FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
