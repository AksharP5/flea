import QtQuick
import qs.Commons

// Tailscale's own mark, reproduced from the official artwork the way Flea's ui/TailscaleMark.qml
// reproduces it: Send is Taildrop, and a brand row keeps the brand's mark rather than a cut glyph.
// The shelf carries its own copy because it ships as its own repository at release.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: "transparent"

  // The official file's own box and geometry: circles of radius 18 at 30.5, 84.5 and 138.5.
  readonly property real grid: 169
  readonly property real dotRadius: 18
  readonly property var centres: [30.5, 84.5, 138.5]
  // The official draws the middle row plus the bottom centre solid and the rest at 0.4.
  readonly property real mutedOpacity: 0.4
  readonly property real unit: root.iconSize / root.grid

  implicitWidth: root.iconSize
  implicitHeight: root.iconSize

  Repeater {
    model: 9

    delegate: Rectangle {
      required property int index
      readonly property int row: Math.floor(index / 3)
      readonly property int col: index % 3
      // Row 1 is the middle row, and column 1 of row 2 is the bottom centre.
      readonly property bool solid: row === 1 || (row === 2 && col === 1)

      width: 2 * root.dotRadius * root.unit
      height: width
      radius: width / 2
      x: root.centres[col] * root.unit - width / 2
      y: root.centres[row] * root.unit - height / 2
      color: root.color
      opacity: solid ? 1.0 : root.mutedOpacity
    }
  }
}
