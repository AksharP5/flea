//@ pragma ShellId flea-lazy-host-test
import QtQuick
import Quickshell
// Live host gate: the production ui/NetworkHostGate.qml orders after rows paint,
// never synchronously, with a fallback when the listing never lands. The gates
// below are the production file through a Loader, not a copy, so a change to it
// turns this red. tests/lazy-objects.sh drives it.
ShellRoot {
    id: root
    property string uiDir: Quickshell.env("LAZY_HOST_UI")
    property bool finished: false
    property int failures: 0
    function fail(text) {
        failures += 1
        console.log("LAZY_HOST FAIL " + text)
    }
    function done() {
        if (root.finished) return
        root.finished = true
        if (failures === 0) console.log("LAZY_HOST ordered-after-rows fallback-when-never-lands")
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    Loader {
        id: gateA
        source: "file://" + root.uiDir + "/NetworkHostGate.qml"
        onStatusChanged: if (status === Loader.Error) root.fail("the production gate did not load")
    }
    Loader {
        id: gateB
        source: "file://" + root.uiDir + "/NetworkHostGate.qml"
        onStatusChanged: if (status === Loader.Error) root.fail("the fallback gate did not load")
    }
    Timer {
        id: kick
        interval: 200
        running: true
        repeat: false
        onTriggered: {
            if (!gateA.item || !gateB.item) {
                root.fail("the production gate built nothing")
                root.done()
                return
            }
            if (gateA.item.afterRowsMs !== 100 || gateA.item.fallbackMs !== 2000) {
                root.fail("the production gate defaults moved")
                root.done()
                return
            }
            gateA.item.listInFlight = false
            if (gateA.item.ordered) root.fail("ordered synchronously with rows, expected after paint")
            checkA.restart()
            earlyB.restart()
        }
    }
    Timer {
        id: checkA
        interval: 250
        repeat: false
        onTriggered: {
            if (!gateA.item.ordered) root.fail("never ordered after rows")
        }
    }
    Timer {
        id: earlyB
        interval: 1000
        repeat: false
        onTriggered: {
            if (gateB.item.ordered) {
                root.fail("fallback ordered too early")
                root.done()
            }
        }
    }
    Timer {
        id: lateB
        interval: 2400
        running: true
        repeat: false
        onTriggered: {
            if (!gateB.item || !gateB.item.ordered) root.fail("fallback never ordered a listing that never lands")
            root.done()
        }
    }
    Timer {
        id: guard
        interval: 8000
        running: true
        repeat: false
        onTriggered: {
            root.fail("timeout")
            root.done()
        }
    }
}
