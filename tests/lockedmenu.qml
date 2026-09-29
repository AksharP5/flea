//@ pragma ShellId flea-lockedmenu-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/lockedmenu.sh's harness: the real ui/ContextMenu.qml over stub owners, proving openLocked refuses empty and closes a stale frame.
ShellRoot {
    id: root

    readonly property string want: "Open in terminal, Permissions and Copy path are hidden in Settings > Menus."
    property int checks: 0
    property var failures: []
    property var refused: []

    function check(label, actual, expected) {
        root.checks += 1
        if (actual === expected) {
            console.log("LOCKEDMENU ok " + label)
            return
        }
        root.failures.push(label)
        console.log("LOCKEDMENU FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function report() {
        if (root.failures.length === 0)
            console.log("LOCKEDMENU PASS " + root.checks + " checks")
        root.quit()
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: Flea.Theme.color.background

        TextInput {
            id: probe
            width: 200
            height: 30
            focus: true
        }
        Flea.ContextMenu {
            id: menu
            focusOwner: probe
        }
    }

    Connections {
        target: menu
        function onRefused(reason) { root.refused.push(reason) }
    }

    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.run()
    }

    // All steps run synchronously: openLocked and openForRail build entries and move focus at once.
    function run() {
        Flea.ViewState.state = {}
        probe.forceActiveFocus()
        check("probe holds keyboard at start", probe.activeFocus, true)
        menu.openLocked("/locked", 0o040000, Qt.point(60, 60))
        check("all hidden refuses once", root.refused.length, 1)
        check("refusal names Menus switch", root.refused.length > 0 ? root.refused[0] : "", root.want)
        check("fresh refusal opens nothing", menu.opened, false)
        check("fresh refusal leaves no target", menu.lockedPath, "")
        check("fresh refusal keeps rail clear", menu.railEntries.length, 0)
        check("fresh refusal shows no frame", menu.visible, false)
        check("fresh refusal takes no focus", menu.keyboardFocused, false)
        check("fresh refusal keeps probe focus", probe.activeFocus, true)
        Flea.ViewState.state = ({ menu: ({ hidden: ["openTerminal", "permissions"] }) })
        menu.openLocked("/locked", 0o040000, Qt.point(60, 60))
        check("one row opens", menu.opened, true)
        check("one row targets folder", menu.lockedPath, "/locked")
        check("one row is locked menu", menu.forLocked, true)
        check("one row draws copypath alone", menu.entries.length, 1)
        check("one row action", menu.entries.length > 0 ? menu.entries[0].action : "", "copypath")
        check("success focuses catcher", menu.keyboardFocused, true)
        check("open adds no refusal", root.refused.length, 1)
        menu.close()
        Flea.ViewState.state = {}
        probe.forceActiveFocus()
        menu.openForRail("k1", [{ action: "open", label: "Open" }], Qt.point(10, 10))
        check("rail menu opens", menu.opened, true)
        menu.openLocked("/locked", 0o040000, Qt.point(60, 60))
        check("stale refusal refuses again", root.refused.length, 2)
        check("stale refusal names switch", root.refused.length > 1 ? root.refused[1] : "", root.want)
        check("stale refusal closes frame", menu.opened, false)
        check("stale refusal clears rail", menu.railEntries.length, 0)
        check("stale refusal clears target", menu.lockedPath, "")
        check("stale refusal shows no frame", menu.visible, false)
        check("stale refusal returns focus", probe.activeFocus, true)
        check("stale refusal drops catcher", menu.keyboardFocused, false)
        root.report()
    }
}
