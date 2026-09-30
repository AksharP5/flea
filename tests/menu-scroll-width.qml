//@ pragma ShellId flea-menu-scroll-width-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/menu-scroll-width.sh's harness: a context menu keeps no scrollbar gutter at rest or overflowing, while an ordinary CardScroll keeps its lane; see ui/CardScroll.qml.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property string shortNote: ""

    function log(line) { console.log("MENUSCROLL " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (!cond) shell.failures.push(name + " got " + detail)
    }
    function isType(o, name) {
        var s = String(o)
        return s.indexOf(name) === 0 || s.indexOf("QQuick" + name) === 0
    }
    function findFirst(item, name) {
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o !== item && shell.isType(o, name)) return o
            var kids = (o && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return null
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.CardScroll {
            id: plain
            width: 320
            height: 200
            Column { width: parent.width; Text { text: "one" } }
        }

        Flea.ContextMenu {
            id: menu
            anchors.fill: parent
            opened: true
        }
    }

    // Sample input: entries(2, false) is two file rows; withSub puts a flyout on the first.
    function entries(n, withSub) {
        var out = []
        for (var i = 0; i < n; i++) {
            var e = { label: "Row " + i, action: "noop" + i, glyph: "file" }
            if (withSub && i === 0)
                e.submenu = [{ id: "a", label: "App A" }, { id: "b", label: "App B" }]
            out.push(e)
        }
        return out
    }

    function ready(main) {
        return main && main.contentHeight > 0 && main.holderWidth > 0
    }

    function measure(tag, expectOverflow) {
        var pad = Flea.Theme.spacing.rowPaddingX
        var main = shell.findFirst(menu.frameItem, "CardScroll")
        var sub = shell.findFirst(menu.submenuFrameItem, "CardScroll")
        var bar = main ? shell.findFirst(main, "ViewportScrollBar") : null
        if (!main || !sub || !bar) {
            shell.failures.push(tag + " menu bodies not found")
            return ""
        }
        // The ordinary scroll keeps its lane; both menu bodies keep none, short or overflowing.
        shell.check(tag + ":plain-gutter", plain.gutter === pad, String(plain.gutter))
        shell.check(tag + ":plain-holder", plain.holderWidth === plain.width - pad,
                    String(plain.holderWidth))
        shell.check(tag + ":main-gutter", main.gutter === 0, String(main.gutter))
        shell.check(tag + ":main-holder", main.holderWidth === main.width, String(main.holderWidth))
        shell.check(tag + ":main-row", menu.itemFor(0).width === main.holderWidth,
                    String(menu.itemFor(0).width))
        shell.check(tag + ":flyout-gutter", sub.gutter === 0, String(sub.gutter))
        shell.check(tag + ":flyout-holder", sub.holderWidth === sub.width, String(sub.holderWidth))
        shell.check(tag + ":overflow", bar.overflow === expectOverflow, String(bar.overflow))
        // No resting chrome: the bar overlays while used and shows nothing standing still.
        shell.check(tag + ":resting", bar.shown === false, String(bar.shown))
        return tag + " frame=" + Math.round(main.width) + " holder=" + Math.round(main.holderWidth)
            + " overflow=" + bar.overflow + " flyout=" + Math.round(sub.width)
            + " plain=" + Math.round(plain.width) + "/" + Math.round(plain.holderWidth)
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function advance() {
        shell.ticks += 1
        var main = menu.frameItem ? shell.findFirst(menu.frameItem, "CardScroll") : null
        if (shell.phase === 0 && shell.ticks >= 2) {
            menu.entries = shell.entries(3, true)
            menu.openSubmenu(0)
            shell.phase = 1
            shell.ticks = 0
        } else if (shell.phase === 1 && (shell.ready(main) || shell.ticks > 50)) {
            shell.shortNote = shell.measure("short", false)
            menu.entries = shell.entries(60, true)
            menu.openSubmenu(0)
            shell.phase = 2
            shell.ticks = 0
        } else if (shell.phase === 2 && (shell.ready(main) || shell.ticks > 50)) {
            var longNote = shell.measure("long", true)
            if (shell.failures.length === 0)
                shell.log("PASS " + shell.shortNote + " " + longNote
                          + " text=" + Flea.Theme.font.body + "/" + Flea.Theme.font.caption
                          + " pad=" + Flea.Theme.spacing.rowPaddingX)
            else
                for (var i = 0; i < shell.failures.length; i++)
                    shell.log("FAIL " + shell.failures[i])
            shell.log("DONE failures=" + shell.failures.length)
            shell.phase = 3
            shell.quit()
        }
    }
}
