//@ pragma ShellId flea-preview-decode-test

import Quickshell
import QtQuick

// tests/preview-decode.sh's harness: the real SelectionPreview swept and rested over a stub pane, then the real PreviewImage.
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

    // The backend's row shape: a text start row, fifty sweep photos, the big PNG rest row.
    function rowFor(i) {
        if (i < 0 || i > shell.restRow) return null
        if (i === 0) return { n: "note.txt", d: false, t: false, s: 64, m: 1000, p: 33188, i: "text-x-generic" }
        if (i === shell.restRow) return { n: "big.png", d: false, t: true, s: 2000000, m: 1051, p: 33188, i: "image-x-generic" }
        return { n: "s" + (i - 1) + ".jpg", d: false, t: true, s: 100000 + i, m: 1000 + i, p: 33188, i: "image-x-generic" }
    }

    // The stub backend answers meta for every row and asks for no thumbnail, since every row already has one.
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

    // The stub pane says local btrfs, so a rule that read originals on a local disk would fire here.
    Item {
        id: stub
        property int cursorIndex: -1
        property string path: ""
        property int settleMs: 120
        property var thumbState: ({ file: {} })
        property string fsPath: ""
        property string fsName: "btrfs"
        // The fsinfo line has named the class, and "" is local, which ui/Pane.qml holds unknown until it lands.
        property string storageClass: ""
        property bool storageKnown: true
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

    // Every row pre-thumbnailed, so a load during the sweep opens its cache file and the sweep window counts it.
    function begin() {
        stub.path = shell.photoDir
        stub.fsPath = shell.photoDir
        var files = {}
        for (var i = 1; i < shell.restRow; i++) files[i] = shell.photoDir + "/t" + (i - 1) + ".png"
        files[shell.restRow] = shell.photoDir + "/t50.png"
        stub.thumbState = ({ file: files })
        stub.cursorIndex = 0
        shell.log("READY pid=" + Quickshell.processId)
        settleTimer.restart()
    }

    Timer {
        id: settleTimer
        interval: 400
        // The text row has loaded by now, so the sweep window opens on the sweep alone.
        onTriggered: {
            shell.mark("sweep")
            shell.log("SWEEP START")
            shell.movesLeft = shell.sweepCount
            moveTimer.restart()
        }
    }

    // Fifty cursor moves at key-repeat rate, each restarting SelectionPreview's settle before it expires.
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

    // Two seconds, longer than the 0.3.5 candidate's 580 ms sharp decode, then Quick Look's half.
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

    // Sample log line: "PREVIEW QL portrait decoded=400x600 drawn=314x471", the turned photo decoded whole and upright, drawn at the exact fit.
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
