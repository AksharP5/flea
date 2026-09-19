import QtQuick
import QtQuick.Shapes
import qs.Commons

// Flea's own mark, reproduced from ui/FleaMark.qml: the same 24 unit grid, the same path and the
// same brand stroke. BarMark rule 1: nothing is ever added to it, so this is the whole widget.
Item {
  id: root

  property color color: "white"
  // The size token every OEM bar mark takes, never a literal and never iconSmall.
  property real iconSize: Style.font.icon
  // Directive 53a: parity is ink against ink, not box against box. Measured in one bar shot at
  // GM's text size, the Tailscale mark's ink is 13 px against a token of 16, and this box is the
  // ink itself, so centring the box centres the ink the way the OEM mark's lands.
  readonly property real opticalScale: 0.8125
  implicitWidth: Math.round(root.iconSize * root.opticalScale)
  implicitHeight: root.implicitWidth

  readonly property real grid: 24
  // A brand mark, not a cut glyph: the spiral keeps the brand's 2 rather than the shell's stroke.
  readonly property real brandStroke: 2
  // The ink inside that grid: the path spans 3 to 21 and the stroke adds half its width each side.
  readonly property real inkOrigin: 2
  readonly property real inkExtent: 20
  readonly property real markScale: Math.min(root.width, root.height) / root.inkExtent

  Shape {
    width: root.grid
    height: root.grid
    preferredRendererType: Shape.CurveRenderer
    transform: [
      Scale { xScale: root.markScale; yScale: root.markScale },
      Translate { x: -root.inkOrigin * root.markScale; y: -root.inkOrigin * root.markScale }
    ]

    ShapePath {
      strokeColor: root.color
      fillColor: "transparent"
      strokeWidth: root.brandStroke
      capStyle: ShapePath.SquareCap
      joinStyle: ShapePath.MiterJoin
      PathSvg { path: "M21 21H3V3h18v14H7V7h10v6h-6" }
    }
  }
}
