import QtQuick
import "." as Flea
import "js/ClipMarks.js" as ClipMarks
import "js/DirSizes.js" as DirSizes
import "js/ExtThumbs.js" as ExtThumbs
import "js/Filter.js" as Filter
import "js/Scroll.js" as Scroll
import "js/Tap.js" as Tap
import "js/Thumbs.js" as Thumbs

// The listing's render, scroll and settle-triggered refetch, split out of Pane.qml; reaches Pane's state through the pane reference and the context menu through menu, both handed in at instantiation.
ListView {
    id: root

    property var pane: null
    property var menu: null

    // Shared once, read plainly per row, so no delegate builds its own width or array.
    property real rowWidth: Scroll.contentWidth(root.width, Theme.spacing.rowPaddingX)
    // Dual mode hides mode and kind on top of the stored set; one array, never one per row.
    property var rowHiddenCols: root.pane && root.pane.dualMode ? ["mode", "kind"].concat(ViewState.hiddenCols) : ViewState.hiddenCols
    // Shared name budgets remove the per-row floor; Row keeps its local default for PickerList and drop targets.
    readonly property bool listDual: root.pane && root.pane.dualMode ? true : false
    readonly property real listMarkSlot: root.listDual ? Theme.markSize : Theme.iconSize
    readonly property real listSizeWidth: root.listDual ? Theme.dualColumn.size : Theme.column.size
    readonly property real listDateWidth: root.listDual ? Theme.dualColumn.date : Theme.column.date
    // The same set Row.cols resolves, from the same width and hidden array, so the two cannot drift.
    readonly property var listCols: root.listDual ? Theme.dualColumns(root.rowWidth, root.rowHiddenCols) : Theme.columns(root.rowWidth, root.rowHiddenCols, root.listDateWidth)
    readonly property bool listModeShown: root.listCols ? !!root.listCols.mode : false
    readonly property bool listSizeShown: root.listCols ? !!root.listCols.size : false
    readonly property bool listDateShown: root.listCols ? !!root.listCols.date : false
    readonly property bool listKindShown: root.listCols ? !!root.listCols.kind : false
    // Matches Row.clipPx; the reserve keeps the glyph readable.
    readonly property int listClipPx: 12
    // Exact drawn geometry: the row less padding, mark, gap, columns, gaps and name-to-mode gap, in pixels then floored.
    readonly property real nameSlotPlainPx: Math.max(0, root.rowWidth - 2 * Theme.spacing.rowPaddingX - root.listMarkSlot - Theme.spacing.gap - (root.listModeShown ? Theme.column.mode : 0) - (root.listSizeShown ? root.listSizeWidth : 0) - (root.listDateShown ? root.listDateWidth : 0) - (root.listKindShown ? Theme.column.kind : 0) - (root.listKindShown ? Theme.spacing.gap : 0) - ((root.listDateShown && !root.listDual) ? Theme.spacing.gap : 0) - ((root.listSizeShown && !root.listDual) ? Theme.spacing.gap : 0) - (root.listModeShown ? Theme.spacing.gap : 0))
    readonly property real nameSlotClipPx: Math.max(0, root.nameSlotPlainPx - Theme.spacing.gap - root.listClipPx)
    readonly property int nameBudgetPlain: Theme.bodyAdvance > 0 && root.nameSlotPlainPx > 0 ? Math.floor(root.nameSlotPlainPx / Theme.bodyAdvance) : -1
    readonly property int nameBudgetClip: Theme.bodyAdvance > 0 && root.nameSlotClipPx > 0 ? Math.floor(root.nameSlotClipPx / Theme.bodyAdvance) : -1
    property bool clipEmpty: ClipMarks.isEmpty(root.pane ? root.pane.clipboard : null)
    // The short-circuit below is the only release while empty, so a cut of a large directory frees its lookup here.
    onClipEmptyChanged: { if (root.clipEmpty) ClipMarks.release() }

    // Pane owns cursorIndex, thumbState and dirSizeState; List only computes what changed and hands it back.
    // Both ends of cursorClamped are view positions, not listing rows: under a filter they differ.
    signal cursorClamped(int first, int last)
    signal thumbsApplied(var work)
    signal dirSizesApplied(var ask)
    signal dirSizesCancelled()

    focus: true
    model: pane.shownTotal
    clip: true
    cacheBuffer: Theme.fileRowHeight * pane.cacheRows
    boundsBehavior: Flickable.StopAtBounds
    highlightMoveDuration: 0
    // Every property the delegate draws is a binding on index, so a row leaving the buffer is re-bound rather than rebuilt.
    reuseItems: true

    Flea.FastScrollHandler {
        parent: root
        flickable: root
    }

    readonly property alias scrollBar: verticalScroll
    Flea.ViewportScrollBar {
        id: verticalScroll
        parent: root
        anchors { top: parent.top; right: parent.right }
        flickable: root
    }

    Flea.SelectionBand {
        parent: root
        pane: root.pane
        flickable: root
    }

    Flea.FileDrag {
        id: dragSession
        pane: root.pane
    }

    delegate: Flea.Row {
        id: cell
        required property int index
        // index is where the row is drawn; listingIndex is the row the backend numbers, and under a
        // filter the two are different. Everything that leaves this delegate takes the listing one.
        readonly property int listingIndex: Filter.at(root.pane.shown, index)
        // The scroll lane stays clear so rows never reflow under the bar.
        width: root.rowWidth
        row: root.pane.rowFor(listingIndex)
        cursor: listingIndex === root.pane.cursorIndex
        paneFocused: root.pane.paneFocused
        dualMode: root.pane.dualMode
        hiddenCols: root.rowHiddenCols
        hovered: hover.hovered
        thumb: root.thumbFor(listingIndex)
        selected: root.pane.isSelected(listingIndex)
        // Empty short-circuits before the library, so no row calls it while the clipboard is empty.
        clipMark: root.clipEmpty ? "" : ClipMarks.markForRow(root.pane, cell.row ? cell.row.n : "", root.pane.clipboard)
        // Shared budgets: one floor per List state, not per row; drop rows keep local measured geometry in Row.
        assignedNameBudget: cell.clipMark.length > 0 ? root.nameBudgetClip : root.nameBudgetPlain
        kindNames: root.pane.kindNames
        dirSize: root.dirSizeFor(listingIndex)
        // A filter paints its run the same way a search does; filtering below is what keeps the
        // ordinary columns, because these rows are still this directory's own and not walk results.
        searchQuery: root.pane.searchMode.length > 0 ? root.pane.searchQuery : root.pane.filterQuery
        filtering: root.pane.shown !== null
        renaming: listingIndex === root.pane.renamingIndex
        renamePane: root.pane
        // -1 is also what Filter.at answers for a stale delegate, so an idle list must never light one.
        dropTarget: dragSession.dropIndex >= 0 && listingIndex === dragSession.dropIndex
        dropCopying: dragSession.dragCopy

        onRenameCommitted: function (newName) { root.pane.commitRename(newName) }
        onRenameAbandoned: root.pane.renamingIndex = -1

        HoverHandler {
            id: hover
            enabled: root.pane.selectionBand === null
        }

        TapHandler {
            id: tap
            enabled: !cell.renaming
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: function (eventPoint, button) {
                if (button === Qt.RightButton)
                    Tap.tappedMenu(listingIndex, eventPoint, root.pane, root.menu)
                else
                    Tap.tapped(listingIndex, tap.tapCount, tap.point.modifiers, root.pane)
            }
        }

        Flea.RowDrag {
            session: dragSession
            listingIndex: cell.listingIndex
            row: cell.row
        }
    }


    // The listing keeps one row of bare ground at its end. SearchFilter rule 1 took the filter's
    // sentence off this slot, and the ground under it is not the sentence: it is where a band starts
    // and where the background menu is raised, and a listing whose last row sits flush on the bottom
    // edge offers neither once it is scrolled to the end.
    footer: Item {
        width: root.rowWidth
        height: Theme.chromeHeight
    }

    // Empty space under the last row belongs to the directory, not to a row, so it raises the
    // background menu. Tap.onBackground says the point missed every delegate, which is what leaves a
    // right click on a row to that row's own handler above.
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: function (eventPoint) {
            if (Tap.onBackground(root, eventPoint))
                root.menu.openBackground(eventPoint.scenePosition)
        }
    }

    onContentYChanged: {
        // The wheel moves the view and not the cursor, so the cursor follows the viewport here.
        var first = Math.floor(root.contentY / Theme.fileRowHeight)
        var last = Math.min(root.pane.shownTotal - 1, first + root.pane.visibleRows - 1)
        if (root.pane.renamingIndex >= 0) {
            var range = root.visibleRange()
            first = range.first
            last = range.last
        }
        if (last >= first && root.pane.selectionBand === null) {
            root.cursorClamped(first, last)
        }
        root.menu.close()
        // Gated on hasPending (see DirSizes.js) rather than diffed at settle like thumbcancel, see docs/protocol.md "dirsizecancel".
        if (DirSizes.hasPending(root.pane.dirSizeState)) {
            root.pane.backend.dirsizecancel()
            root.dirSizesCancelled()
        }
        coalesce.start()
        settle.restart()
    }

    function visibleRange() {
        var fallback = Thumbs.viewport(root.contentY, Theme.fileRowHeight, root.pane.visibleRows, root.pane.shownTotal)
        // The retained error caption expands one row; query actual delegates while it is present.
        if (root.pane.renamingIndex >= 0) {
            var first = root.indexAt(0, root.contentY)
            var last = root.indexAt(0, root.contentY + root.height - 1)
            first = first < 0 ? fallback.first : first
            return {first: first, last: last < 0 ? Math.min(root.count - 1, first + root.pane.visibleRows) : last}
        }
        return fallback
    }

    // Pane's own open() and its Connections.onRows reach these two through the wrapper functions below.
    Timer {
        id: coalesce
        interval: root.pane.coalesceMs
        repeat: false
        onTriggered: root.requestIfDrifted()
    }

    // Resize and filter changes can change the visible work without moving contentY.
    Connections {
        target: root.pane
        function onVisibleRowsChanged() { settle.restart() }
        function onFilterQueryChanged() {
            if (!root.visible) return
            var work = Filter.cut({ask: [], drop: []}, root.pane.shown, root.pane.thumbState)
            work.drop = work.drop.filter(function(index) { return index !== root.pane.previewIndex })
            if (work.drop.length > 0) {
                root.pane.backend.thumbcancel(work.drop)
                root.thumbsApplied(work)
            }
            if (DirSizes.hasPending(root.pane.dirSizeState)) {
                root.pane.backend.dirsizecancel()
                root.dirSizesCancelled()
            }
            settle.restart()
        }
    }

    Connections {
        target: ViewState
        function onThumbnailModeChanged() { if (root.visible) settle.restart() }
        // A hidden-then-shown Size column asks for the visible rows at that moment.
        function onHiddenColsChanged() { if (root.visible) settle.restart() }
    }

    Timer {
        id: settle
        interval: root.pane.firstSettleMs
        repeat: false
        onTriggered: { root.requestThumbs(); root.requestDirSizes() }
    }

    // Pane.open() primes the next settle to the short first-screen interval before any row arrives.
    function primeSettle() { settle.interval = root.pane.firstSettleMs }
    function restartCoalesce() { coalesce.restart() }
    function restartSettle() { settle.restart() }

    // Only the visible rows, only once each, and only after the list has stopped moving.
    // Unknown storage holds until fsinfo names it, so the first screen never decodes as local.
    function requestThumbs() {
        if (!root.visible || root.pane.listInFlight || !root.pane.storageKnown)
            return
        var view = root.visibleRange()
        // A filtered viewport covers a set and not a run, so the run it spans is what the planner
        // gets and Filter.cut takes back every row inside that run the filter is hiding.
        var span = Filter.span(root.pane.shown, view.first, view.last)
        var work = Filter.cut(Thumbs.plan(root.pane.thumbState, root.pane.rows, root.pane.held, span.first, span.last, ViewState.thumbnailMode), root.pane.shown, root.pane.thumbState)
        work.drop = work.drop.filter(function (index) { return index !== root.pane.previewIndex })
        root.pane.backend.thumbcancel(work.drop)
        // An off class still asks; the backend answers from the cache alone, see ui/js/ExtThumbs.js.
        work.cacheOnly = ExtThumbs.cacheOnly(root.pane.storageClass, ViewState.preview)
        root.pane.backend.thumb(work.ask, work.cacheOnly)
        // The short first settle latches to the fling debounce only once a request has actually gone out.
        if (work.ask.length > 0)
            settle.interval = root.pane.settleMs
        root.thumbsApplied(work)
    }

    function thumbFor(index) {
        return Thumbs.allowed(root.pane.rowFor(index), ViewState.thumbnailMode) ? Thumbs.fileFor(root.pane.thumbState, index) : ""
    }

    function dirSizeFor(index) {
        return DirSizes.sizeFor(root.pane.dirSizeState, index)
    }

    // Same idiom as requestThumbs, minus a cancel: onContentYChanged already sent it, see above.
    function requestDirSizes() {
        if (!root.visible || root.pane.shownTotal === 0 || root.pane.listInFlight)
            return
        // A hidden Size column or a network or phone folder draws no size, so it asks for no walk.
        if (!DirSizes.wantsSizes("list", ViewState.hiddenCols, root.pane.storageClass, root.pane.storageKnown))
            return
        // Thumbs.viewport() is reused: it takes no thumb-specific state, only geometry.
        var view = root.visibleRange()
        var span = Filter.span(root.pane.shown, view.first, view.last)
        var ask = Filter.keep(DirSizes.plan(root.pane.dirSizeState, root.pane.rows, root.pane.held, span.first, span.last, ViewState.thumbnailMode), root.pane.shown)
        if (ask.length > 0) {
            root.pane.backend.dirsize(ask)
            settle.interval = root.pane.settleMs
        }
        root.dirSizesApplied(ask)
    }

    // Handle an empty held window explicitly before applying held-edge arithmetic.
    function requestIfDrifted() {
        // No window while a filter narrows rows already held, nor while a listing is out, whose windows are the directory asked for.
        if (root.pane.total === 0 || root.pane.shown !== null || root.pane.listInFlight)
            return
        var firstVisible = Math.floor(root.contentY / Theme.fileRowHeight)
        var lastVisible = firstVisible + root.pane.visibleRows
        if (root.pane.renamingIndex >= 0) {
            var range = root.visibleRange()
            firstVisible = range.first
            lastVisible = range.last + 1
        }
        if (root.pane.rows.length === 0) {
            root.requestAround(firstVisible)
            return
        }
        var heldEnd = root.pane.held + root.pane.rows.length
        if (firstVisible - root.pane.held < root.pane.refetchMargin && root.pane.held > 0) {
            root.requestAround(firstVisible)
        } else if (heldEnd - lastVisible < root.pane.refetchMargin && heldEnd < root.pane.total) {
            root.requestAround(firstVisible)
        }
    }

    function requestAround(firstVisible) {
        var start = Math.max(0, firstVisible - root.pane.buffer)
        root.pane.backend.window(start, root.pane.windowSize)
    }
}
