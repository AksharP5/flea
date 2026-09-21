//@ pragma ShellId flearetryprobe

import Quickshell
import QtQuick

// The entry's own retry plumbing, loaded the way ui/boot/shell.qml loads it: a file: URL, because
// the boot directory cannot reach ui/js/Renderer.js through qs:. Drives the arm no live scene-graph
// failure on this box can reach, which is the one where the retry DOES fire. See tests/ui.sh renderer.
ShellRoot {
    Component.onCompleted: {
        var component = Qt.createComponent("file://" + Quickshell.env("RETRY_HELPER"))
        if (component.status !== Component.Ready) {
            console.warn("RETRY status " + component.status + " " + component.errorString())
        } else {
            var helper = component.createObject(null)
            console.warn("RETRY argv " + JSON.stringify(helper.fallbackCommand(Quickshell.env("RETRY_BACKEND"))))
            helper.destroy()
        }
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
