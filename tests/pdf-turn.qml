//@ pragma ShellId flea-pdf-turn-test

import Quickshell
import QtQuick

// tests/pdf-turn.sh's harness: the real ui/PreviewPdf.qml (the preview column's page) or
// ui/PdfViewer.qml (Quick Look's) turns pages while every frame of the page area is saved, so the
// script can prove from pixels alone that no frame between two pages was drawn without one.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("PDF_TURN_UI")
    readonly property string surfaceKind: Quickshell.env("PDF_TURN_SURFACE")
    readonly property string outDir: Quickshell.env("PDF_TURN_OUT")
    // Forward over three unrendered pages, back and forth over two cached ones, onto the slow page,
    // then, as Quick Look does between two PDFs, the same surface opens another document.
    readonly property var plan: [1, 1, 1, -1, 1, 1, "switch"]
    readonly property int lightMs: 500
    readonly property int heavyMs: 1500
    readonly property real grabScale: 0.25

    property int step: -1
    property double stepStart: 0
    property bool capturing: false
    property int seq: 0
    property int pending: 0

    function log(line) { console.log("PDFTURN " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    // The page area only: PdfViewer's chrome carries a counter that changes on every turn by design.
    function area() {
        if (shell.surfaceKind === "column")
            return host
        var kids = loader.item.children
        for (var i = 0; i < kids.length; i++)
            if (kids[i].contentY !== undefined) return kids[i]
        return null
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 560
        color: "#303030"

        Rectangle {
            id: host
            // The OEM fallback background, the ground the column frame draws under a page.
            color: "#101315"
            x: 20
            y: 20
            width: 752
            height: 470

            Loader {
                id: loader
                anchors.fill: parent
                source: "file://" + shell.uiDir + (shell.surfaceKind === "column" ? "/PreviewPdf.qml" : "/PdfViewer.qml")
                onLoaded: {
                    item.path = Quickshell.env("PDF_TURN_PDF")
                    item.active = true
                }
                onStatusChanged: if (status === Loader.Error) { shell.log("FAIL the surface did not load"); shell.quit() }
            }
        }

        // A one-pixel change that makes the window draw, so a step whose turn changes nothing is still sampled.
        Rectangle { id: nudge; width: 1; height: 1; opacity: 0.02; color: flip ? "black" : "white"; property bool flip: false }

        Connections {
            target: host.Window.window
            function onAfterAnimating() {
                if (!shell.capturing)
                    return
                var s = ++shell.seq
                var t = Date.now() - shell.stepStart
                var step = shell.step
                var item = shell.area()
                shell.pending += 1
                item.grabToImage(function (result) {
                    result.saveToFile(shell.outDir + "/f-" + step + "-" + String(s).padStart(5, "0") + ".png")
                    shell.pending -= 1
                }, Qt.size(Math.round(item.width * shell.grabScale), Math.round(item.height * shell.grabScale)))
                shell.log("FRAME " + step + " " + s + " " + t)
            }
        }
    }

    Timer {
        id: waitDocument
        interval: 50
        running: true
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            if (loader.item && loader.item.pageCount === 5) {
                stop()
                settle.start()
            } else if (waited > 20000) {
                stop()
                shell.log("FAIL the document never opened")
                shell.quit()
            }
        }
    }

    Timer { id: settle; interval: 1500; onTriggered: shell.next() }

    function next() {
        shell.capturing = false
        if (shell.step + 1 > shell.plan.length) {
            drain.start()
            return
        }
        shell.step += 1
        shell.stepStart = Date.now()
        shell.capturing = true
        nudge.flip = !nudge.flip
        var action = shell.step > 0 ? shell.plan[shell.step - 1] : 0
        if (action === "switch")
            loader.item.path = Quickshell.env("PDF_TURN_OTHER")
        else if (action !== 0)
            loader.item.turn(action)
        shell.log("STEP " + shell.step + " page " + loader.item.page)
        stepTimer.interval = shell.step >= 6 ? shell.heavyMs : shell.lightMs
        stepTimer.restart()
    }

    Timer { id: stepTimer; onTriggered: shell.next() }

    Timer {
        id: drain
        interval: 200
        repeat: true
        onTriggered: {
            if (shell.pending > 0)
                return
            stop()
            shell.log("DONE " + shell.seq)
            shell.quit()
        }
    }
}
