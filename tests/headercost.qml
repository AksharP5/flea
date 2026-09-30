//@ pragma ShellId flea-headercost-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/ColumnFit.js" as CellRef
import "flea/js/Columns.js" as ClampRef

// Headercost: one Header as ui/Pane.qml builds it holds no accent or metrics at rest; both build only while used. The fit loader stays empty until a double click or F4, persists one widths-map update per fit, and releases after; refusals persist nothing.
ShellRoot {
    id: root

    property var failures: []
    property int checks: 0
    property var singleRow: ({ n: "headercost.txt", p: 33188, d: false, s: 18000, m: 1758835200, k: 0 })
    property var dirRow: ({ n: "big", p: 16877, d: true, s: 60, m: 1758835200, k: 0 })

    Flea.Header {
        id: probeHeader
        width: 800
        pane: ({ rows: [root.singleRow], kindNames: [], dirSizeState: { file: {}, order: [] }, held: 0 })
    }

    // All four columns drawn, so one F4 can owe four widths in a single update.
    Flea.Header {
        id: fitHeader
        width: 2000
        hiddenCols: []
        pane: ({ rows: [root.singleRow], kindNames: ["File", "Image"], dirSizeState: { file: {}, order: [] }, held: 0 })
    }

    Flea.Header {
        id: emptyHeader
        width: 2000
        hiddenCols: []
        pane: ({ rows: [], kindNames: [], dirSizeState: { file: {}, order: [] }, held: 0 })
    }

    Flea.Header {
        id: gateHeader
        width: 2000
        hiddenCols: []
        pane: ({ rows: [root.singleRow], kindNames: [], dirSizeState: { file: {}, order: [] }, held: 0 })
    }

    // The caption face FitMetrics measures in, read independently of that file.
    TextMetrics { id: refText }

    // One counted check; a mismatch names what the loader or the write did.
    // Sample input: check("fit is one call", 1, 1) passes silently.
    function check(label, actual, expected) {
        root.checks += 1
        if (actual !== expected)
            failures.push(label + ": got " + actual + ", expected " + expected)
    }

    // Children and resources, recursively; transforms ride their item and are not walked.
    function walk(item, fn) {
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            fn(o)
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
            var res = (o !== null && o.resources !== undefined) ? o.resources : []
            for (var j = 0; j < res.length; j++) stack.push(res[j])
        }
    }

    // Sample input: String(o) is "QQuickRectangle(0x55d0...)" for a built-in type and "ResizeHandle_QMLTYPE_7(0x...)" for a file type.
    function isType(o, name) { var s = String(o); return s.indexOf(name) === 0 || s.indexOf("QQuick" + name) === 0 }

    function handles() {
        var out = []
        root.walk(probeHeader, function (o) { if (root.isType(o, "ResizeHandle")) out.push(o) })
        return out
    }

    // The one handle for a column key, so the hot accent is read off the dragged column.
    function handleFor(key) {
        var found = null
        root.walk(probeHeader, function (o) { if (root.isType(o, "ResizeHandle") && o.columnKey === key) found = o })
        return found
    }

    // The first accent rectangle under a handle, if one is built.
    function accentUnder(handle) {
        var found = null
        root.walk(handle, function (o) { if (o !== handle && found === null && root.isType(o, "Rectangle")) found = o })
        return found
    }

    // The fit Loader of one header, so OEM title internals never count.
    function fitLoaderOf(h) {
        var found = null
        var kids = h.children
        for (var i = 0; i < kids.length; i++) if (root.isType(kids[i], "Loader")) found = kids[i]
        return found
    }

    // Direct children and resources of the header, so OEM title internals never count.
    function directKind(name) {
        var n = 0
        var kids = probeHeader.children
        for (var i = 0; i < kids.length; i++) if (root.isType(kids[i], name)) n += 1
        var res = probeHeader.resources
        for (var j = 0; j < res.length; j++) if (root.isType(res[j], name)) n += 1
        return n
    }

    function rectsUnder(handle) {
        var n = 0
        root.walk(handle, function (o) { if (o !== handle && root.isType(o, "Rectangle")) n += 1 })
        return n
    }

    function zonesUnder(handle) {
        var n = 0
        root.walk(handle, function (o) { if (root.isType(o, "MouseArea")) n += 1 })
        return n
    }

    // Owned write double: the shell stages this spy as ViewState.qml before construction, so autofit paths run against actual Header.qml with no file write, no production seam and no runtime patching. The liveness probe fails the run closed when the fixture is not talking to the constructed spy; call grouping only.
    function armWriteCapture() {
        Flea.ViewState.reset()
        Flea.ViewState.seed({})
        check("write spy is live", JSON.stringify(Flea.ViewState.state.columnWidths), "{}")
        return root.failures.length === 0
    }

    function writes() { return Flea.ViewState.commits }

    function resetWrites() { Flea.ViewState.reset() }

    // Seed the stored widths without writing, so unchanged and multi-change phases start exact.
    function seedWidths(map) { Flea.ViewState.seed(map) }

    // A fit path must leave no metrics object behind, or rest is a leak with one autofit of history.
    function checkReleased(who, h) {
        var fit = root.fitLoaderOf(h)
        check(who + " finds its fit Loader", fit !== null, true)
        if (fit === null)
            return
        check(who + " releases its loader", fit.active, false)
        check(who + " holds no item", fit.item, null)
        check(who + " unloads its source", String(fit.source), "")
    }

    // Delegates are built on the polish pass, so the read waits one turn like mount-listing.qml.
    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.measureRest()
    }

    Timer {
        id: hotProbe
        interval: 300
        repeat: false
        onTriggered: root.measureHot()
    }

    Timer {
        id: fitProbe
        interval: 300
        repeat: false
        onTriggered: root.measureFit()
    }

    function measureRest() {
        var hs = root.handles()
        check("four resize handles or the walker is blind", hs.length, 4)
        var zones = 0
        var built = 0
        for (var k = 0; k < hs.length; k++) {
            zones += root.zonesUnder(hs[k])
            built += root.rectsUnder(hs[k])
        }
        check("four grab zones or the walker is blind", zones, 4)
        check("no accent rectangle at rest", built, 0)
        check("no TextMetrics at rest", root.directKind("TextMetrics"), 0)
        check("its Loader present at rest", root.directKind("Loader") > 0, true)
        var allRects = 0
        root.walk(probeHeader, function (o) { if (root.isType(o, "Rectangle")) allRects += 1 })
        check("a Rectangle somewhere or the walker is blind", allRects > 0, true)
        var fit = root.fitLoaderOf(probeHeader)
        check("fit Loader found at rest", fit !== null, true)
        if (fit !== null) {
            check("fit Loader idle at rest", fit.active, false)
            check("no fit item at rest", fit.item, null)
            check("fit source empty at rest", String(fit.source), "")
        }
        probeHeader.dragKey = "size"
        hotProbe.start()
    }

    function measureHot() {
        var hs = root.handles()
        var hot = 0
        for (var i = 0; i < hs.length; i++) hot += root.rectsUnder(hs[i])
        check("one dragged column builds one accent", hot, 1)
        var sizeHandle = root.handleFor("size")
        check("size handle found", sizeHandle !== null, true)
        if (sizeHandle !== null) {
            var accent = root.accentUnder(sizeHandle)
            check("dragged column builds an accent to measure", accent !== null, true)
            if (accent !== null) {
                var hairline = Flea.Theme.spacing.hairline
                // Qt rounds a centred item to a whole pixel, so the centre holds to half a pixel.
                check("hot accent is the hairline wide", Math.abs(accent.width - hairline) <= 0.001, true)
                var mid = accent.mapToItem(sizeHandle, accent.width / 2, 0).x
                check("hot accent centred on its handle", Math.abs(mid - sizeHandle.width / 2) <= 0.5, true)
            }
        }
        probeHeader.dragKey = ""
        fitProbe.start()
    }

    function measureFit() {
        if (!root.armWriteCapture()) {
            root.finish(0)
            return
        }
        // The loader builds in the same turn, so the item is consumable at once, never a turn later.
        var first = probeHeader.fittedWidth("size")
        var fit = root.fitLoaderOf(probeHeader)
        check("fit builds synchronously", fit !== null && fit.active === true && fit.item !== null && fit.source !== "", true)
        var second = probeHeader.fittedWidth("size")
        check("a size cell measures positive", first > 0, true)
        check("two fits agree", second, first)
        // The same string Row draws, measured here in the caption face FitMetrics must use.
        refText.font.family = Flea.Theme.font.family
        refText.font.pixelSize = Flea.Theme.font.caption
        refText.text = CellRef.cellText("size", root.singleRow, [], null)
        var expectedSize = ClampRef.clampListWidth(Math.max(ClampRef.MIN_LIST_WIDTH, Math.ceil(refText.advanceWidth)))
        check("fit measures the caption face", first, expectedSize)
        // autofitColumn returns early unless the header is sortable with a size column, so a release check would pass unexercised.
        check("the probe header can autofit", probeHeader.sortable && !probeHeader.dualMode && probeHeader.cols.size, true)
        root.seedWidths({})
        root.resetWrites()
        probeHeader.autofitColumn("size")
        check("one double click persists one update", root.writes().length, 1)
        if (root.writes().length === 1)
            check("that update carries the fitted size", root.writes()[0].entries.size, expectedSize)
        root.checkReleased("autofitColumn", probeHeader)
        root.fitPhase()
        root.finish(first)
    }

    // F4 over four drawn columns owes every changed width in exactly one update.
    function fitPhase() {
        check("four columns drawn for the F4 phase", fitHeader.cols.mode && fitHeader.cols.size && fitHeader.cols.date && fitHeader.cols.kind, true)
        var keys = ["mode", "size", "date", "kind"]
        var expected = {}
        for (var e = 0; e < keys.length; e++) expected[keys[e]] = fitHeader.fittedWidth(keys[e])
        root.seedWidths({})
        root.resetWrites()
        fitHeader.autofitAll()
        check("F4 persists exactly one update", root.writes().length, 1)
        if (root.writes().length === 1) {
            var leaf = root.writes()[0].entries
            var names = []
            for (var k in leaf) names.push(k)
            names.sort()
            check("that update carries all four columns", names.join(","), "date,kind,mode,size")
            for (var c = 0; c < keys.length; c++) check("fitted " + keys[c], leaf[keys[c]], expected[keys[c]])
        }
        root.checkReleased("autofitAll", fitHeader)
        // Seeded exact, a second F4 owes nothing.
        root.seedWidths(expected)
        root.resetWrites()
        fitHeader.autofitAll()
        check("an unchanged F4 persists nothing", root.writes().length, 0)
        root.checkReleased("unchanged F4", fitHeader)
        // An empty held window keeps its columns: no fit, no write.
        check("the empty header draws its size column", emptyHeader.cols.size, true)
        root.resetWrites()
        emptyHeader.autofitColumn("size")
        emptyHeader.autofitAll()
        check("an empty fit persists nothing", root.writes().length, 0)
        root.checkReleased("empty fit", emptyHeader)
        // Hidden columns are never fitted and never written, while drawn ones still are.
        fitHeader.hiddenCols = ["size", "kind"]
        check("hidden size and kind drop out", !fitHeader.cols.size && !fitHeader.cols.kind && fitHeader.cols.mode && fitHeader.cols.date, true)
        root.seedWidths({})
        root.resetWrites()
        fitHeader.autofitAll()
        check("a hidden F4 still persists one update", root.writes().length, 1)
        if (root.writes().length === 1) {
            var hleaf = root.writes()[0].entries
            check("hidden size unwritten", ("size" in hleaf), false)
            check("hidden kind unwritten", ("kind" in hleaf), false)
            check("drawn mode still fitted", ("mode" in hleaf), true)
            check("drawn date still fitted", ("date" in hleaf), true)
        }
        root.checkReleased("hidden F4", fitHeader)
        fitHeader.hiddenCols = []
        root.dirPhase()
        root.refusePhase()
    }

    // The held index behind one held row selects the dirsize the row would draw.
    function dirPhase() {
        fitHeader.pane = ({ rows: [root.dirRow], kindNames: [], dirSizeState: { file: {}, order: [] }, held: 7 })
        var bare = fitHeader.fittedWidth("size")
        fitHeader.pane = ({ rows: [root.dirRow], kindNames: [], dirSizeState: { file: { 7: { bytes: 124700000, partial: false } }, order: [7] }, held: 7 })
        var walked = fitHeader.fittedWidth("size")
        check("the held walk selects its exact byte count", CellRef.dirSizeFor(fitHeader.pane.dirSizeState, fitHeader.pane.held, 0).bytes, 124700000)
        refText.text = CellRef.cellText("size", root.dirRow, [], { bytes: 124700000, partial: false })
        check("that width is the caption face again", walked, ClampRef.clampListWidth(Math.max(ClampRef.MIN_LIST_WIDTH, Math.ceil(refText.advanceWidth))))
        // The walk at index 0 must not answer a cursor held at 7: the offset is held plus at.
        fitHeader.pane = ({ rows: [root.dirRow], kindNames: [], dirSizeState: { file: { 0: { bytes: 124700000, partial: false } }, order: [0] }, held: 7 })
        check("a walk at the wrong held index is not read", fitHeader.fittedWidth("size"), bare)
        fitHeader.pane = ({ rows: [root.singleRow], kindNames: ["File", "Image"], dirSizeState: { file: {}, order: [] }, held: 0 })
        fitHeader.releaseFit()
        root.checkReleased("dirsize phase", fitHeader)
    }

    // Null, search and dual paths do no work and persist nothing.
    function refusePhase() {
        check("the gate header would write when allowed", gateHeader.sortable && !gateHeader.dualMode && gateHeader.cols.size, true)
        root.resetWrites()
        gateHeader.autofitColumn("size")
        check("an allowed fit writes first, so refusals below are not vacuous", root.writes().length, 1)
        root.checkReleased("allowed gate fit", gateHeader)
        gateHeader.pane = null
        root.resetWrites()
        gateHeader.autofitColumn("size")
        gateHeader.autofitAll()
        check("a null pane persists nothing", root.writes().length, 0)
        root.checkReleased("null pane", gateHeader)
        gateHeader.pane = ({ rows: [root.singleRow], kindNames: [], dirSizeState: { file: {}, order: [] }, held: 0 })
        gateHeader.searchMode = "typing"
        root.resetWrites()
        gateHeader.autofitColumn("size")
        gateHeader.autofitAll()
        check("a search header persists nothing", root.writes().length, 0)
        root.checkReleased("search header", gateHeader)
        gateHeader.searchMode = ""
        gateHeader.dualMode = true
        root.resetWrites()
        gateHeader.autofitColumn("size")
        gateHeader.autofitAll()
        check("a dual header persists nothing", root.writes().length, 0)
        root.checkReleased("dual header", gateHeader)
        gateHeader.dualMode = false
    }

    function finish(first) {
        console.log("HEADERCOST DONE checks=" + root.checks)
        if (failures.length === 0)
            console.log("HEADERCOST PASS accents=0 metrics=0 hot=1 fit=" + first)
        for (var f = 0; f < failures.length; f++)
            console.log("HEADERCOST FAIL " + failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
