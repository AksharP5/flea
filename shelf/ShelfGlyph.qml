import QtQuick
import QtQuick.Shapes

// One mark on the Omarchy cut, drawn from a 24 unit path the way Flea's own ui/Glyph.qml draws it:
// 2px stroke, square caps, mitre joins, no fill. The shelf carries its own copy because it ships as
// its own repository at release and a plugin cannot import the app's components.
Item {
  id: root

  property string path: ""
  property color color: "white"
  property real stroke: 2
  readonly property real grid: 24
  readonly property real markScale: Math.min(root.width, root.height) / root.grid

  Shape {
    width: root.grid
    height: root.grid
    x: (root.width - root.grid * root.markScale) / 2
    y: (root.height - root.grid * root.markScale) / 2
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { xScale: root.markScale; yScale: root.markScale }

    ShapePath {
      strokeColor: root.color
      fillColor: "transparent"
      strokeWidth: root.stroke
      capStyle: ShapePath.SquareCap
      joinStyle: ShapePath.MiterJoin
      PathSvg { path: root.path }
    }
  }
}
