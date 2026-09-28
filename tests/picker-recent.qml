import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// Absent history: no rows, no warning on either read; a directory: no rows, one warning (checked in picker-recent.sh).
ShellRoot {
    id: root
    readonly property string home: Quickshell.env("HOME")
    readonly property string xbel: Quickshell.env("XDG_DATA_HOME") + "/recently-used.xbel"
    property int checks: 0
    property int failures: 0
    property int stepIndex: 0
    property real stepStarted: 0
    property bool inStep: false
    property int refreshed: 0
    // The model answers once at construction, so each step waits for one answer past the count it started from.
    property int before: 0

    function check(label, actual, expected) {
        root.checks++
        if (JSON.stringify(actual) === JSON.stringify(expected)) {
            console.log("ok   " + label)
            return
        }
        root.failures++
        console.log("FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }

    Flea.PickerRecent {
        id: recents
        onRefreshed: root.refreshed += 1
    }

    Process { id: writer }

    readonly property var steps: [
        function () {
            root.check("the history path is the desktop file", recents.file, root.xbel)
            root.before = root.refreshed
            recents.refresh()
            return true
        },
        function () { return root.refreshed === root.before + 1 },
        function () {
            root.check("an absent history answers no rows", recents.paths, [])
            root.before = root.refreshed
            recents.refresh()
            return true
        },
        function () { return root.refreshed === root.before + 1 },
        function () {
            root.check("a second read of the still-absent file answers no rows either", recents.paths, [])
            writer.command = ["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "sh", root.presentBody, root.xbel]
            writer.running = true
            return true
        },
        function () { return !writer.running },
        function () {
            root.before = root.refreshed
            recents.refresh()
            return true
        },
        function () { return root.refreshed === root.before + 1 },
        function () {
            root.check("a present history lists its bookmarks", recents.paths, [root.home + "/new.png", root.home + "/old.txt"])
            writer.command = ["sh", "-c", "rm -f \"$1\"; mkdir -p \"$1\"", "sh", root.xbel]
            writer.running = true
            return true
        },
        function () { return !writer.running },
        function () {
            root.before = root.refreshed
            recents.refresh()
            return true
        },
        function () { return root.refreshed === root.before + 1 },
        function () {
            root.check("a history path that is a directory answers no rows", recents.paths, [])
            console.log("picker-recent: " + root.checks + " checks, " + root.failures + " failed")
            Qt.exit(root.failures === 0 ? 0 : 1)
            return true
        }
    ]

    // Two bookmarks, the newer second in file order so the read has to sort it.
    readonly property string presentBody: "<?xml version=\"1.0\" encoding=\"UTF-8\"?><xbel version=\"1.0\">"
        + "<bookmark href=\"file://" + root.home + "/old.txt\" visited=\"2026-09-20T10:00:00Z\"/>"
        + "<bookmark href=\"file://" + root.home + "/new.png\" visited=\"2026-09-22T10:00:00Z\"/></xbel>"

    Timer {
        interval: 10
        repeat: true
        running: root.stepIndex < root.steps.length
        onTriggered: {
            if (root.stepStarted === 0)
                root.stepStarted = Date.now()
            if (root.inStep)
                return
            root.inStep = true
            var done = false
            try {
                done = root.steps[root.stepIndex]()
            } catch (error) {
                root.failures++
                console.log("FAIL step " + root.stepIndex + " threw: " + error)
                root.stepIndex = root.steps.length
            }
            if (done) {
                root.stepIndex++
                root.stepStarted = 0
            } else if (Date.now() - root.stepStarted > 10000) {
                root.failures++
                console.log("FAIL step " + root.stepIndex + " never completed")
                root.stepIndex = root.steps.length
            }
            root.inStep = false
            if (root.stepIndex >= root.steps.length && root.failures > 0)
                Qt.exit(1)
        }
    }
    Timer { interval: 15000; running: true; onTriggered: Qt.exit(1) }
}
