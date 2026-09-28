import QtQuick
Item {
    function parts(s) { return s.split(/'/) }
    function remote(p) { return /^smb:\/\//.test(p) }
    Connections {
        target: foo
        function onReady() { console.log("ready") }
        onFailed: console.log("failed")
    }
}
