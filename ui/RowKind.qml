import QtQuick

// One list-row metadata cell: the kind column with the Text itself as root.
Text {
    id: root

    property bool kindShown: false
    property bool dropTarget: false
    property color ink: Theme.color.foreground
    property string cellText: ""

    visible: root.kindShown && !root.dropTarget
    width: root.kindShown ? Theme.column.kind : 0
    // A hidden column holds no text, because a laid-out Text costs memory whether or not it is drawn.
    text: root.cellText
    color: root.ink
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
