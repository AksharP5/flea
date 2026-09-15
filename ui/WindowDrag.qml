import QtQuick

// The pointer's title bar: ui/shell.qml asks for no decorations, so nothing in this tree ever asked
// the compositor to move the window and only its own Super bind could.
Item {
    id: root

    // The caller's path editor is up, and a press that travels there selects text rather than moves.
    required property bool editing

    anchors.fill: parent

    DragHandler {
        id: move

        // A handler and not a MouseArea, so a press that does not travel stays a click on the button,
        // crumb or path under the pointer, and target is null because the move belongs to the window.
        target: null
        acceptedButtons: Qt.LeftButton
        // Well under Qt's own 10, because a title bar reads a few pixels of travel as intent.
        dragThreshold: 4
        enabled: !root.editing

        onActiveChanged: {
            if (!move.active)
                return
            // The same attached route ui/CardScroll.qml and ui/Ipc.qml take, so no window is threaded in.
            var window = root.Window.window
            if (window)
                window.startSystemMove()
        }
    }
}
