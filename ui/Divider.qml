import QtQuick

// One hairline both the rail edge and the column edges draw, so width and ink match by construction.
Rectangle {
    property bool isDivider: true
    width: Theme.spacing.hairline
    color: Theme.color.foreground
    opacity: 0.12
}
