import QtQuick
import qs.Commons
import "." as Flea

// A live chrome control inks in foreground; active and focused ones use the accent.
Item {
    id: root

    property string glyph: "file"
    property bool active: false
    property bool keyboardFocused: false
    // False while something the chrome sits under takes the pointer; the handlers stop, the drawing does not.
    property bool inputLive: true
    property color restingColor: Theme.color.foreground
    // DragThreshold lets a drag that starts on a chrome bar button move the window; an overlay's instance passes ReleaseWithinBounds.
    property int gesturePolicy: TapHandler.DragThreshold
    property real glyphSize: Theme.chromeMarkSize

    signal activated()

    // A control with nowhere to go keeps its slot so the bar never reflows, and says so by dimming.
    property real disabledOpacity: Theme.disabledOpacity

    property string accessName: {
        if (root.glyph === "arrow-left")
            return "Back"
        if (root.glyph === "arrow-up")
            return "Parent folder"
        if (root.glyph === "search")
            return "Search"
        if (root.glyph === "list")
            return "List view"
        if (root.glyph === "columns")
            return "Columns view"
        if (root.glyph === "grid")
            return "Grid view"
        return root.glyph
    }

    // The mark stays the chrome token; the hit box is at least 24 px wide and the strip's height.
    implicitWidth: Math.max(Theme.hitMin, Theme.chromeMarkSize)
    implicitHeight: Theme.chromeHeight
    scale: tap.pressed && root.enabled && !Theme.reducedMotion ? 0.96 : 1

    Accessible.role: Accessible.Button
    Accessible.name: root.accessName
    Accessible.onPressAction: if (root.enabled) root.activated()

    Behavior on scale {
        enabled: !Theme.reducedMotion
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    Flea.Glyph {
        anchors.centerIn: parent
        width: root.glyphSize
        height: root.glyphSize
        name: root.glyph
        // Containers Tier A: a chrome glyph wears no box, so the keyboard says where it is by brightness and the caller dims the rest of the strip.
        color: !root.enabled ? Theme.color.muted
             : root.active ? Theme.color.accent
             : root.keyboardFocused ? Theme.color.foreground : root.restingColor
        opacity: root.enabled ? 1 : root.disabledOpacity
    }

    HoverHandler {
        enabled: root.inputLive
        cursorShape: Qt.PointingHandCursor
    }

    // overlay-tap-exempt: the instance chooses, and tests/shellload.sh holds every overlay's instance to ReleaseWithinBounds.
    TapHandler {
        id: tap
        enabled: root.inputLive
        acceptedButtons: Qt.LeftButton
        gesturePolicy: root.gesturePolicy
        onTapped: root.activated()
    }
}
