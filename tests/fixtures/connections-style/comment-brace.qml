import QtQuick
Item {
    Connections {
        target: foo
        function onReady() { console.log("ready") }
        // A stray } in a comment closes a naive brace scan early.
        onFailed: console.log("failed")
    }
}
