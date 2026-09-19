import QtQuick
import QtQuick.Shapes
import qs.Commons

// The LocalSend mark, reproduced from the official artwork rather than recut, the same ruling that
// brought TailscaleMark and DropboxMark back: a solid disc inside a ring of eight dashes, monochrome
// and palette-tinted, no brand teal. Outside the cut and outside Glyph.qml, where FleaMark sits.
Item {
    id: root

    // The type scale, not the slot, and clamped so a reproduction can never out-size the cut glyph
    // beside it. A smaller caller slot still wins, the way Glyph's own min() lets it.
    property real iconSize: Theme.markSize
    property color color: "transparent"

    // Measured off docs/design/flea-shelf/export/localsend-96.png at alpha 128: the disc ends at
    // 20 px, the dash band runs 31.25 to 36.25 px, and the ink is eight runs of 31 degrees whose
    // centres are 45 degrees apart. The logo's own ink box is 72.5 px of that 96 px file, and this
    // mark fills its slot rather than keeping the file's padding, which is the AdGuard lesson, so
    // every fraction below is of that ink box.
    readonly property real discRadius: 0.276
    readonly property real ringRadius: 0.466
    readonly property real dashStroke: 0.069
    // Round ends add half the stroke beyond each arc, which is what turns the 22.5 degrees drawn
    // here into the 31 degrees of ink the artwork shows.
    readonly property real dashArc: 22.5
    readonly property int dashes: 8

    readonly property real drawn: Math.min(Theme.markSize, root.iconSize)

    implicitWidth: root.drawn
    implicitHeight: root.drawn
    width: root.drawn
    height: root.drawn

    // All eight arcs in one path string: a ShapePath is not an Item, so a Repeater cannot make them.
    readonly property string ring: {
        var centre = root.drawn / 2
        var radius = root.ringRadius * root.drawn
        var half = root.dashArc / 2
        var out = ""
        for (var i = 0; i < root.dashes; i++) {
            var from = (i * 360 / root.dashes - half) * Math.PI / 180
            var to = (i * 360 / root.dashes + half) * Math.PI / 180
            out += "M " + (centre + radius * Math.cos(from)) + " " + (centre + radius * Math.sin(from))
                 + " A " + radius + " " + radius + " 0 0 1 "
                 + (centre + radius * Math.cos(to)) + " " + (centre + radius * Math.sin(to)) + " "
        }
        return out
    }

    Rectangle {
        anchors.centerIn: parent
        width: 2 * root.discRadius * root.drawn
        height: width
        radius: width / 2
        color: root.color
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: root.dashStroke * root.drawn
            capStyle: ShapePath.RoundCap

            PathSvg { path: root.ring }
        }
    }
}
