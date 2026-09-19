import QtQuick
import "." as Flea

// The chrome's four view modes, one choice hairline-separated from the contextual actions beside it.
// The chosen one is foreground and its three neighbours are muted, which is brightness and survives
// every palette: an accent-inked current mode is invisible on kanagawa, where accent equals
// foreground exactly, and measures under 1.5:1 against muted on three more.
Row {
    id: root

    property string viewMode: ""

    signal chosen(string mode)

    spacing: Theme.spacing.gap

    // The group's own left edge; ui/ChromeBar.qml draws the matching one before Settings.
    Rectangle {
        width: Theme.spacing.hairline
        height: Theme.chromeMarkSize - Theme.spacing.hairline
        y: (parent.height - height) / 2
        color: Theme.color.foreground
        opacity: 0.12
    }

    Repeater {
        model: ["list", "columns", "grid", "dual"]

        // No box and no plate: four glyphs in a strip are Tier A, where a box would be furniture.
        delegate: Flea.ChromeButton {
            required property string modelData
            glyph: modelData
            restingColor: root.viewMode === modelData ? Theme.color.foreground : Theme.color.muted
            onActivated: root.chosen(modelData)
        }
    }
}
