import QtQuick

// ListColumns040 board: one 9 px grab zone over a column hairline, 4 px either side,
// with the resize cursor and an accent hairline on hover or drag. Positioned by its
// caller over the hairline it moves; the drag itself lives in ui/Header.qml, so this
// owns no state beyond the press it is carrying.
Item {
    id: root

    property string columnKey: ""
    // True while this column's drag is in flight, held by the caller, not the press.
    property bool hot: false
    signal pressed(var mouse)
    signal moved(var mouse)
    signal released()
    signal doubleClicked()

    width: 9

    Rectangle {
        anchors.centerIn: parent
        width: Theme.spacing.hairline
        height: parent.height
        color: Theme.color.accent
        visible: zone.containsMouse || root.hot
    }

    MouseArea {
        id: zone
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.SplitHCursor
        onPressed: function (mouse) { root.pressed(mouse) }
        onPositionChanged: function (mouse) { root.moved(mouse) }
        onReleased: root.released()
        onCanceled: root.released()
        onDoubleClicked: root.doubleClicked()
    }
}
