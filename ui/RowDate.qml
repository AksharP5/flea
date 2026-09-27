import QtQuick

// One list-row metadata cell: the date column. Root is the Text itself, so replacing
// ui/Row.qml's inline modified Text with RowDate builds the same one object.
Text {
    id: root

    property bool dateShown: false
    property bool kindShown: false
    property bool dropTarget: false
    property real dateWidth: Theme.column.date
    property color ink: Theme.color.foreground
    property string cellText: ""

    visible: root.dateShown && !root.dropTarget
    width: root.dateShown ? root.dateWidth : 0
    text: root.cellText
    color: root.ink
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
