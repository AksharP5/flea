import QtQuick

// The listing's loading touch, EmptyState's sibling: the caller places it over listArea and
// gates visibility on listingState. The hold-off keeps a local listing, single-digit
// milliseconds on this box, from ever flashing the mark; only slow sources (network mounts,
// a cold spinning disk) live long enough to show it.
Item {
    id: root

    readonly property int holdOffMs: 150
    property bool armed: false

    // running binds to visibility rather than an onVisibleChanged handler: the pane starts life
    // in "loading", so visible is true at creation and a change handler would never fire.
    Timer {
        id: holdOff
        interval: root.holdOffMs
        running: root.visible
        onTriggered: root.armed = true
    }

    onVisibleChanged: if (!root.visible) root.armed = false

    Column {
        anchors.centerIn: parent
        spacing: Theme.spacing.gap
        visible: root.armed

        Spinner {
            anchors.horizontalCenter: parent.horizontalCenter
            // The same brand mark as EmptyState's hero, which States.dc.html draws at 48; two row heights was 74.
            width: Theme.heroMarkSize
            height: Theme.heroMarkSize
        }

        // States draws the crawl with one word under it, and one word is the whole of what it knows.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "reading"
            color: Theme.color.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
        }
    }
}
