import QtQuick

// One list-row metadata cell: the size column. Root is the Text itself, so replacing
// ui/Row.qml's inline size Text with RowSize builds the same one object.
Text {
    id: root

    property bool sizeShown: false
    property bool dateShown: false
    property bool dualMode: false
    property bool dropTarget: false
    property real sizeWidth: Theme.column.size
    property color ink: Theme.color.foreground
    property string cellText: ""

    visible: root.sizeShown && !root.dropTarget
    width: root.sizeShown ? root.sizeWidth : 0
    // A hidden column holds no text, because a laid-out Text costs memory whether or not it is drawn.
    text: root.cellText
    color: root.ink
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
