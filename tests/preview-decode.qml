//@ pragma ShellId flea-preview-decode-test

import Quickshell
import QtQuick

// tests/preview-decode.sh's harness. First the real ui/SelectionPreview.qml, the product path into
// the preview column, starts on a text row, then holds one photo per cursor move at key-repeat rate
// over a stub pane, then rests on a 6016x3900 PNG. The script counts the fixture directory's own
// open events between touch sentinel files this harness drops at each phase boundary, in event
// order rather than by comparing two clocks. Then the real ui/PreviewImage.qml, Quick Look's image
// pane, decodes an EXIF-turned photo, a 3000x100 banner and a small PNG in a 754x471 box, and logs
// each decode's size and the size it is drawn at.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("PREVIEW_UI")
    readonly property string photoDir: Quickshell.env("PREVIEW_PHOTOS")
    readonly property int sweepCount: 50
    readonly property int restRow: 51

    property int movesLeft: 0

    function log(line) { console.log("PREVIEW " + line) }
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
    // kindNames for the load, thumbState for the thumbnail binding, and a backend answering meta for
    // every row. It says local btrfs, so a rule that reads originals on a local disk would fire here.
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

        // Quick Look's box on this test, the Columns frame's own 754x471, loaded only after the column's windows close.
        Loader {
            id: quickLook
            x: 20
            y: 20
            width: 754
            height: 471
            active: false
            source: "file://" + shell.uiDir + "/PreviewImage.qml"
            onStatusChanged: if (status === Loader.Error) { shell.log("FAIL Quick Look's image pane did not load"); shell.quit() }
        }
    }

    // Settled start on the text row with the sweep sentinel dropped first and every row pre-thumbnailed, so module load never enters a window and a sweep-time load would decode and redden.
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

    // The rest has loaded once the column holds a path; whatever it opens is what the done window counts.
    Timer {
        id: restPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            if (loader.item.path !== "") {
                stop()
                shell.log("RESTED")
                doneTimer.restart()
            } else if (waited > 1000) {
                stop()
                shell.log("FAIL the rest never loaded")
                shell.quit()
            }
        }
    }

    // Two seconds of rest, longer than the 0.3.5 candidate's 580 ms sharp decode, then the done
    // sentinel closes the rest window and Quick Look's half begins.
    Timer {
        id: doneTimer
        interval: 2000
        onTriggered: {
            shell.mark("done")
            shell.log("DONE")
            quickLook.active = true
            shell.lookAt("portrait", shell.photoDir + "/portrait.jpg")
        }
    }

    // The Image inside ui/PreviewImage.qml, found by the property only an Image has, so the test names no id of the pane's.
    function picture() {
        var kids = quickLook.item ? quickLook.item.children : []
        for (var i = 0; i < kids.length; i++)
            if (kids[i].autoTransform !== undefined) return kids[i]
        return null
    }

    property string looking: ""
    property string lookingName: ""
    function lookAt(label, path) {
        shell.looking = label
        shell.lookingName = path.substring(path.lastIndexOf("/") + 1)
        quickLook.item.path = path
        lookPoll.waited = 0
        lookPoll.restart()
    }

    // Sample log line: "PREVIEW QL portrait decoded=314x471 drawn=314x471".
    Timer {
        id: lookPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var img = shell.picture()
            // The source check keeps the portrait's Ready from answering for the small PNG.
            if (quickLook.item && quickLook.item.status === "image" && img && String(img.source).endsWith("/" + shell.lookingName)) {
                stop()
                shell.log("QL " + shell.looking + " decoded=" + img.implicitWidth + "x" + img.implicitHeight
                          + " drawn=" + Math.round(img.width) + "x" + Math.round(img.height))
                if (shell.looking === "portrait") shell.lookAt("banner", shell.photoDir + "/banner.png")
                else if (shell.looking === "banner") shell.lookAt("small", shell.photoDir + "/small.png")
                else quitTimer.restart()
            } else if (waited > 5000) {
                stop()
                shell.log("FAIL Quick Look never drew " + shell.looking + " (status " + (quickLook.item ? quickLook.item.status : "none") + ")")
                shell.quit()
            }
        }
    }

    Timer {
        id: quitTimer
        interval: 500
        onTriggered: shell.quit()
    }
}
