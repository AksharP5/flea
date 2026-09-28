import QtQuick

// Orders the network host once, a beat after the first rows or at the fallback if they never land.
Item {
    id: root
    // False until a real listing starts, so the creation binding never fires the edge.
    property bool listInFlight: false
    property int afterRowsMs: 100
    property int fallbackMs: 2000
    property bool ordered: false
    signal orderRequested()
    // One order only: the host build is not repeatable and the fallback stops here.
    function order() {
        if (root.ordered) return
        root.ordered = true
        root.orderRequested()
    }
    onListInFlightChanged: {
        if (!root.listInFlight && !root.ordered) afterRows.restart()
    }
    Timer {
        id: afterRows
        interval: root.afterRowsMs
        repeat: false
        onTriggered: root.order()
    }
    Timer {
        id: fallback
        interval: root.fallbackMs
        running: !root.ordered
        repeat: false
        onTriggered: root.order()
    }
}
