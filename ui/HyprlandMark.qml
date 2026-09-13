import QtQuick
import QtQuick.Shapes
import qs.Commons

// The Hyprland droplet, reproduced rather than recut, the same ruling that brought TailscaleMark and
// DropboxMark back: a brand row carries the brand's own mark and never a generic glyph. Outside the
// cut and outside Glyph.qml, where FleaMark sits.
Item {
    id: root

    // The type scale, not the slot, and clamped so a reproduction can never out-size the cut glyph
    // beside it. A smaller caller slot still wins, the way Glyph's own min() lets it.
    property real iconSize: Theme.markSize
    property color color: "transparent"

    // The artwork is drawn on the same 24 unit grid every mark in this tree uses.
    readonly property real grid: 24
    readonly property real drawn: Math.min(Theme.markSize, root.iconSize)

    implicitWidth: root.drawn
    implicitHeight: root.drawn
    width: root.drawn
    height: root.drawn

    Shape {
        width: root.grid
        height: root.grid
        // Scale's origin defaults to (0,0), so the grid box is scaled from the top left into the slot.
        transform: Scale { xScale: root.drawn / root.grid; yScale: root.drawn / root.grid }
        preferredRendererType: Shape.CurveRenderer

        // The hollow centre is the even-odd rule over one subpath pair, which is how the artwork cuts it.
        ShapePath {
            fillColor: root.color
            fillRule: ShapePath.OddEvenFill
            strokeColor: "transparent"
            strokeWidth: 0

            PathSvg {
                path: "M12 2.2c4 5.4 6.9 9.4 6.9 12.6a6.9 6.9 0 1 1-13.8 0c0-3.2 2.9-7.2 6.9-12.6Z"
                    + "M12 8.1c-2.4 3.3-4.1 5.8-4.1 7.6a4.1 4.1 0 0 0 8.2 0c0-1.8-1.7-4.3-4.1-7.6Z"
            }
        }
    }
}
