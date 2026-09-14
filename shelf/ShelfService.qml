import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The only thing here that touches the outside world: the pile's own state file, which the
// `flea shelf` backend writes and this reads. The widget never learns how a file got into the pile.
Item {
    id: root
    visible: false

    property var settings: ({})

    readonly property string home: Quickshell.env("HOME") || ""
    // XDG_STATE_HOME is what the driven tests point at a sandbox, the way every other plugin reads it.
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/omarchy/flea-shelf"
    readonly property string statePath: root.stateDir + "/shelf.json"

    property var pile: Model.empty()
    readonly property int count: root.pile.count
    readonly property bool holding: root.pile.count > 0
    // Nothing is known before the first read answers, so the mark must not assert empty on a shell start.
    property bool read: false

    // Re-clamped on read, so a hand-edited shell.json cannot poison the timer.
    function intSetting(name, fallback, minValue, maxValue) {
        var raw = root.settings ? root.settings[name] : undefined
        var n = parseInt(raw, 10)
        if (!isFinite(n)) n = fallback
        return Math.max(minValue, Math.min(maxValue, n))
    }

    readonly property int refreshIntervalSec: root.intSetting("refreshIntervalSec", 5, 1, 120)
    readonly property int millisecondsPerSecond: 1000

    function load(text) {
        root.pile = Model.parse(text)
        root.read = true
    }

    FileView {
        id: file
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.load(file.text())
        // A pile nobody has started yet has no file at all, which is the empty shelf and not an error.
        onLoadFailed: root.load("")
    }

    // A watch cannot fire for a file that does not exist yet, so the first drop is found by this.
    Timer {
        interval: root.refreshIntervalSec * root.millisecondsPerSecond
        running: true
        repeat: true
        onTriggered: file.reload()
    }
}
