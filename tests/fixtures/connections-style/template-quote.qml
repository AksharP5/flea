import QtQuick
Item {
    property string note: `it's ${1}`
    Connections {
        target: foo
        function onReady() { console.log("ready") }
        onFailed: console.log("failed")
    }
}
