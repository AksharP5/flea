import QtQuick
import "js/RecentDates.js" as RecentDates

// One list-row metadata cell: the date column, drawing today in the foreground role when highlighted.
Text {
    id: root

    property bool dateShown: false
    property bool dropTarget: false
    property real dateWidth: Theme.column.date
    property color ink: Theme.color.foreground
    property string cellText: ""
    // ViewState's switch and midnight boundary plus this row's mtime; the compare is one number.
    property bool highlightToday: false
    property double todayStart: 0
    property var mtime: null

    visible: root.dateShown && !root.dropTarget
    width: root.dateShown ? root.dateWidth : 0
    text: root.cellText
    color: RecentDates.isRecent(root.highlightToday, root.mtime, root.todayStart) ? Theme.color.foreground : root.ink
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
