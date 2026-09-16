import QtQuick
import "." as Flea
import "js/Focus.js" as Focus

// The pane's rail, and the two ways it comes and goes. With Auto-hide sidebar off it is part of the
// pane and Show sidebar governs it, which is 0.2.1's behaviour. Directive 77, GM's own sentence:
// "hovering over the left side should show it, like every other autohide feature in every other file
// manager ever". So with the switch on the rail is withdrawn at every width, the pointer at the
// window's left edge reveals it over the pane rather than reflowing it, and it withdraws a moment
// after the pointer or the keyboard leaves.
Item {
    id: root

    property var pane: null
    readonly property bool overlay: ViewState.railAutoHide
    readonly property bool hidden: root.overlay ? !root.revealed : ViewState.railHidden
    // An overlay owes the pane no width, so the listing never reflows as the rail comes and goes.
    // This item is that width, and the rail itself draws past it.
    readonly property real inset: root.overlay ? 0 : rail.width
    readonly property real railWidth: rail.active ? rail.width : 0
    readonly property var item: rail.item

    // Long enough that crossing the edge on the way somewhere else does not flash the rail, and that
    // leaving it by a pixel on the way to a row does not drop it.
    readonly property int settleMs: 220
    property bool revealed: false
    property bool over: false
    // The rail's own context menu takes the pointer with it, so without this the rail withdraws out
    // from under the menu it just opened.
    readonly property bool menuHere: root.pane !== null && root.pane.contextMenu().opened
                                     && root.pane.contextMenu().forRail
    readonly property bool wanted: edge.hovered || root.over || root.menuHere
                                   || (root.pane !== null && root.pane.focusView === Focus.RAIL)

    onWantedChanged: {
        if (root.wanted) { settle.stop(); root.revealed = true }
        else settle.restart()
    }
    // The switch itself is a fresh start either way: nothing is revealed until the pointer asks.
    onOverlayChanged: root.revealed = false

    anchors { top: parent.top; bottom: parent.bottom }
    width: root.inset

    Timer {
        id: settle
        interval: root.settleMs
        onTriggered: root.revealed = false
    }

    // The strip that answers the pointer, at the window's own left edge and only while the switch is
    // on. It holds no MouseArea, so a click on the listing under it still lands on the listing.
    Item {
        id: strip
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: Theme.space(4)
        enabled: root.overlay
        HoverHandler { id: edge; enabled: root.overlay }
    }

    Loader {
        id: rail
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: item ? item.implicitWidth : 0
        active: root.pane !== null && !root.pane.listOnly && root.pane.sharedSidebar === null && !root.hidden
        sourceComponent: Flea.Sidebar {
            backend: root.pane.backend
            navigationPane: root.pane.railPane
            focused: root.pane.railPane.focusView === Focus.RAIL
            trashActive: root.pane.railPane.trash.opened
            onOpened: function(path) { root.pane.railPane.open(path) }
            onNetworkOpened: function(path, origin) { if (origin) origin.open(path) }
            onTrashRequested: root.pane.railPane.trash.open()
            onMessage: function(text, isError) { root.pane.message(text, isError) }
            onForgetMessage: function(text) { root.pane.forgetMessage(text) }
            menu: root.pane.railPane.contextMenu()
            onRenameFinished: root.pane.railPane.listArea.forceActiveFocus()
            // The rail stays up while the pointer is on it, which is the other half of the reveal.
            HoverHandler { onHoveredChanged: root.over = hovered }
        }
    }
}
