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
Item {
    id: root

    signal ready(string path, var origin)
    signal starting(string text, var origin)
    signal failed(string text, var origin)
    signal notice(string text, var origin)

    // The test seam: FLEA_GVFS_FUSE names a fake bridge command the way FLEA_BIN names one.
    property string fuseEnv: Quickshell.env("FLEA_GVFS_FUSE") || ""
    property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    // The C locale ui/NetworkMounts.qml pins on its own gio calls, passed in so one property sets it.
    property var environment: ({})
    property var state: GvfsBridge.create()
    // Which question checkProcess is answering: the opening check, a wait poll or the final
    // look after an exit.
    property string pendingMode: ""
    property bool _awaitingStart: false

    function dir() { return GvfsBridge.bridgeDir(root.runtimeDir) }

    function ensure(path, label, origin) {
        run(GvfsBridge.ensure(root.state, { path: path, label: label, origin: origin,
            bridgeDir: root.dir(), fuseBin: GvfsBridge.fuseBin(root.fuseEnv) }))
    }

    function run(actions) {
        for (var i = 0; i < actions.length; i++) {
            var action = actions[i]
            if (action.op === "check" || action.op === "verify") {
                root.pendingMode = action.op
                checkProcess.command = ["test", "-d", action.path]
                checkProcess.running = true
            } else if (action.op === "start") {
                root._awaitingStart = true
                bridgeProcess.command = action.argv
                bridgeProcess.running = true
                pollTimer.restart()
                startingTimer.restart()
            } else if (action.op === "ready") {
                stopWaiting()
                root.ready(action.path, action.origin)
            } else if (action.op === "show") {
                root.starting(action.text, action.origin)
            } else if (action.op === "fail") {
                stopWaiting()
                root.failed(action.text, action.origin)
            } else if (action.op === "refuse") {
                root.notice(action.text, action.origin)
            }
        }
    }

    function stopWaiting() {
        pollTimer.stop()
        startingTimer.stop()
    }

    Timer {
        id: startingTimer
        interval: GvfsBridge.STARTING_MS
        repeat: false
        onTriggered: root.run(GvfsBridge.onElapsed(root.state))
    }

    Timer {
        id: pollTimer
        interval: GvfsBridge.POLL_MS
        repeat: true
        onTriggered: {
            if (checkProcess.running || !root.state.waiter
                    || root.state.phase !== "waiting")
                return
            root.pendingMode = "poll"
            checkProcess.command = ["test", "-d", root.state.waiter.path]
            checkProcess.running = true
        }
    }

    Process {
        id: checkProcess
        onExited: function (exitCode) {
            var mode = root.pendingMode
            root.pendingMode = ""
            if (mode === "poll")
                root.run(GvfsBridge.onPolled(root.state, exitCode === 0))
            else if (mode === "verify")
                root.run(GvfsBridge.onVerified(root.state, exitCode === 0))
            else
                root.run(GvfsBridge.onChecked(root.state, exitCode === 0))
        }
    }

    Process {
        id: bridgeProcess
        // Attached rather than detached, so the exit status reaches the error line: the open
        // waits for the folder and not for this process, which is the detached half of it.
        environment: root.environment
        onStarted: root._awaitingStart = false
        onRunningChanged: {
            if (root._awaitingStart && !running) {
                root._awaitingStart = false
                root.run(GvfsBridge.onStartFailed(root.state))
            }
        }
        onExited: function (exitCode) {
            root.run(GvfsBridge.onExited(root.state, exitCode))
        }
    }
}
