import QtQuick
import "." as Flea
import "js/Crumbs.js" as Crumbs

// A dual pane's own path, drawn with the chrome's crumbs so issue 45's one tap on a parent reaches either pane.
Rectangle {
    id: root

    property string path: ""
    property string home: ""
    property bool focused: false
    readonly property alias crumbItems: crumbs
    readonly property alias crumbSlot: slot

    signal chosen(string path)
    signal editRequested()

    color: root.focused ? Theme.color.surface : Theme.color.background

    // One glyph's advance is every glyph's advance in this face, the same fit ui/ChromeBar.qml makes.
    TextMetrics {
        id: metrics
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        text: "0"
    }

    Item {
        id: slot
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.rowPaddingX
        anchors.rightMargin: Theme.spacing.rowPaddingX
        clip: true

        Row {
            id: row
            height: slot.height

            Repeater {
                id: crumbs
                model: Crumbs.fitCrumbs(Crumbs.crumbs(root.path, root.home), Math.floor(slot.width / metrics.advanceWidth))

                delegate: Flea.Crumb {
                    height: slot.height
                    restColor: Theme.color.foreground
                    onChosen: function (path) { root.chosen(path) }
                    onEditRequested: root.editRequested()
                }
            }
        }

        // The rest of the strip names no directory and keeps the double click that types the path.
        Item {
            anchors { left: row.right; right: parent.right; top: parent.top; bottom: parent.bottom }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onDoubleTapped: root.editRequested()
            }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Theme.spacing.hairline
        color: Theme.color.muted
    }
}
