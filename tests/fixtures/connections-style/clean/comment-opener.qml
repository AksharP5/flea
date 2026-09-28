import QtQuick
Item {
    // Connections { target: old; function onA() {} onB: f() }
    Connections {
        // Connections { was split per pane
        target: foo
        function onReady() { console.log("ready") }
    }
}
