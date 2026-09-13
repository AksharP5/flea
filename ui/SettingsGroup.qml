import QtQuick
import "." as Flea

// One settings heading. Where the group has a master, the heading is also that master's control:
// SettingsMenus rule 3 puts the tri-state box and the group's own enabled count on the heading it
// governs, so neither is a row of its own and every group answers the question it raises.
Item {
    id: root

    // {label, master, state, value} from ui/js/Settings.js, the group row itself.
    property var row: ({})
    property bool first: false

    // Settings headings scale their resolved 12/15/4/8 insets once from the boards' bodySmall 13 anchor.
    readonly property real insetScale: Theme.font.bodySmall / 13
    readonly property real gap: root.first ? 0 : Math.round(8 * root.insetScale)
    readonly property real paddingTop: Math.round((root.first ? 12 : 15) * root.insetScale)
    readonly property real paddingBottom: Math.round(4 * root.insetScale)
    readonly property bool hasMaster: root.row.master === true
    // SettingsRest rule 3: a group whose one action governs the whole list carries it here instead.
    readonly property bool hasAction: (root.row.action || "") !== ""

    implicitHeight: label.y + Math.max(label.height, root.hasMaster || root.hasAction ? box.implicitHeight : 0) + root.paddingBottom

    Text {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing.rowPaddingX
        y: root.gap + (root.first ? 0 : Theme.spacing.hairline) + root.paddingTop
        height: Theme.font.caption * 1.6 + topPadding
        topPadding: Math.ceil(font.pixelSize * 0.15)
        verticalAlignment: Text.AlignVCenter
        text: root.row.label || ""
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        font.bold: true
        // The canvas sets every group eyebrow in small caps, the same treatment the rail's own headings take.
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.font.caption * 0.14
        textFormat: Text.PlainText
    }

    Row {
        visible: root.hasAction
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.rowPaddingX
        anchors.verticalCenter: label.verticalCenter
        spacing: Theme.spacing.gap - Theme.spacing.hairline

        Flea.Glyph {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.font.caption
            height: width
            name: "plus"
            color: Theme.color.foreground
        }

        Text {
            height: box.implicitHeight
            verticalAlignment: Text.AlignVCenter
            text: root.row.value || ""
            color: Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
        }
    }

    Row {
        visible: root.hasMaster
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.rowPaddingX
        anchors.verticalCenter: label.verticalCenter
        spacing: Theme.spacing.gap

        Text {
            height: box.implicitHeight
            verticalAlignment: Text.AlignVCenter
            text: root.row.value || ""
            color: Theme.color.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            font.letterSpacing: Theme.font.caption * 0.14
            textFormat: Text.PlainText
        }

        // The tri-state the group reads: every id on is a tick, some on a bar, none an empty box.
        Flea.CheckBox {
            id: box
            value: root.row.state === "all" ? "on" : (root.row.state === "some" ? "some" : "off")
        }
    }
}
