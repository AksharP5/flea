//@ pragma ShellId flea-statusbar-hint-test

import QtQuick
import Quickshell
import "flea" as Flea

// StatusHint drives the real StatusBar through its failing shape: a long error elides in the
// primary while the whole dismissal hint stays drawn, at two widths and two lane sizes.
ShellRoot {
    id: root

    property var failures: []
    property int checks: 0
    property int step: 0
    property bool done: false

    function repeat(ch, n) {
        var s = ""
        for (var i = 0; i < n; i++) s += ch
        return s
    }

    function check(label, actual, expected) {
        root.checks += 1
        if (actual !== expected)
            failures.push(label + ": got " + actual + ", expected " + expected)
    }

    function checkFits(label, actual, minimum) {
        root.checks += 1
        if (!(actual + 0.01 >= minimum))
            failures.push(label + ": got " + actual + ", minimum " + minimum)
    }

    // Independent read of both TextMetrics extents for the exact hint string, beside the live Text.
    TextMetrics {
        id: probeMetrics
        font.family: bar880.secondaryItem.font.family
        font.pixelSize: bar880.secondaryItem.font.pixelSize
        text: " · esc dismisses"
    }

    Column {
        Item {
            width: 880
            height: bar880.implicitHeight
            Flea.StatusBar {
                id: bar880
                width: 880
                path: "/hint-fixture"
                total: 5
                listingState: "ready"
                fsName: "overlay"
                fsFree: 142300000000
            }
        }
        Item {
            width: 1100
            height: bar1100.implicitHeight
            Flea.StatusBar {
                id: bar1100
                width: 1100
                path: "/hint-fixture"
                total: 5
                listingState: "ready"
                fsName: "overlay"
                fsFree: 142300000000
            }
        }
    }

    function settleBar(bar) {
        bar.errors = []
        bar.notice = ""
        bar.activities = []
        bar.searchLine = ""
        bar.retryLine = ""
        bar.searchRunning = false
    }

    function showLongError(bar) {
        settleBar(bar)
        bar.errors = [{ text: "Copy failed: " + root.repeat("0", 200) + ".txt · permission denied", detail: "", place: "" }]
    }

    function setLanePx(bar, px) {
        bar.primaryItem.font.pixelSize = px
        bar.secondaryItem.font.pixelSize = px
        bar.undoItem.font.pixelSize = px
        bar.countsItem.font.pixelSize = px
        bar.diskItem.font.pixelSize = px
    }

    function assertLongError(bar, label) {
        check(label + " keeps the whole hint", bar.secondaryItem.text, " · esc dismisses")
        checkFits(label + " secondary fits its extent", bar.secondaryItem.width, bar.secondaryItem.implicitWidth)
        check(label + " secondary never elides", bar.secondaryItem.truncated, false)
        check(label + " primary elides instead", bar.primaryItem.truncated, true)
        check(label + " zones keep their facts", bar.countsItem.text + "|" + (bar.diskItem.text.length > 0), "5 items|true")
    }

    function logMetrics(label) {
        console.log("STATUSHINT METRICS " + label + " px=" + bar880.secondaryItem.font.pixelSize
            + " metricsWidth=" + probeMetrics.width + " advance=" + probeMetrics.advanceWidth
            + " implicit=" + bar880.secondaryItem.implicitWidth + " hintWidth=" + bar880.hintWidth)
    }

    Timer {
        interval: 600
        running: true
        repeat: true
        onTriggered: root.advance()
    }

    // Each step settles one layout before the next reads it, the way rowcost waits one turn.
    function advance() {
        if (root.done) return
        if (root.step === 0) {
            showLongError(bar880)
            showLongError(bar1100)
            setLanePx(bar880, 12)
            setLanePx(bar1100, 12)
        } else if (root.step === 1) {
            assertLongError(bar880, "880x12")
            assertLongError(bar1100, "1100x12")
            logMetrics("hint12")
            setLanePx(bar880, 14)
            setLanePx(bar1100, 14)
        } else if (root.step === 2) {
            assertLongError(bar880, "880x14")
            assertLongError(bar1100, "1100x14")
            logMetrics("hint14")
            settleBar(bar880)
            bar880.notice = "Copied 1 item · z undoes"
        } else if (root.step === 3) {
            check("undo draws its own target", bar880.undoItem.text, "z undoes")
            check("undo target stays whole", bar880.undoItem.truncated, false)
            check("undo leaves the secondary empty", bar880.secondaryItem.text, "")
            check("hint reserves the undo lane", bar880.hintWidth > 0, true)
            settleBar(bar880)
            bar880.notice = "Renamed to notes.txt"
        } else if (root.step === 4) {
            check("no hint reserves nothing", bar880.hintWidth, 0)
            check("no hint draws nothing", bar880.secondaryItem.width, 0)
            showLongError(bar880)
            bar880.activities = [{ owner: null, text: "Copying " + root.repeat("1", 150) + " of 999", transfer: { running: false } }]
        } else if (root.step === 5) {
            check("long sticky still elides its tail", bar880.secondaryItem.truncated, true)
            check("long sticky keeps the primary elided", bar880.primaryItem.truncated, true)
            check("long sticky lane fits its room",
                (bar880.primaryItem.width + bar880.secondaryItem.width) <= (bar880.centreItem.room + 1), true)
            settleBar(bar880)
            bar880.activities = [{ owner: null, text: "Copying 1 of 2", transfer: { running: false } }]
            bar880.searchLine = root.repeat("s", 200)
            bar880.searchRunning = true
        } else {
            check("long search still elides its tail", bar880.secondaryItem.truncated, true)
            root.done = true
            if (root.failures.length === 0)
                console.log("STATUSHINT PASS checks=" + root.checks)
            else
                console.log("STATUSHINT FAIL " + root.failures.join(" | "))
        }
        root.step += 1
    }
}
