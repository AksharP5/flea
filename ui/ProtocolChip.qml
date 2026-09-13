import QtQuick

// One protocol chip. Every member wears the box, Containers Tier B, and the picked one says so by
// brightening its text and its border rather than by taking a fill.
Item {
    id: root

    property string label: ""
    property bool picked: false

    signal activated()
    signal tabbed(var from, bool back)

    readonly property bool focused: root.activeFocus

    function takeFocus() {
        root.forceActiveFocus()
    }

    Keys.onTabPressed: function(event) { root.tabbed(root, (event.modifiers & Qt.ShiftModifier) !== 0) }
    Keys.onBacktabPressed: root.tabbed(root, true)
    Keys.onReturnPressed: root.activated()
    Keys.onEnterPressed: root.activated()
    Keys.onSpacePressed: root.activated()

    implicitWidth: Math.max(Theme.hitMin, text.implicitWidth + 2 * Theme.spacing.gap + 2 * Theme.spacing.hairline)
    implicitHeight: Math.max(Theme.hitMin, text.implicitHeight + Theme.spacing.gap + 2 * Theme.spacing.hairline)

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.onPressAction: root.activated()

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: Theme.spacing.hairline
        border.color: root.picked || root.focused ? Theme.color.foreground : Theme.color.muted
    }

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: root.picked ? Theme.color.foreground : Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        textFormat: Text.PlainText
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.activated()
    }
}
