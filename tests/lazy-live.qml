//@ pragma ShellId flea-lazy-objects-test

import QtQuick
import Quickshell

// p036lazy's live half: the GVFS bridge object does not exist before first use, and the same
// ensure that builds it serves a local path at once with no bridge start. tests/lazy-objects.sh drives it.
ShellRoot {
    id: root

    property bool finished: false

    function finish(message) {
        if (root.finished)
            return
        root.finished = true
        console.log(message)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    NetworkMounts {
        id: network

        onOpened: function (path) {
            if (path === "/tmp" && network.bridgeBuilt && network.bridge !== null)
                root.finish("LAZY_OBJECTS bridge=absent-then-built served-on-same-call")
            else
                root.finish("LAZY_OBJECTS FAIL opened=" + path)
        }
    }

    Timer {
        interval: 200
        running: true
        repeat: false
        onTriggered: {
            if (network.bridgeBuilt || network.bridge !== null) {
                root.finish("LAZY_OBJECTS FAIL bridge exists before first use")
                return
            }
            // A local folder needs no bridge: the same ensure that builds the object serves it.
            var bridge = network.ensureBridge()
            if (bridge === null || !network.bridgeBuilt) {
                root.finish("LAZY_OBJECTS FAIL ensure built nothing")
                return
            }
            bridge.ensure("/tmp", "tmp", null)
        }
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: root.finish("LAZY_OBJECTS FAIL timeout")
    }
}
