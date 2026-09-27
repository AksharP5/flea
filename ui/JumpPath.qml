import QtQuick
import "js/Jump.js" as Jump

// One jump row's label: the path split as the chrome splits it, a muted parent and a foreground leaf,
// with the scorer's one match run on the accent wash ui/MatchText.qml draws behind a search match.
// Each piece is PlainText, because a folder name is arbitrary text. A path too long for the slot
// slides left inside it, the chrome's own left elision, because the tail is what names the folder.
Item {
    id: root

    // One entry of ui/js/Jump.js rows: { text, leafStart, washStart, washLength }.
    property var entry: ({})
    readonly property var pieces: Jump.segments(root.entry)
    // The cuts behind segments() are [0, leafStart, length] plus at most the wash's two edges,
    // so no row ever splits into more than four pieces: four standing Texts rebind per keystroke
    // instead of rebuilding, the way the dropdown's own rows do.
    readonly property int maxPieces: 4

    implicitHeight: line.height
    clip: true

    Row {
        id: line
        x: Math.min(0, root.width - line.width)
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            model: root.maxPieces

            delegate: Text {
                id: piece
                required property int index
                readonly property var part: piece.index < root.pieces.length ? root.pieces[piece.index] : null
                visible: piece.part !== null
                text: piece.part ? piece.part.text : ""
                color: piece.part && piece.part.leaf ? Theme.color.foreground : Theme.color.muted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
                textFormat: Text.PlainText

                // Behind the ink, which keeps its own colour: accent on foreground is unreadable on some palettes.
                Rectangle {
                    z: -1
                    anchors.fill: parent
                    visible: piece.part ? piece.part.wash : false
                    color: Qt.alpha(Theme.color.accent, Theme.washActive)
                }
            }
        }
    }
}
