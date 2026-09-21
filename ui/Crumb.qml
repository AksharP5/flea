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

    // Both flags, measured on Qt 6.11.2: only the pair lets the tap count decide, so a double click types the path and never also navigates.
    // The gesture sits on the crumb because a TapHandler on a parent takes the second tap from the child under the pointer.
    TapHandler {
        acceptedButtons: Qt.LeftButton
        exclusiveSignals: TapHandler.SingleTap | TapHandler.DoubleTap
        // The collapsed marker names no directory, so a press on it opens nothing rather than whichever crumb it stands for.
        onSingleTapped: if (!crumb.modelData.last && !crumb.modelData.elided) crumb.chosen(crumb.modelData.path)
        onDoubleTapped: crumb.editRequested()
    }
}
