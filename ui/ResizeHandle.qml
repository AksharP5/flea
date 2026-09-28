import QtQuick

// ListColumns040 board: one grab zone over a column hairline; the caller centres it on a whole pixel, the drag lives in ui/Header.qml.
Item {
    id: root

    property string columnKey: ""
    // True while this column's drag is in flight, held by the caller, not the press.
    property bool hot: false
    signal pressed(var mouse)
    signal moved(var mouse)
    signal released()
    signal doubleClicked()

    width: 9 // ui/Header.qml offsets each zone by floor(width / 2), so this is the only number.

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
