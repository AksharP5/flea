import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
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
            root.check("a stale history still asks at once, with what is kept", root.asked[0].recent, [])
            root.check("with the favourites as the rail holds them", root.asked[0].favourites, root.sources.favourites)
            root.type("o")
            root.check("no answer yet, so no dropdown", chrome.jump.shown, false)
            root.press(Qt.Key_Return)
            root.check("Enter on a name before the answer is held, not resolved as a path", [root.entered, chrome.editing], [[], true])
            chrome.jump.take(0, root.sources.favourites, root.sources.zoxide, root.sources.recent)
            root.check("an answer carrying no ask's id is dropped", [chrome.jump.shown, root.entered], [false, []])
            chrome.jump.take(1, root.sources.favourites, root.sources.zoxide, [])
            root.check("the provisional answer draws but does not spend the held Enter", [root.entered, chrome.editing], [[], true])
            root.check("its rows are the kept sources alone", root.rows(), [
                root.home + "/Projects", root.home + "/Documents/claude/omarchy", root.home + "/Documents",
                root.home + "/Downloads", root.home + "/Documents/claude/flea"])
            return true
        },
        // The whole ask waits for the provisional answer and the history read, in either order.
        function () { return root.asked.length === 2 },
        function () {
            root.check("the read history's files, newest first, on the whole ask", root.asked[1].recent,
                       [root.home + "/Pictures/screenshots/shot.png", root.home + "/Work/field/notes.md"])
            root.answer(0)
            root.check("this open's whole answer takes the held Enter to the first row", root.entered, [root.home + "/Projects"])
            root.check("and the bar closes", chrome.editing, false)
            chrome.startEdit()
            return true
        },
        function () { return root.asked.length === 3 },
        function () {
            root.answer(0)
            root.type("o")
            // No frecency in this answer, so the own-name matches go favourites first, then zoxide, then recent.
            root.check("query o lists one ranked list", root.rows(), [
                root.home + "/Projects", root.home + "/Documents/claude/omarchy", root.home + "/Documents",
                root.home + "/Downloads", root.home + "/Pictures/screenshots", root.home + "/Documents/claude/flea", root.home + "/Work/field"])
            root.check("the cursor opens on the first row", chrome.jump.cursor, 0)
            root.press(Qt.Key_Down); root.press(Qt.Key_Down); root.press(Qt.Key_Down)
            root.check("three downs move three rows", chrome.jump.cursor, 3)
            root.press(Qt.Key_Down); root.press(Qt.Key_Up); root.press(Qt.Key_Down)
            root.press(Qt.Key_Return)
            root.check("Enter opens the row under the cursor", root.entered[1], root.home + "/Pictures/screenshots")
            chrome.startEdit()
            return true
        },
        function () { return root.asked.length === 4 },
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
        function () { return root.asked.length === 5 },
        function () {
            root.answer(0)
            root.type("zzz")
            root.press(Qt.Key_Return)
            root.check("a name that matches nothing is still a relative path", root.entered[3], root.here + "/zzz")
            chrome.startEdit()
            return true
        },
        function () { return root.asked.length === 6 },
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
        function () { return root.asked.length === 7 },
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
        function () { return root.asked.length === 8 },
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
        function () { return root.asked.length === 9 },
        function () {
            root.answer(0)
            root.type("o")
            root.press(Qt.Key_Escape)
            root.check("esc closes the dropdown with the bar and opens nothing", [chrome.editing, chrome.jump.shown, root.entered.length], [false, false, 7])
            // The recent history is read once and kept: every open so far read nothing more.
            var before = root.asked.length
            chrome.startEdit()
            root.check("an open with the history unchanged asks at once, from what it kept", root.asked.length, before + 1)
            root.check("so the history was read once, by the first open", chrome.jump.historyReads, 1)
            root.press(Qt.Key_Escape)
            history.command = ["sh", "-c", root.rewrite, "sh", root.xbel, root.home]
            history.running = true
            return true
        },
        // The desktop replaces the file, the way GTK writes it: a temp and a rename.
        function () { return !history.running && Date.now() - root.stepStarted > root.settleMs },
        function () { chrome.startEdit(); return true },
        function () { return root.asked.length === 11 },
        function () {
            // The provisional take is what sends the whole ask: the backend never answers here.
            root.answer(0)
            return true
        },
        function () { return root.asked.length === 12 },
        function () {
            root.check("the next open reads the replaced history, once", chrome.jump.historyReads, 2)
            root.check("and asks with its newest file first", root.asked[11].recent[0], root.home + "/Music/new.flac")
            root.press(Qt.Key_Escape)
            history.command = ["sh", "-c", "rm -f -- \"$1\"", "sh", root.xbel]
            history.running = true
            return true
        },
        function () { return !history.running && Date.now() - root.stepStarted > root.settleMs },
        function () { chrome.startEdit(); return true },
        function () { return root.asked.length === 13 },
        function () {
            root.answer(0)
            return true
        },
        function () { return root.asked.length === 14 },
        function () {
            root.check("a history that is gone is read as empty", [root.asked[13].recent, chrome.jump.historyReads], [[], 3])
            root.press(Qt.Key_Escape)
            return true
        }
    ]

    // Where the history lives for this run, and one newer bookmark written over it by a temp and a rename.
    readonly property string xbel: Quickshell.env("XDG_DATA_HOME") + "/recently-used.xbel"
    readonly property string rewrite: "printf '<?xml version=\"1.0\"?><xbel version=\"1.0\"><bookmark href=\"file://%s/Music/new.flac\" "
        + "visited=\"2026-09-24T10:00:00Z\"/></xbel>' \"$2\" > \"$1.new\" && mv -- \"$1.new\" \"$1\""
    // Long enough for the change to reach the watcher, which inotify delivers within milliseconds.
    readonly property int settleMs: 300
    Process { id: history }

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
