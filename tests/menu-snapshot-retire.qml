//@ pragma ShellId flea-menu-snapshot-retire-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/menu-snapshot-retire.sh's harness: a snapshot reply after its dismissed menu retires silently.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property int expectId: 0

    function log(line) { console.log("SNAPRETIRE " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (cond) shell.log("PASS " + name)
        else shell.failures.push(name + " got " + detail)
    }

    Item {
        // Sample reply: {op:"snapshot", id:1, ok:true}; a refusal carries ok:false with its error.
        Item {
            id: stubBackend
            signal menuResult(var message)
            signal formatsResult(var message)
            signal changed(string path)
            signal located(var message)
            signal localSendPeers(var peers, string reason)
            signal localSendSent(bool ok, string reason)
            signal failed(string where, string input, string message, int mode)
            property var sent: []
            function send(m) { sent.push(m) }
            function askFormats() { return 0 }
        }

        Item {
            id: stubMenu
            property bool opened: false
            property bool hasRow: true
            function refreshProviderRows() {}
            function providersSettled() {}
            function validateChoice(action, subId) { return true }
        }

        Item {
            id: stubPane
            property string menuSelectionIdentity: "ID-A"
            property string path: "/payload"
            property int cursorIndex: 0
            property bool listInFlight: false
            property var backend: stubBackend
            property var taildropService: null
            property var dropboxService: null
            property var messages: []
            function contextMenu() { return stubMenu }
            function message(text, isError) { messages.push(text + "|" + isError) }
        }
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.PaneMenuActions {
            id: actions
            pane: stubPane
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    // Each phase snapshots, reorders the reply behind a refresh, then delivers it explicitly.
    function advance() {
        shell.ticks += 1
        if (shell.ticks < 2) return
        if (shell.phase === 0) {
            stubMenu.opened = true
            actions.snapshot([0])
            shell.expectId = actions.requestId
            stubMenu.opened = false
            stubPane.menuSelectionIdentity = "ID-B"
            stubBackend.menuResult({op: "snapshot", id: shell.expectId, ok: true})
            shell.check("dismissed-stale-silent", stubPane.messages.length === 0 && !actions.ready,
                stubPane.messages.join(";") + " ready=" + actions.ready)
            shell.phase = 1
        } else if (shell.phase === 1) {
            stubPane.messages = []
            stubPane.menuSelectionIdentity = "ID-A"
            stubMenu.opened = true
            actions.snapshot([0])
            shell.expectId = actions.requestId
            stubPane.menuSelectionIdentity = "ID-B"
            stubBackend.menuResult({op: "snapshot", id: shell.expectId, ok: true})
            shell.check("open-stale-refuses", stubPane.messages.length === 1
                && stubPane.messages[0] === "Selected items changed; reopen the menu.|true",
                stubPane.messages.join(";"))
            stubMenu.opened = false
            shell.phase = 2
        } else if (shell.phase === 2) {
            stubPane.messages = []
            stubPane.menuSelectionIdentity = "ID-A"
            actions.snapshot([0])
            shell.expectId = actions.requestId
            stubBackend.menuResult({op: "snapshot", id: shell.expectId, ok: false, error: "backend broke"})
            shell.check("dismissed-refusal-reports", stubPane.messages.length === 1
                && stubPane.messages[0] === "backend broke|true", stubPane.messages.join(";"))
            shell.phase = 3
        } else if (shell.phase === 3) {
            stubPane.messages = []
            stubPane.menuSelectionIdentity = "ID-A"
            actions.snapshot([0])
            shell.expectId = actions.requestId
            stubBackend.menuResult({op: "snapshot", id: shell.expectId, ok: true, count: 2})
            shell.check("dismissed-fresh-readies", stubPane.messages.length === 0 && actions.ready,
                stubPane.messages.join(";") + " ready=" + actions.ready)
            shell.phase = 4
        } else if (shell.phase === 4) {
            stubPane.messages = []
            stubPane.menuSelectionIdentity = "ID-A"
            actions.snapshot([0])
            shell.expectId = actions.requestId
            actions.open("copyTo")
            stubMenu.opened = false
            stubPane.menuSelectionIdentity = "ID-B"
            stubBackend.menuResult({op: "snapshot", id: shell.expectId, ok: true})
            shell.check("waiting-action-refuses", stubPane.messages.length === 1
                && stubPane.messages[0] === "Selected items changed; reopen the menu.|true",
                stubPane.messages.join(";"))
            for (var i = 0; i < shell.failures.length; i++)
                shell.log("FAIL " + shell.failures[i])
            shell.log("DONE failures=" + shell.failures.length)
            shell.phase = 5
            shell.quit()
        }
    }
}
