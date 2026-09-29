//@ pragma ShellId flea-headerhandles-test

import QtQuick
import Quickshell
import "flea" as Flea

// e33: the four resize edges live behind one Loader, so Columns and Grid views build none.
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

    // Sample input: String(o) is "ResizeHandle_QMLTYPE_7(0x...)" for a file type.
    function isHandle(o) {
        var s = String(o)
        return s.indexOf("ResizeHandle") === 0 || s.indexOf("QQuickResizeHandle") === 0
    }

    // Children, resources and a Loader's item, so a handle behind a Loader still counts.
    function handlesUnder(item) {
        var out = []
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o !== item && root.isHandle(o)) out.push(o)
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
            var res = (o !== null && o.resources !== undefined) ? o.resources : []
            for (var j = 0; j < res.length; j++) stack.push(res[j])
            if (o !== null && o.item !== undefined && o.item !== null && typeof o.item === "object") stack.push(o.item)
        }
        return out
    }

    function handleFor(header, key) {
        var hs = root.handlesUnder(header)
        for (var i = 0; i < hs.length; i++) if (hs[i].columnKey === key) return hs[i]
        return null
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
            root.checkAfterPolish()
        } catch (e) {
            root.fail("measure threw " + e)
            root.report()
        }
    }

    // One more turn, so a Loader deactivating on the view assignment has unbuilt.
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

    function check() {
        var listHandles = root.handlesUnder(listHeader)
        var columnsHandles = root.handlesUnder(columnsHeader)
        var gridHandles = root.handlesUnder(gridHeader)
        if (columnsHandles.length !== 0)
            root.fail("columns view builds " + columnsHandles.length + " ResizeHandles, want 0")
        if (gridHandles.length !== 0)
            root.fail("grid view builds " + gridHandles.length + " ResizeHandles, want 0")
        var keys = ["mode", "size", "date", "kind"]
        var want = 0
        var k = 0
        for (k = 0; k < keys.length; k++) if (listHeader.cols[keys[k]]) want += 1
        if (listHandles.length !== want)
            root.fail("list view builds " + listHandles.length + " ResizeHandles, want " + want)
        for (k = 0; k < keys.length; k++) {
            var cell = listHeader.cell(keys[k])
            var handle = root.handleFor(listHeader, keys[k])
            if (!listHeader.cols[keys[k]]) {
                if (handle !== null) root.fail(keys[k] + " builds a handle while hidden")
                continue
            }
            if (handle === null) {
                root.fail(keys[k] + " builds no handle")
                continue
            }
            if (cell === null) {
                root.fail(keys[k] + " has no cell to measure")
                continue
            }
            var expect = cell.x - Math.floor(handle.width / 2)
            if (Math.abs(handle.x - expect) > 0.5)
                root.fail(keys[k] + " sits at x " + handle.x + ", want " + expect)
        }
        if (root.failures.length === 0)
            console.log("HEADERHANDLES PASS list=" + listHandles.length + " columns=0 grid=0")
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("HEADERHANDLES FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
