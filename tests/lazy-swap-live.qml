//@ pragma ShellId flea-lazy-swap-test
import QtQuick
import Quickshell
// Live swap gate: wrapper absent at launch, whole (non-zero size) on first open.
ShellRoot {
    id: root
    property string uiDir: Quickshell.env("LAZY_SWAP_UI")
    property bool finished: false
    function finish(message) {
        if (root.finished) return
        root.finished = true
        console.log(message)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 600
        Item {
            id: host
            anchors.fill: parent
            Loader {
                id: previewLoader
                anchors.fill: parent
                source: "file://" + root.uiDir + "/Preview.qml"
                onStatusChanged: if (status === Loader.Error) root.finish("LAZY_SWAP FAIL preview did not load")
            }
        }
    }
    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: {
            var preview = previewLoader.item
            if (!preview) {
                root.finish("LAZY_SWAP FAIL preview never loaded")
                return
            }
            if (preview.swapBuilt || preview.swap !== null) {
                root.finish("LAZY_SWAP FAIL wrapper exists before first use")
                return
            }
            var swap = preview.ensureSwap()
            if (swap === null || !preview.swapBuilt) {
                root.finish("LAZY_SWAP FAIL ensure built nothing")
                return
            }
            if (swap.width <= 0 || swap.height <= 0) {
                root.finish("LAZY_SWAP FAIL wrapper built with zero size")
                return
            }
            // The wrapper captures Preview's own panes item through its panesSource,
            // the production wiring ui/Preview.qml sets and ui/QuickLookSwap.qml binds.
            if (!swap.panesSource || swap.captureSource !== swap.panesSource) {
                root.finish("LAZY_SWAP FAIL wrapper does not capture Preview panes")
                return
            }
            root.finish("LAZY_SWAP wrapper=absent-then-built size=" + swap.width + "x" + swap.height)
        }
    }
    Timer {
        interval: 10000
        running: true
        repeat: false
        onTriggered: root.finish("LAZY_SWAP FAIL timeout")
    }
}
