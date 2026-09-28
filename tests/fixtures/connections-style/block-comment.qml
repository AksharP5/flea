import QtQuick
Item {
    Connections {
        target: foo
        /* a } in a block comment */
        function onReady() { console.log("ready") }
        onFailed: console.log("failed")
    }
}
