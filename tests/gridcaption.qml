//@ pragma ShellId flea-gridcaption-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/GridGeometry.js" as GridGeometry
import "flea/js/Density.js" as Density

// Actual GridTile caption geometry at two text sizes; the old fractional slot must fail at 14.
ShellRoot {
    id: root

    // The native witness name, so GridNames wraps and elides exactly the failing caption.
    readonly property string longName: "long-grid-caption-with-enough-words-to-wrap-and-truncate-after-two-complete-lines.txt"
    readonly property var fileRow: ({ n: root.longName, i: "text-x-generic", p: 0, d: false, s: 1, m: 0, t: false, v: 0 })

    // The real cell height GridArea gives a tile, so bottom<=height means the window contains it.
    function cellH() {
        return GridGeometry.cellHeightFor(Flea.ViewState.thumbnailPixels, Flea.Theme.spacing.gap,
            Math.ceil(Flea.Theme.grid.captionHeight),
            Density.gridPadY(Flea.Theme.spacing.rowPaddingX, Flea.ViewState.density))
    }

    Column {
        Flea.GridTile { id: normalTile; width: 147; height: root.cellH(); row: root.fileRow }
        Flea.GridTile { id: dropTile; width: 147; height: root.cellH(); row: root.fileRow; dropTarget: true }
    }

    property int phase: 0
    property var failures: []

    // Each phase lands a turn after the last write, so the relayout it measures has settled.
    Timer {
        id: stepper
        interval: 700
        running: true
        repeat: true
        onTriggered: root.step()
    }

    function check(cond, label) {
        if (!cond)
            root.failures.push(label)
    }

    function measure(base, withNegative) {
        var lineH = Flea.Theme.grid.captionLineHeight
        var cap = normalTile.captionItem
        var ntext = String(cap.text)
        console.log("GRIDCAPTION MEASURE base=" + base + " tile=normal lines=" + cap.lineCount + " textHeight=" + cap.contentHeight + " slotHeight=" + cap.height + " bottom=" + (cap.y + cap.height) + " tileHeight=" + normalTile.height)
        root.check(cap.lineCount === 2, "base " + base + " normal lines " + cap.lineCount)
        root.check(ntext.slice(-4) === ".txt", "base " + base + " normal tail " + ntext.slice(-12))
        root.check(ntext.indexOf("…") >= 0, "base " + base + " normal no ellipsis")
        root.check(cap.contentHeight <= cap.height, "base " + base + " normal textHeight " + cap.contentHeight + " over slot " + cap.height)
        root.check(cap.y + cap.height <= normalTile.height, "base " + base + " normal bottom past tile")
        if (withNegative)
            root.check(cap.contentHeight > 2 * lineH, "base " + base + " old slot already contained it")
        var dcap = dropTile.captionItem
        console.log("GRIDCAPTION MEASURE base=" + base + " tile=drop lines=" + dcap.lineCount + " textHeight=" + dcap.contentHeight + " slotHeight=" + dcap.height + " bottom=" + (dcap.y + dcap.height) + " tileHeight=" + dropTile.height)
        root.check(dcap.lineCount === 1, "base " + base + " drop lines " + dcap.lineCount)
        root.check(dcap.contentHeight <= dcap.height, "base " + base + " drop textHeight " + dcap.contentHeight + " over slot " + dcap.height)
        root.check(dcap.y + dcap.height <= dropTile.height, "base " + base + " drop bottom past tile")
    }

    function step() {
        if (root.phase === 0)
            Flea.ViewState.setTextSize({ mode: 12 })
        else if (root.phase === 1)
            root.measure(12, false)
        else if (root.phase === 2)
            Flea.ViewState.setTextSize({ mode: 14 })
        else if (root.phase === 3)
            root.measure(14, true)
        else
            root.report()
        root.phase++
    }

    function report() {
        stepper.running = false
        if (root.failures.length === 0)
            console.log("GRIDCAPTION PASS base=12,14 normal=2lines drop=1line")
        for (var f = 0; f < root.failures.length; f++)
            console.log("GRIDCAPTION FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
