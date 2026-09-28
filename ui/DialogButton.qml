import QtQuick
import qs.Commons
import "js/Buttons.js" as Buttons

// Variant A (Buttons040, GM 2026-09-24): the one control every dialog, card and picker button draws.
Item {
    id: root

    property string label: ""
    property bool primary: false
    // A destructive action rests as the error label in a muted frame, never primary.
    property bool destructive: false
    property real horizontalPadding: Theme.spacing.gap
    // An action this dialog cannot take right now. The ink says so and the press
    // does nothing, rather than a live control that answers nothing.
    property bool available: true
    // The keyboard's own signal. Callers whose focus sits on a wrapper pass it down.
    property bool focused: root.activeFocus
    // True where the form owns the Tab order and the button only reports through tabbed.
    property bool tabHandle: false

    signal activated()
    // The form owns the order; a button only reports that Tab happened inside it.
    signal tabbed(var from, bool back)

    // The canvas draws a secondary button as a hairline rule carrying live text, so only the frame
    // takes muted, the role ThemeRoles.html gives borders and inactive controls; the label is alive.
    readonly property color frame: root.primary && root.available ? Theme.color.accentFrame : Theme.color.muted
    readonly property color ink: !root.available ? Theme.color.muted
        : root.destructive ? Theme.color.error : Theme.color.foreground
    // The frame and this wash say which action is being asked for; an accent label said it by going darker, HANDOFF rule 18.
    readonly property color wash: root.primary && root.available ? Qt.alpha(Theme.color.accent, Buttons.WASH_PRESS) : "transparent"

    implicitWidth: Math.max(Theme.hitMin, text.implicitWidth + 2 * root.horizontalPadding + 2 * Theme.spacing.hairline)
    implicitHeight: Theme.rowHeight - Theme.spacing.rowPaddingY
    opacity: root.available ? 1 : Buttons.DISABLED_OPACITY
    scale: tap.pressed && root.available && !Theme.reducedMotion ? 0.96 : 1

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.onPressAction: if (root.available) root.activated()

    Behavior on scale {
        enabled: !Theme.reducedMotion
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    Rectangle {
        anchors.fill: parent
        color: root.wash
        border.width: Theme.spacing.hairline
        border.color: root.frame
    }

    // Hover and press lay the control's own ink over the wash a primary carries.
    Rectangle {
        anchors.fill: parent
        color: tap.pressed && root.available ? Qt.alpha(root.ink, Buttons.WASH_PRESS)
            : hover.hovered && root.available ? Qt.alpha(root.ink, Buttons.WASH_HOVER) : "transparent"
    }

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: root.ink
        font.family: Theme.font.family
        font.pixelSize: Buttons.labelSizeFor(Theme.font.body)
        textFormat: Text.PlainText
    }

    // Focus never moves the frame: the ring says where the keyboard is.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Buttons.RING
        color: "transparent"
        border.width: Buttons.RING
        border.color: Theme.color.foreground
        visible: root.focused && root.available
    }

    HoverHandler {
        id: hover
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    // A focused button answers Enter exactly as a press does; a handled Tab is accepted here so Qt never moves focus past the form's own stepFocus order.
    Keys.onReturnPressed: function(event) { if (root.available) root.activated(); else event.accepted = false }
    Keys.onEnterPressed: function(event) { if (root.available) root.activated(); else event.accepted = false }
    Keys.onSpacePressed: function(event) { if (root.available) root.activated(); else event.accepted = false }
    Keys.onTabPressed: function(event) {
        if (!root.tabHandle) { event.accepted = false; return }
        root.tabbed(root, (event.modifiers & Qt.ShiftModifier) !== 0)
        event.accepted = true
    }
    Keys.onBacktabPressed: function(event) {
        if (!root.tabHandle) { event.accepted = false; return }
        root.tabbed(root, true)
        event.accepted = true
    }

    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: if (root.available) root.activated()
    }
}
