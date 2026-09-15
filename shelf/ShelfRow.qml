import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One row of the card, Main board rules 3, 4 and 6: a separator and a section header when the row
// opens a group, then the row itself in the shape panels/dropbox gives its FileRow, a CursorSurface
// with the mark slot on the centre line, the name, the size and one trailing control.
Column {
  id: row
  // The card this row belongs to: its palette, its cursor, its chosen set and its signals.
  required property var card
  required property int index
  required property var modelData
  width: parent ? parent.width : 0
  // A group opens with the gap the OEM panels leave around a section header, then its rows.
  spacing: Style.space(10)
  readonly property bool picked: row.card.chosen[row.modelData.path] === true
  readonly property string caption: Model.captionFor(row.card.rows, row.index, row.card.kinds)
  // Rule 4: a thumbnail path is not a thumbnail, because the cache file can be evicted
  // between the answer and the decode; a row whose Image failed is marked by its kind.
  readonly property string thumb: Model.thumbFor(row.card.thumbs, row.modelData)
  readonly property bool thumbDrawn: row.thumb.length > 0 && shot.status === Image.Ready

  // Rule 2: a separator between groups, so the first group on the card has nothing above it.
  PanelSeparator {
    visible: row.caption.length > 0 && row.index > 0
    width: parent.width
    foreground: row.card.foreground
  }

  PanelSectionHeader {
    visible: row.caption.length > 0
    width: parent.width
    text: row.caption
    foreground: row.card.foreground
    fontFamily: row.card.fontFamily
  }

  CursorSurface {
    width: parent.width
    // The OEM contract: the pointer moves the cursor and the paint comes from the cursor,
    // so one row is lit at a time whether the hand is on the keyboard or the mouse.
    hasCursor: row.card.cursorIndex === row.index
    current: row.picked
    foreground: row.card.foreground
    accent: row.card.accent
    implicitHeight: Math.max(name.implicitHeight, trailing.implicitHeight) + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton
      // Rule 11: a row is the handle the pile is carried out by. The token is minted on the
      // press because a platform drag cannot be started from inside its own loop, and the
      // drag itself waits for the platform's drag distance so a plain click stays a click.
      property point pressAt: Qt.point(0, 0)
      // A ctrl or shift press is a marking gesture, so it mints nothing and carries nothing.
      property bool marking: false
      onEntered: {
        row.card.cursorIndex = row.index
        row.card.hoveredIndex = row.index
      }
      onExited: if (row.card.hoveredIndex === row.index) row.card.hoveredIndex = -1
      onPressed: function (mouse) {
        rowMouse.pressAt = Qt.point(mouse.x, mouse.y)
        rowMouse.marking = (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0
        if (rowMouse.marking) {
          return
        }
        row.card.carriedPaths = Model.carryPaths(row.card.chosen, row.card.rows, row.index)
        row.card.liftRequested(false)
      }
      onPositionChanged: function (mouse) {
        if (!rowMouse.pressed || rowMouse.marking) {
          return
        }
        var dx = mouse.x - rowMouse.pressAt.x
        var dy = mouse.y - rowMouse.pressAt.y
        if (Math.abs(dx) + Math.abs(dy) >= Qt.styleHints.startDragDistance) {
          row.card.wantCarry()
        }
      }
      onReleased: row.card.dropCarry()
      onCanceled: row.card.dropCarry()
      // Rule 3, the contract Flea's own listing has: ctrl toggles this row, shift takes the range
      // from the cursor, a plain click moves the cursor and clears the marks, and a capture row
      // keeps the click that puts it on the shelf.
      onClicked: function (mouse) {
        if ((mouse.modifiers & Qt.ControlModifier) !== 0) {
          row.card.markRow(row.index)
        } else if ((mouse.modifiers & Qt.ShiftModifier) !== 0) {
          row.card.markRange(row.index)
        } else {
          row.card.clearMarks(row.index)
          if (row.modelData.section === Model.CAPTURE) {
            row.card.captureAddRequested(row.index)
          }
        }
      }

      // Rule 9: the row's own full path is its tooltip, so the card never spends a line on it.
      PanelToolTip {
        visible: parent.containsMouse
        text: row.modelData.path
        fontFamily: row.card.fontFamily
      }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.spacing.labelGap

      // Rule 3 and rule 4: the mark slot on the row's centre line, holding the thumbnail
      // when the file has one, the kind mark when it does not, and the check while a subset
      // is being chosen: a row cannot say both what it is and whether it is taken.
      Item {
        id: slot
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: row.card.markSize
        implicitHeight: row.card.markSize
        // Rule 3: the box is the pointer's way to mark, so it is there whenever the row is under the
        // pointer and whenever anything is marked; otherwise the slot says what kind the row is.
        readonly property bool choosing: row.card.chosenCount > 0 || row.card.hoveredIndex === row.index

        Image {
          id: shot
          anchors.fill: parent
          visible: !slot.choosing && row.thumbDrawn
          source: row.thumb.length > 0 ? "file://" + row.thumb : ""
          // Sized on purpose, the way ui/Row.qml sizes it: the decode is capped to the slot
          // it is drawn in rather than the cache file's own 256.
          sourceSize.width: row.card.markSize * Screen.devicePixelRatio
          sourceSize.height: row.card.markSize * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          // A synchronous decode would land on the bar's own frame.
          asynchronous: true
        }

        ShelfGlyph {
          anchors.fill: parent
          visible: !slot.choosing && !row.thumbDrawn
          path: Model.glyphFor(row.modelData)
          color: row.card.foreground
        }

        ShelfCheck {
          anchors.centerIn: parent
          visible: slot.choosing
          on: row.picked
          foreground: row.card.foreground

          // A click on the box marks the row and nothing else: it never moves the cursor.
          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: row.card.markRow(row.index)
          }
        }
      }

      Text {
        id: name
        Layout.fillWidth: true
        text: row.modelData.name
        color: row.card.foreground
        font.family: row.card.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
        textFormat: Text.PlainText
      }

      // Rule 3: the size is right-aligned, and the family is Flea's own monospace, so its
      // figures are tabular without asking for a font feature.
      Text {
        Layout.alignment: Qt.AlignVCenter
        text: Model.sizeText(row.modelData)
        color: row.card.muted
        font.family: row.card.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
      }

      // Rules 3 and 6: one button shape at row size, x on a pile row, the pin on a pinned
      // one, and an empty slot of the same width on a capture so every size lines up.
      ShelfActionButton {
        id: trailing
        Layout.alignment: Qt.AlignVCenter
        enabled: row.modelData.section !== Model.CAPTURE
        opacity: enabled ? 1 : 0
        path: row.modelData.pinned ? Model.ACTION_GLYPHS.pin : Model.ACTION_GLYPHS.remove
        tooltipText: row.modelData.pinned ? "Unpin" : "Take off the shelf"
        foreground: row.card.foreground
        onClicked: row.modelData.pinned ? row.card.pinRequested(row.index)
                                        : row.card.removeRequested(row.index)
      }
    }
  }
}
