import QtQuick
import QtQuick.Pdf
import qs.Commons
import "js/Format.js" as Format
import "js/Swap.js" as Swap

// A page of a PDF, rendered into the preview column's frame. QtPdf ships inside the already
// installed qt6-webengine and needs no package of its own; proven to import and render under
// Quickshell itself on this box, not only under qml6.
Item {
    id: root

    property string path: ""
    property bool active: false
    // Which page the frame is showing, zero-based, always inside the document it belongs to.
    property int page: 0
    // The Flickable the page scrolls in, so the loading mark stands in the visible frame at any zoom.
    property Item viewport: null

    // What the facts table shows as Pages; 0 until the document is ready, or if it never becomes so.
    readonly property int pageCount: doc.status === PdfDocument.Ready ? doc.pageCount : 0
    readonly property bool failed: doc.status === PdfDocument.Error

    // The page whose render is on screen, -1 until one has landed for this document.
    property int shownPage: -1
    // A render slower than the listing swap's cap stops passing the old page off as the one asked for.
    property bool fellBack: false
    // What the chrome counts: the page on screen, or the one asked for once nothing else stands in for it.
    readonly property int drawnPage: root.shownPage >= 0 && !root.fellBack ? root.shownPage : root.page

    // The page's proportions come from the document, never from the rendered image. Reading the
    // image's implicit size closed a loop through the width binding below: sourceSize changed the
    // implicit size, which re-evaluated width, which re-set sourceSize. Qt broke that binding, and a
    // broken width binding is a page that never resizes when the frame or the zoom changes.
    // corner: a document mixing page shapes draws the old page in the new page's box until its render lands.
    readonly property real pageAspect: {
        if (doc.status !== PdfDocument.Ready || root.pageCount <= 0)
            return 1
        var box = doc.pagePointSize(Math.min(root.page, root.pageCount - 1))
        return box.height > 0 ? box.width / box.height : 1
    }

    // A new document starts at its first page, whatever page the last one was left on, and its own
    // opening waits for the cursor to settle, which is issue 117 below.
    onPathChanged: { root.page = 0; pdfSettle.restart() }
    onPageCountChanged: if (root.pageCount > 0) root.page = Math.min(root.page, root.pageCount - 1)
    // A turn arms the cap for a page other than the one on screen; with no page shown yet it does nothing, and turning back onto the shown page stops the cap instead.
    onPageChanged: {
        if (page.status !== Image.Loading) return
        if (root.shownPage < 0) return
        if (root.page !== root.shownPage) renderCap.start()
        else { renderCap.stop(); root.fellBack = false }
    }

    function turn(delta) {
        if (root.pageCount <= 0)
            return
        root.page = Math.max(0, Math.min(root.pageCount - 1, root.page + delta))
    }

    // Loading a page other than the one on screen starts the cap; a landed or failed render ends it.
    function renderChanged() {
        if (page.status === Image.Loading) {
            if (root.shownPage >= 0 && page.currentFrame !== root.shownPage)
                renderCap.restart()
            return
        }
        renderCap.stop()
        root.fellBack = false
        // A document switch reports Ready for loads that drew nothing, or that drew the last file.
        var landed = page.status === Image.Ready && page.implicitWidth > 0
                     && page.source.toString() === doc.source.toString()
        root.shownPage = landed ? page.currentFrame : -1
    }

    // Issue 117, vianney-g: a source change while an async page render is in flight can destroy the
    // carrier device under Qt's own reader thread, which aborts the process, so a walk through a
    // folder of PDFs settles before a document is opened rather than opening one per cursor step.
    property string opened: ""
    readonly property int settleMs: 120
    onActiveChanged: pdfSettle.restart()
    Timer {
        id: pdfSettle
        interval: root.settleMs
        onTriggered: {
            var next = root.active ? root.path : ""
            if (next === root.opened)
                return
            // Another document's page is never this one's: it is dropped, and kept by no render, before the switch.
            renderCap.stop()
            root.fellBack = false
            root.shownPage = -1
            root.opened = next
        }
    }

    Timer {
        id: renderCap
        interval: Swap.HOLD_MS
        onTriggered: root.fellBack = true
    }

    PdfDocument {
        id: doc
        // Format.fileUri, not a concatenation: a path can carry a # or a ? and either one truncates
        // a hand-built URI at that character. A document is only opened while the column shows one.
        source: root.opened.length > 0 ? Format.fileUri(root.opened) : ""
    }

    // The page's own paper under the raster: on this box a rendered page can arrive with text drawn
    // and no background, and the dark frame showed through it. Paper is the document's, not a theme
    // role, so the colour is a constant; visible only with the page, so a loading document draws none.
    Rectangle {
        anchors.centerIn: parent
        visible: page.visible
        width: page.width
        height: page.height
        color: "#ffffff"
    }

    // The page is the only light surface in the app, which is exactly what the canvas draws.
    PdfPageImage {
        id: page
        anchors.centerIn: parent
        // Drawn once a render has landed: the paper alone before it was the white flash on every turn.
        visible: root.shownPage >= 0 && !root.fellBack
        document: doc
        // Qt ignores a frame at or past frameCount, which is 0 until the first render lands, so the binding reads it to reapply a turn made during that render.
        currentFrame: page.frameCount > 0 ? Math.min(root.page, page.frameCount - 1) : 0
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        // Qt 6.8's double buffer: the page on screen stays until the next render is ready, where
        // without it Qt dropped the old pixmap at the turn and the paper showed white for the render.
        // Off until this document has a page on screen, so no render can keep another document's.
        retainWhileLoading: root.shownPage >= 0
        onStatusChanged: root.renderChanged()
        // Fit inside the frame without ever upscaling past the page's own resolution.
        width: Math.min(parent.width, parent.height * root.pageAspect)
        height: Math.min(parent.height, parent.width / root.pageAspect)

        // Rasterised at the size it is drawn at, so a zoomed page sharpens instead of scaling up a
        // page-point-sized bitmap; the deadband and the assignment (not a binding) are both Qt's
        // own PdfPageView.qml reRenderIfNecessary, without which a resize re-renders every frame.
        onWidthChanged: page.rerenderIfNeeded()
        // PdfPageImage copies the document's source into its own inherited source property only as
        // the document turns Ready, and a re-render that beats that copy makes Qt warn that the two
        // are in conflict; the guard below waits for the copy and this re-renders once it lands.
        onSourceChanged: page.rerenderIfNeeded()

        function rerenderIfNeeded() {
            // source is a url, so it is converted before comparing: a bare === against a
            // string is false forever and would stop this guard from ever firing. Opening the
            // next document leaves the last one's source here until the copy, and the page box
            // resizing meanwhile (pageAspect is 1 while it loads) was that warning, twice a switch.
            if (page.source.toString() === "" || page.source.toString() !== doc.source.toString())
                return
            var target = Math.round(page.width)
            if (target <= 0)
                return
            var ratio = page.sourceSize.width > 0 ? target / page.sourceSize.width : 0
            if (ratio > 1.1 || ratio < 0.9)
                page.sourceSize = Qt.size(target, 0)
        }
    }

    // Past the cap the loading mark takes the frame, the fallback ui/PaneSwap.qml gives a slow listing.
    LoadingState {
        parent: root.viewport ? root.viewport : root
        anchors.fill: parent
        visible: root.fellBack
        heldOff: true
    }
}
