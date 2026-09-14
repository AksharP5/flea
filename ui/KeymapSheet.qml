import QtQuick
import qs.Commons
import "." as Flea
import "js/Keymap.js" as Keymap

// The keymap sheet ? opens, drawn as the Keys panel on Operations.dc.html draws it. Every row comes
// from keys.toml through Keymap.SHEET, so a key that loses its binding cannot go on being advertised.
Item {
    id: root

    property bool opened: false
    property Item focusHolder: null
    readonly property var sheet: Keymap.sheetFor(ViewState.keysPreset, "gui", root.focusHolder ? root.focusHolder.dualMode : false)
    // KeymapSheet rule 1: a binding gets a group in keys.toml and the sheet reads it, in the order
    // that table lists them, with the heading its own key carries under a raised first letter.
    readonly property var groups: {
        var out = []
        for (var name in Keymap.SHEET_GROUPS) {
            var order = Keymap.SHEET_GROUPS[name], claimed = []
            // The group's own list is the order the board draws, cursor keys before the chords;
            // the generated sheet is in keys.toml's file order, which puts every preset row first.
            for (var i = 0; i < order.length; i++) {
                var row = root.sheet.filter(function (candidate) { return candidate.action === order[i] })
                if (row.length > 0)
                    claimed.push(row[0])
            }
            if (claimed.length > 0)
                out.push({ title: name.charAt(0).toUpperCase() + name.slice(1), rows: claimed })
        }
        return out
    }

    // The canvas drew this panel at 300, the convert popup's width, beside four illustrative rows.
    // The real sheet is sixty rows whose chords run to eighteen characters: at 300 a cap took the
    // whole half-cell, the wording beside it elided to a single ellipsis, and the two columns
    // overprinted each other. 480 is the Open with card's own anchor and leaves both room.
    readonly property int sheetWidth: 480
    readonly property int clampMargin: 8
    // var, not Item: BorderSurface is a qs.Ui type qmllint cannot resolve, and Item would read as incompatible.
    readonly property var cardItem: card
    // A cap is sized from the type scale, never from the text inside it, so every cap is one height.
    readonly property int capSize: Theme.markSize
    // The board's own rhythm, measured off its drawing at GM's text size: a 32px row around the 19px
    // cap, which is the row padding above and below it, and the wording a gap clear of the cap's box.
    readonly property int rowPitch: root.capSize + 2 * Theme.spacing.rowPaddingY
    readonly property int capGap: Theme.spacing.gap

    // One cap column for the whole sheet, measured off the widest chord this preset spells. Sizing
    // each cap to its own text left every wording starting on a different x, and a wide chord took
    // the cell whole and drew across the column beside it.
    readonly property string widestCap: {
        var out = ""
        for (var i = 0; i < root.sheet.length; i++)
            if (root.sheet[i].keys.length > out.length) out = root.sheet[i].keys
        return out
    }
    readonly property int capWidth: Math.max(root.capSize, Math.ceil(capMetrics.width) + root.capGap)
    // Board rule 4: no label is ever cut, so the floor is the widest wording this preset really
    // draws. A window that cannot give two cells that much takes one column and scrolls instead.
    readonly property string widestLabel: {
        var out = ""
        for (var i = 0; i < root.sheet.length; i++)
            if (root.sheet[i].label.length > out.length) out = root.sheet[i].label
        return out
    }
    readonly property int cellFloor: root.capWidth + root.capGap + Math.ceil(labelFloor.width)
    // Two columns is what the canvas draws, and what keeps the whole map on one panel where it fits.
    readonly property int columns: body.width >= 2 * root.cellFloor + Theme.spacing.rowPaddingX ? 2 : 1

    TextMetrics {
        id: capMetrics
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        text: root.widestCap
    }

    TextMetrics {
        id: labelFloor
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        text: root.widestLabel
    }
    readonly property real groundOpacity: 0.5

    anchors.fill: parent
    visible: root.opened
    z: 2

    function open(holder) {
        root.focusHolder = holder
        root.opened = true
        keys.forceActiveFocus()
    }

    function close() {
        if (!root.opened)
            return
        root.opened = false
        if (root.focusHolder)
            root.focusHolder.forceActiveFocus()
    }

    // What a test reads instead of running OCR over the panel, the same idiom ui/Pane.qml's
    // menuEntries() uses: one row per line, the cap and the wording it is drawn beside.
    function rows() {
        var out = []
        for (var g = 0; g < root.groups.length; g++) {
            out.push(root.groups[g].title)
            for (var i = 0; i < root.groups[g].rows.length; i++)
                out.push(root.groups[g].rows[i].keys + " " + root.groups[g].rows[i].label)
        }
        return out.join("\n")
    }

    // A dimmed ground, and a click on it closes, the same shape ui/ConvertDialog.qml uses.
    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
        opacity: root.groundOpacity

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            onClicked: root.close()
            onWheel: function (wheel) { wheel.accepted = true }
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.max(0, Math.min(Theme.space(root.sheetWidth) * Theme.dialogWidthRatio, root.width - 2 * root.clampMargin))
        // Clamped to the window; the body scrolls whatever the clamp cut, see ui/CardScroll.qml.
        height: Math.min(body.wanted + 2 * Theme.spacing.rowPaddingX, root.height - 2 * root.clampMargin)
        color: Theme.color.surface
        border.width: Theme.spacing.hairline
        border.color: Theme.color.muted
        // Mirrors hyprland decoration:rounding, same as ui/ConvertDialog.qml; 0 on a stock box stays square.
        radius: Style.cornerRadius

        Flea.CardScroll {
            id: body
            anchors.fill: parent
            anchors.margins: Theme.spacing.rowPaddingX

        Column {
            width: parent.width
            spacing: Theme.spacing.gap

            // Rule 2: the one clause a reader needs, in the corner every other surface puts it in.
            Item {
                width: parent.width
                height: title.implicitHeight

                Text {
                    id: title
                    anchors.left: parent.left
                    text: "Keys"
                    color: Theme.color.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.bodySmall
                    textFormat: Text.PlainText
                }

                Text {
                    anchors.right: parent.right
                    anchors.baseline: title.baseline
                    text: "esc closes"
                    color: Theme.color.muted
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.caption
                    textFormat: Text.PlainText
                }
            }

            Grid {
                columns: root.columns
                // The heading above each block is the air between two of them; a row gap here would
                // be a second one, and the board draws the four blocks on one rhythm.
                rowSpacing: 0
                columnSpacing: Theme.spacing.rowPaddingX

                Repeater {
                    model: root.groups

                    // Equal halves, so the second column starts on one x the whole way down.
                    delegate: Column {
                        id: block
                        required property var modelData
                        width: (body.width - (root.columns - 1) * Theme.spacing.rowPaddingX) / root.columns

                        // The heading carries its own air, above and below, rather than a spacing
                        // every row would take as well: a row's pitch is inside its own box.
                        Text {
                            text: block.modelData.title
                            topPadding: Theme.spacing.gap
                            bottomPadding: Theme.spacing.hairline * 4
                            color: Theme.color.muted
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.caption
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: Theme.spacing.hairline
                            textFormat: Text.PlainText
                        }

                        Repeater {
                            model: block.modelData.rows

                            delegate: Item {
                                id: entry
                                required property var modelData
                                width: block.width
                                height: root.rowPitch
                                // Nothing this cell draws may reach the cell beside it, whatever it holds.
                                clip: true

                                Rectangle {
                                    id: capBox
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    // The sheet's own cap column, never this row's text: see root.capWidth.
                                    width: root.capWidth
                                    height: root.capSize
                                    color: "transparent"
                                    border.width: Theme.spacing.hairline
                                    border.color: Theme.color.muted

                                    Text {
                                        id: cap
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacing.hairline
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: entry.modelData.keys
                                        color: Theme.color.foreground
                                        font.family: Theme.font.family
                                        font.pixelSize: Theme.font.caption
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    anchors.left: capBox.right
                                    anchors.leftMargin: root.capGap
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: entry.modelData.label
                                    // The wording is the sheet's own running text, so it takes the
                                    // foreground the board draws it in; muted is for the headings.
                                    color: Theme.color.foreground
                                    font.family: Theme.font.family
                                    font.pixelSize: Theme.font.caption
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        // Any key closes it: the sheet is a reference and not a mode, and ? is how it comes back.
        Keys.onPressed: function (event) {
            root.close()
            event.accepted = true
        }
    }
}
