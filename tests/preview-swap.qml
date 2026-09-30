//@ pragma ShellId flea-preview-swap-test

import Quickshell
import QtQuick

// File-hold harness: the real PreviewSwap holds one file preview's picture while the next builds under it.
// Sample input: PREVIEW_SWAP_SURFACE=column PREVIEW_SWAP_DIRECT=1 mutates without a hold, the v0.3.4 defect control.
// Folder data-hold order is simulated here; tests/columnsfolder.qml drives the real ColumnsArea for it.
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
    // A column folder move holds by data: the old color stays until the peek lands.
    property string pendingFolder: ""
    // Folder-guard execution: when set, the move plan is skipped and the real swap proves its returns.
    readonly property bool folderGuard: Quickshell.env("PREVIEW_SWAP_FOLDERGUARD") === "1"
    // Swap.HOLD_MS is 150, so the real cap fires inside this wait; the positive control proves it.
    readonly property int guardWaitMs: 600
    // Guard loaders settle a frame after kickoff, so the start retries briefly before failing loud.
    readonly property int guardRetryLimit: 20
    readonly property int guardRetryMs: 50
    property int guardTries: 0
    property bool guardCapDone: false
    property bool guardPositiveDone: false
    property int guardCapFb0: 0
    property int guardPositiveFb0: 0

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
                source: shell.surfaceKind === "quicklook"
                    ? "file://" + shell.uiDir + "/QuickLookSwap.qml"
                    : "file://" + shell.uiDir + "/PreviewSwap.qml"
                onLoaded: {
                    item.burstEnds = shell.surfaceKind === "column"
                    item.ground = "#101315"
                    if (shell.surfaceKind === "quicklook") {
                        item.groundInset = 1
                        item.groundRadius = 8
                        item.panesSource = qlPanes
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

            // Folder-guard fixtures: three isolated swaps, so the readiness guard cannot mask the cap.
            Loader {
                id: guardCheckLoader
                x: 0
                y: 0
                width: 10
                height: 10
                active: shell.folderGuard
                source: shell.folderGuard ? "file://" + shell.uiDir + "/PreviewSwap.qml" : ""
            }
            Loader {
                id: guardCapLoader
                x: 10
                y: 0
                width: 10
                height: 10
                active: shell.folderGuard
                source: shell.folderGuard ? "file://" + shell.uiDir + "/PreviewSwap.qml" : ""
            }
            Loader {
                id: guardPositiveLoader
                x: 20
                y: 0
                width: 10
                height: 10
                active: shell.folderGuard
                source: shell.folderGuard ? "file://" + shell.uiDir + "/PreviewSwap.qml" : ""
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

    // One move holds the old picture while the next builds under it; a column folder waits by data with no hold.
    function move(kindIndex) {
        var kind = shell.kinds[kindIndex]
        var key = "/previews\n" + kindIndex
        var isPdf = kind === "pdf"
        // The decode landing: fast kinds well inside Swap.HOLD_MS, a PDF inside its longer cap.
        landTimer.interval = isPdf ? 200 : 60
        if (!shell.direct && shell.surfaceKind === "column" && kind === "folder") {
            shell.pendingFolder = kind
            landTimer.restart()
            return
        }
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
        landTimer.restart()
    }

    Timer {
        id: landTimer
        repeat: false
        onTriggered: {
            // The data-held folder lands with its rows in one pass, still under no picture.
            if (shell.pendingFolder !== "") {
                shell.currentKind = shell.pendingFolder
                shell.pendingFolder = ""
                shell.simReady = true
                settleTimer.restart()
                return
            }
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

    // The held check and the held cap stay holding; the unheld positive control must expire.
    function guardStart() {
        if (!guardCheckLoader.item || !guardCapLoader.item || !guardPositiveLoader.item) {
            shell.guardTries += 1
            if (shell.guardTries > shell.guardRetryLimit) {
                shell.log("FOLDERGUARD FAIL no guard item to drive")
                shell.quit()
                return
            }
            guardRetry.restart()
            return
        }
        var checkItem = guardCheckLoader.item
        checkItem.folderHold = true
        checkItem.holding = true
        checkItem.started = true
        checkItem.ready = true
        checkItem.check()
        if (checkItem.holding !== true) {
            shell.log("FOLDERGUARD FAIL held check released, want holding")
            shell.quit()
            return
        }
        var capItem = guardCapLoader.item
        capItem.folderHold = true
        capItem.holding = true
        capItem.started = true
        capItem.ready = true
        shell.guardCapFb0 = capItem.fallbacks
        capItem.start(false)
        var positiveItem = guardPositiveLoader.item
        positiveItem.folderHold = false
        positiveItem.holding = true
        positiveItem.started = true
        positiveItem.ready = false
        shell.guardPositiveFb0 = positiveItem.fallbacks
        positiveItem.start(false)
        guardCapTimer.restart()
        guardPositiveTimer.restart()
    }

    function guardFinish() {
        if (!shell.guardCapDone || !shell.guardPositiveDone)
            return
        shell.log("FOLDERGUARD DONE check=held cap=held positive=expired")
        shell.quit()
    }

    Timer {
        id: guardRetry
        interval: shell.guardRetryMs
        repeat: false
        onTriggered: shell.guardStart()
    }

    Timer {
        id: guardCapTimer
        interval: shell.guardWaitMs
        repeat: false
        onTriggered: {
            var capItem = guardCapLoader.item
            if (!capItem || capItem.holding !== true || capItem.fallbacks !== shell.guardCapFb0) {
                shell.log("FOLDERGUARD FAIL held cap expired, want holding with fallbacks unchanged")
                shell.quit()
                return
            }
            shell.guardCapDone = true
            shell.guardFinish()
        }
    }

    Timer {
        id: guardPositiveTimer
        interval: shell.guardWaitMs
        repeat: false
        onTriggered: {
            var positiveItem = guardPositiveLoader.item
            if (!positiveItem || positiveItem.holding !== false || positiveItem.fallbacks !== shell.guardPositiveFb0 + 1) {
                shell.log("FOLDERGUARD FAIL positive control saw no expiry, want released with one fallback")
                shell.quit()
                return
            }
            shell.guardPositiveDone = true
            shell.guardFinish()
        }
    }

    Timer {
        id: kickoff
        interval: 400
        repeat: false
        onTriggered: {
            if (shell.folderGuard) {
                shell.guardStart()
                return
            }
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
    // The settled grab reads the common parent, the way ui/Preview.qml holds both, so a half-built pane shows.
    function grabTarget() { return shell.surfaceKind === "quicklook" ? host : shell.swap }
    Timer {
        id: grabTimer
        interval: 200
        repeat: false
        onTriggered: {
            shell.pending += 1
            var target = shell.grabTarget()
            target.grabToImage(function (result) {
                result.saveToFile(shell.outDir + "/settled.png")
                shell.pending -= 1
                drain.restart()
            }, Qt.size(target.width, target.height))
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
