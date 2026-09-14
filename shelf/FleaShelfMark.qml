import QtQuick
import QtQuick.Shapes

// Flea's own mark, reproduced from ui/FleaMark.qml: the same 24 unit grid, the same path and the
// same brand stroke. BarMark rule 1: nothing is ever added to it, so this is the whole widget.
Item {
    id: root

    property color color: "white"
    readonly property real grid: 24
    readonly property real markScale: Math.min(root.width, root.height) / root.grid
    // A brand mark, not a cut glyph: the spiral keeps the brand's 2 rather than the shell's stroke.
    readonly property real brandStroke: 2

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
            strokeWidth: root.brandStroke
            capStyle: ShapePath.SquareCap
            joinStyle: ShapePath.MiterJoin
            PathSvg { path: "M21 21H3V3h18v14H7V7h10v6h-6" }
        }
    }
}
