import QtQuick
import "js/PreviewSwap.js" as PreviewSwap

// A preview's last picture held on screen while the next preview builds under it, and let go in the frame
// the new one is whole; see AGENTS.md "The preview swap". The layer exists only while a hold does, so a
// settled preview is drawn directly and costs no texture.
Item {
    id: root

    // What the surface draws: the host's children land in here.
    default property alias content: content.data
    // Quick Look keeps its panes eager outside this wrapper and builds only it on first open, so
    // the picture captures that outer container rather than children of its own. Null draws as before.
    property Item captureSource: null
    // The host's answer: what is under the picture is the whole preview it was asked for.
    property bool ready: true
    // True for the column, where a move during a hold means held j, and the stale picture gives way to loading.
    property bool burstEnds: false
    // What the host paints behind the panes, laid under them inside the picture only: text drawn into a clear
    // layer blends its edges against nothing and comes out heavier than the same text drawn on its real ground.
    property color ground: "transparent"
    property real groundInset: 0
    property real groundRadius: 0

    property bool capturing: false
    property bool holding: false
    property bool started: false
    property bool fellBack: false
    // The frame after a release: the content is drawn again and the picture no longer is, and only then does the layer go.
    property bool dropping: false
    property var key: undefined
    property var queued: []

    // What ui/Ipc.qml previewSwapState reads: how each hold ended and every frame drawn half-built.
    property int holds: 0
    property int fallbacks: 0
    property int bursts: 0
    property int heldFrames: 0
    property int midFrames: 0
    property int loadingFrames: 0
    property var last: ({ ms: 0, end: "" })
    property double since: 0

    // A move: the change runs once a picture of the preview as it stands is frozen, or at once when nothing needs one.
    // After a burst the loading state stays live under held j; atWork is the new preview's own start, which is held again.
    function hold(apply, key, atWork) {
        if (atWork !== true && root.fellBack && root.burstEnds && !root.capturing && !root.holding) {
            root.run([apply])
            return
        }
        var action = PreviewSwap.onMove({ capturing: root.capturing, holding: root.holding, key: root.key },
                                        key, root.burstEnds)
        if (action === PreviewSwap.BURST) {
            root.bursts += 1
            root.release("burst", true)
            root.run([apply])
            return
        }
        if (action === PreviewSwap.JOIN) {
            // A newer target means the work already started was for a row the cursor has left.
            if (root.key !== key) {
                root.key = key
                root.started = false
                cap.stop()
            }
            if (root.holding)
                root.run([apply])
            else if (apply)
                root.queued.push(apply)
            return
        }
        if (!root.visible || root.width <= 0 || root.height <= 0) {
            root.run([apply])
            return
        }
        root.key = key
        root.started = false
        root.fellBack = false
        root.since = Date.now()
        root.holds += 1
        root.queued = apply ? [apply] : []
        root.capturing = true
        root.dropping = false
        // A layer still going from the last release is reused, so it is asked for a fresh picture.
        if (layer.item)
            layer.item.scheduleUpdate()
        captureGuard.restart()
    }

    // The host: the new preview's own work has begun, so the cap counts from here.
    function start(isPdf) {
        if (!root.holding && !root.capturing)
            return
        root.started = true
        cap.interval = PreviewSwap.capMs(isPdf)
        cap.restart()
        Qt.callLater(root.check)
    }

    // A folder wait keeps the live picture under its own fallback, so the old work's cap stops here.
    function stopCap() { cap.stop() }

    function captured() {
        if (!root.capturing)
            return
        captureGuard.stop()
        // holding first: with capturing cleared first the Loader would drop the frozen layer for one binding pass.
        root.holding = true
        root.capturing = false
        var pending = root.queued
        root.queued = []
        root.run(pending)
        root.check()
    }

    function check() {
        if (root.holding && root.started && root.ready)
            root.release("landed", false)
    }

    function release(end, fell) {
        cap.stop()
        captureGuard.stop()
        if (root.capturing || root.holding) {
            root.last = { ms: Date.now() - root.since, end: end }
            root.dropping = true
        }
        root.capturing = false
        root.holding = false
        root.started = false
        root.fellBack = fell === true
        var pending = root.queued
        root.queued = []
        root.run(pending)
    }

    // Quick Look closing: nothing queued may run after it, and the picture goes with it.
    function cancel() {
        root.queued = []
        root.release("cancelled", false)
    }

    function run(changes) {
        for (var i = 0; i < changes.length; i++) {
            if (changes[i])
                changes[i]()
        }
    }

    // tests/preview-swap.qml reparents its body under the picture; the default alias
    // covers declarative children and this covers the one runtime move.
    function contentItem() { return content }

    function describe() {
        return { holding: root.holding, capturing: root.capturing, fellBack: root.fellBack, holds: root.holds,
                 fallbacks: root.fallbacks, bursts: root.bursts, heldFrames: root.heldFrames,
                 midFrames: root.midFrames, loadingFrames: root.loadingFrames, last: root.last }
    }

    onReadyChanged: {
        if (root.ready)
            root.fellBack = false
        root.check()
    }
    onVisibleChanged: if (!root.visible) root.release("hidden", false)

    Item {
        id: content
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            anchors.margins: root.groundInset
            radius: root.groundRadius
            color: root.ground
            visible: root.capturing || root.holding
        }
    }

    // The picture: the content drawn once into a texture that then stops updating, shown in its place.
    Loader {
        id: layer
        anchors.fill: parent
        active: root.capturing || root.holding || root.dropping
        sourceComponent: ShaderEffectSource {
            sourceItem: root.captureSource !== null ? root.captureSource : content
            // Destroying a layer that hides its source left one frame with neither drawn, so a release unhides first.
            hideSource: root.capturing || root.holding
            visible: root.capturing || root.holding
            live: false
            onScheduledUpdateCompleted: root.captured()
        }
    }

    // While a picture stands for the preview, the pointer reaches nothing under it: no hover, wheel or press.
    MouseArea {
        anchors.fill: parent
        enabled: root.capturing || root.holding
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onWheel: function (wheel) { wheel.accepted = true }
    }

    Timer {
        id: cap
        repeat: false
        onTriggered: {
            if (!root.holding && !root.capturing)
                return
            root.fallbacks += 1
            root.release("expired", true)
        }
    }

    // One frame later the texture is let go; frameSwapped arrives here queued from the render thread.
    Connections {
        target: root.dropping ? root.Window.window : null
        function onFrameSwapped() { root.dropping = false }
    }

    // A window that is not drawing never completes a capture, so the change goes ahead unheld.
    Timer {
        id: captureGuard
        interval: PreviewSwap.CAPTURE_MS
        repeat: false
        onTriggered: if (root.capturing) root.release("uncaptured", false)
    }

    // afterAnimating runs on this thread just before each frame is synchronised, so it sees what that frame draws.
    // Live from the first hold until ready lands after the release, so a half-built frame is never drawn uncounted; an idle window still pays nothing.
    Connections {
        target: (root.capturing || root.holding || root.dropping || !root.ready) ? root.Window.window : null
        function onAfterAnimating() {
            if (!root.visible)
                return
            var kind = PreviewSwap.frameKind(root.capturing || root.holding, root.ready, root.fellBack)
            if (kind === "held")
                root.heldFrames += 1
            else if (kind === "mid")
                root.midFrames += 1
            else if (kind === "loading")
                root.loadingFrames += 1
        }
    }
}
