//@ pragma ShellId flea-columnspeekgate-test

import QtQuick
import Quickshell
import "flea" as Flea

// e39 neighbour gate over the real ColumnsArea: width/path steps ask the parent first time; root and hidden views ask nothing.
ShellRoot {
    id: root

    Component {
        id: backendStub
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
            signal metaResult(var message)
            property var peekLog: []
            function peek(path, size, hidden) { peekLog.push(String(path)) }
            function askMeta(index, wantLines, wantMedia, wantArchive) { return 0 }
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/x/y"
            property var rows: []
            property int cursorIndex: 0
            property bool showHidden: false
            property int windowSize: 35
            property bool listInFlight: false
            property string listingState: "ready"
            property string searchMode: ""
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: ["text-x-generic"]
            property bool storageKnown: true
            property string storageClass: "local"
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
            function isSelected(index) { return false }
            function selectedIndices() { return [] }
            function selectionCount() { return 0 }
            function thumbFor(index) { return "" }
            function open(path) {}
            function openFile(path) {}
            function focusRequested() {}
        }
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend })
    property var failures: []

    // The area lives in a real window, the ColumnsArea the product parents; visibility there is effective.
    FloatingWindow {
        implicitWidth: 1200
        implicitHeight: 600
        color: Flea.Theme.color.background

        Flea.ColumnsArea {
            id: area
            width: 800
            height: 600
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            pane: root.stubPane
            menu: menuStub.createObject(root)
        }
    }

    function fail(text) { root.failures.push(text) }
    function asked(path) { return root.stubBackend.peekLog.indexOf(String(path)) >= 0 }

    Timer {
        interval: 700
        running: true
        repeat: false
        onTriggered: root.phaseBase()
    }
    Timer { id: widthTimer; interval: 250; repeat: false; onTriggered: root.phaseWidth() }
    Timer { id: pathTimer; interval: 250; repeat: false; onTriggered: root.phasePathBase() }
    Timer { id: pathCheckTimer; interval: 250; repeat: false; onTriggered: root.phasePath() }
    Timer { id: rootTimer; interval: 250; repeat: false; onTriggered: root.phaseRoot() }
    Timer { id: hiddenTimer; interval: 250; repeat: false; onTriggered: root.phaseHidden() }
    Timer { id: hiddenOnTimer; interval: 250; repeat: false; onTriggered: root.phaseHiddenOn() }

    // Narrow first: no ancestor column is wanted, so no parent peek goes out.
    function phaseBase() {
        if (root.asked("/x"))
            root.fail("base at width 800 already asks /x, want no ancestor ask")
        if (root.failures.length > 0) { root.report(); return }
        area.width = 1100
        widthTimer.start()
    }

    // The width step alone asks the parent; the cursor never moved.
    function phaseWidth() {
        if (!root.asked("/x"))
            root.fail("width 800 to 1100 asks no parent peek, want /x")
        if (root.failures.length > 0) { root.report(); return }
        root.stubBackend.peeked("/x", false, 0, [], false, 0, false, root.stubPane.windowSize)
        root.stubBackend.peekLog = []
        root.stubPane.path = ""
        pathTimer.start()
    }

    // An empty path asks nothing, so the next step names its own parent.
    function phasePathBase() {
        if (root.stubBackend.peekLog.length !== 0)
            root.fail("empty path asks " + root.stubBackend.peekLog.join(",") + ", want nothing")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.path = "/x/y"
        pathCheckTimer.start()
    }

    // The path step alone asks the parent; the cursor never moved.
    function phasePath() {
        if (!root.asked("/x"))
            root.fail("path empty to /x/y asks no parent peek, want /x")
        if (root.failures.length > 0) { root.report(); return }
        root.stubBackend.peeked("/x", false, 0, [], false, 0, false, root.stubPane.windowSize)
        root.stubBackend.peekLog = []
        root.stubPane.path = "/"
        rootTimer.start()
    }

    // At the root no ancestor column is shown, so no peek goes out.
    function phaseRoot() {
        if (root.stubBackend.peekLog.length !== 0)
            root.fail("path /x/y to / asks " + root.stubBackend.peekLog.join(",") + ", want nothing")
        if (root.failures.length > 0) { root.report(); return }
        area.width = 1100
        area.visible = false
        root.stubBackend.peekLog = []
        root.stubPane.path = "/p/q"
        hiddenTimer.start()
    }

    // A hidden view asks nothing, though the width shows the parent and the path names one.
    function phaseHidden() {
        if (root.stubBackend.peekLog.length !== 0)
            root.fail("hidden view asks " + root.stubBackend.peekLog.join(",") + ", want nothing")
        if (root.failures.length > 0) { root.report(); return }
        area.visible = true
        hiddenOnTimer.start()
    }

    // Becoming visible re-asks the shown ancestors fresh from the path and width now in force.
    function phaseHiddenOn() {
        if (!root.asked("/p"))
            root.fail("visible again asks [" + root.stubBackend.peekLog.join(",") + "] at width=" + area.width + " path=" + root.stubPane.path + ", want /p")
        if (root.failures.length === 0)
            console.log("COLUMNSPEEKGATE PASS width=parent path=parent root=empty hidden=held visible=/p")
        root.reportFailures()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNSPEEKGATE FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    function reportFailures() {
        if (root.failures.length === 0) {
            Quickshell.execDetached(["kill", String(Quickshell.processId)])
            return
        }
        root.report()
    }
}
