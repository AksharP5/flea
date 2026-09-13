import QtQuick
import "." as Flea

// The marks a multi-selection stacks in the preview frame, one per kind, front-most first. The
// canvas offsets its marks a quarter of the mark across and an eleventh of it down, so both steps
// are measured against the mark this pane actually draws, HANDOFF rule 17's stateMarkSize.
Item {
    id: root

    // Glyph names, front-most first, as ui/js/Facts.js multiMarks builds them.
    property var marks: []

    readonly property int stepX: Math.round(Theme.stateMarkSize / 4)
    readonly property int stepY: Math.round(Theme.stateMarkSize / 11)
    // Every mark behind the front one is a step fainter, which is the canvas's 1.0, 0.7 and 0.4.
    readonly property real fade: 0.3
    readonly property int steps: Math.max(0, root.marks.length - 1)

    width: Theme.stateMarkSize + root.steps * root.stepX
    height: Theme.stateMarkSize + root.steps * root.stepY

    Repeater {
        model: root.marks

        delegate: Flea.Glyph {
            required property string modelData
            required property int index
            // Model order paints back to front, so the front mark has to claim its own z.
            z: root.marks.length - index
            x: (root.steps - index) * root.stepX
            y: index * root.stepY
            maxSize: Theme.stateMarkSize
            width: Theme.stateMarkSize
            height: Theme.stateMarkSize
            name: modelData
            color: Theme.color.muted
            opacity: 1 - index * root.fade
        }
    }
}
