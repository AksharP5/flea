import QtQuick

// One list-row metadata cell: the mode column.
Text {
    id: root

    property bool modeShown: false
    property bool dropTarget: false
    property color ink: Theme.color.foreground
    property string cellText: ""

    visible: root.modeShown && !root.dropTarget
    width: root.modeShown ? Theme.column.mode : 0
    // A hidden column holds no text, because a laid-out Text costs memory whether or not it is drawn.
    text: root.cellText
    color: root.ink
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
