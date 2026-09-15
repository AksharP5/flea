pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "js/ShelfPile.js" as ShelfPile

// SettingsRest rule 4: the pins the Settings panel lists are the shelf's own entries, read from the
// pile the bar plugin reads and written through the same `flea shelf` calls the card makes, so the
// panel and the card can never disagree about what is pinned.
QtObject {
    id: root

    readonly property string pileFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
                                       + "/omarchy/flea-shelf/shelf.json"
    property var records: []
    property string lastError: ""

    readonly property var pile: FileView {
        path: root.pileFile
        watchChanges: true
        // A home that has pinned nothing has no pile file, which onLoadFailed answers with no rows.
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.records = ShelfPile.pinned(text())
        onLoadFailed: root.records = []
    }

    // What the running call was, so a refusal names it, and the one waiting behind it: a pin pressed
    // while the last one is still running is answered rather than dropped.
    property string running: ""
    property var waiting: []

    readonly property var writer: Process {
        running: false
        onExited: function (code) {
            root.lastError = code === 0 ? "" : "The shelf could not " + root.running + " that row."
            root.running = ""
            root.pile.reload()
            // Drained from the event loop because the process is still running inside this handler,
            // and the row stays in the queue until it starts so a call arriving then cannot jump it.
            if (root.waiting.length > 0) {
                Qt.callLater(root.drain)
            }
        }
    }

    function pin(path) {
        root.run(["shelf", "pin", path])
    }

    function unpin(path) {
        root.run(["shelf", "unpin", path])
    }

    // Rule 4: the pins are a list the operator orders, and their order is the pile's own.
    function move(path, direction) {
        root.moveTo(path, root.at(path) + direction)
    }

    function moveTo(path, to) {
        if (root.at(path) < 0 || to < 0 || to >= root.records.length) {
            return
        }
        root.run(["shelf", "order", path, String(to)])
    }

    function at(path) {
        for (var i = 0; i < root.records.length; i++) {
            if (root.records[i].path === path) {
                return i
            }
        }
        return -1
    }

    function run(args) {
        // Anything already waiting goes first, or a call arriving while the queue drains would jump
        // it and land a pin and its unpin the wrong way round.
        if (root.writer.running || root.waiting.length > 0) {
            root.waiting = root.waiting.concat([args])
            return
        }
        root.lastError = ""
        root.start(args)
    }

    function drain() {
        if (root.writer.running || root.waiting.length === 0) {
            return
        }
        var next = root.waiting[0]
        root.waiting = root.waiting.slice(1)
        root.start(next)
    }

    function start(args) {
        root.running = args[1]
        root.writer.command = [Quickshell.env("FLEA_BIN") || "flea"].concat(args)
        root.writer.running = true
    }
}
