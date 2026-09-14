import QtQuick
import Quickshell
import Quickshell.Wayland
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
  // The motion vocabulary's first entry, Land: the pile grew, so presence takes 220 ms to full and
  // the accent decays over the 600 ms after it. Work and Refuse land with the units that give them
  // a trigger, the operations and the drop, because nothing animates for an event this cannot see.
  readonly property int landMs: 220
  readonly property int accentDecayMs: 600
  property real landAccent: 0

  // The card's own slot, rule 5: one voice at a time, and the pile's own state owns neither.
  property string result: ""
  property string error: ""

  ShelfService {
    id: shelf
    settings: root.settings
    // Rule 4's budget: sizes are asked for while the card is up and never while it is closed.
    drawing: root.opened
    onGrew: landing.restart()
    onMinted: function (token, moving) { card.lift(token, !moving) }
    onFailed: function (why) { root.error = why }
  }

  SequentialAnimation {
    id: landing
    PropertyAction { target: root; property: "landAccent"; value: 1 }
    PauseAnimation { duration: root.landMs }
    NumberAnimation { target: root; property: "landAccent"; to: 0; duration: root.accentDecayMs }
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
          // Rule 4: accent is transient and supporting, never the resting colour.
          color: root.landAccent > 0
                 ? Qt.tint(root.barForeground, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, root.landAccent))
                 : root.barForeground
          opacity: root.markOpacity
          // Rule 2's only channel, and Land's 220 ms is the step it takes to full presence.
          Behavior on opacity { NumberAnimation { duration: root.landMs } }
        }
      }
    }
    onPressed: function (buttonCode) { root.toggle() }
  }

  // The card is its own layer surface, sized to itself. The shell's KeyboardPanel is a full-screen
  // overlay so a click anywhere dismisses it, and a full-screen overlay is a surface a drag can
  // never leave: the pointer stays on the shelf and the drop never reaches the window underneath.
  // Measured on this box before the change, with the overlay: Flea's DropArea saw no enter at all.
  PanelWindow {
    id: panel
    visible: root.opened
    color: "transparent"
    implicitWidth: card.implicitWidth + surface.contentLeftInset + surface.contentRightInset
    implicitHeight: card.implicitHeight + surface.contentTopInset + surface.contentBottomInset
    anchors { top: true; right: true }
    margins { right: Style.gapsOut; top: Style.gapsOut }
    WlrLayershell.namespace: "flea-shelf-card"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // The ground, border and corner the shell's own popups draw: Ui/KeyboardPanel.qml and
    // Ui/PopupCard.qml both fill a BorderSurface this way, so the shelf card is an Omarchy card.
    BorderSurface {
      id: surface
      anchors.fill: parent
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      focus: root.opened
      Keys.onEscapePressed: root.close()

      ShelfCard {
        id: card
        x: surface.contentLeftInset
        y: surface.contentTopInset
        width: surface.width - surface.contentLeftInset - surface.contentRightInset
        height: surface.height - surface.contentTopInset - surface.contentBottomInset
        pile: Model.sized(shelf.pile, shelf.sizes)
        captures: shelf.captures
        // The empty card names only the routes that are on: the mark is drawn today, the rail edge
        // and the summon bind arrive with the units that build them.
        hint: Model.emptyHint(shelf.pile, shelf.captures, { edge: "", mark: true, bind: "" })
        foreground: Color.popups.text
        result: root.result
        error: root.error
        onRemoveRequested: function (index) {
          root.error = ""
          shelf.forget(shelf.pile.items[index].path)
        }
        onCaptureAddRequested: function (index) {
          root.error = ""
          shelf.add(shelf.captures[index].path)
        }
        onActionRequested: function (id) { root.result = ""; root.error = id + " lands with the actions." }
        onLiftRequested: function (copying) { shelf.mintDrag(!copying) }
      }
    }
  }
}
