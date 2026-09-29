//@ pragma ShellId flea-headerhandles-test

import QtQuick
import Quickshell
import "flea" as Flea

// e33: the four resize edges live behind one Loader, so only the list view builds them.
ShellRoot {
    id: root

    property var failures: []

    Flea.Header {
        id: listHeader
        width: 800
        pane: ({ rows: [], kindNames: [], dirSizeState: { file: {}, order: [] }, held: 0 })
    }

    Flea.Header {
        id: columnsHeader
        width: 800
        y: 100
        pane: ({ rows: [], kindNames: [], dirSizeState: { file: {}, order: [] }, held: 0 })
    }

    Flea.Header {
        id: gridHeader
        width: 800
        y: 200
        pane: ({ rows: [], kindNames: [], dirSizeState: { file: {}, order: [] }, held: 0 })
    }

    Flea.Header {
        id: dualHeader
        width: 800
        y: 300
        pane: ({ rows: [], kindNames: [], dirSizeState: { file: {}, order: [] }, held: 0 })
    }

    Flea.Header {
        id: searchHeader
        width: 800
        y: 400
        pane: ({ rows: [], kindNames: [], dirSizeState: { file: {}, order: [] }, held: 0 })
    }

    Flea.Header {
        id: nopaneHeader
        width: 800
        y: 500
    }

    // Sample input: String(o) is "ResizeHandle_QMLTYPE_7(0x...)" for a file type.
    function isHandle(o) {
        var s = String(o)
        return s.indexOf("ResizeHandle") === 0 || s.indexOf("QQuickResizeHandle") === 0
    }

    // Each identity walked once, so a handle reachable by two paths still counts once.
    function handlesUnder(item) {
        var out = []
        var seen = []
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o === null || o === undefined) continue
            if (seen.indexOf(o) >= 0) continue
            seen.push(o)
            if (o !== item && root.isHandle(o)) out.push(o)
            var kids = (o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
            var res = (o.resources !== undefined) ? o.resources : []
            for (var j = 0; j < res.length; j++) stack.push(res[j])
            if (o.item !== undefined && o.item !== null && typeof o.item === "object") stack.push(o.item)
        }
        return out
    }

    function fail(text) { root.failures.push(text) }

    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.measure()
    }

    function measure() {
        try {
            // Dynamic assignment, so the same file loads on a Header with no viewMode.
            columnsHeader["viewMode"] = "columns"
            gridHeader["viewMode"] = "grid"
            dualHeader["dualMode"] = true
            searchHeader["searchMode"] = "query"
            root.checkAfterPolish()
        } catch (e) {
            root.fail("measure threw " + e)
            root.report()
        }
    }

    // One more turn, so a Loader deactivating on the gating assignment has unbuilt.
    Timer {
        id: secondPass
        interval: 400
        repeat: false
        onTriggered: root.checkAfterPolish()
    }

    property bool waited: false

    function checkAfterPolish() {
        try {
            if (!root.waited) {
                root.waited = true
                secondPass.start()
                return
            }
            root.check()
        } catch (e) {
            root.fail("check threw " + e)
            root.report()
        }
    }

    // A gated-away header builds nothing; a hidden column keeps its handle built but invisible.
    function checkGated(header, handles, label) {
        if (handles.length !== 0)
            root.fail(label + " builds " + handles.length + " ResizeHandles, want 0")
    }

    function check() {
        root.checkGated(columnsHeader, root.handlesUnder(columnsHeader), "columns view")
        root.checkGated(gridHeader, root.handlesUnder(gridHeader), "grid view")
        root.checkGated(dualHeader, root.handlesUnder(dualHeader), "dual header")
        root.checkGated(searchHeader, root.handlesUnder(searchHeader), "search header")
        root.checkGated(nopaneHeader, root.handlesUnder(nopaneHeader), "paneless header")
        var listHandles = root.handlesUnder(listHeader)
        if (listHandles.length !== 4)
            root.fail("list view builds " + listHandles.length + " ResizeHandles, want 4")
        var keys = ["mode", "size", "date", "kind"]
        var shown = 0
        for (var k = 0; k < keys.length; k++) {
            var matches = 0
            var handle = null
            for (var i = 0; i < listHandles.length; i++) {
                if (listHandles[i].columnKey === keys[k]) { handle = listHandles[i]; matches += 1 }
            }
            if (matches !== 1) {
                root.fail("list view builds " + matches + " " + keys[k] + " handles, want 1")
                continue
            }
            if (!listHeader.cols[keys[k]]) {
                if (handle.visible !== false)
                    root.fail(keys[k] + " is visible while its column is hidden")
                continue
            }
            if (handle.visible !== true) {
                root.fail(keys[k] + " is hidden while its column is shown")
                continue
            }
            shown += 1
            var cell = listHeader.cell(keys[k])
            if (cell === null) {
                root.fail(keys[k] + " has no cell to measure")
                continue
            }
            var expect = cell.x - Math.floor(handle.width / 2)
            if (Math.abs(handle.x - expect) > 0.5)
                root.fail(keys[k] + " sits at x " + handle.x + ", want " + expect)
        }
        if (root.failures.length === 0)
            console.log("HEADERHANDLES PASS list=4 shown=" + shown + " columns=0 grid=0 dual=0 search=0 nopane=0")
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("HEADERHANDLES FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
