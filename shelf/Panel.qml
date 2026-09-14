import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The shelf's presence in the bar, and nothing else yet: the card, the drop target, the keys and
// the actions are their own units. BarMark rule 6: it never self-hides, so its slot never moves.
Panel {
    id: root
    moduleName: "io.github.thisisgm.flea-shelf"

    // Without these the bar allocates a zero-width slot: the widget draws nothing and logs nothing.
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
    // BarMark rule 2: empty is 55 percent present and holding is 100, and nothing else changes.
    readonly property real emptyPresence: 0.55
    readonly property real markOpacity: shelf.holding ? 1.0 : root.emptyPresence

    ShelfService {
        id: shelf
        settings: root.settings
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        // Rule 3: the count lives in the tooltip, the card and the edge notch, never in the bar.
        tooltipText: Model.tooltip(shelf.pile)
        iconComponent: Component {
            Item {
                FleaShelfMark {
                    anchors.centerIn: parent
                    width: Style.space(11)
                    height: Style.space(11)
                    color: root.barForeground
                    opacity: root.markOpacity
                }
            }
        }
    }
}
