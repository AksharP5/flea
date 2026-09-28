import QtQuick
Item {
    Connections { target: foo; onFailed: console.log("failed")
        function onReady() { console.log("ready") }
    }
}
