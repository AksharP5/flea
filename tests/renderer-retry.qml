//@ pragma ShellId flearetryprobe

import Quickshell
import QtQuick

// ui/RendererRetry.qml by file: URL, the way ui/boot/shell.qml loads it; see tests/ui.sh renderer.
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
