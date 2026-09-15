import QtQuick
import qs.Commons
import "Run.js" as Run

// The transfer surface the shelf already has: the pointer's cancellation control and the figures,
// off the same 250 ms sample the pane's own card reads. No Flea window need be open, because the
// transfer runs in the backend the action already called.
Item {
  id: root

  property var run: Run.idle()
  property color foreground: Color.popups.text
  property color muted: Qt.darker(foreground, 1.55)
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real pad: Style.spacing.rowPaddingX

  signal cancelRequested()

  readonly property real gap: Style.space(9)
  readonly property real barHeight: Style.space(5)
  readonly property real buttonHeight: Style.space(24)

  visible: root.run.running
  implicitHeight: visible ? column.implicitHeight + 2 * root.gap : 0

  Column {
    id: column
    x: root.pad
    y: root.gap
    width: parent.width - 2 * root.pad
    spacing: Style.space(5)

    Text {
      text: Run.runText(root.run)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      textFormat: Text.PlainText
    }

    Text {
      text: root.run.name
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
      width: parent.width
      textFormat: Text.PlainText
    }

    // The bar is the only place the accent is a fill here, and it is the figure itself.
    Rectangle {
      width: parent.width
      height: root.barHeight
      color: Qt.rgba(root.muted.r, root.muted.g, root.muted.b, 0.35)

      Rectangle {
        width: parent.width * Run.runFraction(root.run)
        height: parent.height
        color: root.accent
      }
    }

    Item {
      width: parent.width
      height: root.buttonHeight

      Rectangle {
        anchors.right: parent.right
        height: parent.height
        width: cancel.implicitWidth + 2 * Style.space(11)
        color: "transparent"
        border.width: 1
        border.color: cancelHover.hovered ? root.foreground : root.muted

        Text {
          id: cancel
          anchors.centerIn: parent
          text: "× Cancel"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }

        HoverHandler { id: cancelHover }
        TapHandler { onSingleTapped: root.cancelRequested() }
      }
    }
  }
}
