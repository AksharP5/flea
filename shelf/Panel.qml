import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Run.js" as Run

// The shelf's presence in the bar, and nothing else yet: the card, the drop target, the keys and
// the actions are their own units. BarMark rule 6: it never self-hides, so its slot never moves.
Panel {
  id: root
  moduleName: "io.github.thisisgm.flea-shelf"

  // Without these the bar allocates a zero-width slot: the widget draws nothing and logs nothing.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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
  // Summon: the card's menu holds the last five piles, and a cleared pile says how to get it back
  // for the four seconds a transient lives.
  property bool menu: false
  // True from the lift until the platform drag ends, however it ended.
  property bool carrying: false
  readonly property int transientMs: 4000
  readonly property int focusHoldMs: 75

  // A card that closed while its menu was up must come back as the pile, not as the menu: the menu is
  // a detour, and the shelf is what the next summon is asking for. A closed card also forgets the
  // gesture it was in the middle of, because the next one is a new question.
  onOpenedChanged: {
    if (root.opened) {
      card.cursorIndex = card.pile.items.length > 0 ? 0 : -1
      return
    }
    root.menu = false
    root.pending = ""
    root.carrying = false
    root.result = ""
    root.error = ""
    card.chosen = ({})
    card.cursorIndex = -1
    card.stripIndex = -1
  }

  ShelfService {
    id: shelf
    settings: root.settings
    // EdgeRail rule 1: the default edge is the one opposite the bar, so the rail needs to know it.
    barPosition: root.bar ? root.bar.position : "top"
    // Rule 4's budget: sizes are asked for while the card is up and never while it is closed.
    drawing: root.opened
    onGrew: landing.restart()
    // Summon: a keybind, a CLI call and the mark all arrive here, by the same path.
    onSummoned: root.opened ? root.close() : root.open()
    onCleared: function (count) {
      root.error = ""
      root.result = Model.clearedText(count)
      transient.restart()
    }
    onMinted: function (token, moving) { card.lift(token, !moving) }
    onFailed: function (why) {
      // Rule 5: one voice. An error takes the slot from a result and expires the same way.
      root.result = ""
      root.error = why
      root.carrying = false
      transient.restart()
    }
  }

  Timer {
    id: transient
    interval: root.transientMs
    onTriggered: {
      root.result = ""
      root.error = ""
    }
  }

  // EdgeRail: the one summon path that is always live, which is why it is the one that must be
  // switchable. Off, left, right or bottom, defaulting to the edge opposite the bar.
  ShelfRail {
    id: rail
    edge: shelf.railEdge
    dwellMs: shelf.railDwellMs
    held: shelf.count
    foreground: Color.popups.text
    onDropped: function (paths) {
      root.error = ""
      shelf.addAll(paths)
    }
    onDwelled: if (!root.opened) root.open()
    onOpened: root.toggle()
  }

  // Actions: the doing half, which the card's strip and its five letters reach through here.
  ShelfActions {
    id: doing
    fleaCommand: shelf.fleaCommand
    held: shelf.count
    onRan: shelf.reread()
    onLanded: function (sentence) {
      root.error = ""
      root.result = sentence
      transient.restart()
    }
    onBrowsed: function (dest) { root.runChosen(dest) }
  }

  // What the strip asked for and has not been given a destination for yet.
  property string pending: ""
  property var flyoutRows: []

  function actOn(id) {
    if (id === "pin") {
      card.pinRequested(card.cursorIndex)
      return
    }
    var paths = Model.actionPaths(card.chosen, card.rows)
    if (paths.length === 0) {
      return
    }
    if (id === "paths") {
      Quickshell.clipboardText = doing.yank(paths)
      root.error = ""
      root.result = Run.copiedPathsText(paths.length)
      transient.restart()
      return
    }
    if (id === "zip") {
      doing.zip(Model.today(), paths)
      return
    }
    if (id === "send") {
      doing.askPeers()
      root.pending = "send"
      root.flyoutRows = doing.peers
      return
    }
    doing.askPlaces()
    root.pending = id
    root.flyoutRows = doing.places
  }

  // The flyout's rows arrive a moment after it opens, because the list is another process's answer.
  Connections {
    target: doing
    function onPlacesChanged() { if (root.pending === "move" || root.pending === "copy") root.flyoutRows = doing.places }
    function onPeersChanged() { if (root.pending === "send") root.flyoutRows = doing.peers }
  }

  function runChosen(dest) {
    var paths = Model.actionPaths(card.chosen, card.rows)
    if (root.pending === "send") {
      doing.send(dest, paths)
    } else if (root.pending.length > 0) {
      doing.transfer(root.pending === "move", dest, paths)
    }
    root.pending = ""
    card.chosen = ({})
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
    // Keys board: right click on the bar mark brings back the last pile you cleared, which is the
    // route that survives when the card is closed and the keyboard is not where your hand is. The
    // button itself already takes all three buttons and says which one in its signal.
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) {
        shelf.restore(0)
        return
      }
      root.toggle()
    }
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
    implicitHeight: (root.menu ? pileMenu.implicitHeight
                              : root.pending.length > 0 ? flyout.implicitHeight
                              : card.implicitHeight)
                    + surface.contentTopInset + surface.contentBottomInset
    anchors { top: true; right: true }
    margins { right: Style.gapsOut; top: Style.gapsOut }
    WlrLayershell.namespace: "flea-shelf-card"
    WlrLayershell.layer: WlrLayer.Overlay
    // Measured on this box: an exclusive grab is never told a drag left the surface, so the card
    // holds the keyboard while it is open and gives it up for the length of a drag; see the README.
    WlrLayershell.keyboardFocus: root.opened && !root.carrying
                                 ? WlrKeyboardFocus.Exclusive
                                 : WlrKeyboardFocus.None

    onVisibleChanged: if (panel.visible) focusHold.restart()

    Timer {
      id: focusHold
      // Enough Qt and Wayland commit cycles for the surface to exist before Qt's own focus is set,
      // which is the OEM keyboard panel's own number for the same wait.
      interval: root.focusHoldMs
      onTriggered: surface.forceActiveFocus()
    }

    // The ground, border and corner the shell's own popups draw: Ui/KeyboardPanel.qml and
    // Ui/PopupCard.qml both fill a BorderSurface this way, so the shelf card is an Omarchy card.
    BorderSurface {
      id: surface
      anchors.fill: parent
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      focus: root.opened
      // Actions: while an action runs the first esc cancels it and the card stays; with nothing
      // running esc leaves the flyout, then the menu, and only then closes the card.
      Keys.onEscapePressed: {
        if (doing.run.running) {
          doing.cancelRun()
        } else if (root.pending.length > 0) {
          root.pending = ""
        } else if (root.menu) {
          root.menu = false
        } else {
          root.close()
        }
      }
      // Keys board: shift-x clears and the pile becomes the last pile, z undoes it, and in the menu
      // a number takes that pile straight back.
      Keys.onPressed: function (event) {
        if (root.pending.length > 0) {
          flyout.key(event)
          return
        }
        if (root.menu) {
          var chosen = event.key - Qt.Key_1
          if (chosen >= 0 && chosen < shelf.piles.length) {
            shelf.restore(chosen)
            root.menu = false
            event.accepted = true
          }
          return
        }
        if (event.key === Qt.Key_X && (event.modifiers & Qt.ShiftModifier)) {
          shelf.clear()
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Z) {
          shelf.restore(0)
          event.accepted = true
          return
        }
        // Everything else the card owns: the cursor, the subset gesture and the action strip.
        card.key(event)
      }

      ShelfMenu {
        id: pileMenu
        visible: root.menu
        x: surface.contentLeftInset
        y: surface.contentTopInset
        width: surface.width - surface.contentLeftInset - surface.contentRightInset
        piles: shelf.piles
        foreground: Color.popups.text
        pad: card.pad
        stripHeight: card.stripHeight
        rowHeight: card.rowHeight
        onChosen: function (index) {
          shelf.restore(index)
          root.menu = false
        }
        onDismissed: root.menu = false
      }

      ShelfFlyout {
        id: flyout
        visible: root.pending.length > 0
        x: surface.contentLeftInset
        y: surface.contentTopInset
        width: surface.width - surface.contentLeftInset - surface.contentRightInset
        title: Run.flyoutTitle(root.pending, Model.actionPaths(card.chosen, card.rows).length)
        rows: root.flyoutRows
        browsable: root.pending === "move" || root.pending === "copy"
        foreground: Color.popups.text
        pad: card.pad
        stripHeight: card.stripHeight
        rowHeight: card.rowHeight
        onChosen: function (index) { root.runChosen(root.flyoutRows[index]) }
        // The chooser answers in its own time, so what it is choosing for is still owed until it
        // does: clearing pending here would drop the destination the operator picked.
        onBrowse: doing.choose(flyout.title, root.flyoutRows.length > 0 ? root.flyoutRows[0] : "")
        onDismissed: root.pending = ""
      }

      ShelfCard {
        id: card
        visible: !root.menu && root.pending.length === 0
        x: surface.contentLeftInset
        y: surface.contentTopInset
        width: surface.width - surface.contentLeftInset - surface.contentRightInset
        height: surface.height - surface.contentTopInset - surface.contentBottomInset
        pile: shelf.pile
        rows: Model.rows(shelf.pile, shelf.captures, shelf.sizes)
        kinds: shelf.shelfSettings
        keyHints: shelf.keyHints
        incoming: rail.incoming
        // The empty card names only the routes that are on: the mark is drawn today, the rail edge
        // and the summon bind arrive with the units that build them.
        hint: Model.emptyHint(shelf.pile, shelf.captures,
                              { edge: "", mark: true, bind: shelf.summonBind })
        // Actions: the strip acts on what the card is drawing, chosen or whole.
        foreground: Color.popups.text
        result: root.result
        error: root.error
        onRemoveRequested: function (index) {
          var row = card.rows[index]
          if (!row || row.section === "capture") {
            return
          }
          root.error = ""
          shelf.forget(row.path)
        }
        onPinRequested: function (index) {
          var row = card.rows[index]
          if (!row) {
            return
          }
          root.error = ""
          shelf.pin(row.path, !row.pinned)
        }
        onOpenRequested: function (path) {
          root.error = ""
          shelf.open(path)
        }
        onMenuRequested: {
          shelf.askPiles()
          root.menu = true
        }
        onActionRequested: function (id) { root.actOn(id) }
        onCancelRequested: doing.cancelRun()
        run: doing.run
        onLiftRequested: function (copying) {
          var carried = Model.actionPaths(card.chosen, card.rows)
          root.carrying = shelf.mintDrag(Model.dragMoves(carried, card.rows, !copying), carried)
        }
        onCarried: function (carrying) { root.carrying = carrying }
      }
    }
  }
}
