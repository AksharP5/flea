import QtQuick
Item {
    Connections {
        target: foo
        function onReady() { console.log("ready") }
        property string tricky: '}'
        onFailed: console.log("failed")
    }
}
