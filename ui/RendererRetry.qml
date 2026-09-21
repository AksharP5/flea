import QtQuick
import Quickshell
import "js/Renderer.js" as Renderer

// Loaded by file: URL when the scene graph fails, because the boot directory cannot import
// ui/js/Renderer.js through qs: and the startup path must not compile it.
QtObject {
    function fallbackCommand(backendName) {
        return Renderer.fallbackCommand(backendName, Quickshell.env("FLEA_RENDERER_AUTOMATIC"), Quickshell.env("FLEA_BIN"))
    }
}
