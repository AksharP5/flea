import QtQuick
import qs.Commons
import "Model.js" as Model

// The pile itself, Main board rules 2 to 8. The card is the shelf's own surface: it reads like a
// Flea listing on purpose, the same strip height, the same row pitch and the same mark slot, so the
// shelf is Flea's shelf and not a second application that happens to hold files.
Item {
  id: root

  property var pile: Model.empty()
  property color foreground: Color.foreground
  property color muted: Qt.darker(foreground, 1.55)
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  // Rule 5: one slot, one voice, and the card's own two are the last result and the one error.
  property string result: ""
  property string error: ""
  property int hoveredIndex: -1
  property int cursorIndex: -1
  // ShelfEmpty rules 2 and 5: the tray is on the card whether the pile is empty or not.
  property var captures: []
  property string hint: ""
  // EdgeRail: how many a drag over the rail is offering, which the header says and the line shows.
  property int incoming: 0

  signal removeRequested(int index)
  signal captureAddRequested(int index)
  // Summon: the pointer's way to the last five piles is the card's own menu.
  signal menuRequested()
  signal actionRequested(string id)
  // Rule 2: the header is the handle the whole pile is carried by. The modifier is read at the
  // lift and never after it, because a platform drag runs a loop this window gets no keys in.
  signal liftRequested(bool copying)

  // The payload the drag carries once the token is back: the token and the intent, then the paths
  // for every other application, which is offered a copy and never a move (DragOut rule 4).
  property var dragMime: ({})
  Drag.dragType: Drag.Automatic
  Drag.supportedActions: Qt.CopyAction
  Drag.proposedAction: Qt.CopyAction
  Drag.mimeData: root.dragMime

  // The token arrives from the service a few milliseconds after the press, with the button still
  // down, which is where the platform drag can be started from.
  function lift(token, copying) {
    var uris = []
    for (var i = 0; i < root.pile.items.length; i++) {
      uris.push("file://" + encodeURI(root.pile.items[i].path))
    }
    var mime = { "application/x-flea-shelf": token + "\n" + (copying ? "copy" : "move") }
    mime["text/uri-list"] = uris.join("\r\n") + "\r\n"
    root.dragMime = mime
    root.Drag.active = true
  }

  Drag.onDragFinished: {
    root.Drag.active = false
    root.dragMime = ({})
  }

  // Rules 2 and 3: the same strip height and the same row as Flea's own, which means the same
  // derivation rather than the same literals, so both land on one number at every text size.
  // ui/Theme.qml: rowHeight is the line box plus its padding, the mark is the type scale's own
  // step, and the chrome strip is 0.72 of a row. Measured at text size 14: 37, 19 and 27.
  readonly property int body: Style.font.bodySmall
  readonly property real lineBoxRatio: 1.8
  readonly property real chromeRowRatio: 0.72
  readonly property real rowHeight: Math.round(root.body * root.lineBoxRatio) + 2 * Style.spacing.controlPaddingY
  readonly property real stripHeight: Math.round(root.rowHeight * root.chromeRowRatio)
  readonly property real markSize: root.body * 1.45
  // The card's own width, scaled from the board's 380 the way Flea scales a column, off base 12.
  readonly property real cardWidth: Math.round(380 * root.body / 12)
  readonly property real pad: Style.spacing.rowPaddingX
  readonly property var actions: [
    { id: "move", label: "Move", key: "m" },
    { id: "copy", label: "Copy", key: "c" },
    { id: "zip", label: "Zip", key: "a" },
    { id: "send", label: "Send", key: "t" },
    { id: "paths", label: "Paths", key: "y" }
  ]

  implicitWidth: cardWidth
  implicitHeight: column.implicitHeight

  // The pointer route to Recent piles. Only the right button, so every left press still reaches the
  // header's lift, a row's x and the tray's own thumbs.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    onClicked: root.menuRequested()
  }

  Column {
    id: column
    width: parent.width

    // Rule 2: the header is the strip height, and it is the handle the whole pile is carried by.
    Item {
      id: header
      width: parent.width
      height: root.stripHeight

      // The press is the lift: the token is minted on it and the platform drag starts when the
      // token is back, with the button still down. A handler that waits for a drag threshold
      // cannot be used here, because the mint has to happen before the loop the drag enters.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: function (mouse) {
          root.liftRequested((mouse.modifiers & Qt.ControlModifier) !== 0)
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        x: root.pad
        text: Model.headerText(root.pile)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: root.pad
        text: Model.headerRight(root.incoming)
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }

    Repeater {
      model: root.pile.items

      // Rule 4: one line per row, mark, name and size, and no source path: a pile spanning five
      // folders would otherwise read as five different kinds of row.
      Item {
        id: row
        required property int index
        required property var modelData
        width: column.width
        height: root.rowHeight
        readonly property bool lifted: root.hoveredIndex === row.index || root.cursorIndex === row.index

        Rectangle {
          anchors.fill: parent
          color: root.accent
          opacity: row.lifted ? 0.14 : 0
        }

        ShelfGlyph {
          id: mark
          x: root.pad
          anchors.verticalCenter: parent.verticalCenter
          width: root.markSize
          height: root.markSize
          path: Model.glyphFor(row.modelData)
          color: root.foreground
        }

        Text {
          id: name
          anchors.verticalCenter: parent.verticalCenter
          x: mark.x + mark.width + Style.space(10)
          width: size.x - x - Style.space(10)
          text: row.modelData.name
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideMiddle
          textFormat: Text.PlainText
        }

        Text {
          id: size
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: remove.left
          anchors.rightMargin: Style.space(10)
          text: Model.sizeText(row.modelData)
          // Rule 4: a hovered, marked or cursor row lifts its size to full foreground.
          color: row.lifted ? root.foreground : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }

        // Rule 6: the row's own x, muted until the row is under the pointer. It takes the
        // reference off the shelf and never touches the file.
        Text {
          id: remove
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: root.pad
          text: "×"
          color: removeHover.hovered ? root.foreground : root.muted
          opacity: row.lifted ? 1 : 0
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          textFormat: Text.PlainText

          HoverHandler { id: removeHover }
          TapHandler { onSingleTapped: root.removeRequested(row.index) }
        }

        HoverHandler {
          onHoveredChanged: root.hoveredIndex = hovered ? row.index : (root.hoveredIndex === row.index ? -1 : root.hoveredIndex)
        }
      }
    }

    // EdgeRail: the line that says where the ones being dragged in will land, which is after the
    // pile, because the shelf holds what it was given in the order it was given it.
    Rectangle {
      width: parent.width - 2 * root.pad
      x: root.pad
      height: visible ? Math.max(1, Style.space(2)) : 0
      visible: root.incoming > 0
      color: root.accent
    }

    // ShelfEmpty rule 6: empty is a state, not a failure. One mark, one caption, and the footer's
    // own hint line beneath it; no apology copy and no onboarding card.
    Item {
      width: parent.width
      height: visible ? Math.round(root.rowHeight * 4) : 0
      visible: root.pile.items.length === 0 && root.captures.length === 0

      Column {
        anchors.centerIn: parent
        spacing: Style.space(12)

        ShelfGlyph {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(44)
          height: width
          path: Model.SHELF_GLYPH
          color: root.muted
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "NOTHING ON THE SHELF"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          textFormat: Text.PlainText
        }
      }
    }

    ShelfTray {
      width: parent.width
      captures: root.captures
      foreground: root.foreground
      muted: root.muted
      fontFamily: root.fontFamily
      pad: root.pad
      stripHeight: root.stripHeight
      onAddRequested: function (index) { root.captureAddRequested(index) }
    }

    // Rule 5: the footer is one slot with one voice, and it says nothing rather than two things.
    Item {
      width: parent.width
      height: root.stripHeight

      Text {
        anchors.verticalCenter: parent.verticalCenter
        x: root.pad
        width: parent.width - 2 * root.pad
        text: Model.footerText(root.hoveredIndex >= 0 && root.pile.items[root.hoveredIndex]
                               ? root.pile.items[root.hoveredIndex].path : "",
                               root.result, root.error, root.hint)
        color: root.error ? Color.urgent : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
        textFormat: Text.PlainText
      }
    }

    // Rule 7: every action carries its key inline, always. The card is its own surface, so Flea's
    // keyHints toggle does not govern this strip. Zip takes a, because z is undo everywhere.
    Row {
      width: parent.width
      // ShelfEmpty rule 1: absent, not greyed. Five dead buttons teach the eye to ignore the strip.
      visible: root.pile.items.length > 0
      height: visible ? root.stripHeight : 0
      spacing: Style.space(14)
      leftPadding: root.pad

      Repeater {
        model: root.actions

        Row {
          id: action
          required property var modelData
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(5)

          Text {
            text: action.modelData.label
            color: actionHover.hovered ? root.foreground : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }

          Text {
            text: action.modelData.key
            color: root.muted
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }

          HoverHandler { id: actionHover }
          TapHandler { onSingleTapped: root.actionRequested(action.modelData.id) }
        }
      }
    }
  }
}
