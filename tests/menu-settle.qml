//@ pragma ShellId flea-menu-settle-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/menu-settle.sh's harness: the real ui/ContextMenu.qml placed again while open, with nothing new to draw, still ends its pointer settle.
ShellRoot {
    id: shell

    property int step: 0
    property double since: Date.now()
    // How long each wait may run: a settle ends on the next frame, so a second is already far past a stalled one.
    readonly property int openWaitMs: 3000
    readonly property int idleMs: 500
    readonly property int settleWaitMs: 1000

    function log(line) { console.log("MENU_SETTLE " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.ContextMenu { id: menu }
    }

    // One step per tick: open, wait for the open to settle, sit idle so no frame is pending, place again, wait again.
    function advance() {
        var waited = Date.now() - shell.since
        if (shell.step === 0 && waited >= shell.idleMs) {
            menu.openAt(Qt.point(60, 60))
            shell.log("opened rows=" + menu.entries.length + " settling=" + menu.pointerSettling)
            shell.step = 1
            shell.since = Date.now()
        } else if (shell.step === 1 && !menu.pointerSettling) {
            shell.log("the open settled in " + waited + " ms")
            shell.step = 2
            shell.since = Date.now()
        } else if (shell.step === 1 && waited > shell.openWaitMs) {
            shell.log("FAIL the open itself never settled")
            shell.step = 4
            shell.quit()
        } else if (shell.step === 2 && waited >= shell.idleMs) {
            menu.place(menu.mapToItem(null, menu.placeX, menu.placeY))
            shell.log("placed again while open settling=" + menu.pointerSettling)
            shell.step = 3
            shell.since = Date.now()
        } else if (shell.step === 3 && !menu.pointerSettling) {
            shell.log("PASS the second place settled in " + waited + " ms")
            shell.step = 4
            shell.quit()
        } else if (shell.step === 3 && waited > shell.settleWaitMs) {
            shell.log("FAIL a place that drew nothing left the settle standing for " + waited + " ms")
            shell.step = 4
            shell.quit()
        }
    }

    Timer {
        interval: 20
        repeat: true
        running: shell.step < 4
        onTriggered: shell.advance()
    }
}
