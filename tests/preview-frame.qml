//@ pragma ShellId flea-preview-frame-test

import QtQuick
import Quickshell
import "flea" as Flea

// The Columns preview frame drawn by the real ui/PreviewColumn.qml, offscreen: an office file's embedded
// thumbnail at its own aspect with no "no preview" over it, and a small original at its own size, never
// enlarged. tests/preview-frame.sh drives it.
ShellRoot {
    id: root

    readonly property string dir: Quickshell.env("FLEA_PREVIEW_FRAME_DIR")
    property var failures: []
    property int step: 0

    function fail(what) { root.failures.push(what) }
    function near(a, b) { return Math.abs(a - b) <= 1 }

    FloatingWindow {
        implicitWidth: 1000
        implicitHeight: 900
        color: "black"

        // The fixtures, drawn here so the test needs no image tool: a portrait office page and an original
        // smaller than the frame.
        Repeater {
            id: fixtures
            model: [["office", 181, 256], ["small", 120, 68]]
            delegate: Rectangle {
                required property var modelData
                width: modelData[1]
                height: modelData[2]
                color: "#7aa2f7"
                Rectangle { anchors.centerIn: parent; width: parent.width / 2; height: parent.height / 2; color: "#e0af68" }
            }
        }

        Flea.PreviewColumn {
            id: column
            width: 800
            height: 860
        }
    }

    // The frame's pictures in declaration order: frameThumb first.
    function images() {
        var out = []
        var kids = column.frameItem.children
        for (var i = 0; i < kids.length; i++)
            if (String(kids[i]).indexOf("QQuickImage") === 0) out.push(kids[i])
        return out
    }

    // Whether a visible item under the frame says "no preview", which the Unsupported state writes.
    function saysNoPreview(item) {
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i]
            if (!child.visible) continue
            if (child.text === "no preview" || root.saysNoPreview(child)) return true
        }
        return false
    }

    function show(row, kindName, extra) {
        column.readsOriginal = extra.readsOriginal === true
        column.noThumbComing = extra.noThumbComing === true
        column.thumb = extra.thumb || ""
        column.row = row
        column.kindName = kindName
        column.meta = {}
        column.path = extra.path
    }

    Timer {
        id: tick
        interval: 5
        repeat: true
        property int waited: 0
        onTriggered: {
            var imgs = root.images()
            var thumb = imgs[0]
            if (++waited > 1000) { root.fail("step " + root.step + " timed out"); root.finish(); return }
            if (root.step === 1) {
                if (column.frameStatus !== Image.Ready) return
                // An office page is unsupported as a preview but has its own picture, which is what the frame shows.
                if (column.previewState !== "unsupported") root.fail("office row read as " + column.previewState)
                if (root.saysNoPreview(column.frameItem)) root.fail("office thumbnail drawn under a no preview mark")
                if (!thumb.visible || thumb.opacity !== 1) root.fail("office thumbnail not drawn")
                if (!root.near(thumb.width / thumb.height * 256, 181)) root.fail("office thumbnail drawn at " + thumb.width + "x" + thumb.height + ", not 181:256")
                if (!root.near(thumb.height, column.frameItem.height - 2)) root.fail("office thumbnail not fitted to the frame, " + thumb.height + " tall")
                root.step = 2; waited = 0
                root.show({ n: "small.png", d: false, s: 1, m: 1, p: 33188, i: "image-png", t: false, k: 0 }, "PNG image",
                          { path: root.dir + "/small.png", noThumbComing: true })
            } else if (root.step === 2) {
                if (column.frameStatus !== Image.Ready) return
                if (thumb.width !== 120 || thumb.height !== 68) root.fail("a 120x68 original drawn at " + thumb.width + "x" + thumb.height)
                root.finish()
            }
        }
    }

    function finish() {
        tick.stop()
        for (var f = 0; f < root.failures.length; f++)
            console.log("PREVIEW_FRAME FAIL " + root.failures[f])
        if (root.failures.length === 0)
            console.log("PREVIEW_FRAME PASS office=fitted small=own-size")
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    // Saves the four fixtures, then starts on the office row.
    property int saved: 0
    Component.onCompleted: saveTimer.start()
    Timer {
        id: saveTimer
        interval: 50
        onTriggered: {
            var names = ["office", "small"]
            for (var i = 0; i < names.length; i++) {
                let name = names[i]
                fixtures.itemAt(i).grabToImage(function (result) {
                    result.saveToFile(root.dir + "/" + name + ".png")
                    if (++root.saved === names.length) {
                        root.step = 1
                        root.show({ n: "report.odt", d: false, s: 1, m: 1, p: 33188, i: "x-office-document", t: true, k: 0 },
                                  "ODT document", { thumb: root.dir + "/office.png", path: root.dir + "/report.odt" })
                        tick.start()
                    }
                })
            }
        }
    }
}
