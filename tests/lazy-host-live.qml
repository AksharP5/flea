//@ pragma ShellId flea-lazy-host-test
import QtQuick
import Quickshell
// Live host gate: production NetworkHostGate orders after rows paint, never synchronously, with fallback.
ShellRoot {
    id: root
    property string uiDir: Quickshell.env("LAZY_HOST_UI")
    property bool finished: false
    property int failures: 0
    property int orderCount: 0
    property int orderCountB: 0
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
    // Stub pane holding the binding WindowBody sets, false before the first open.
    QtObject {
        id: stubPane
        property bool inFlight: false
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
            if (gateA.item.listInFlight !== false) {
                root.fail("the production gate defaults listInFlight true, expected false")
                root.done()
                return
            }
            gateA.item.orderRequested.connect(function () { root.orderCount += 1 })
            gateB.item.orderRequested.connect(function () { root.orderCountB += 1 })
            // Bind like WindowBody does, so a true default would flip false here and order early.
            gateA.item.listInFlight = Qt.binding(function () { return stubPane.inFlight })
            noEarly.restart()
            earlyB.restart()
        }
    }
    // No order before any listing: catches a creation true-to-false edge starting afterRows.
    Timer {
        id: noEarly
        interval: 150
        repeat: false
        onTriggered: {
            if (gateA.item.ordered || root.orderCount !== 0) {
                root.fail("ordered before any listing, expected silence until rows land")
                root.done()
                return
            }
            stubPane.inFlight = true
            stubPane.inFlight = false
            earlyCheck.restart()
            checkA.restart()
        }
    }
    // Lower bound after rows land: catches an interval of 0 or a Qt.callLater order.
    Timer {
        id: earlyCheck
        interval: 50
        repeat: false
        onTriggered: {
            if (gateA.item.ordered) root.fail("ordered synchronously with rows, expected after paint")
        }
    }
    Timer {
        id: checkA
        interval: 250
        repeat: false
        onTriggered: {
            if (!gateA.item.ordered) root.fail("never ordered after rows")
            else if (root.orderCount !== 1) root.fail("expected exactly one order, got " + root.orderCount)
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
            if (root.orderCountB !== 1) root.fail("expected exactly one fallback order, got " + root.orderCountB)
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
