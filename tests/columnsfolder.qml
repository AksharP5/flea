//@ pragma ShellId flea-columnsfolder-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/PreviewSwap.js" as WorkCap
import "flea/js/Swap.js" as SwapCap

// Real ColumnsArea over a stub pane: unanswered folders hold data and the handed picture until landing or fallback, back reshows the file, and empty lands settled with no entrance.
ShellRoot {
    id: root

    Component {
        id: backendStub
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
            signal metaResult(var message)
            property int dirDev: 0
            property int metaSeq: 0
            property var peekLog: []
            function peek(path, size, hidden) { peekLog.push(String(path)) }
            function askMeta(index, wantLines, wantMedia, wantArchive) { metaSeq += 1; return metaSeq }
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe/studio"
            property var rows: []
            property int cursorIndex: 0
            property bool showHidden: false
            property int windowSize: 35
            property bool listInFlight: false
            property string listingState: "ready"
            property string searchMode: ""
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: ["text-x-generic", "image-x-generic"]
            property bool storageKnown: true
            property string storageClass: "local"
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
            function isSelected(index) { return false }
            function selectedIndices() { return [] }
            function selectionCount() { return 0 }
            function thumbFor(index) { return "" }
            function open(path) {}
            function openFile(path) {}
            function focusRequested() {}
        }
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend })
    property var failures: []

    // The area lives in a real window, so the swap's scheduled updates complete and every hold below is a frozen picture.
    FloatingWindow {
        implicitWidth: 1200
        implicitHeight: 600
        color: Flea.Theme.color.background

        Flea.ColumnsArea {
            id: area
            anchors.fill: parent
            pane: root.stubPane
            menu: menuStub.createObject(root)
        }
    }

    property var fileA: ({ n: "a.txt", d: false, k: 0, p: 420, s: 13, m: 7, t: false, i: "text-x-generic" })
    // Image rows with a thumbnail coming that never arrives stay unready, so a file hold outlives its own load.
    property var fileB: ({ n: "b.png", d: false, k: 1, p: 420, s: 15, m: 8, t: true, i: "image-x-generic" })
    property var fileC: ({ n: "c.png", d: false, k: 1, p: 420, s: 17, m: 24, t: true, i: "image-x-generic" })
    property var fileD: ({ n: "d.png", d: false, k: 1, p: 420, s: 19, m: 25, t: true, i: "image-x-generic" })
    property var folderSub: ({ n: "sub", d: true, k: 0, p: 493, s: 0, m: 9, t: false, i: "folder" })
    property var folderLate: ({ n: "late", d: true, k: 0, p: 493, s: 0, m: 11, t: false, i: "folder" })
    property var folderW1: ({ n: "w1", d: true, k: 0, p: 493, s: 0, m: 21, t: false, i: "folder" })
    property var folderW2: ({ n: "w2", d: true, k: 0, p: 493, s: 0, m: 22, t: false, i: "folder" })
    property var folderW3: ({ n: "w3", d: true, k: 0, p: 493, s: 0, m: 23, t: false, i: "folder" })
    property var kidRow: ({ n: "kid.txt", d: false, k: 0, p: 420, s: 1, m: 10, t: false, i: "text-x-generic" })

    function fail(text) { root.failures.push(text) }
    // The asked path follows the cursor folder, so phase b names a folder phase a never answered.
    function childPath() {
        var row = root.stubPane.rowFor(root.stubPane.cursorIndex)
        if (row && row.d === true) return root.stubPane.join(root.stubPane.path, row.n)
        return root.stubPane.join(root.stubPane.path, "sub")
    }
    function latePath() { return root.stubPane.join(root.stubPane.path, "late") }
    function swap() { return area.swapState() }
    function preview() { return area.previewColumn }

    // One peek answer on the real signal path, so onPeeked lands the waiting folder itself.
    function answerPeek(rows) {
        var path = root.childPath()
        root.stubBackend.peeked(path, false, rows.length, rows, false, 0, false, root.stubPane.windowSize)
    }

    // One meta answer for the file load in flight, so its hold lands instead of falling back.
    function answerMeta() {
        var token = root.preview().pendingToken
        if (!token) { root.fail("meta has no token to answer"); return }
        root.stubBackend.metaResult({ token: token, w: 0, h: 0, ms: 0, rate: 0, entries: 0,
            unpacked: 0, afailed: false, names: [], lines: 3, partial: false, lfailed: false,
            target: "", targetdir: "", owner: "", orient: 1 })
    }

    function assertIdle(label) {
        var s = root.swap()
        if (s.holding || s.capturing)
            root.fail(label + " leaves the third swap holding, want idle")
    }

    // The folder's wait keeps the live picture: the landing or the cap releases it with the folder.
    function assertHeld(label) {
        if (!root.swap().holding && !root.swap().capturing)
            root.fail(label + " leaves the third swap idle, want the live picture kept")
    }

    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.phaseNull()
    }
    Timer { id: answerEmptyTimer; interval: 300; repeat: false; onTriggered: root.phaseEmptyLands() }
    Timer { id: fileTimer; interval: 450; repeat: false; onTriggered: root.phaseFileMeta() }
    Timer { id: fileReadyTimer; interval: 400; repeat: false; onTriggered: root.phaseFileReady() }
    // A hold is proven by holding, which only captured() sets after a real scheduled update completes.
    Timer { id: holdPoll; interval: 20; repeat: true; property int polls: 0; onTriggered: root.pollHold() }
    Timer { id: cancelledTimer; interval: 120; repeat: false; onTriggered: root.phaseCancelled() }
    Timer { id: folderShownTimer; interval: 250; repeat: false; onTriggered: root.phaseFolderShown() }
    Timer { id: backMetaTimer; interval: 400; repeat: false; onTriggered: root.phaseBackMeta() }
    Timer { id: backReadyTimer; interval: 400; repeat: false; onTriggered: root.phaseBackReady() }
    Timer { id: wManualPoll; interval: 20; repeat: true; property int polls: 0; property bool seen: false; onTriggered: root.pollManual() }
    Timer { id: wLandTimer; interval: 40; repeat: false; onTriggered: root.phaseWLanded() }
    Timer { id: wBackTimer; repeat: false; onTriggered: root.phaseWBack() }
    Timer { id: wThirdTimer; interval: 70; repeat: false; onTriggered: root.phaseWThird() }
    // The check lands past the first move's deadline and before the restarted one, so start() standing in for restart() reddens.
    Timer { id: wKept2Timer; interval: SwapCap.HOLD_MS - wThirdTimer.interval + 30; repeat: false; onTriggered: root.phaseWKept2() }
    Timer { id: wFinalTimer; interval: SwapCap.HOLD_MS + 90; repeat: false; onTriggered: root.phaseWFinal() }

    // a) launch-shaped null first show, then the cursor lands on an unanswered folder.
    function phaseNull() {
        if (area.shownHasRow !== false)
            root.fail("a) a null first show holds a row, want none")
        if (root.preview().row !== null)
            root.fail("a) a null first show holds a preview, want none")
        root.assertIdle("a) a null first show")
        root.stubPane.rows = [root.folderSub]
        if (area.shownHasRow !== false)
            root.fail("a) an unanswered folder shows at once, want the old column kept")
        if (area.shownIsDir !== false)
            root.fail("a) an unanswered folder marks dir, want the old column kept")
        if (root.preview().row !== null)
            root.fail("a) an unanswered folder previews, want nothing held and nothing cleared")
        root.assertIdle("a) an unanswered folder wait")
        if (root.failures.length > 0) { root.report(); return }
        answerEmptyTimer.start()
    }

    // a) the peek lands: shown whole, never holding; d) the empty landing settles with no entrance.
    function phaseEmptyLands() {
        root.answerPeek([])
        if (area.shownIsDir !== true)
            root.fail("a) a landed peek keeps the old column, want the folder")
        if (area.shownChildPath !== root.childPath())
            root.fail("a) a landed peek shows " + area.shownChildPath + ", want " + root.childPath())
        root.assertIdle("a) a landed peek")
        var empty = area.childEmptyItem()
        if (!empty)
            root.fail("d) an empty folder draws no empty tile")
        else {
            if (empty.markItem.settled !== true)
                root.fail("d) a data-held empty landing runs its entrance, want it settled")
            if (empty.markItem.opacity !== 1)
                root.fail("d) a data-held empty landing marks at " + empty.markItem.opacity + ", want 1")
            if (empty.animateEntrance !== true)
                root.fail("d) a data-held empty landing leaves its entrance off")
        }
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.rows = [root.fileA, root.fileB, root.folderLate]
        root.stubPane.cursorIndex = 0
        fileTimer.start()
    }

    function phaseFileMeta() { root.answerMeta(); fileReadyTimer.start() }

    function phaseFileReady() {
        var preview = root.preview()
        if (!preview.row || preview.row.n !== "a.txt")
            root.fail("file setup loads a.txt, got " + (preview.row ? preview.row.n : "nothing"))
        if (area.shownIsDir !== false)
            root.fail("file setup shows a folder, want the file")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.cursorIndex = 1
        root.awaitHold()
    }

    // The next move starts only from a frozen picture, never from a capture still in flight.
    function awaitHold() { holdPoll.polls = 0; holdPoll.start() }
    function pollHold() {
        holdPoll.polls += 1
        if (root.swap().holding === true) { holdPoll.stop(); root.phaseLiveMove() }
        else if (holdPoll.polls > 100) { holdPoll.stop(); root.fail("no scheduled update completed for the file hold"); root.report() }
    }

    // The underlying row kept across an unanswered folder wait, pinned at the move: a slow first capture lets the file's settle load it before the picture freezes, and that advance is valid.
    property string keptName: ""
    function keepUnderlying() { var row = root.preview().row; root.keptName = row ? String(row.n) : "" }
    function keptUnderlying() { var row = root.preview().row; return row ? String(row.n) : "" }

    // b) a file move holds a live picture; j onto the folder hands that picture to the folder's wait.
    function phaseLiveMove() {
        root.keepUnderlying()
        // The tested folder is still unanswered, or the wait below is answered already.
        if (area.answered(root.latePath()) !== false)
            root.fail("b) late answers before the move, want it unanswered")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.cursorIndex = 2
        cancelledTimer.start()
    }

    function phaseCancelled() {
        root.assertHeld("b) j onto an unanswered folder")
        if (root.keptUnderlying() !== root.keptName)
            root.fail("b) j onto an unanswered folder shows " + root.keptUnderlying() + ", want " + root.keptName + " kept")
        if (area.shownIsDir !== false)
            root.fail("b) an unanswered folder shows at once, want the old column kept")
        if (area.answered(area.childPath) !== false)
            root.fail("b) the waiting folder answers before its peek, want it unanswered")
        if (root.failures.length > 0) { root.report(); return }
        root.answerPeek([root.kidRow])
        // The reply just sent is the delivery this phase waits for.
        if (area.answered(area.childPath) !== true)
            root.fail("b) a landed peek leaves late unanswered, want it answered")
        folderShownTimer.start()
    }

    function phaseFolderShown() {
        if (area.shownIsDir !== true)
            root.fail("b) a landed folder peek keeps the old column, want the folder")
        if (area.shownChildPath !== root.childPath())
            root.fail("b) a landed folder peek shows " + area.shownChildPath + ", want " + root.childPath())
        if (root.preview().visible !== false)
            root.fail("b) a landed folder keeps the preview visible, want it hidden")
        if (root.preview().row !== null)
            root.fail("b) a landed folder keeps its preview data, want the hidden preview cleared")
        root.assertIdle("b) a landed folder peek")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.cursorIndex = 0
        backMetaTimer.start()
    }

    function phaseBackMeta() { root.answerMeta(); backReadyTimer.start() }

    function phaseBackReady() {
        var preview = root.preview()
        if (!preview.row || preview.row.n !== "a.txt")
            root.fail("c) back on the file shows " + (preview.row ? preview.row.n : "nothing") + ", want a.txt")
        if (area.shownIsDir !== false)
            root.fail("c) back on the file keeps the folder, want the file")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.cursorIndex = 2
        root.stubPane.rows = [root.fileC, root.folderW1]
        root.stubPane.storageClass = "network"
        root.stubPane.cursorIndex = 0
        area.loadSelection()
        if (root.swap().capturing !== true) { root.fail("w25) Ctrl+Space starts no capture"); root.report(); return }
        root.stubPane.cursorIndex = 1
        wManualPoll.polls = 0
        wManualPoll.start()
    }

    // The manual frame stays ready across the cursor move, so aggregate ready is honestly true mid-wait.
    function pollManual() {
        wManualPoll.polls += 1
        var s = root.swap()
        if (s.holding === true) wManualPoll.seen = true
        if (wManualPoll.seen && s.holding !== true) { wManualPoll.stop(); root.fail("w25) manual wait released mid-wait"); root.report(); return }
        if (s.holding === true && area.folderWaiting === true && root.preview().ready === true) { wManualPoll.stop(); root.manualLanded(); return }
        if (wManualPoll.polls > 7) { wManualPoll.stop(); root.fail("w25) manual wait never formed"); root.report(); return }
    }

    function manualLanded() {
        var held = root.swap().holding === true
        var begun = root.preview().swap.started === true
        var manual = root.preview().manualHold === true
        var loaded = root.preview().loadedIndex
        var cursor = root.stubPane.cursorIndex
        console.log("COLUMNSFOLDER MANUAL loaded=" + loaded + " cursor=" + cursor + " ready=" + (root.preview().ready === true) + " waiting=" + (area.folderWaiting === true) + " manual=" + manual + " holding=" + held + " started=" + begun)
        if (!manual || !begun || !held || loaded !== 0 || cursor !== 1) { root.fail("w25) manual wait misformed"); root.report(); return }
        root.answerPeek([root.kidRow])
        wLandTimer.start()
    }

    // The landing releases the handed picture with the folder in one pass.
    function phaseWLanded() {
        if (area.shownIsDir !== true)
            root.fail("w25) a landed folder peek keeps the old column, want the folder")
        if (area.shownChildPath !== root.childPath())
            root.fail("w25) a landed folder peek shows " + area.shownChildPath + ", want " + root.childPath())
        var landed = area.rowsFor(area.shownChildPath)
        if (landed.length !== 1 || landed[0].n !== "kid.txt")
            root.fail("w25) a landed folder draws no peeked rows, want the answered folder")
        if (root.preview().visible !== false)
            root.fail("w25) a landed folder keeps the preview visible, want it hidden")
        if (root.preview().row !== null)
            root.fail("w25) a landed folder keeps its preview data, want the hidden preview cleared")
        root.assertIdle("w25) a landed folder peek")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.storageClass = "local"
        root.stubPane.rows = [root.fileC, root.fileD, root.folderW2, root.folderW3]
        root.stubPane.cursorIndex = 1
        wBackTimer.interval = root.stubPane.settleMs + WorkCap.capMs(false) - 60
        wBackTimer.start()
    }

    // A second file hold hands over to the first pending folder move.
    function phaseWBack() {
        if (root.swap().holding !== true) { root.fail("w25) no frozen picture before the second folder move"); root.report(); return }
        root.keepUnderlying()
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.cursorIndex = 2
        wThirdTimer.start()
    }

    // A second pending folder move restarts the bound instead of starving it.
    function phaseWThird() {
        root.assertHeld("w25) the first pending folder move")
        root.stubPane.cursorIndex = 3
        wKept2Timer.start()
    }

    // The old work cap fires inside this double wait on the pre-fix tree too.
    function phaseWKept2() {
        root.assertHeld("w25) the old work cap over two pending moves")
        if (area.shownIsDir !== false)
            root.fail("w25) a doubly waiting folder shows early, want the old column kept")
        if (root.failures.length > 0) { root.report(); return }
        wFinalTimer.start()
    }

    // The last move's own fallback shows it pending; the wait stays bounded.
    function phaseWFinal() {
        if (area.shownIsDir !== true)
            root.fail("w25) an unanswered double wait keeps the old column, want the pending folder")
        if (area.shownChildPath !== root.childPath())
            root.fail("w25) the fallback shows " + area.shownChildPath + ", want " + root.childPath())
        if (area.answered(area.childPath) !== false)
            root.fail("w25) the fallback wait answers without a peek, want it pending")
        if (root.preview().visible !== false)
            root.fail("w25) the fallback keeps the preview visible, want it hidden")
        if (root.preview().row !== null)
            root.fail("w25) the fallback keeps its preview data, want the hidden preview cleared")
        root.assertIdle("w25) an unanswered double wait")
        if (root.failures.length === 0)
            console.log("COLUMNSFOLDER PASS folder=data-held preview=kept file=reshown empty=settled w25=kept-landed-bounded")
        root.reportFailures()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNSFOLDER FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    function reportFailures() {
        if (root.failures.length === 0) {
            Quickshell.execDetached(["kill", String(Quickshell.processId)])
            return
        }
        root.report()
    }
}
