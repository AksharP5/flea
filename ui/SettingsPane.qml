import QtQuick
import "." as Flea
import "js/Settings.js" as Settings

// View supplies the compact card's stable height; longer sections scroll within the same viewport.
Flickable {
    id: root

    property string section: "display"
    // The one object ui/js/Settings.js rows() reads, built by the panel so both files see the same
    // values. Not named state: that is Item's own property, and shadowing it is a qmllint override.
    property var values: ({})
    property int cursor: 0
    property string side: "pane"
    readonly property real compactHeight: sections.count > 0 && sections.itemAt(0) ? sections.itemAt(0).implicitHeight : 0

    signal activated(int index)
    signal pointerMoved(int index)
    signal favouriteMoved(int index, int to)
    signal favouriteRemoved(int index)
    signal stepped(int index, int direction)
    signal stopPicked(int index, int stop)

    // count is read so the binding re-evaluates once the Repeater has built its columns.
    readonly property Item current: sections.count > 0
        ? sections.itemAt(root.section === "columns" ? Settings.SECTIONS.length : Settings.sectionIndex(root.section)) : null

    onContentYChanged: inspection.restart()
    onSectionChanged: inspection.restart()
    onVisibleChanged: if (visible) inspection.restart()
    Timer {
        id: inspection
        interval: 120
        onTriggered: {
            if (!root.visible || root.section !== "places" || !root.current) return
            var indices = []
            for (var i = 0; i < root.current.rows.count; i++) {
                var item = root.current.rows.itemAt(i)
                if (item && item.row.kind === "favourite" && item.y + item.height > root.contentY && item.y < root.contentY + root.height)
                    indices.push(item.row.favouriteIndex)
            }
            Favourites.inspect(indices)
        }
    }
    contentWidth: width
    contentHeight: root.current ? root.current.implicitHeight : 0
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    onHeightChanged: root.showCursor(root.cursor, false)

    Flea.FastScrollHandler {
        parent: root
        flickable: root
    }

    // SettingsMenus rule 4: a section taller than the viewport fades at its lower edge instead of
    // slicing a row, so the cut says that more follows. parent: root keeps it off the content item,
    // which is what scrolls; a fully transparent stop is written in the ground's own channels,
    // because "transparent" is black at zero alpha and ramps through grey on the way there.
    Rectangle {
        parent: root
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(Theme.rowHeight * 0.7)
        visible: root.contentHeight - root.contentY - root.height > Theme.spacing.hairline
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(Theme.color.surface.r, Theme.color.surface.g, Theme.color.surface.b, 0) }
            GradientStop { position: 1; color: Theme.color.surface }
        }
    }

    // The row item at an index of the chosen section, or null before the columns exist.
    function rowItem(index) { return root.current ? root.current.rows.itemAt(index) : null }

    // The Column inside the Flickable holds rows of two different heights, so the visible window is
    // moved onto the row itself rather than derived from an index times a row height.
    // last is the cursor sitting on the final row that can hold it: the rows after it are read-only,
    // so revealing the cursor alone would leave the section's own tail unreachable by the keyboard.
    function showCursor(index, last) {
        var item = root.rowItem(index)
        if (!item)
            return
        // The tail is revealed by taking the cursor row to the top of the pane, never past it: on a
        // short window the rows after it are taller than the viewport, and scrolling to the content's
        // own end would push the row the keyboard is on off the top of the card.
        if (last) {
            root.contentY = Math.max(0, Math.min(root.contentHeight - root.height, item.y))
            return
        }
        if (item.y < root.contentY)
            root.contentY = item.y
        else if (item.y + item.height > root.contentY + root.height)
            root.contentY = item.y + item.height - root.height
    }

    Repeater {
        id: sections
        // Keep View's measurement intact while its Columns subpage is open.
        model: Settings.SECTIONS.concat([{id: "columns"}])

        delegate: Column {
            id: column
            required property var modelData
            readonly property alias rows: rowItems
            width: root.width
            visible: modelData.id === root.section

            Repeater {
                id: rowItems
                model: Settings.rows(column.modelData.id, root.values)

                delegate: Flea.SettingsRow {
                    required property var modelData
                    required property int index
                    width: column.width
                    row: modelData
                    firstRow: index === 0
                    current: column.visible && root.side === "pane" && root.cursor === index
                    onActivated: root.activated(index)
                    onPointerMoved: root.pointerMoved(index)
                    onFavouriteMoved: function (to) { root.favouriteMoved(index, to) }
                    onFavouriteRemoved: root.favouriteRemoved(index)
                    onStepped: function (direction) { root.stepped(index, direction) }
                    onStopPicked: function (stop) { root.stopPicked(index, stop) }
                }
            }
        }
    }
}
