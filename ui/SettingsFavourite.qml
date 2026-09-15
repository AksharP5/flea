import QtQuick
import "." as Flea

// Favourite records keep their exact label/path; only the drag handle initiates reordering.
Item {
    id: root
    property var row: ({})
    signal activated()
    signal moved(int to)
    signal removed()
    readonly property Item dragItem: grip
    readonly property Item removeItem: remove
    implicitHeight: Theme.railRowHeight

    Flea.Glyph {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.railIconSize
        height: width
        name: root.row.glyph || "folder"
        color: root.row.error ? Theme.color.error : Theme.color.muted
    }
    Text {
        anchors.left: icon.right
        anchors.leftMargin: Theme.spacing.gap
        anchors.right: path.left
        anchors.rightMargin: Theme.spacing.gap
        anchors.verticalCenter: parent.verticalCenter
        text: root.row.label || ""
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
        color: root.row.error ? Theme.color.error : Theme.color.foreground
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
    Text {
        id: path
        anchors.right: grip.left
        anchors.rightMargin: Theme.spacing.gap
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.width * 0.46)
        text: root.row.value || ""
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        color: root.row.error ? Theme.color.error : Theme.color.muted
        elide: Text.ElideMiddle
        textFormat: Text.PlainText
    }
    // SettingsRest rule 4: an action that acts on one row reads as a mark on that row, where a button
    // under the list leaves its target to be inferred from a cursor somewhere above it.
    Flea.Glyph {
        id: remove
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.hitMin
        height: Theme.hitMin
        name: "x"
        color: Theme.color.muted
        Accessible.role: Accessible.Button
        Accessible.name: "Remove " + (root.row.label || "")
        Accessible.onPressAction: root.removed()
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: root.removed()
        }
    }

    Flea.Glyph {
        id: grip
        anchors.right: remove.left
        anchors.rightMargin: 0
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.hitMin
        height: Theme.hitMin
        name: "list"
        color: Theme.color.muted
        DragHandler {
            id: drag
            target: null
            xAxis.enabled: false
            property real startY: 0
            onActiveChanged: {
                if (active) { startY = persistentTranslation.y; return }
                // A pin is a favourite-shaped row ordered inside the shelf's own pile, so the drag
                // counts rows in whichever list this one came from.
                var from = root.row.pinIndex !== undefined ? root.row.pinIndex : root.row.favouriteIndex
                var last = (root.row.pinIndex !== undefined ? root.row.pinCount : Favourites.records.length) - 1
                // Qt clears active translation before this release callback.
                var to = Math.max(0, Math.min(last,
                    from + Math.round((persistentTranslation.y - startY) / Theme.railRowHeight)))
                if (to !== from) root.moved(to)
            }
        }
    }
    TapHandler {
        // The remove mark owns its own corner of the row, and a TapHandler under another one still
        // taps, so the row reads where the press landed rather than opening the folder it removes.
        onTapped: function (point) { if (point.position.x < remove.x) root.activated() }
    }
}
