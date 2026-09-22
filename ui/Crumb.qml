import QtQuick

// One piece of a path that a click can land on, the chrome's and a dual pane's alike; keys.toml's "chrome" rows are its contract.
Text {
    id: crumb

    required property var modelData
    // What an ancestor reads at rest: muted in the chrome, where only the leaf is lit, and the foreground on a dual pane's path.
    property color restColor: Theme.color.muted

    signal chosen(string path)
    signal editRequested()

    // corner: a path is arbitrary text, so PlainText, the same rule every filename on this surface follows.
    text: crumb.modelData.text
    color: crumb.modelData.last || (crumbHover.hovered && !crumb.modelData.elided) ? Theme.color.foreground : crumb.restColor
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter

    HoverHandler {
        id: crumbHover
        cursorShape: crumb.modelData.last || crumb.modelData.elided ? Qt.IBeamCursor : Qt.PointingHandCursor
    }

    // No exclusiveSignals, GM's ruling of 2026-09-22: the pair held every tap for the whole double-click interval, about 400 ms.
    // The gesture sits on the crumb because a TapHandler on a parent takes the second tap from the child under the pointer.
    TapHandler {
        acceptedButtons: Qt.LeftButton
        // The collapsed marker names no directory, so a press on it opens nothing rather than whichever crumb it stands for.
        onSingleTapped: if (!crumb.modelData.last && !crumb.modelData.elided) crumb.chosen(crumb.modelData.path)
        // Only where a tap opens nothing does a double click type the path; on a parent it is two taps.
        onDoubleTapped: if (crumb.modelData.last || crumb.modelData.elided) crumb.editRequested()
    }
}
