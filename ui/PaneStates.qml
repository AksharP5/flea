import QtQuick
import "." as Flea

// What a pane draws instead of rows: the empty hero, the reading spiral and the failure block. All
// three sit over the same slot and are gated on the same listing state, so they live together and
// ui/Pane.qml carries one child rather than three.
Item {
    id: root

    required property var pane
    property bool trashOpen: false

    readonly property alias emptyItem: emptyState
    readonly property alias messageItem: paneMessage

    Flea.EmptyState {
        id: emptyState
        // The hero belongs over the listing that is empty, which in the columns view is the active
        // column and not the whole area right of the parent. Measured on this box, spanning the
        // active column and the child slot together centred the mark at 1755 against the list
        // view's 1364: the animation jumped a third of the window on a view switch and landed on
        // the divider between the two slots. Over the active column it lands at 1363, so all three
        // views draw it in the same place and none of them draws it on a rule.
        x: root.pane.listSlot.x + (root.pane.viewMode === "columns" && root.pane.columnsArea ? root.pane.columnsArea.columnWidth : 0)
        y: root.pane.listSlot.y
        width: root.pane.viewMode === "columns" && root.pane.columnsArea
               ? root.pane.columnsArea.columnWidth : root.pane.listSlot.width
        height: root.pane.listSlot.height
        visible: !root.trashOpen && root.pane.listingState === "empty"
        caption: root.pane.searchMode === "results" ? "Nothing matches " + root.pane.searchQuery : ""
        mark: "search"
        hint: root.pane.searchMode === "results" ? "Press Escape to clear."
            : ViewState.keyHints ? "Press Ctrl+Shift+N for a new folder." : ""
    }

    Flea.LoadingState {
        x: root.pane.listSlot.x
        y: root.pane.listSlot.y
        width: root.pane.listSlot.width
        height: root.pane.listSlot.height
        visible: !root.trashOpen && root.pane.listingState === "loading"
    }

    Flea.StateMessage {
        id: paneMessage
        active: !root.trashOpen
        x: root.pane.listSlot.x + Theme.spacing.rowPaddingX
        y: root.pane.listSlot.y
        width: root.pane.listSlot.width - 2 * Theme.spacing.rowPaddingX
        height: root.pane.listSlot.height
        message: root.pane.stateMessage
        listingState: root.pane.listingState
        lockedMode: root.pane.lockedMode
        total: root.pane.total
        filterQuery: root.pane.filterQuery
        shown: root.pane.filterQuery.length > 0 ? root.pane.shownTotal : -1
    }
}
