import QtQuick
import "js/RecentDates.js" as RecentDates

// One list-row metadata cell: the date column. Root is the Text itself, so replacing
// ui/Row.qml's inline modified Text with RowDate builds the same one object.
// With Highlight today's dates on, a stamp from today draws in the foreground role and
// every older stamp keeps the handed dim ink; the text keeps its one sortable form.
Text {
    id: root

    property bool dateShown: false
    property bool kindShown: false
    property bool dropTarget: false
    property real dateWidth: Theme.column.date
    property color ink: Theme.color.foreground
    property string cellText: ""
    // The switch and the window-level local-midnight boundary from ViewState, plus
    // this row's own backend mtime in seconds; the compare is one number, no Date.
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
