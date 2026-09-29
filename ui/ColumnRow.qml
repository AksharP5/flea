import QtQuick
import qs.Commons
import "." as Flea
import "js/Drag.js" as DragOps
import "js/Icons.js" as Icons
import "js/Format.js" as Format
import "js/Names.js" as Names

// One row of a Miller column: a mark, a name, and the chevron a chosen directory carries. Simpler
// than a list row on purpose, because a column has no size, date, mode or kind to draw.
Item {
    id: root

    // {n, d, i} as a peek answers them, or a listing row, which carries the same three fields.
    property var row: null
    // The pane's thumbnail path for this row, empty for a peek's row: only the listing's own column asks for any.
    property string thumb: ""
    // A path is not a thumbnail: a cache file evicted between the answer and the decode leaves the mark to the glyph.
    readonly property bool thumbDrawn: root.thumb.length > 0 && thumbImage.status !== Image.Error
    readonly property alias iconStatus: thumbImage.status
    readonly property Item thumbItem: thumbImage
    // The row this column's own cursor is on. Only the active column paints it in the accent.
    property bool cursor: false
    // A member of the pane's selection, which only the column drawing the pane's own listing has.
    property bool selected: false
    // The same row in an ancestor column: the cursor trail, lifted like a hover rather than accented.
    property bool lifted: false
    // The active column draws a size; a peek column cannot ask for one and leaves this false.
    property bool showSize: false
    // The recursive size of a directory row, resolved by index the way the list resolves it.
    property var dirSize: null
    // An ancestor column that is not on the trail reads back, so its text drops to muted.
    property bool dim: false
    property bool hovered: false
    property bool dropTarget: false
    property bool dropCopying: false
    // The area derives it per visible row, so an empty clipboard costs nothing.
    property string clipMark: ""
    // A cut row dims to the ClipMarks board's own opacity, content only.
    readonly property bool clipCut: root.clipMark === "scissors"
    // One dim for the content below, so one ternary serves the mark, the name and the size.
    readonly property real dimOpacity: root.clipCut ? Theme.disabledOpacity : 1
    // The mark's own size: 12 px in the muted role, 9 px after the name, per the board.
    readonly property int clipPx: 12
    // The column hands one budget for every row, with ElideMiddle as the backstop.
    property int nameBudget: -1

    // Truthiness, like the two readers below: ui/ColumnPane.qml hands this rows[index] raw, so a
    // listing that shrank leaves a surviving delegate holding undefined, which is not null.
    readonly property bool isDir: !!root.row && root.row.d === true
    readonly property color ink: root.cursor ? Theme.color.accent
                                : root.dim ? Theme.color.muted
                                : Theme.color.foreground

    // One height for every row: ui/ColumnPane.qml draws the editor over the row rather than inside
    // it, so no row grows and the overlay's own y is plain arithmetic on this height.
    implicitHeight: Theme.fileRowHeight

    Rectangle {
        anchors.fill: parent
        // Match the active listing's cursor and marked-selection roles.
        color: root.cursor ? Style.selectedAccentFill
             : root.selected ? Style.selectionFill
             : root.lifted ? Style.hoverFill
             : root.hovered ? Style.hoverFill
             : "transparent"
    }

    Rectangle {
        anchors.fill: parent
        visible: root.dropTarget
        color: Util.alpha(Theme.color.accent, Style.hoverFillAlpha)
        border.width: Theme.spacing.hairline
        border.color: Theme.color.accent
    }

    Rectangle {
        visible: root.cursor
        width: Theme.spacing.hairline * 2
        height: parent.height
        color: Theme.color.accent
    }

    // One content carries the dim, so one opacity serves the mark, the name and the size.
    Item {
        id: content
        anchors.fill: parent
        opacity: root.dimOpacity

        Item {
            id: markSlot
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacing.rowPaddingX
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSize
            height: Theme.iconSize

            // Sized on purpose, the same decode arm as ui/Row.qml: the cache PNG is capped at the icon's own size.
            Image {
                id: thumbImage
                anchors.fill: parent
                visible: root.thumbDrawn
                sourceSize.width: Theme.iconSize
                sourceSize.height: Theme.iconSize
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                // No cache by URL: a regenerated thumbnail keeps its path, and a cached decode would keep the old pixels.
                cache: false
                source: root.thumb.length > 0 ? Format.fileUri(root.thumb) : ""
            }

            Flea.Glyph {
                anchors.fill: parent
                visible: !root.thumbDrawn
                name: root.row ? Icons.glyphForRow(root.row.i, root.row.p) : "file"
                color: root.cursor ? Theme.color.accent : Theme.color.muted
            }
        }

        // corner: arbitrary filename text draws PlainText and elides in the middle per Names040.
        Text {
            id: nameText
            anchors.left: markSlot.right
            anchors.leftMargin: Theme.spacing.gap
            anchors.right: sizeCell.left
            anchors.rightMargin: (root.showSize ? Theme.spacing.gap : 0) + (root.clipMark.length > 0 ? Theme.spacing.gap + root.clipPx : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: root.row && root.nameBudget >= 0 ? Names.middleElide(root.row.n, Math.max(0, root.nameBudget - (root.clipMark.length > 0 ? Math.ceil((Theme.spacing.gap + root.clipPx) / Theme.bodyAdvance) : 0))) : (root.row ? root.row.n : "")
            color: root.ink
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
        }

        // Only the active column carries a number (ColumnsTabs board rule 3); the size holds its right edge off the parent by the chevron width.
        Text {
            id: sizeCell
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacing.rowPaddingX + chevronSlot.width + (root.showSize ? Theme.spacing.gap : 0)
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showSize && !root.dropTarget
            width: visible ? Theme.column.size : 0
            text: root.showSize && root.row ? root.sizeText() : ""
            color: root.ink
            horizontalAlignment: Text.AlignRight
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
    }

    // Built only on a clipboard row, so no row at rest binds to name geometry (tests/columnscost.qml).
    Loader {
        id: clipLoader
        active: root.clipMark.length > 0
        width: root.clipPx
        height: root.clipPx
        x: root.clipMark.length > 0 ? nameText.x + Math.min(nameText.implicitWidth, nameText.width) + Theme.spacing.gap : 0
        anchors.verticalCenter: parent.verticalCenter
        // The board's own nudge: the mark sits one pixel above the text centre line.
        anchors.verticalCenterOffset: -1
        sourceComponent: Flea.Glyph {
            width: root.clipPx
            height: root.clipPx
            name: root.clipMark
            color: Theme.color.muted
        }
    }

    // The list's own cell text, so a size reads the same wherever it is drawn.
    function sizeText() {
        if (Format.isSymlink(root.row.p)) return "link"
        if (!root.row.d) return Format.size(root.row.s)
        if (!root.dirSize) return "·"
        return (root.dirSize.partial ? ">" : "") + Format.size(root.dirSize.bytes)
    }

    // Only a chosen directory carries it: it says the column to the right is showing what is inside.
    Item {
        id: chevronSlot
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        width: root.dropTarget ? dropLabel.implicitWidth : root.showChevron ? Theme.font.caption : 0
        height: root.dropTarget ? dropLabel.implicitHeight : Theme.font.caption

        Flea.Glyph {
            anchors.fill: parent
            visible: root.showChevron && !root.dropTarget
            name: "chevron-right"
            color: root.cursor ? Theme.color.accent : Theme.color.muted
        }

        Text {
            id: dropLabel
            anchors.centerIn: parent
            visible: root.dropTarget
            text: DragOps.label(root.dropCopying)
            color: Theme.color.accent
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
        }
    }

    readonly property bool showChevron: root.isDir && (root.cursor || root.lifted)

    HoverHandler {
        id: hover
        onHoveredChanged: root.hovered = hovered
    }

    // Test seam as functions, so no row at rest binds to name geometry (tests/columnscost.qml).
    function clipX() { return clipLoader.x }
    function clipExpectedX() { return nameText.x + Math.min(nameText.implicitWidth, nameText.width) + Theme.spacing.gap }
    function displayText() { return nameText.text }
    function nameItem() { return nameText }
    // Row-relative boxes for the geometry suite, so the probe reads the drawn layout and not the source.
    function markRight() { return content.x + markSlot.x + markSlot.width }
    function nameGeom() { return [content.x + nameText.x, nameText.width] }
    function sizeGeom() { return [content.x + sizeCell.x, sizeCell.width] }
    function chevronGeom() { return [chevronSlot.x, chevronSlot.width] }
}
