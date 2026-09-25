//@ pragma ShellId flea-arm-prompt-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Status.js" as Status
import "flea/js/Trash.js" as Trash

// tests/arm-prompt.sh's harness, on its own clock: the real ui/StatusBar.qml shows a dd prompt only while its arm lives and leaves nothing stale, and the real ui/TrashView.qml disarms on another key and on choose().
ShellRoot {
    id: shell

    readonly property string prompt: "Press d again to trash, or Delete on its own."
    readonly property string notice: "Renamed to notes.txt"
    // How much of the arm's clock is left when the expiry leg arms, and how long past it the harness waits before calling it stuck.
    readonly property int clockLeftMs: 100
    readonly property int clockGraceMs: 1000
    property int step: 0
    property double stamp: 0
    property int checks: 0
    property var failures: []

    function check(label, actual, expected) {
        shell.checks += 1
        if (actual === expected) {
            console.log("ARM_PROMPT ok " + label)
            return
        }
        shell.failures.push(label)
        console.log("ARM_PROMPT FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function finish() {
        console.log("ARM_PROMPT DONE " + shell.checks + " checks, " + shell.failures.length + " failed")
        shell.step = 9
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    // The owner a pane or the Trash view is to the bar: all it reads and writes is the stamp.
    QtObject {
        id: owner
        property double trashArmedAt: 0
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 600
        color: "#303030"

        Flea.StatusBar {
            id: bar
            width: 800
            armOwner: owner
        }

        Flea.TrashView {
            id: view
            y: 40
            width: 800
            height: 500
        }

        TestEvent { id: keys }
    }

    // What ui/TrashHost.qml does with the view's reports, so its dd prompt reaches this bar as it does in the window.
    Connections {
        target: view
        function onStatusReported(message, error) { bar.say(message, error) }
    }

    // The owner stamps, then says its prompt, the order ui/js/Trash.js and ui/TrashView.qml keep.
    function arm(stampedAt) {
        owner.trashArmedAt = stampedAt
        bar.say(shell.prompt, false)
    }

    function disarmLeg() {
        bar.say(shell.notice, false)
        shell.check("a notice is up before the arm", bar.transient_, shell.notice)
        shell.arm(Date.now())
        shell.check("the arm's prompt shows", bar.transient_, shell.prompt)
        shell.check("and the notice it covered is gone while the arm lives", bar.notice, "")
        owner.trashArmedAt = 0
        shell.check("the owner's disarm ends the prompt at once", bar.prompt + "|" + (bar.arm === null), "|true")
        shell.check("and leaves nothing stale on the bar", bar.transient_, "")
    }

    function clockLeg() {
        bar.say(shell.notice, false)
        shell.stamp = Date.now() - Trash.ARM_MS + shell.clockLeftMs
        shell.arm(shell.stamp)
        shell.check("an arm with " + shell.clockLeftMs + " ms left shows its prompt", bar.transient_, shell.prompt)
        shell.check("over nothing it covered", bar.notice, "")
    }

    function clockEnded() {
        shell.check("the clock ends the arm no earlier than its own " + Trash.ARM_MS + " ms", Date.now() - shell.stamp >= Trash.ARM_MS, true)
        shell.check("and the bar shows nothing stale after it", bar.transient_, "")
        shell.check("and the owner is disarmed with it", owner.trashArmedAt, 0)
    }

    function viewLeg() {
        view.forceActiveFocus()
        shell.check("the Trash view holds the keyboard", view.activeFocus, true)
        view.trashArmedAt = Date.now()
        keys.keyClickChar("j", Qt.NoModifier, -1)
        shell.check("j disarms the Trash view", view.trashArmedAt, 0)
        view.trashArmedAt = Date.now()
        keys.keyClickChar("m", Qt.NoModifier, -1)
        shell.check("m, which moves nothing, disarms it through the key handler alone", view.trashArmedAt, 0)
        view.trashArmedAt = Date.now()
        view.choose(0, false)
        shell.check("choose() disarms it", view.trashArmedAt, 0)
        // The firing pair, with the view as the bar's owner the way ui/WindowBody.qml sets it while the view is open.
        bar.armOwner = view
        view.selected = ({ "trash:///fixture.txt": true })
        keys.keyClickChar("d", Qt.NoModifier, -1)
        shell.check("the view's first d arms it and draws its prompt on the bar",
                    (view.trashArmedAt > 0) + "|" + Status.isPrompt(bar.transient_), "true|true")
        keys.keyClickChar("d", Qt.NoModifier, -1)
        shell.check("the second d spends the arm", view.trashArmedAt, 0)
        shell.check("so the bar shows no prompt over the review", bar.transient_, "")
        shell.check("and the review opens", view.confirming, true)
    }

    function advance() {
        if (shell.step === 0) {
            shell.disarmLeg()
            shell.clockLeg()
            shell.step = 1
        } else if (shell.step === 1 && bar.arm === null) {
            shell.clockEnded()
            shell.viewLeg()
            shell.finish()
        } else if (shell.step === 1 && Date.now() - shell.stamp > Trash.ARM_MS + shell.clockGraceMs) {
            shell.check("the arm's clock ended it", bar.arm === null, true)
            shell.viewLeg()
            shell.finish()
        }
    }

    Timer {
        interval: 20
        repeat: true
        running: shell.step < 9
        onTriggered: shell.advance()
    }
}
