pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "js/Scripts.js" as Model

// MenuAdditions rule 2: the scripts a menu can run, read out of ~/.config/flea/scripts when a menu
// opens rather than watched, and run with the selected paths as arguments in the first one's folder.
// The one thing here that touches the outside world, the way ui/NetworkMounts.qml is for gio.
Item {
    id: root

    // [{ id, label, path }], sorted by name, the label the file name without its extension.
    property var entries: []
    property bool loaded: false
    readonly property string directory: (Quickshell.env("XDG_CONFIG_HOME") && Quickshell.env("XDG_CONFIG_HOME").length > 0
                                         ? Quickshell.env("XDG_CONFIG_HOME") : Quickshell.env("HOME") + "/.config") + "/flea/scripts"

    signal said(string text, bool isError)

    function refresh() {
        if (!lister.running)
            lister.running = true
    }

    function run(id, paths) {
        var script = ""
        for (var i = 0; i < root.entries.length; i++)
            if (root.entries[i].id === id) script = root.entries[i].path
        if (script.length === 0 || paths.length === 0) {
            root.said("That script is no longer there.", true)
            return
        }
        runner.script = script
        runner.workingDirectory = paths[0].substring(0, paths[0].lastIndexOf("/")) || "/"
        runner.command = [script].concat(paths)
        runner.running = true
    }

    // An executable regular file, one level down and nothing else: a directory of scripts is a flat
    // one, and -perm -u+x is the owner bit the board names.
    Process {
        id: lister
        command: ["find", root.directory, "-maxdepth", "1", "-type", "f", "-perm", "-u+x", "-printf", "%f\\n"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.entries = Model.parse(text, root.directory)
                root.loaded = true
            }
        }
    }

    // A script's own last stderr line is the report, elided to one sentence by the status centre.
    Process {
        id: runner
        property string script: ""
        stderr: StdioCollector { waitForEnd: true }
        onExited: function (code, status) {
            if (code === 0)
                return
            root.said(Model.failure(runner.script.substring(runner.script.lastIndexOf("/") + 1), runner.stderr.text, code), true)
        }
    }
}
