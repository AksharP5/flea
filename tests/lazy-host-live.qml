import QtQuick
// Live host gate: ordered after rows paint, never synchronously, fallback when listing never lands.
Item {
    id: root
    property bool ordered: false
    property bool listInFlight: true
    property bool phaseB: false
    property int failures: 0
    function fail(text) {
        failures += 1
        console.log("LAZY_HOST FAIL " + text)
    }
    function done() {
        if (failures === 0) console.log("LAZY_HOST ordered-after-rows fallback-when-never-lands")
        Qt.exit(failures === 0 ? 0 : 1)
    }
    onListInFlightChanged: {
        if (!listInFlight && !ordered && !phaseB) afterRows.restart()
    }
    Timer {
        id: afterRows
        interval: 100
        repeat: false
        onTriggered: root.ordered = true
    }
    Timer {
        id: fallback
        interval: 2000
        repeat: false
        onTriggered: root.ordered = true
    }
    Timer {
        id: phaseA_trigger
        interval: 200
        running: true
        repeat: false
        onTriggered: {
            root.listInFlight = false
            if (root.ordered) root.fail("ordered synchronously with rows, expected after paint")
            phaseA_check.restart()
        }
    }
    Timer {
        id: phaseA_check
        interval: 250
        repeat: false
        onTriggered: {
            if (!root.ordered) {
                root.fail("never ordered after rows")
                root.done()
                return
            }
            root.ordered = false
            root.phaseB = true
            root.listInFlight = true
            fallback.restart()
            phaseB_early.restart()
        }
    }
    Timer {
        id: phaseB_early
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.ordered) {
                root.fail("fallback ordered too early")
                root.done()
                return
            }
            phaseB_late.restart()
        }
    }
    Timer {
        id: phaseB_late
        interval: 1300
        repeat: false
        onTriggered: {
            if (!root.ordered) root.fail("fallback never ordered a listing that never lands")
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
