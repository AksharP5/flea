import QtQuick
import qs.Commons
import "." as Flea
import "js/Jump.js" as Jump

// The path bar's folder jump, the Jump board: a name typed into the bar lists matching folders from
// Flea's favourites, zoxide's ranking and the desktop's recent history in a dropdown flush under the
// field, at its width and in the menu recipe. ui/ChromeBar.qml owns the field and forwards its keys
// here; ui/js/Jump.js decides the rows. Nothing is written anywhere, and zoxide is asked once per open.
Item {
    id: root

    property bool editing: false
    // The field's line as typed; ui/js/Jump.js decides whether it is a name to jump by or a path.
    property string query: ""
    property string home: ""
    // The tallest the dropdown may be before it scrolls: the window less the chrome strip above and the
    // status bar below, both a chrome strip tall, and a gap clear of the status bar.
    readonly property real room: (root.Window.window ? root.Window.window.height : 0) - 2 * Theme.chromeHeight - Theme.spacing.gap

    // The backend's answer for this open, { favourites, zoxide, recent }, empty until it arrives.
    property var sources: ({})
    readonly property bool answered: root.sources.favourites !== undefined
    // Tab is the path bar's own completion, so a line it has touched is a path for the rest of the edit:
    // with two children sharing a prefix it stops short of the slash, and Enter still means ./that.
    property bool pathTyped: false
    readonly property var entries: root.editing && !root.pathTyped ? Jump.rows(root.sources, root.query, root.home) : []
    property int cursor: -1
    readonly property bool shown: root.entries.length > 0
    // Every open asks with a new id and takes only the answer carrying it, so a slow answer to an earlier
    // open can never land in this one, or move a cursor the user has already moved.
    property int asked: 0
    // Enter on a name before this open's answer is in: held, then taken by the answer, so the same keys
    // open the same folder however fast they were typed.
    property bool enterWaiting: false
    // Where any row last saw the pointer, so rows changing under a resting pointer never move the cursor; see ui/MenuRow.qml.
    property point pointerGlobal: Qt.point(-1, -1)

    // ui/WindowBody.qml carries these to the pane's backend and back, the way it carries the bar's Tab.
    signal requested(int id, var favourites, var recent)
    signal chosen(string path)
    // Enter that the dropdown did not take after all: nothing matched, so the bar resolves the line as a path.
    signal declined()

    // The keys arrive through the field's Keys.forwardTo, which skips an invisible item, so this stays
    // visible for the whole edit and hands back every key it does not use; only the frame hides.
    visible: root.editing
    // The parent is the bar's path slot, which stops a hairline above the strip's bottom edge.
    y: root.parent ? root.parent.height + Theme.spacing.hairline : 0
    width: root.parent ? root.parent.width : 0
    height: frame.height

    onEntriesChanged: root.cursor = Jump.step(root.entries, -1, 1)
    onCursorChanged: scroll.reveal(rowItems.itemAt(root.cursor))
    onEditingChanged: {
        root.sources = ({})
        root.enterWaiting = false
        root.pathTyped = false
        root.asked += 1
        if (root.editing) {
            // Read afresh on every open, because every other application appends to the history.
            recent.active = true
            recent.item.refresh()
        }
    }

    // The backend's jumped line; one for another open, or landing after the bar closed, is dropped.
    function take(id, favourites, zoxide, recentFolders) {
        if (!root.editing || id !== root.asked) {
            return
        }
        root.sources = { favourites: favourites, zoxide: zoxide, recent: recentFolders }
        if (root.enterWaiting) {
            root.enterWaiting = false
            root.enter()
        }
    }

    // Enter itself: the cursor row when there is one, and otherwise the line as a path, as before the jump.
    function enter() {
        if (root.cursor >= 0) {
            root.chosen(root.entries[root.cursor].path)
        } else {
            root.declined()
        }
    }

    function favouritePaths() {
        var records = Flea.Favourites.records
        var out = []
        for (var i = 0; i < records.length; i++) {
            out.push(String(records[i].path || ""))
        }
        return out
    }

    // The picker's own reader of recently-used.xbel, built by the first open so a window whose bar is
    // never typed into loads no XML module at all.
    Loader {
        id: recent
        active: false
        source: "PickerRecent.qml"
    }

    Connections {
        target: recent.item
        function onRefreshed() {
            if (root.editing) {
                root.requested(root.asked, root.favouritePaths(), recent.item.paths)
            }
        }
    }

    // The backend answers inside its own zoxide and stat budgets, docs/protocol.md "jump"; one that never
    // answers at all, a backend gone, must not hold an Enter for good, so past this the line is a path.
    readonly property int answerLimitMs: 4000
    Timer {
        id: enterLimit
        interval: root.answerLimitMs
        running: root.enterWaiting
        onTriggered: {
            root.enterWaiting = false
            root.declined()
        }
    }

    Keys.onPressed: function (event) {
        // A held Enter stands for the line as it was, so nothing typed after it changes what it opens; esc still closes.
        if (root.enterWaiting && event.key !== Qt.Key_Escape) {
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.pathTyped = true
            event.accepted = false
            return
        }
        if (root.shown && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
            root.cursor = Jump.step(root.entries, root.cursor, event.key === Qt.Key_Down ? 1 : -1)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.shown) {
                root.enter()
                event.accepted = true
                return
            }
            if (!root.answered && !root.pathTyped && Jump.isQuery(root.query)) {
                root.enterWaiting = true
                event.accepted = true
                return
            }
        }
        event.accepted = false
    }

    Rectangle {
        id: frame
        visible: root.shown
        width: root.width
        height: Math.max(0, Math.min(rows.implicitHeight + 2 * Theme.spacing.rowPaddingY, root.room))
        color: Theme.color.surface
        border.width: Theme.spacing.hairline
        border.color: Theme.color.muted
        radius: Style.cornerRadius

        // The ground takes every pointer event the rows leave, so nothing reaches the listing beneath.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            onWheel: function (wheel) { wheel.accepted = true }
        }

        Flea.CardScroll {
            id: scroll
            anchors.fill: parent
            anchors.topMargin: Theme.spacing.rowPaddingY
            anchors.bottomMargin: Theme.spacing.rowPaddingY

            Column {
                id: rows
                width: parent.width

                Repeater {
                    id: rowItems
                    model: root.entries
                    // The menu's own row, so the lift, the mark slot, the pointer rules and the separator are
                    // the context menu's; the label is the path the chrome would draw, laid over its empty one.
                    delegate: Flea.MenuRow {
                        id: row
                        required property var modelData
                        required property int index
                        width: rows.width
                        entry: row.modelData.separator === true ? row.modelData : ({ glyph: "folder", label: "", hint: "" })
                        current: root.cursor === row.index
                        lastPointerGlobal: root.pointerGlobal
                        onPointerSeen: function (at) { root.pointerGlobal = at }
                        onPointerMoved: root.cursor = row.index
                        onActivated: root.chosen(row.modelData.path)

                        Flea.JumpPath {
                            visible: !row.isSeparator
                            entry: row.modelData
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacing.rowPaddingX + row.slotSize + Theme.spacing.gap
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacing.rowPaddingX
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }

        Flea.MenuEdgeFade {
            anchors.top: parent.top
            visible: scroll.contentY > 0
        }

        Flea.MenuEdgeFade {
            anchors.bottom: parent.bottom
            visible: scroll.contentY + scroll.height < scroll.contentHeight
            rotation: 180
        }
    }
}
