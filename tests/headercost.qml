//@ pragma ShellId flea-headercost-test

import QtQuick
import Quickshell
import "flea" as Flea

// Headercost: one Header as ui/Pane.qml builds it holds no accent or metrics at rest; both build only while used.
ShellRoot {
    id: root

    property var failures: []

    Flea.Header {
        id: probeHeader
        width: 800
        pane: ({ rows: [{ n: "headercost.txt", p: 33188, d: false, s: 18000, m: 1758835200, k: 0 }], kindNames: [], dirSizeState: { file: {}, order: [] }, held: 0 })
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

    // The fit Loader among the header's direct children, so OEM title internals never count.
    function fitLoader() {
        var found = null
        var kids = probeHeader.children
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

    function measureRest() {
        var hs = root.handles()
        if (hs.length !== 4)
            failures.push("found " + hs.length + " resize handles, not 4; the walker is blind")
        var zones = 0
        var k = 0
        for (k = 0; k < hs.length; k++) {
            zones += root.zonesUnder(hs[k])
            var built = root.rectsUnder(hs[k])
            if (built !== 0)
                failures.push("handle " + k + " builds " + built + " accent rectangles at rest")
        }
        if (zones !== 4)
            failures.push("found " + zones + " grab zones, not 4; the walker is blind")
        var metrics = root.directKind("TextMetrics")
        if (metrics !== 0)
            failures.push("header builds " + metrics + " TextMetrics at rest")
        if (metrics === 0 && root.directKind("Loader") === 0)
            failures.push("found neither TextMetrics nor its Loader; the walker is blind")
        var allRects = 0
        root.walk(probeHeader, function (o) { if (root.isType(o, "Rectangle")) allRects += 1 })
        if (allRects === 0)
            failures.push("found no Rectangle at all; the walker is blind")
        var fit = root.fitLoader()
        if (fit === null)
            failures.push("found no fit Loader; the walker is blind")
        else {
            if (fit.active !== false)
                failures.push("fit Loader is active at rest")
            if (fit.item !== null)
                failures.push("fit Loader holds an item at rest")
        }
        probeHeader.dragKey = "size"
        hotProbe.start()
    }

    function measureHot() {
        var hs = root.handles()
        var hot = 0
        for (var i = 0; i < hs.length; i++) hot += root.rectsUnder(hs[i])
        if (hot !== 1)
            failures.push("a dragged column builds " + hot + " accent rectangles, not 1")
        var sizeHandle = root.handleFor("size")
        if (sizeHandle === null)
            failures.push("found no size handle; the walker is blind")
        else {
            var accent = root.accentUnder(sizeHandle)
            if (accent === null)
                failures.push("a dragged column builds no accent to measure")
            else {
                var hairline = Flea.Theme.spacing.hairline
                if (Math.abs(accent.width - hairline) > 0.001)
                    failures.push("hot accent is " + accent.width + " px wide, not the " + hairline + " px hairline")
                var mid = accent.mapToItem(sizeHandle, accent.width / 2, 0).x
                // Qt rounds a centred item to a whole pixel, so the centre holds to half a pixel.
                if (Math.abs(mid - sizeHandle.width / 2) > 0.5)
                    failures.push("hot accent sits at " + mid + ", not the handle centre " + sizeHandle.width / 2)
            }
        }
        var first = -1
        var second = -2
        try {
            first = probeHeader.fittedWidth("size")
            second = probeHeader.fittedWidth("size")
        } catch (e) {
            failures.push("fittedWidth threw " + e)
        }
        if (first <= 0)
            failures.push("fittedWidth measured " + first + " px for a size cell")
        if (first !== second)
            failures.push("two fits disagree, " + first + " against " + second)
        // autofitColumn returns early unless the header is sortable with a size column, so a release check would pass unexercised.
        if (!probeHeader.sortable || probeHeader.dualMode || !probeHeader.cols.size)
            failures.push("the probe header cannot autofit, so the release checks below would prove nothing")
        try {
            probeHeader.autofitColumn("size")
        } catch (e) {
            failures.push("autofitColumn threw " + e)
        }
        root.assertFitReleased("autofitColumn")
        try {
            probeHeader.autofitAll()
        } catch (e) {
            failures.push("autofitAll threw " + e)
        }
        root.assertFitReleased("autofitAll")
        probeHeader.dragKey = ""
        if (failures.length === 0)
            console.log("HEADERCOST PASS accents=0 metrics=0 hot=1 fit=" + first)
        for (var f = 0; f < failures.length; f++)
            console.log("HEADERCOST FAIL " + failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    // A fit path must leave no metrics object behind, or rest is a leak with one autofit of history.
    function assertFitReleased(who) {
        var fit = root.fitLoader()
        if (fit === null)
            failures.push(who + ": found no fit Loader; the walker is blind")
        else {
            if (fit.active !== false)
                failures.push(who + " left its fit Loader active")
            if (fit.item !== null)
                failures.push(who + " left its TextMetrics built")
        }
    }
}
