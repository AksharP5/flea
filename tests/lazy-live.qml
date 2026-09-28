//@ pragma ShellId flea-lazy-objects-test
import QtQuick
import Quickshell
// Live bridge gate: absent at launch, built on first ensure, local served on the same call.
ShellRoot {
    id: root
    property bool finished: false
    property bool ensureReturned: false
    property bool openedSync: false
    function finish(message) {
        if (root.finished) return
        root.finished = true
        console.log(message)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    NetworkMounts {
        id: network
        onOpened: function (path) {
            if (!root.ensureReturned && path === "/tmp") root.openedSync = true
            if (path === "/tmp" && network.bridgeBuilt && network.bridge !== null && root.openedSync)
                root.finish("LAZY_OBJECTS bridge=absent-then-built served-on-same-call")
            else if (path === "/tmp")
                root.finish("LAZY_OBJECTS FAIL opened=" + path + " sync=" + root.openedSync)
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
