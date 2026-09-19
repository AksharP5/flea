import QtQuick
import qs.Commons
import "." as Flea
import "js/Facts.js" as Facts
import "js/Kinds.js" as Kinds
import "js/Motion.js" as Motion

// The overlay lives inside the Flea window, Finder's Quick Look shape: a second window breaks omarchy-drive focus flea and every test that narrows on it.
Item {
    id: root
    anchors.fill: parent
    // active flips instantly, so the IPC read never races the close fade; visible outlives it until surface's own opacity finishes.
    visible: root.active || surface.opacity > 0
    z: 1

    property bool active: false
    // shell.qml wires the pane in: the archive pane asks the backend about the cursor row and nothing else here reads it.
    property var pane: null
    property string path: ""
    property string iconName: ""
    property string kindName: ""
    property int size: 0
    property string kind: ""
    readonly property bool isMedia: root.kind === "audio" || root.kind === "video"
    readonly property bool isPdf: root.kind === "pdf"
    readonly property bool isImage: root.kind === "image"
    readonly property bool isArchive: root.kind === "archive"
    // The backend's meta answer for the open archive, null until it lands; archiveRow is the row it was asked for.
    property var archiveMeta: null
    property int archiveRow: -1
    // MediaPdf rule 6's fourth fact: Qt carries no sample-rate key at all (QMediaMetaData::Key, Qt 6.11), so the number is the backend probe's, asked the way an archive's is.
    property int mediaRate: 0
    property int mediaRow: -1
    readonly property bool archiveFailed: root.isArchive && root.archiveMeta !== null && root.archiveMeta.archiveFailed === true
    // For ui/Ipc.qml: the item drawing this kind's content, whether a player exists, and what the text and archive panes hold.
    function surfaceItem() {
        if (root.isImage) return imageLoader.item
        if (root.isMedia) return mediaLoader.item
        if (root.isPdf) return pdfLoader.item
        if (root.isArchive) return archivePane
        if (root.kind === "text") return textPane.bodyItem
        return null
    }
    function mediaLoaded() { return mediaLoader.item !== null }
    function textShown() { return textPane.shownText() }
    function archiveNames() { return root.archiveMeta && root.archiveMeta.names ? root.archiveMeta.names.map(function (e) { return e.n }).join("|") : "" }
    readonly property bool pdfExpanded: root.isPdf && pdfLoader.item !== null && pdfLoader.item.expanded
    // The PDF surface, null with no document loaded: ui/Ipc.qml answers "" for that, so an unmeasured state never reads as a value.
    readonly property var pdfItem: pdfLoader.item
    // What the strip actually draws: shell.qml's IPC reads this rather than re-deriving the visible: expression.
    readonly property alias stripVisible: mediaStrip.visible
    // The strip's own mute mark and the flag it draws from, so a test reads and clicks what is there.
    readonly property var muteMark: mediaStrip.muteItem
    readonly property bool muted: Flea.MediaSound.muted
    // fleaWindow.itemRect needs the real Item, the same seam rowCentre already reads through pane.
    readonly property var seekSlider: mediaStrip.seekItem
    readonly property string status: {
        if (!root.active) return ""
        if (root.isMedia) return mediaLoader.item ? mediaLoader.item.status : "loading"
        if (root.isPdf) return (pdfLoader.item && pdfLoader.item.failed) ? "This file could not be read." : "pdf"
        if (root.isImage) return imageLoader.item ? imageLoader.item.status : "loading"
        if (root.isArchive) return root.archiveMeta === null ? "loading" : (root.archiveFailed ? "This archive could not be read." : "archive")
        if (root.kind === "text") return textPane.status
        return "This file cannot be previewed."
    }

    property string pendingPath: ""
    property string pendingIcon: ""
    property string pendingKind: ""
    property int pendingSize: 0
    // The settle idiom Pane's own thumbnail request reuses: a held j/k costs zero reloads until the cursor rests.
    readonly property int followSettleMs: 120
    // The same dim ui/SettingsPanel.qml lays over the listing.
    readonly property real groundOpacity: 0.5

    // Read through to PreviewMedia so this file never imports QtMultimedia, and 0 before the loader has an item.
    readonly property int position: (root.isMedia && mediaLoader.item) ? mediaLoader.item.position : 0
    readonly property int duration: (root.isMedia && mediaLoader.item) ? mediaLoader.item.duration : 0

    // Shown on open, hidden stripHideMs after the last reveal, video only: audio has nothing else to look at.
    property bool stripShown: true
    // StatusBar.messageMs, the OEM's own transient interval, which Sidebar's unmount arm reuses for the same reason.
    readonly property int stripHideMs: 4000

    function revealStrip() {
        root.stripShown = true
        stripHideTimer.restart()
    }

    function togglePlay() { if (root.isMedia && mediaLoader.item) mediaLoader.item.togglePlay() }

    // MediaMute rule 3: one session flag, so the column's strip and this one always agree.
    function toggleMute() { if (root.isMedia) Flea.MediaSound.toggle() }

    // Absolute seek in ms, clamped by PreviewMedia's own seekTo; the slider's onReleased calls this directly.
    function seekTo(ms) { if (root.isMedia && mediaLoader.item) mediaLoader.item.seekTo(ms) }

    // Relative seek in ms, Left/Right's own shape; seekTo does the clamping.
    function seek(deltaMs) {
        root.seekTo(root.position + deltaMs)
    }

    // The PDF viewer's three actions come through this file, so ui/js/Focus.js never learns a Loader item answers them.
    function turnPage(delta) { if (root.isPdf && pdfLoader.item) pdfLoader.item.turn(delta) }

    function zoomBy(steps) { if (root.isPdf && pdfLoader.item) pdfLoader.item.zoomBy(steps) }

    function toggleExpand() { if (root.isPdf && pdfLoader.item) pdfLoader.item.toggleExpand() }

    // Space opens on the cursor row; this is immediate, follow() below is the held-key j/k path.
    function open(newPath, newIcon, newSize, newKind) {
        followSettle.stop()
        root.load(newPath, newIcon, newSize, newKind)
    }

    function follow(newPath, newIcon, newSize, newKind) {
        root.pendingPath = newPath
        root.pendingIcon = newIcon
        root.pendingSize = newSize
        root.pendingKind = newKind
        followSettle.restart()
    }

    // Dropping the loader's source is what stops playback: media dies with the loader.
    function close() {
        followSettle.stop()
        stripHideTimer.stop()
        root.active = false
        root.kind = ""
        mediaLoader.source = ""
        pdfLoader.source = ""
        imageLoader.source = ""
        root.archiveMeta = null
        root.archiveRow = -1
        root.mediaRate = 0
        root.mediaRow = -1
        if (root.pane) root.pane.listArea.forceActiveFocus()
    }

    function load(newPath, newIcon, newSize, newKind) {
        root.path = newPath
        root.iconName = newIcon
        root.size = newSize
        // MediaPdf rule 6: the overlay is the bigger surface, so it says at least what the column says, and the kind is the caller's because the backend named it for that row.
        root.kindName = newKind || ""
        root.kind = Kinds.quickLookKind(newIcon, newPath)
        root.active = true
        mediaLoader.source = root.isMedia ? "PreviewMedia.qml" : ""
        pdfLoader.source = root.isPdf ? "PdfViewer.qml" : ""
        imageLoader.source = root.isImage ? "PreviewImage.qml" : ""
        root.askArchive()
        root.askMedia()
        root.revealStrip()
    }

    // One row, only while an archive is the thing open: the same no-sweep rule the column follows.
    function askArchive() {
        root.archiveMeta = null
        root.archiveRow = root.isArchive && root.pane ? root.pane.cursorIndex : -1
        if (root.archiveRow >= 0)
            root.pane.backend.askMeta(root.archiveRow, false, false, true)
    }

    // The same one row, for the one fact the transport under the overlay cannot report.
    function askMedia() {
        root.mediaRate = 0
        root.mediaRow = root.isMedia && root.pane ? root.pane.cursorIndex : -1
        if (root.mediaRow >= 0)
            root.pane.backend.askMeta(root.mediaRow, false, true, false)
    }

    Connections {
        target: root.pane ? root.pane.backend : null
        function onMeta(row, w, h, durationMs, sampleRate, entries, unpacked, archiveFailed, names, lines, partial, linesFailed, target, targetDir, owner) {
            if (root.isArchive && row === root.archiveRow)
                root.archiveMeta = { entries: entries, unpacked: unpacked, archiveFailed: archiveFailed, names: names }
            if (root.isMedia && row === root.mediaRow)
                root.mediaRate = sampleRate
        }
    }

    // A meta asked across a listing change is answered with silence, so the rows landing re-asks it, the way ui/ColumnsArea.qml does.
    Connections {
        target: root.pane
        function onRowsChanged() {
            if (root.active && root.isArchive && root.archiveMeta === null) root.askArchive()
            if (root.active && root.isMedia && root.mediaRate === 0) root.askMedia()
        }
    }

    Timer {
        id: followSettle
        interval: root.followSettleMs
        repeat: false
        onTriggered: root.load(root.pendingPath, root.pendingIcon, root.pendingSize, root.pendingKind)
    }

    Timer {
        id: stripHideTimer
        interval: root.stripHideMs
        repeat: false
        onTriggered: root.stripShown = false
    }

    MouseArea {
        anchors.fill: parent
        // A shield that outlives the overlay swallows the first click after it and freezes row hover for the window.
        enabled: root.active
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        // A click behind the overlay would silently move the cursor or open the listing's menu on it.
        // A left click outside the surface closes, GM's rule of 2026-09-11, and a right click is only swallowed.
        onClicked: function (mouse) {
            if (mouse.button === Qt.LeftButton && !surface.contains(surface.mapFromItem(root, mouse.x, mouse.y)))
                root.close()
        }
        onPositionChanged: root.revealStrip()
    }

    // PdfViewer.html and MediaPlayer.html draw a pane with its own edge: on the surface colour alone the inset vanished into the listing behind it.
    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
        opacity: root.active ? root.groundOpacity : 0
        Behavior on opacity {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: root.active ? Motion.durMs.open : Motion.durMs.close }
        }
    }

    Rectangle {
        id: surface
        anchors.centerIn: parent
        border.width: Theme.spacing.hairline
        border.color: Theme.color.muted
        // Open rises into place and close only fades, faster, because the translation is enabled: root.active.
        anchors.verticalCenterOffset: root.active ? 0 : Motion.translateUpPx
        opacity: root.active ? 1 : 0
        // Expand drops the Quick Look inset, which is the whole of the canvas's "expand fills the window".
        readonly property real inset: root.pdfExpanded ? 1 : Theme.preview.fraction
        width: parent.width * surface.inset
        height: parent.height * surface.inset
        color: Theme.color.surface
        // Mirrors hyprland decoration:rounding; media fills the surface and keeps square corners, a visible corner only shows on text and audio panes.
        radius: Style.cornerRadius

        Behavior on anchors.verticalCenterOffset {
            enabled: root.active && !Theme.reducedMotion
            NumberAnimation { duration: Motion.durMs.open; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve }
        }

        Behavior on opacity {
            enabled: !Theme.reducedMotion
            NumberAnimation {
                duration: root.active ? Motion.durMs.open : Motion.durMs.close
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.bezierCurve
            }
        }

        Flea.PreviewText {
            id: textPane
            anchors.fill: parent
            anchors.margins: Theme.spacing.gap
            active: root.kind === "text"
            path: root.path
            size: root.size
        }

        Loader {
            id: mediaLoader
            anchors.fill: parent
            onLoaded: {
                item.path = Qt.binding(function () { return root.path })
                item.kind = Qt.binding(function () { return root.kind })
                item.size = Qt.binding(function () { return root.size })
                item.kindName = Qt.binding(function () { return root.kindName })
                item.rate = Qt.binding(function () { return root.mediaRate })
            }
        }

        // source rather than sourceComponent, so a file is decoded only while an image is open and its texture goes with the item.
        Loader {
            id: imageLoader
            anchors.fill: parent
            onLoaded: item.path = Qt.binding(function () { return root.path })
        }

        // The canvas's PdfViewer, source not sourceComponent, so QtQuick.Pdf loads on the first PDF and never for a folder without one.
        Loader {
            id: pdfLoader
            anchors.fill: parent
            onLoaded: {
                item.path = Qt.binding(function () { return root.path })
                item.active = true
                item.forceActiveFocus()
            }
        }

        Connections {
            target: pdfLoader.item
            function onClosed() { root.close() }
        }

        // The canvas's Archive tile at Quick Look size: the name, the count the index gave, then the entries.
        Column {
            id: archivePane
            anchors.fill: parent
            anchors.margins: Theme.spacing.rowPaddingX
            spacing: Theme.spacing.gap
            visible: root.isArchive && root.archiveMeta !== null && !root.archiveFailed

            // corner: a filename is arbitrary text, so PlainText, the same rule every name on this surface follows.
            Text {
                width: parent.width
                text: root.path.substring(root.path.lastIndexOf("/") + 1)
                color: Theme.color.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
            }

            Text {
                width: parent.width
                text: Facts.archiveLine(root.archiveMeta)
                color: Theme.color.muted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.caption
                textFormat: Text.PlainText
            }

            Flea.PreviewArchive {
                width: parent.width
                height: parent.height - y
                meta: root.archiveMeta
            }
        }

        // Declined, or an archive whose index could not be read: a mark over the sentence, never a bare surface.
        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.spacing.rowPaddingX
            spacing: Theme.spacing.gap
            visible: root.kind === "unsupported" || root.archiveFailed

            Flea.Glyph {
                anchors.horizontalCenter: parent.horizontalCenter
                // The overlay declining is a pane state standing alone, which States.dc.html draws at 40.
                maxSize: Theme.stateMarkSize
                width: Theme.stateMarkSize
                height: Theme.stateMarkSize
                name: root.archiveFailed ? "alert" : "file"
                color: root.archiveFailed ? Theme.color.error : Theme.color.muted
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.status
                color: root.archiveFailed ? Theme.color.foreground : Theme.color.muted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
        }

        // Media still buffering or an image still decoding shows the crawl; LoadingState's hold-off keeps a fast local open from flashing it.
        Flea.LoadingState {
            anchors.fill: parent
            visible: (root.isMedia || root.isImage || root.isArchive) && root.status === "loading"
        }

        // MediaStrip unframed: quiet over the video, permanent on audio, and the column draws the framed form of the same file.
        Flea.MediaStrip {
            id: mediaStrip
            visible: root.isMedia && (root.kind === "audio" || root.stripShown)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            framed: false
            playing: root.status === "playing"
            position: root.position
            duration: root.duration
            onToggled: root.togglePlay()
            onSeeked: function (ms) { root.seekTo(ms) }
            onTouched: root.revealStrip()
        }
    }
}
