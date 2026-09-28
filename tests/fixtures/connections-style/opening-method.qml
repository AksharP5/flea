import QtQuick
Item {
    Connections { target: foo; function onReady() { console.log("ready") }
        onFailed: console.log("failed")
    }
}
