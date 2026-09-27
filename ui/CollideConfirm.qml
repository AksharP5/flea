import QtQuick
import qs.Commons
import "." as Flea
import "js/Collide.js" as Collide
import "js/Icons.js" as Icons

// One choice for every name a paste or a drop would land on, on ui/TrashConfirm.qml's card, keys and look.
FocusScope {
    id: root
    anchors.fill: parent
    visible: opened
    property bool opened: false
    property string titleText: ""
    property var names: []
    property string moreText: ""
    property string focusName: Collide.START
    readonly property string explainText: Collide.EXPLAIN
    readonly property real referenceScale: Theme.font.bodySmall / 13
    readonly property real cardPadding: Math.round(16 * referenceScale)
    readonly property real cardBottomPadding: Theme.spacing.rowPaddingX
    // GM's ruling: 368 design pixels hold the four labels at base size, and a larger stop grows the card rather than wrap one.
    readonly property real contentWidth: Math.max(Math.round(368 * referenceScale * Theme.dialogWidthRatio), buttons.implicitWidth)
    signal chosen(string choice)
    readonly property var cardItem: card
    readonly property bool titleTruncated: title.truncated
    readonly property bool buttonsFit: buttons.width <= body.width
    readonly property int explainLines: explain.lineCount
    function buttonItem(name) { return ({cancel: cancelButton, skip: skipButton, keep: keepButton, replace: replaceButton})[name] || null }
    function open(heading, list, more) {
        titleText = heading
        names = list
        moreText = more
        focusName = Collide.START
        body.contentY = 0
        opened = true
        forceActiveFocus()
    }
    function choose(choice) {
        opened = false
        chosen(choice)
    }
    // A press lands on its own button first, so the accent never shows one choice while another is taken.
    function press(choice) {
        focusName = choice
        choose(choice)
    }
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) root.choose("cancel")
        else if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) { event.accepted = true; return }
        else if (Collide.activates(event.key)) root.choose(root.focusName)
        else root.focusName = Collide.moved(root.focusName, event.key)
        if (root.opened) body.reveal(root.buttonItem(root.focusName))
        event.accepted = true
    }
    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
        opacity: 0.5
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.choose("cancel")
            onWheel: function(wheel) { wheel.accepted = true }
        }
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.max(0, Math.min(root.contentWidth + 2 * root.cardPadding + 2 * Theme.spacing.hairline, root.width - 2 * Theme.spacing.gap))
        height: Math.max(0, Math.min(body.wanted + root.cardPadding + root.cardBottomPadding + 2 * Theme.spacing.hairline, root.height - 2 * Theme.spacing.gap))
        color: Theme.color.surface
        border.color: Theme.color.muted
        border.width: Theme.spacing.hairline
        radius: Style.cornerRadius
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onWheel: function(wheel) { wheel.accepted = true }
        }
        Flea.CardScroll {
            id: body
            anchors.fill: parent
            anchors.leftMargin: root.cardPadding + Theme.spacing.hairline
            anchors.rightMargin: root.cardPadding + Theme.spacing.hairline
            anchors.topMargin: root.cardPadding + Theme.spacing.hairline
            anchors.bottomMargin: root.cardBottomPadding + Theme.spacing.hairline
            Column {
                width: body.width
                spacing: Theme.spacing.gap
                Text {
                    id: title
                    width: parent.width
                    text: root.titleText
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.color.foreground
                    font { family: Theme.font.family; pixelSize: Theme.font.body; bold: true }
                }
                Column {
                    width: parent.width
                    Repeater {
                        model: root.names
                        delegate: Row {
                            id: nameRow
                            required property var modelData
                            width: parent.width
                            height: Theme.fileRowHeight
                            spacing: Theme.spacing.gap
                            Flea.Glyph { width: Theme.markSize; height: parent.height; name: nameRow.modelData.d ? "folder" : Icons.glyphFor(nameRow.modelData.i); color: Theme.color.foreground }
                            Text { width: Math.max(0, parent.width - Theme.markSize - parent.spacing); anchors.verticalCenter: parent.verticalCenter; text: nameRow.modelData.n; textFormat: Text.PlainText; elide: Text.ElideRight; color: Theme.color.foreground; font { family: Theme.font.family; pixelSize: Theme.font.body } }
                        }
                    }
                    Text {
                        width: parent.width
                        visible: root.moreText.length > 0
                        text: root.moreText
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.color.foreground
                        font { family: Theme.font.family; pixelSize: Theme.font.caption }
                    }
                }
                Text {
                    id: explain
                    width: parent.width
                    text: root.explainText
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.color.foreground
                    font { family: Theme.font.family; pixelSize: Theme.font.caption }
                }
                Row {
                    id: buttons
                    anchors.right: parent.right
                    spacing: Theme.spacing.gap
                    Flea.DialogButton { id: cancelButton; label: Collide.LABELS.cancel; focused: root.focusName === "cancel"; onActivated: root.press("cancel") }
                    Flea.DialogButton { id: skipButton; label: Collide.LABELS.skip; focused: root.focusName === "skip"; onActivated: root.press("skip") }
                    Flea.DialogButton { id: keepButton; label: Collide.LABELS.keep; primary: true; focused: root.focusName === "keep"; onActivated: root.press("keep") }
                    Flea.DialogButton { id: replaceButton; label: Collide.LABELS.replace; destructive: true; focused: root.focusName === "replace"; onActivated: root.press("replace") }
                }
            }
        }
    }
}
