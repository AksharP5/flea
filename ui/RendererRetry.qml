import QtQuick
import Quickshell
import "js/Renderer.js" as Renderer

// ui/boot/shell.qml loads this by file: URL when the scene graph fails. It exists because the boot
// directory cannot import ui/js/Renderer.js through qs:, and because loading the rule at the moment
// it is needed keeps it off the startup path entirely.
QtObject {
    function fallbackCommand(backendName) {
        return Renderer.fallbackCommand(backendName, Quickshell.env("FLEA_RENDERER_AUTOMATIC"), Quickshell.env("FLEA_BIN"))
    }
}
