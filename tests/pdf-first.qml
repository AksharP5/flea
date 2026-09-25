//@ pragma ShellId flea-pdf-first-test

import Quickshell
import QtQuick

// tests/pdf-first.sh's harness: the real ui/PreviewPdf.qml opens a two-page document with a slow
// first page, turns before that render lands, and logs its state every 15 ms, so the script can
// prove the turn left the cap alone while no page was shown and the second page still landed.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("PDF_FIRST_UI")
    readonly property string pdfPath: Quickshell.env("PDF_FIRST_PDF")

    property double turnAt: 0

    function log(line) { console.log("PDFFIRST " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function state() {
        var item = loader.item
        return "page=" + item.page + " shown=" + item.shownPage + " fellBack=" + (item.fellBack ? 1 : 0)
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 560
        color: "#303030"

        Rectangle {
            id: host
            color: "#101315"
            x: 20
            y: 20
            width: 752
            height: 470

            Loader {
                id: loader
                anchors.fill: parent
                source: "file://" + shell.uiDir + "/PreviewPdf.qml"
                onLoaded: {
                    item.path = shell.pdfPath
                    item.active = true
                }
                onStatusChanged: if (status === Loader.Error) { shell.log("FAIL the surface did not load"); shell.quit() }
            }
        }
    }

    // The document reports both pages once its first render starts; the turn follows about 50 ms later, while that slow render is still in flight.
    Timer {
        id: waitDocument
        interval: 10
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            waited += interval
            if (loader.item && loader.item.pageCount === 2) {
                stop()
                turnTimer.restart()
            } else if (waited > 20000) {
                stop()
                shell.log("FAIL the document never opened")
                shell.quit()
            }
        }
    }

    Timer {
        id: turnTimer
        interval: 50
        onTriggered: {
            shell.turnAt = Date.now()
            loader.item.turn(1)
            shell.log("TURN " + shell.state())
            stateTimer.restart()
            doneTimer.restart()
        }
    }

    Timer {
        id: stateTimer
        interval: 15
        repeat: true
        onTriggered: shell.log("STATE " + (Date.now() - shell.turnAt) + " " + shell.state())
    }

    Timer {
        id: doneTimer
        interval: 50
        repeat: true
        onTriggered: {
            if (loader.item && loader.item.shownPage === 1) {
                stop()
                stateTimer.stop()
                shell.log("DONE")
                shell.quit()
            } else if (Date.now() - shell.turnAt > 5000) {
                stop()
                stateTimer.stop()
                shell.log("FAIL the second page never showed")
                shell.quit()
            }
        }
    }
}
