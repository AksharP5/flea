//@ pragma ShellId flea-sharp-decode-test

import Quickshell
import QtQuick

// tests/sharp-decode.sh's harness: the real ui/SelectionPreview.qml, the product path into the
// preview column, starts on a text row and then holds one photo per cursor move at key-repeat
// rate over a stub pane. The script counts the fixture directory's own open events between touch
// sentinel files this harness drops at each phase boundary, so a sweep that starts no decode and
// a rest that starts exactly one are proved from outside the column, in event order rather than by
// comparing two clocks. This pins the product path on the base commit too: it names no property
// any fix added, so it behaves the same there. It is not a fix.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("SHARP_UI")
    readonly property string photoDir: Quickshell.env("SHARP_PHOTOS")
    readonly property int sweepCount: 50
    readonly property int restRow: 51

    property int movesLeft: 0

    function log(line) { console.log("SHARP " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function mark(name) { Quickshell.execDetached(["touch", shell.photoDir + "/sentinel-" + name]) }

    // The row shape the backend's rows line carries: a text row first so the initial load opens no
    // image, fifty sweep photos, and the big PNG rest row last.
    function rowFor(i) {
        if (i < 0 || i > shell.restRow) return null
        if (i === 0) return { n: "note.txt", d: false, t: false, s: 64, m: 1000, p: 33188, i: "text-x-generic" }
        if (i === shell.restRow) return { n: "big.png", d: false, t: true, s: 2000000, m: 1051, p: 33188, i: "image-x-generic" }
        return { n: "s" + (i - 1) + ".jpg", d: false, t: true, s: 100000 + i, m: 1000 + i, p: 33188, i: "image-x-generic" }
    }

    // The stub pane SelectionPreview reads: cursor and directory identity for the settle, join and
    // kindNames for the load, thumbState for the thumbnail binding, fsPath and fsName for the
    // local-disk original rule, and a backend answering meta for every row the sweep and the rest hold.
    Item {
        id: stubBackend
        signal metaResult(var message)
        property int nextToken: 0
        property var pending: []
        function askMeta(index, text, media, archive) {
            nextToken += 1
            pending.push({ token: nextToken, index: index })
            metaTimer.restart()
            return nextToken
        }
        function thumb(rows) {}
    }

    // Local disk answers in milliseconds, so a settled selection is never left waiting on a reply.
    Timer {
        id: metaTimer
        interval: 5
        onTriggered: {
            for (var i = 0; i < stubBackend.pending.length; i++) {
                var req = stubBackend.pending[i]
                var big = req.index === shell.restRow
                stubBackend.metaResult({ token: req.token, w: big ? 6016 : 640, h: big ? 3900 : 480 })
            }
            stubBackend.pending = []
        }
    }

    Item {
        id: stub
        property int cursorIndex: -1
        property string path: ""
        property int settleMs: 120
        property var thumbState: ({ file: {} })
        property string fsPath: ""
        property string fsName: "btrfs"
        property bool listInFlight: false
        property var kindNames: []
        property var preview: ({ active: false })
        property var backend: stubBackend
        signal rowsChanged()
        signal selectionVersionChanged()
        function rowFor(i) { return shell.rowFor(i) }
        function join(base, name) { return base + "/" + name }
        function selectionCount() { return 1 }
        function selectedIndices() { return [stub.cursorIndex] }
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 600
        color: "#303030"

        Rectangle {
            id: host
            color: "#101315"
            x: 20
            y: 20
            width: 760
            height: 560

            Loader {
                id: loader
                anchors.fill: parent
                source: "file://" + shell.uiDir + "/SelectionPreview.qml"
                onLoaded: {
                    item.pane = stub
                    shell.begin()
                }
                onStatusChanged: if (status === Loader.Error) { shell.log("FAIL the preview did not load"); shell.quit() }
            }
        }
    }

    // The settled engine behind the first measurement: the cursor starts on the text row and the
    // sweep sentinel is dropped before anything moves, so module load and the first layout never
    // enter a window, and the script reads every earlier event as drained once it sees the file.
    // Every row carries the thumbnail its sharp original waits for, so a settle that let a sweep load would decode during the sweep and redden the script.
    function begin() {
        stub.path = shell.photoDir
        stub.fsPath = shell.photoDir
        var files = {}
        for (var i = 1; i < shell.restRow; i++) files[i] = shell.photoDir + "/t" + (i - 1) + ".png"
        files[shell.restRow] = shell.photoDir + "/t50.png"
        stub.thumbState = ({ file: files })
        stub.cursorIndex = 0
        shell.mark("sweep")
        shell.log("READY pid=" + Quickshell.processId)
        settleTimer.restart()
    }

    Timer {
        id: settleTimer
        interval: 400
        onTriggered: {
            shell.log("SWEEP START")
            shell.movesLeft = shell.sweepCount
            moveTimer.restart()
        }
    }

    // Fifty cursor moves at key-repeat rate: SelectionPreview clears and restarts its settle on
    // every one, so path stays empty for the whole sweep and no decode may start.
    Timer {
        id: moveTimer
        interval: 30
        repeat: true
        onTriggered: {
            stub.cursorIndex = shell.sweepCount + 1 - shell.movesLeft
            shell.movesLeft -= 1
            if (shell.movesLeft <= 0) {
                stop()
                shell.log("SWEEP END")
                stub.cursorIndex = shell.restRow
                shell.mark("rest")
                shell.log("REST START")
                restPoll.restart()
            }
        }
    }

    // The rest has loaded once the column holds a path; the decode it starts is what the done window counts.
    Timer {
        id: restPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            if (loader.item.path !== "") {
                stop()
                shell.log("INJECT")
                doneTimer.restart()
            } else if (waited > 1000) {
                stop()
                shell.log("FAIL the rest never loaded")
                shell.quit()
            }
        }
    }

    // The rest the brief names holds the process after the decode, and the done sentinel closes
    // the rest window; the extra half second lets the spawned touch land before the kill does.
    Timer {
        id: doneTimer
        interval: 2000
        onTriggered: {
            shell.mark("done")
            shell.log("DONE")
            quitTimer.restart()
        }
    }

    Timer {
        id: quitTimer
        interval: 500
        onTriggered: shell.quit()
    }
}
