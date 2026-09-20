//@ pragma AppId com.thisisgm.flea
//@ pragma ShellId flea
//@ pragma NativeTextRendering
//@ pragma CacheDir $BASE/flea

import Quickshell
import QtQuick

// The entry is the window, and it imports Quickshell and QtQuick only. Quickshell serves a config
// through qs: URLs and Qt's QML disk cache takes local files only, so every type this file reaches
// is compiled again on every launch; ui/WindowBody.qml arrives by file: URL, which is cached, once
// the first frame has swapped. This file sits in its own directory because a document implicitly
// imports its own, and ui/qmldir's singletons would compile here and never be instantiated.
// See AGENTS.md "The first window".
ShellRoot {
    FloatingWindow {
        id: fleaWindow
        title: "Flea"
        implicitWidth: 900
        implicitHeight: 600
        // The launcher hands over the theme's background, so the window the operator sees before
        // the body lands is already the colour the body paints. Same fallback as ui/Theme.qml.
        color: Quickshell.env("FLEA_FIRST_PAINT") || "#101315"
        // Long enough that a drawn window has swapped its first frame, short enough that a window
        // which is never drawn still gets its body while the operator is still looking at it.
        readonly property int bodyBackstopMs: 250
        property bool rendererFallbackStarted: false

        // Every *Centre reader on the IPC seam is this: an item's painted box, reduced to the point a test clicks.
        function centreOf(item) {
            if (!item)
                return ""
            var rect = fleaWindow.itemRect(item)
            return Math.round(rect.x + rect.width / 2) + " " + Math.round(rect.y + rect.height / 2)
        }
        // "x y width height" in window pixels, for a test that asserts a card stays inside the window.
        function rectOf(item) {
            if (!item)
                return ""
            var rect = fleaWindow.itemRect(item)
            var left = Math.round(rect.x), top = Math.round(rect.y)
            return left + " " + top + " " + (Math.round(rect.x + rect.width) - left) + " " + (Math.round(rect.y + rect.height) - top)
        }
        // centreOf's sibling, "x width centre": the edges round because a click needs a whole pixel, the centre keeps three decimals because the misalignment it reads is half of one.
        function boxOf(item) {
            if (!item)
                return ""
            var rect = fleaWindow.itemRect(item)
            return Math.round(rect.x) + " " + Math.round(rect.width) + " " + (rect.x + rect.width / 2).toFixed(3)
        }

        // A qs: import outside the config root is blackholed, so this directory cannot reach
        // ui/js/Format.js and the one call it needs is written out here.
        function fileUrl(path) {
            return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F")
        }

        // Once. frameSwapped repeats and the backstop below fires in parallel.
        function loadBody() {
            if (bodyLoader.status !== Loader.Null)
                return
            bodyBackstop.stop()
            bodyLoader.setSource(fleaWindow.fileUrl(Quickshell.shellDir + "/../WindowBody.qml"), { host: fleaWindow })
        }

        // Quickshell 0.3.1 has no exit API and Qt.quit() is a no-op, so the shell signals itself,
        // and it is signalled from here because a window closed before the body loads still has to
        // take the process with it.
        Connections { target: Quickshell; function onLastWindowClosed() { fleaWindow.quit() } }

        // Nothing has been told to drain before the body exists, so an early exit kills directly.
        function quit() {
            if (bodyLoader.item)
                bodyLoader.item.quitBackends()
            else
                Quickshell.execDetached(["kill", String(Quickshell.processId)])
        }

        // sceneGraphError arrives on the first frame, which is before the body exists, so PR119's
        // retry lives here rather than in the body.
        function handleSceneGraphError(error, message) {
            var backendName = Quickshell.env("QSG_RHI_BACKEND")
            console.warn("graphics backend " + backendName + " failed (" + error + "): " + message)
            var retry = retryCommand(backendName)
            if (retry && !rendererFallbackStarted) {
                rendererFallbackStarted = true
                Quickshell.execDetached(retry)
            }
            quit()
        }

        // ui/RendererRetry.qml owns the argv rule, and loading it by file: URL only after the error
        // has arrived is what keeps ui/js/Renderer.js off the startup path.
        function retryCommand(backendName) {
            var helper = Qt.createComponent(fleaWindow.fileUrl(Quickshell.shellDir + "/../RendererRetry.qml"))
            if (helper.status !== Component.Ready) {
                console.warn("flea: the renderer retry helper did not load, so there is no fallback: " + helper.errorString())
                return null
            }
            var object = helper.createObject(fleaWindow)
            var retry = object.fallbackCommand(backendName)
            object.destroy()
            return retry
        }

        Loader {
            id: bodyLoader
            anchors.fill: parent
            // An empty window forever is what this catches; the engine prints the reason above it.
            onStatusChanged: {
                if (status === Loader.Error) {
                    console.warn("flea: the window body did not load, so there is nothing to show")
                    fleaWindow.quit()
                }
            }
        }

        // Null while this file loads and the QQuickWindow once it exists, which is before the scene graph starts.
        Connections {
            target: bodyLoader.Window.window
            function onFrameSwapped() { fleaWindow.loadBody() }
            function onSceneGraphError(error, message) { fleaWindow.handleSceneGraphError(error, message) }
        }

        // A window that maps where it is never drawn swaps no frame, and would wait forever.
        Timer {
            id: bodyBackstop
            interval: fleaWindow.bodyBackstopMs
            repeat: false
            running: true
            onTriggered: fleaWindow.loadBody()
        }
    }
}
