import QtQuick
import QtTest
import Quickshell
import "flea" as Flea

// The folder jump's wiring through the real ui/ChromeBar.qml and ui/PathJump.qml, keys delivered by
// QtTest's TestEvent into an offscreen window. tests/jump-ui.sh plays the backend: this file records what
// the bar asks for and answers it by hand, which is what lets a stale answer and a missing one be staged.
ShellRoot {
    id: root
    readonly property string home: Quickshell.env("HOME")
    readonly property string here: root.home + "/Documents"
    readonly property var sources: ({
        favourites: [root.home + "/Projects", root.home + "/Documents/claude/flea", root.home + "/Documents/claude/omarchy"],
        zoxide: [root.home + "/Documents", root.home + "/Downloads"],
        recent: [root.home + "/Pictures/screenshots", root.home + "/Work/field"]
    })
    property var asked: []
    property var entered: []
    property var peeked: []
    property int checks: 0
    property int failures: 0
    property int stepIndex: 0
    property real stepStarted: 0
    property bool inStep: false

    function check(label, actual, expected) {
        root.checks++
        if (JSON.stringify(actual) === JSON.stringify(expected)) {
            console.log("ok   " + label)
            return
        }
        root.failures++
        console.log("FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function rows() {
        return chrome.jump.entries.filter(function (e) { return e.separator !== true }).map(function (e) { return e.path })
    }
    function type(text) {
        for (var i = 0; i < text.length; i++)
            keys.keyClickChar(text.charAt(i), Qt.NoModifier, -1)
    }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }
    function answer(offset) {
        var last = root.asked[root.asked.length - 1]
        chrome.jump.take(last.id + offset, root.sources.favourites, root.sources.zoxide, root.sources.recent)
    }
    // Each step returns true when it is done; a step that waits returns false until its condition holds.
    readonly property var steps: [
        function () { chrome.startEdit(); return true },
        function () { return root.asked.length === 1 },
        function () {
            var first = root.asked[0]
            root.check("one open asks once, with the favourites as the rail holds them", first.favourites, root.sources.favourites)
            root.check("and the recent history's files, newest first", first.recent,
                       [root.home + "/Pictures/screenshots/shot.png", root.home + "/Work/field/notes.md"])
            root.type("o")
            root.check("no answer yet, so no dropdown", chrome.jump.shown, false)
            root.press(Qt.Key_Return)
            root.check("Enter on a name before the answer is held, not resolved as a path", [root.entered, chrome.editing], [[], true])
            root.answer(-1)
            root.check("an answer carrying an earlier open's id is dropped", [chrome.jump.shown, root.entered], [false, []])
            root.answer(0)
            root.check("this open's answer takes the held Enter to the first row", root.entered, [root.home + "/Projects"])
            root.check("and the bar closes", chrome.editing, false)
            chrome.startEdit()
            return true
        },
        function () { return root.asked.length === 2 },
        function () {
            root.answer(0)
            root.type("o")
            root.check("query o lists the board's rows in the board's order", root.rows(), [
                root.home + "/Projects", root.home + "/Documents/claude/flea", root.home + "/Documents/claude/omarchy",
                root.home + "/Documents", root.home + "/Downloads", root.home + "/Pictures/screenshots", root.home + "/Work/field"])
            root.check("the cursor opens on the first row", chrome.jump.cursor, 0)
            root.press(Qt.Key_Down); root.press(Qt.Key_Down); root.press(Qt.Key_Down)
            root.check("three downs step over the separator", chrome.jump.cursor, 4)
            root.press(Qt.Key_Down); root.press(Qt.Key_Up); root.press(Qt.Key_Down)
            root.press(Qt.Key_Return)
            // Row 4 is ~/Documents, the folder the bar is on, which Enter leaves alone as a typed path does; row 5 is not.
            root.check("Enter opens the row under the cursor", root.entered[1], root.home + "/Downloads")
            chrome.startEdit()
            return true
        },
        function () { return root.asked.length === 3 },
        function () {
            root.answer(0)
            root.type("Wo")
            root.press(Qt.Key_Tab)
            return root.peeked.length === 1
        },
        function () {
            chrome.completeWith(root.peeked[0].dir, root.peeked[0].hidden, [{ n: "Work", d: true }])
            root.check("Tab completes the one child the way it always has", chrome.editText, "Work/")
            root.check("and a line with a slash lists nothing", chrome.jump.shown, false)
            root.press(Qt.Key_Return)
            root.check("so Enter opens the completed child", root.entered[2], root.here + "/Work")
            chrome.startEdit()
            return true
        },
        function () { return root.asked.length === 4 },
        function () {
            root.answer(0)
            root.type("zzz")
            root.press(Qt.Key_Return)
            root.check("a name that matches nothing is still a relative path", root.entered[3], root.here + "/zzz")
            chrome.startEdit()
            return true
        },
        function () { return root.asked.length === 5 },
        function () {
            root.type("o")
            root.press(Qt.Key_Return)
            root.check("a held Enter with no answer coming", [root.entered.length, chrome.editing], [4, true])
            return true
        },
        function () { return !chrome.editing || Date.now() - root.stepStarted > chrome.jump.answerLimitMs + 2000 },
        function () {
            root.check("resolves the line as a path once the answer limit passes", root.entered[4], root.here + "/o")
            chrome.startEdit()
            return true
        },
        function () { return root.asked.length === 6 },
        function () {
            root.type("o")
            root.press(Qt.Key_Return)
            root.type("x")
            root.check("a key typed behind a held Enter is not typed", chrome.editText, "o")
            root.answer(0)
            root.check("so the answer opens what the line held when Enter went down", root.entered[5], root.home + "/Projects")
            chrome.startEdit()
            return true
        },
        function () { return root.asked.length === 7 },
        function () {
            root.answer(0)
            root.type("Wo")
            root.check("Wo lists folders before Tab", chrome.jump.shown, true)
            root.press(Qt.Key_Tab)
            return root.peeked.length === 2
        },
        function () {
            chrome.completeWith(root.peeked[1].dir, root.peeked[1].hidden, [{ n: "Work", d: true }, { n: "Workshop", d: true }])
            root.check("two children stop Tab at their shared prefix, with no slash", chrome.editText, "Work")
            root.check("and a line Tab has touched lists nothing", chrome.jump.shown, false)
            root.press(Qt.Key_Return)
            root.check("so Enter opens ./Work as it always has", root.entered[6], root.here + "/Work")
            chrome.startEdit()
            return true
        },
        function () { return root.asked.length === 8 },
        function () {
            root.answer(0)
            root.type("o")
            root.press(Qt.Key_Escape)
            root.check("esc closes the dropdown with the bar and opens nothing", [chrome.editing, chrome.jump.shown, root.entered.length], [false, false, 7])
            return true
        }
    ]

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 600

        Item {
            anchors.fill: parent
            TestEvent { id: keys }
        }

        Flea.ChromeBar {
            id: chrome
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            path: root.here
            home: root.home
            onJumpRequested: function (id, favourites, recent) { root.asked = root.asked.concat([{ id: id, favourites: favourites, recent: recent }]) }
            onPathEntered: function (path) { root.entered = root.entered.concat([path]) }
            onCompleteRequested: function (dir, hidden) { root.peeked = root.peeked.concat([{ dir: dir, hidden: hidden }]) }
        }
    }

    Timer {
        interval: 10
        repeat: true
        running: root.stepIndex < root.steps.length
        onTriggered: {
            if (root.stepStarted === 0)
                root.stepStarted = Date.now()
            // QTest delivers a key through a nested event loop, which fires this timer again mid-step; it waits.
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
            } else if (Date.now() - root.stepStarted > chrome.jump.answerLimitMs + 5000) {
                root.failures++
                console.log("FAIL step " + root.stepIndex + " never completed")
                root.stepIndex = root.steps.length
            }
            root.inStep = false
            if (root.stepIndex >= root.steps.length)
                console.log("jump-ui: " + root.checks + " checks, " + root.failures + " failed")
        }
    }
}
