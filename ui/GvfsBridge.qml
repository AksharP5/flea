import QtQuick
import Quickshell
import Quickshell.Io
import "js/GvfsBridge.js" as GvfsBridge

// Phones and shares open through the GVFS FUSE bridge at $XDG_RUNTIME_DIR/gvfs, and gvfsd
// spawns its own bridge once at its startup only, so one that died stays down until
// something starts it again. ensure() checks the folder first: a served one opens at once
// and starts nothing, an unserved one starts gvfsd-fuse's own argv a single time and the
// folder opening waits for the folder rather than for the process. The window stays put
// either way until ready() carries the folder, and failed() carries the board's error line.
// Local folders never reach here: ui/NetworkMounts.qml only ensures FUSE paths gio resolved.
//
// This service lives in the window-long network host rather than in the rail, so hiding the
// rail mid-wait kills no wait: the ready or the failure still lands and the Starting line it
// showed still clears. The bridge itself starts detached, so closing the rail or the chooser
// never takes gvfsd-fuse down with it; no exit status ever reaches the board, and the whole
// ensure's own deadline is the failure signal instead.
Item {
    id: root

    signal ready(string path, var origin, bool isDir)
    signal starting(string text, var origin)
    signal failed(string text, var origin)
    signal notice(string text, var origin)

    // The test seam: FLEA_GVFS_FUSE names a fake bridge command the way FLEA_BIN names one.
    property string fuseEnv: Quickshell.env("FLEA_GVFS_FUSE") || ""
    property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    // Which question checkProcess is answering: the directory check, the file check, a wait
    // poll or the classify after a poll landed.
    property string pendingMode: ""
    // Set beside the deadline's own kill so the helper's late exit answers nothing: the
    // deadline already failed the wait, and that exit belongs to no waiter anymore.
    property bool _ensureTimedOut: false

    // D-103: flow, never state, which shadows Item.state and was the tree's own qmllint
    // property-override.
    property var flow: GvfsBridge.create()

    function dir() { return GvfsBridge.bridgeDir(root.runtimeDir) }

    function ensure(path, label, origin) {
        root.run(GvfsBridge.ensure(root.flow, { path: path, label: label, origin: origin,
            bridgeDir: root.dir(), fuseBin: GvfsBridge.fuseBin(root.fuseEnv) }))
    }

    function cancel() {
        root.pendingMode = ""
        if (checkProcess.running) { root._ensureTimedOut = true; checkProcess.running = false }
        root.stopWaiting()
        root.run(GvfsBridge.cancel(root.flow))
    }

    // A dialog cancel ends only its own flight's waiter; another flight's wait stands.
    function cancelFor(origin) {
        var waiter = root.flow.waiter
        if (waiter && origin !== null && waiter.origin !== origin) return
        root.cancel()
    }

    function run(actions) {
        for (var i = 0; i < actions.length; i++) {
            var action = actions[i]
            if (action.op === "check" || action.op === "checkFile" || action.op === "classify") {
                root.pendingMode = action.op
                // Directories answer -d, anything else -e: a file under a live bridge is ready
                // without any start, and only a path that is neither starts one.
                checkProcess.command = action.op === "check" || action.op === "classify"
                    ? ["test", "-d", action.path] : ["test", "-e", action.path]
                checkProcess.running = true
                ensureDeadline.restart()
            } else if (action.op === "start") {
                // Detached on purpose: an attached child dies with this service, and killing the
                // rail or the chooser must never take gvfsd-fuse down for every app. There is no
                // exit to wait for, so the folder poll below is the whole failure signal; the
                // single flight in ensure() above is what keeps one wait to one start, because a
                // detached spawn cannot be told apart from another one by a running flag.
                Quickshell.execDetached(action.argv)
                pollTimer.restart()
                startingTimer.restart()
                ensureDeadline.restart()
            } else if (action.op === "ready") {
                root.stopWaiting()
                root.ready(action.path, action.origin, action.isDir)
            } else if (action.op === "show") {
                root.starting(action.text, action.origin)
            } else if (action.op === "fail") {
                root.stopWaiting()
                root.failed(action.text, action.origin)
            } else if (action.op === "refuse") {
                root.notice(action.text, action.origin)
            }
        }
    }

    function stopWaiting() {
        ensureDeadline.stop()
        pollTimer.stop()
        startingTimer.stop()
    }

    // One deadline for the whole ensure, checking, file-checking, waiting and classifying.
    // Whichever leg is still running when it fires is the one that missed it. The flag is set
    // only beside a real kill, so a deadline that lands between two helpers arms nothing for a
    // later wait to swallow: one kill pairs with exactly one late exit.
    Timer {
        id: ensureDeadline
        interval: GvfsBridge.ENSURE_MS
        repeat: false
        onTriggered: {
            if (root.flow.phase === "idle" && !root.flow.waiter)
                return
            if (checkProcess.running) {
                root._ensureTimedOut = true
                checkProcess.running = false
            }
            root.stopWaiting()
            root.run(GvfsBridge.onTimeout(root.flow))
        }
    }

    Timer {
        id: startingTimer
        interval: GvfsBridge.STARTING_MS
        repeat: false
        onTriggered: root.run(GvfsBridge.onElapsed(root.flow))
    }

    Timer {
        id: pollTimer
        interval: GvfsBridge.POLL_MS
        repeat: true
        onTriggered: {
            if (checkProcess.running || !root.flow.waiter
                    || root.flow.phase !== "waiting")
                return
            root.pendingMode = "poll"
            checkProcess.command = ["test", "-e", root.flow.waiter.path]
            checkProcess.running = true
        }
    }

    Process {
        id: checkProcess
        onExited: function (exitCode) {
            if (root._ensureTimedOut) {
                root._ensureTimedOut = false
                root.pendingMode = ""
                return
            }
            var mode = root.pendingMode
            root.pendingMode = ""
            if (mode === "poll")
                root.run(GvfsBridge.onPolled(root.flow, exitCode === 0))
            else if (mode === "checkFile")
                root.run(GvfsBridge.onCheckedFile(root.flow, exitCode === 0))
            else if (mode === "classify")
                root.run(GvfsBridge.onClassified(root.flow, exitCode === 0))
            else
                root.run(GvfsBridge.onChecked(root.flow, exitCode === 0))
        }
    }
}
