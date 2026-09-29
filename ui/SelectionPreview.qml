import QtQuick
import "." as Flea
import "js/Columns.js" as Columns
import "js/Facts.js" as Facts
import "js/Thumbs.js" as Thumbs
import "js/ExtThumbs.js" as ExtThumbs
import "js/Keymap.js" as Keymap
import "js/PreviewKeys.js" as PreviewKeys
import "js/PreviewSwap.js" as PreviewSwap

// Selection loading is independent of column visibility and the separate Quick Look overlay.
Flea.PreviewColumn {
    id: root
    property var pane: null
    property int loadedIndex: -1
    property string loadedDirectory: ""
    property string loadedIdentity: ""
    property int pendingToken: 0
    // ui/ColumnsArea.qml's third-column swap, which then drives the cursor moves; null leaves every change immediate.
    property var swap: null
    property string settleKey: ""
    signal thumbsApplied(var work)
    onExpandRequested: {
        if (!root.row || !root.pane) return
        root.pane.preview.open(root.path, root.row.i, root.row.s, root.kindName)
        root.pane.preview.pdfItem.expandFrom(root.pdfPage(), root.pdfZoom)
    }

    Keys.onPressed: function(event) {
        var context = root.rowState === Facts.PDF ? "pdf"
            : root.rowState === Facts.VIDEO || root.rowState === Facts.AUDIO ? "media" : "preview"
        var action = Keymap.lookup(event.key, event.text, event.modifiers, context)
        if (action === "escape" || action === "focusPreview") root.pane.listArea.forceActiveFocus()
        else if (action === "loadPreview") root.loadSelection()
        else if (root.rowState === Facts.PDF) PreviewKeys.pdfAction(action, root)
        else if (action === "preview") {
            var strip = root.mediaStripItem()
            if (strip) strip.toggled()
            else if (root.row && !root.row.d) root.pane.preview.open(root.path, root.row.i, root.row.s, root.kindName)
        } else if (action === "seekBack" || action === "seekForward") {
            var direction = action === "seekBack" ? -1 : 1
            if (root.rowState === Facts.PDF) root.turnPage(direction)
            else {
                var transport = root.mediaStripItem()
                if (transport) transport.seeked(root.mediaPosition() + direction * PreviewKeys.SEEK_MS)
            }
        } else if (action === "parent") root.turnPage(-1)
        else if (action === "pageForward") root.turnPage(1)
        event.accepted = true
    }

    readonly property bool canRead: root.visible && root.pane !== null && !root.pane.listInFlight
    overlayOpen: root.pane && root.pane.preview ? root.pane.preview.active : false
    thumb: root.pane ? (root.manualHold ? Thumbs.fileFor(root.pane.thumbState, root.pane.cursorIndex)
        : (root.loadedIndex >= 0 ? Thumbs.fileFor(root.pane.thumbState, root.loadedIndex) : "")) : ""
    noThumbComing: root.row !== null && (root.row.t !== true || !root.pane
        || Thumbs.refused(root.pane.thumbState, root.loadedIndex))
    loadingHeldOff: root.swap !== null && root.swap.fellBack

    // What the swap waits for: the cursor row's preview whole, or nothing more coming for it.
    // A held frame is whole from the listing alone, cached thumbnail or not.
    readonly property bool ready: {
        if (root.manualHold)
            return !root.pending
        if (root.pane === null || root.row === null)
            return !root.pending
        if (root.loadedIndex !== root.pane.cursorIndex)
            return false
        return PreviewSwap.columnReady({ state: root.previewState, thumb: root.thumb.length > 0,
            frame: root.frameStatus, noThumbComing: root.noThumbComing, pdfDrawn: root.pdfDrawn,
            pdfFailed: root.pdfFailed, linesLoading: root.linesItem.loading, meta: root.meta !== null })
    }

    // ExtThumbs: how much of a text file this frame may read; the column passes it on.
    textLimit: ExtThumbs.textLimit(root.pane ? root.pane.storageClass : "")
    truncateText: root.pane ? (root.pane.storageClass === "network" || root.pane.storageClass === "phone") : false

    function identity(row) {
        return row ? JSON.stringify([row.n, row.s, row.m, row.p, row.i]) : ""
    }

    function swapKey() { return root.pane.path + "\n" + root.pane.cursorIndex }

    // The settle runs from the key, and a second call for the same row does not push it back.
    function armSettle() {
        if (!ViewState.previewAutomatic || !root.pane)
            return
        var key = root.swapKey()
        if (settle.running && root.settleKey === key)
            return
        root.settleKey = key
        settle.restart()
    }

    function clear() {
        settle.stop()
        root.clearShown()
    }

    // A move's clear: the loading state stands under the swap's picture until the settle loads the new row.
    function clearForMove() {
        root.clearShown()
        root.pending = true
    }

    // A folder or null row keeps the old preview: ColumnsArea holds the old column by data until the peek lands.
    function replace() {
        if (!Columns.isFileRow(root.pane ? root.pane.rowFor(root.pane.cursorIndex) : null)) { settle.stop(); return }
        if (root.swap && ViewState.previewAutomatic && root.canRead) {
            root.armSettle()
            root.swap.hold(root.clearForMove, root.swapKey())
            return
        }
        root.clear()
        if (root.canRead) root.armSettle()
    }

    function clearShown() {
        root.pending = false
        root.pendingToken = 0
        root.manualHold = false
        root.loadedIndex = -1
        root.loadedDirectory = ""
        root.loadedIdentity = ""
        root.row = null
        root.meta = null
        root.path = ""
        root.kindName = ""
        root.selectionCount = 0
        root.selectedRows = []
    }

    function followSelection() {
        if (!root.canRead) return
        var candidate = root.pane.rowFor(root.pane.cursorIndex)
        // Unknown is never held: the class has not named its verdict yet, so the frame waits
        // under the swap's cap and onStorageKnownChanged decides when it lands, never a held mark.
        if (!root.pane.storageKnown) {
            if (root.swap) root.swap.start(false)
            return
        }
        var hold = ExtThumbs.manualHold(root.pane.storageClass, ViewState.preview)
        if (root.loadedDirectory === root.pane.path && root.loadedIndex === root.pane.cursorIndex
                && root.loadedIdentity === root.identity(candidate) && root.manualHold === hold) return
        // A folder or null row keeps the old preview until its peek lands; clearing here would blank the held column.
        if (!Columns.isFileRow(candidate)) { settle.stop(); return }
        // An off class holds the frame on the listing's own facts until Ctrl+Space loads it; nothing loads, so no swap.
        if (hold) { root.clear(); root.holdSelection(candidate); return }
        root.replace()
    }

    // The held frame: the row, its path and its facts from the listing alone, no meta and no
    // thumbnail ask. The loaded identity is recorded so rows replies do not clear and re-hold.
    // Space still opens Quick Look, which loads on request.
    function holdSelection(candidate) {
        if (!candidate || candidate.d) return
        root.manualHold = true
        root.loadedIndex = root.pane.cursorIndex
        root.loadedDirectory = root.pane.path
        root.loadedIdentity = root.identity(candidate)
        root.row = Object.assign({}, candidate)
        root.path = root.pane.join(root.pane.path, candidate.n)
        root.kindName = root.pane.kindNames[candidate.k] || ""
        root.selectionCount = root.pane.selectionCount()
        root.selectedRows = root.pane.selectedIndices().map(function (index) { return root.pane.rowFor(index) }).filter(function (row) { return row !== null })
        if (root.swap) root.swap.start(false)
    }

    // Ctrl+Space calls this directly; automatic selection reaches it only after selection settles.
    function loadSelection() {
        if (!root.canRead) return
        if (!Columns.isFileRow(root.pane.rowFor(root.pane.cursorIndex))) { settle.stop(); return }
        if (root.swap) root.swap.hold(root.load, root.swapKey(), true)
        else root.load()
    }

    // The swap is told the new preview's work has begun, so its cap counts from here, a PDF's after its document settle.
    function load() {
        if (!root.canRead) return
        var pane = root.pane
        var current = pane.rowFor(pane.cursorIndex)
        if (!Columns.isFileRow(current)) { settle.stop(); root.startSwap(false); return }
        root.clear()
        root.loadedIndex = pane.cursorIndex
        root.loadedDirectory = pane.path
        root.loadedIdentity = root.identity(current)
        root.row = Object.assign({}, current)
        root.path = pane.join(pane.path, current.n)
        root.kindName = pane.kindNames[current.k] || ""
        root.selectionCount = pane.selectionCount()
        root.selectedRows = pane.selectedIndices().map(function (index) { return pane.rowFor(index) }).filter(function (row) { return row !== null })
        if (root.selectionCount > 1) { root.startSwap(false); return }
        var kind = Facts.state(current, 1, false, "", root.kindName)
        root.startSwap(kind === Facts.PDF)
        root.pendingToken = pane.backend.askMeta(root.loadedIndex, kind === Facts.TEXT || kind === Facts.CODE,
            kind === Facts.VIDEO || kind === Facts.AUDIO, kind === Facts.ARCHIVE)
        if (current.t && pane.thumbState.file[root.loadedIndex] === undefined) {
            var work = { ask: [root.loadedIndex], drop: [] }
            root.thumbsApplied(work)
            pane.backend.thumb(work.ask)
        }
    }

    function startSwap(isPdf) { if (root.swap) root.swap.start(isPdf) }

    Timer {
        id: settle
        interval: root.pane ? root.pane.settleMs : 120
        // The automatic settle holds an off class; Ctrl+Space's direct loadSelection stays full.
        // Unknown waits through followSelection, so the first settle never spends the class fsinfo has not named yet.
        onTriggered: if (ViewState.previewAutomatic) {
            var hold = root.pane ? (!root.pane.storageKnown || ExtThumbs.manualHold(root.pane.storageClass, ViewState.preview)) : false
            if (hold) root.followSelection()
            else root.loadSelection()
        }
    }
    onCanReadChanged: {
        // A listing going out leaves the preview to Nav.forget's reset, which clears it when held rows go.
        if (!root.canRead && (!root.visible || root.pane === null)) root.clear()
        else if (root.canRead) root.followSelection()
    }
    Connections {
        target: ViewState
        function onPreviewAutomaticChanged() {
            if (ViewState.previewAutomatic) root.followSelection()
            else settle.stop()
        }
        // A class switch moves the frame between held and loaded without a cursor move.
        function onStateChanged() { root.followSelection() }
    }
    Connections {
        target: root.pane
        // With a swap, ui/ColumnsArea.qml calls followSelection after it has put the hold in place.
        function onCursorIndexChanged() { if (!root.swap) root.followSelection() }
        // The class lands with fsinfo, after the rows; a settle fired in between spent local.
        function onStorageClassChanged() { root.followSelection() }
        function onStorageKnownChanged() { root.followSelection() }
        function onRowsChanged() {
            if (root.loadedIndex >= 0 && root.loadedIdentity !== root.identity(root.pane.rowFor(root.loadedIndex)))
                root.replace()
            else if (!root.swap)
                root.followSelection()
        }
        function onPathChanged() { root.replace() }
        function onSelectionVersionChanged() { root.replace() }
    }
    Connections {
        target: root.pane ? root.pane.backend : null
        function onMetaResult(message) {
            if (!root.canRead || !root.pendingToken || message.token !== root.pendingToken
                    || root.loadedDirectory !== root.pane.path
                    || root.loadedIdentity !== root.identity(root.pane.rowFor(root.loadedIndex))) return
            root.pendingToken = 0
            root.meta = { w: message.w, h: message.h, durationMs: message.ms, sampleRate: message.rate,
                entries: message.entries, unpacked: message.unpacked, archiveFailed: message.afailed,
                names: message.names, lines: message.lines, partial: message.partial,
                linesFailed: message.lfailed, target: message.target, targetDir: message.targetdir,
                owner: message.owner || "", orient: message.orient || 1 }
        }
    }
    Component.onCompleted: root.followSelection()
}
