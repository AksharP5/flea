//@ pragma ShellId flea-preview-swap-test

import Quickshell
import QtQuick

// tests/preview-swap.sh's harness: the real ui/PreviewSwap.qml holds one preview's
// picture while the next one builds under it, over every preview kind, on the column
// surface (burstEnds true) and on the Quick Look surface (burstEnds false). Moves run
// the same call sequence the product runs: ColumnsArea.moveThird plus
// SelectionPreview.replace/armSettle/load, or Preview.follow/load for Quick Look.
// Sample input: PREVIEW_SWAP_SURFACE=column PREVIEW_SWAP_DIRECT=1 skips the hold and
// mutates directly, which is the v0.3.4 shape and the control that proves the harness
// can see the defect it guards against.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("PREVIEW_SWAP_UI")
    readonly property string surfaceKind: Quickshell.env("PREVIEW_SWAP_SURFACE")
    readonly property string outDir: Quickshell.env("PREVIEW_SWAP_OUT")
    readonly property bool direct: Quickshell.env("PREVIEW_SWAP_DIRECT") === "1"
    // The ten preview kinds preview-moves.txt walks, there and back: folder, jpg, mp4,
    // pdf, txt, rs, odt, ttf, zip, png. A colour per kind is the settled state the judge
    // reads back; the swap's own midFrames counter is the verdict.
    readonly property var kinds: ["folder", "jpg", "mp4", "pdf", "txt", "rs", "odt", "ttf", "zip", "png"]
    readonly property var plan: [1, 2, 3, 4, 5, 6, 7, 8, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]

    property int step: -1
    property bool simReady: true
    property int pending: 0
    property int seq: 0

    function log(line) { console.log("PREVIEWSWAP " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    function kindColor(kind) {
        if (kind === "folder") return "#3a5f8a"
        if (kind === "jpg") return "#8a3a3a"
        if (kind === "mp4") return "#3a8a5f"
        if (kind === "pdf") return "#8a8a3a"
        if (kind === "txt") return "#5f3a8a"
        if (kind === "rs") return "#3a8a8a"
        if (kind === "odt") return "#8a5f3a"
        if (kind === "ttf") return "#5f8a3a"
        if (kind === "zip") return "#8a3a5f"
        return "#6a6a6a"
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
                id: swapLoader
                anchors.fill: parent
                source: "file://" + shell.uiDir + "/PreviewSwap.qml"
                onLoaded: {
                    item.burstEnds = shell.surfaceKind === "column"
                    item.ground = "#101315"
                    if (shell.surfaceKind === "quicklook") {
                        item.groundInset = 1
                        item.groundRadius = 8
                        item.captureSource = qlPanes
                    }
                }
                onStatusChanged: if (status === Loader.Error) { shell.log("FAIL the swap did not load"); shell.quit() }
            }

            // Quick Look production shape: panes stay eager outside the wrapper, which captures that outer item.
            Item {
                id: qlPanes
                anchors.fill: parent
                visible: shell.surfaceKind === "quicklook"
            }
        }
    }

    // The swap item once loaded; the content below is reparented into it.
    property var swap: swapLoader.item
    property string currentKind: "folder"

    Rectangle {
        id: previewBody
        visible: false
        width: 752
        height: 470
        color: shell.kindColor(shell.currentKind)
        Text {
            anchors.centerIn: parent
            text: shell.currentKind
            color: "white"
            font.pixelSize: 48
        }
    }

    // One move: hold the old picture, mutate under it, start the cap, land ready.
    function move(kindIndex) {
        var kind = shell.kinds[kindIndex]
        var key = "/previews\n" + kindIndex
        var isPdf = kind === "pdf"
        var apply = function () {
            shell.currentKind = kind
            shell.simReady = false
        }
        if (shell.direct) {
            apply()
        } else {
            if (shell.surfaceKind === "column") {
                // Column: hold the clear on the move, then the load holds again at work.
                shell.swap.hold(apply, key)
                shell.swap.hold(function () { shell.simReady = false }, key, true)
            } else {
                // Quick Look: follow holds with no apply, load mutates under the picture.
                shell.swap.hold(null, "/previews/" + kind)
                shell.swap.hold(apply, "/previews/" + kind, true)
            }
        }
        if (!shell.direct)
            shell.swap.start(isPdf)
        // The decode landing: fast kinds well inside Swap.HOLD_MS, a PDF inside its longer cap.
        landTimer.interval = isPdf ? 200 : 60
        landTimer.restart()
    }

    Timer {
        id: landTimer
        repeat: false
        onTriggered: {
            shell.simReady = true
            if (shell.swap)
                shell.swap.check()
            settleTimer.restart()
        }
    }

    Timer {
        id: settleTimer
        interval: 120
        repeat: false
        onTriggered: shell.next()
    }

    Timer {
        id: kickoff
        interval: 400
        repeat: false
        onTriggered: {
            if (!shell.swap) {
                shell.log("FAIL no swap item to drive")
                shell.quit()
                return
            }
            if (shell.surfaceKind === "quicklook" && shell.swap.captureSource === null) {
                shell.log("FAIL quicklook captures nothing without its panes source")
                shell.quit()
                return
            }
            // Column mutates inside the swap; Quick Look mutates its outer panes under the wrapper's picture.
            previewBody.visible = true
            previewBody.parent = shell.surfaceKind === "quicklook" ? qlPanes : shell.swap.contentItem()
            shell.next()
        }
    }

    function next() {
        if (shell.step + 1 >= shell.plan.length) {
            shell.finish()
            return
        }
        shell.step += 1
        shell.move(shell.plan[shell.step])
        shell.log("STEP " + shell.step + " kind " + shell.kinds[shell.plan[shell.step]])
    }

    function finish() {
        var s = shell.swap.describe()
        shell.log("DONE holds=" + s.holds + " fallbacks=" + s.fallbacks + " bursts=" + s.bursts
            + " held=" + s.heldFrames + " mid=" + s.midFrames + " loading=" + s.loadingFrames)
        grabTimer.restart()
    }

    property int grabSeq: 0
    Timer {
        id: grabTimer
        interval: 200
        repeat: false
        onTriggered: {
            shell.pending += 1
            shell.swap.grabToImage(function (result) {
                result.saveToFile(shell.outDir + "/settled.png")
                shell.pending -= 1
                drain.restart()
            }, Qt.size(shell.swap.width, shell.swap.height))
        }
    }

    Timer {
        id: drain
        interval: 200
        repeat: true
        onTriggered: {
            if (shell.pending > 0)
                return
            stop()
            shell.quit()
        }
    }

    Component.onCompleted: {
        // Bind ready after the swap loads; before that there is nothing to hold.
        waitSwap.restart()
    }

    Timer {
        id: waitSwap
        interval: 50
        repeat: true
        onTriggered: {
            if (swapLoader.item) {
                stop()
                // The swap reads readiness off the host; the binding below is that host.
                swapLoader.item.ready = Qt.binding(function () { return shell.simReady })
                kickoff.restart()
            }
        }
    }
}
