//@ pragma ShellId flea-lazy-objects-test
import QtQuick
import Quickshell
// Live bridge gate: absent at launch, built on first ensure, local served on the same call.
// Absent mode (LAZY_BRIDGE_ABSENT=1) runs the same probe in a tree without GvfsBridge.qml:
// the ensure answers null, the request finishes failed naming that file, with no retry.
ShellRoot {
    id: root
    property bool absent: Quickshell.env("LAZY_BRIDGE_ABSENT") === "1"
    property bool finished: false
    property bool ensureReturned: false
    property bool openedSync: false
    property string failMessage: ""
    property bool retried: false
    function finish(message) {
        if (root.finished) return
        root.finished = true
        console.log(message)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    NetworkMounts {
        id: network
        onOpened: function (path) {
            if (root.absent) {
                root.finish("LAZY_OBJECTS FAIL a missing bridge still opened " + path)
                return
            }
            if (!root.ensureReturned && path === "/tmp") root.openedSync = true
            if (path === "/tmp" && network.bridgeBuilt && network.bridge !== null && root.openedSync)
                root.finish("LAZY_OBJECTS bridge=absent-then-built served-on-same-call")
            else if (path === "/tmp")
                root.finish("LAZY_OBJECTS FAIL opened=" + path + " sync=" + root.openedSync)
            else
                root.finish("LAZY_OBJECTS FAIL opened=" + path)
        }
        onMessage: function (text, isError) {
            if (root.absent && isError) root.failMessage = text
        }
        onRetryRequested: function () {
            if (root.absent) root.retried = true
        }
    }
    function absentPhase() {
        if (network.bridge !== null) {
            root.finish("LAZY_OBJECTS FAIL bridge built without its file")
            return
        }
        // The production missing-component path: a null ensure names its file and ends failed.
        var missing = network.ensureBridge()
        if (missing !== null || network.bridge !== null) {
            root.finish("LAZY_OBJECTS FAIL ensure answered without its file")
            return
        }
        network.failBridgeMissing()
        checkAbsent.restart()
    }
    Timer {
        id: checkAbsent
        interval: 250
        repeat: false
        onTriggered: {
            if (root.retried)
                root.finish("LAZY_OBJECTS FAIL missing bridge asked for a password retry")
            else if (network.result !== "failed")
                root.finish("LAZY_OBJECTS FAIL missing bridge finished " + network.result)
            else if (root.failMessage.indexOf("GvfsBridge.qml") < 0)
                root.finish("LAZY_OBJECTS FAIL missing bridge never named its file")
            else
                root.finish("LAZY_OBJECTS bridge-absent-fails-naming-file")
        }
    }
    Timer {
        interval: 200
        running: true
        repeat: false
        onTriggered: {
            if (root.absent) {
                root.absentPhase()
                return
            }
            if (network.bridgeBuilt || network.bridge !== null) {
                root.finish("LAZY_OBJECTS FAIL bridge exists before first use")
                return
            }
            var bridge = network.ensureBridge()
            if (bridge === null || !network.bridgeBuilt) {
                root.finish("LAZY_OBJECTS FAIL ensure built nothing")
                return
            }
            root.ensureReturned = false
            root.openedSync = false
            bridge.ensure("/tmp", "tmp", null)
            root.ensureReturned = true
            if (!root.openedSync) root.finish("LAZY_OBJECTS FAIL ensure did not serve on the same call")
        }
    }
    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: root.finish("LAZY_OBJECTS FAIL timeout")
    }
}
