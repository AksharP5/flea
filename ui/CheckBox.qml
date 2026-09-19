import QtQuick
import "." as Flea

// The one checkbox every surface draws, Containers rule 14. The box is the control and every member
// wears it; state is filled against empty, so no palette has to separate accent from foreground.
Item {
    id: root

    // "off", "on", or "some", which is a group heading's state and never a row's.
    property string value: "off"
    // Availability is not an off value: an unavailable box keeps whatever it holds and dims.
    property bool available: true
    // The keyboard reads as brightness on the frame, so it never competes with filled against empty.
    property bool focused: false

    readonly property bool filled: root.value !== "off"
    readonly property int borderWidth: 2 * Theme.spacing.hairline

    // A 14px interior inside two 2px borders, so 18px outer at bodySmall 13.
    implicitHeight: Math.round(14 * Theme.font.bodySmall / 13) + 2 * root.borderWidth
    implicitWidth: root.implicitHeight
    opacity: root.available ? 1 : Theme.disabledOpacity

    Accessible.role: Accessible.CheckBox
    Accessible.checked: root.value === "on"

    Rectangle {
        anchors.fill: parent
        color: root.filled ? Theme.color.foreground : "transparent"
        border.width: root.borderWidth
        border.color: root.filled || root.focused ? Theme.color.foreground : Theme.color.muted

        // The mark is the fill cut away, so the control needs no third colour and no accent at all.
        Flea.Glyph {
            anchors.centerIn: parent
            width: Theme.font.bodySmall * 10 / 13
            height: width
            strokeWidth: 3
            visible: root.filled
            name: root.value === "some" ? "minus" : "check"
            color: Theme.color.background
        }
    }
}
