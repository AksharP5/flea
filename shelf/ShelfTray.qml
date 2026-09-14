import QtQuick
import qs.Commons
import "Model.js" as Model

// ShelfEmpty rules 2, 4, 5 and 7: the newest captures Omarchy has taken, always on the card. The
// service lists them and this decodes them, capped by sourceSize; a recording draws its own mark and
// decodes nothing, because QtMultimedia costs the bar 20 MB to import and a first frame is not worth
// that. Click adds the capture to the pile, a drag takes it straight out as a copy.
Item {
  id: root

  property var captures: []
  property color foreground: Color.popups.text
  property color muted: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family
  property real pad: Style.spacing.rowPaddingX
  property real stripHeight: 27

  signal addRequested(int index)

  readonly property real gap: Style.space(8)
  readonly property int count: root.captures.length
  readonly property real thumbWidth: root.count > 0
    ? (root.width - 2 * root.pad - (root.count - 1) * root.gap) / root.count
    : 0
  // The board's 112 by 63 thumb, which is this screen's own aspect: these are pictures of it.
  readonly property real thumbHeight: Math.round(root.thumbWidth * 9 / 16)
  readonly property real timeHeight: Math.round(Style.font.caption * 1.6)

  visible: root.count > 0
  // The caption strip, the thumbs, their times, and the board's own breathing space before the footer.
  implicitHeight: root.count > 0 ? root.stripHeight + root.thumbHeight + root.gap + root.timeHeight + root.gap : 0

  Item {
    id: caption
    width: parent.width
    height: root.stripHeight

    Text {
      anchors.verticalCenter: parent.verticalCenter
      x: root.pad
      text: "Recent shots"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.font.caption * 0.14
      textFormat: Text.PlainText
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: root.pad
      text: root.count
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }
  }

  Row {
    anchors.top: caption.bottom
    x: root.pad
    spacing: root.gap

    Repeater {
      model: root.captures

      Column {
        id: cell
        required property int index
        required property var modelData
        spacing: Math.round(root.gap * 0.6)

        Rectangle {
          id: thumb
          width: root.thumbWidth
          height: root.thumbHeight
          color: Qt.darker(Color.popups.background, 1.2)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
          clip: true

          Drag.dragType: Drag.Automatic
          Drag.supportedActions: Qt.CopyAction
          Drag.proposedAction: Qt.CopyAction
          Drag.onDragFinished: thumb.Drag.active = false

          Image {
            anchors.fill: parent
            anchors.margins: 1
            visible: !cell.modelData.recording
            source: cell.modelData.recording ? "" : "file://" + encodeURI(cell.modelData.path)
            // Rule 4's budget: a thumbnail is decoded at the size it is drawn and never full size.
            sourceSize.width: Math.round(root.thumbWidth * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
          }

          ShelfGlyph {
            anchors.centerIn: parent
            visible: cell.modelData.recording
            width: Math.round(root.thumbHeight * 0.5)
            height: width
            path: Model.RECORDING_GLYPH
            color: root.muted
          }

          MouseArea {
            anchors.fill: parent
            property point start
            onPressed: function (mouse) { start = Qt.point(mouse.x, mouse.y) }
            // A click adds and a drag takes it out, so the drag starts only once the pointer has
            // actually travelled: a platform drag begun on the press would eat every click.
            onPositionChanged: function (mouse) {
              if (!pressed || thumb.Drag.active) {
                return
              }
              if (Math.abs(mouse.x - start.x) < Style.space(6) && Math.abs(mouse.y - start.y) < Style.space(6)) {
                return
              }
              thumb.Drag.mimeData = { "text/uri-list": "file://" + encodeURI(cell.modelData.path) + "\r\n" }
              thumb.Drag.active = true
            }
            onClicked: root.addRequested(cell.index)
          }
        }

        Text {
          text: Model.captureTime(cell.modelData.at)
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }
      }
    }
  }
}
