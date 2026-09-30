//@ pragma ShellId flea-listnamebudget-test

import QtQuick
import Quickshell
import "flea" as Flea
// The same resolved URL ui/List.qml imports, so this is the list's own library instance and not a copy.
import "flea/js/ClipMarks.js" as ClipMarks
import "flea/js/TextSize.js" as TextSize

// w34 listnamebudget: a real ui/List.qml shares plain/clip budgets off exact drawn geometry with Picker/drop keeping local for the controller's offscreen run.
ShellRoot {
    id: root

    property var failures: []
    property int plainBefore: -99
    property real slotBefore: -1
    property int resizedBudget: -99

    property var sampleRows: [
        { n: "a.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "averylongfilenamethatgoesonandonandonandonandonandonandonandonandonandonandonandonandon.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "c.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "\uD83C\uDF89party.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 },
        { n: "link.txt", d: false, i: "text-x-generic", p: 511, s: 11, m: 1758835200, t: false, k: 0, v: 0, l: "/probe/target" },
        { n: "f.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 }
    ]
    property var copiedBoard: ({ paths: ["/probe/c.txt"], moving: false })
    property var emptyBoard: ({ paths: [], moving: false })

    Component {
        id: backendStub
        QtObject {
            function peek(path, size, hidden) {}
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
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 6
            property int total: 6
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property string searchMode: ""
            property string searchQuery: ""
            property string filterQuery: ""
            property var selectionBand: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property int visibleRows: 8
            property int cacheRows: 0
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
            function commitRename(newName) {}
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
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: root.sampleRows })

    Flea.List {
        id: list
        width: 700
        height: 300
        pane: root.stubPane
        menu: menuStub.createObject(root)
    }

    // Picker exception: no assigned budget, so it keeps local measured geometry.
    Flea.Row {
        id: pickerRow
        width: 700
        row: ({ n: "averylongfilenamethatgoesonandonandonandonandonandonandonandonandonandon.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
        kindNames: []
        hiddenCols: ["mode", "kind"]
        leadingSlot: 20
        clipMark: ""
    }

    // Drop exception: assigned is set, but the drop keeps local measured geometry with the label reserve.
    Flea.Row {
        id: dropRow
        width: 700
        row: ({ n: "averylongfilenamethatgoesonandonandonandonandonandonandonandonandonandon.txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
        kindNames: []
        hiddenCols: []
        clipMark: ""
        dropTarget: true
        assignedNameBudget: 999
    }

    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.phasePlain()
    }
    Timer { id: t1; interval: 600; repeat: false; onTriggered: root.phaseCopied() }
    Timer { id: t2; interval: 600; repeat: false; onTriggered: root.phaseResized() }
    Timer { id: t3; interval: 600; repeat: false; onTriggered: root.phaseDual() }
    Timer { id: t4; interval: 600; repeat: false; onTriggered: root.phaseHidden() }
    Timer { id: t5; interval: 600; repeat: false; onTriggered: root.phaseFilter() }
    Timer { id: t6; interval: 600; repeat: false; onTriggered: root.phaseFallback() }
    Timer { id: t7; interval: 600; repeat: false; onTriggered: root.phaseSearch() }

    function fail(text) { root.failures.push(text) }
    function delegateAt(i) { return list.itemAtIndex(i) }

    // One floor per List state, not per row: every ordinary delegate shares the same two budgets.
    function checkShared(label) {
        if (list.count !== root.sampleRows.length) {
            root.fail(label + " lists " + list.count + ", want " + root.sampleRows.length)
            return
        }
        var adv = Flea.Theme.bodyAdvance
        if (!(adv > 0)) { root.fail(label + " has no bodyAdvance"); return }
        // Pixel slots stay exact: plain less the clip reserve is the clip slot, floored only after.
        var wantClipPx = Math.max(0, list.nameSlotPlainPx - Flea.Theme.spacing.gap - list.listClipPx)
        if (Math.abs(wantClipPx - list.nameSlotClipPx) > 0.5)
            root.fail(label + " clip slot " + list.nameSlotClipPx + ", want " + wantClipPx)
        if (list.nameBudgetClip >= list.nameBudgetPlain)
            root.fail(label + " clip budget " + list.nameBudgetClip + ", want below plain " + list.nameBudgetPlain)
        for (var i = 0; i < root.sampleRows.length; i++) {
            var d = root.delegateAt(i)
            if (d === null) { root.fail(label + " builds no delegate at " + i); continue }
            if (d.dropTarget) continue
            // SOURCE PIN (branch): ordinary rows take the List-assigned branch, so the one floor lives in List alone.
            var want = d.clipMark.length > 0 ? list.nameBudgetClip : list.nameBudgetPlain
            if (d.assignedNameBudget !== want)
                root.fail(label + " row " + i + " assigns " + d.assignedNameBudget + ", want shared " + want)
            if (d.nameBudget !== want)
                root.fail(label + " row " + i + " budgets " + d.nameBudget + ", want shared " + want)
            // Shared budget matches the drawn name width, so a frozen width or a dropped reserve goes red.
            var w = d.nameItem().width
            var actual = w > 0 ? Math.floor(w / adv) : -1
            if (Math.abs(actual - d.nameBudget) > 1)
                root.fail(label + " row " + i + " draws " + w + "px for budget " + d.nameBudget + ", want " + actual)
            var slot = d.clipMark.length > 0 ? list.nameSlotClipPx : list.nameSlotPlainPx
            if (Math.abs(w - slot) > 2)
                root.fail(label + " row " + i + " draws " + w + "px, want slot " + slot)
        }
        // A long unmarked name pre-truncates; a marked run keeps full text with PlainText and wide glyphs intact.
        var longRow = root.delegateAt(1)
        if (longRow !== null && longRow.nameRun.start < 0 && longRow.elidedName.indexOf("…") < 0)
            root.fail(label + " long name draws full, want middle elide")
        var wideRow = root.delegateAt(3)
        if (wideRow !== null && wideRow.displayName !== "\uD83C\uDF89party.txt")
            root.fail(label + " wide glyph draws " + wideRow.displayName)
        var linkRow = root.delegateAt(4)
        if (linkRow !== null && linkRow.decoratedName !== "link.txt -> /probe/target")
            root.fail(label + " symlink draws " + linkRow.decoratedName)
    }

    function phasePlain() {
        checkShared("plain")
        if (root.failures.length > 0) { root.report(); return }
        root.plainBefore = list.nameBudgetPlain
        root.slotBefore = list.nameSlotPlainPx
        root.stubPane.clipboard = root.copiedBoard
        t1.start()
    }

    function phaseCopied() {
        checkShared("copied")
        var d = root.delegateAt(2)
        if (d !== null && d.clipMark !== "copy")
            root.fail("copied draws " + d.clipMark + " on c.txt, want copy")
        if (root.failures.length > 0) { root.report(); return }
        list.width = 400
        t2.start()
    }

    function phaseResized() {
        checkShared("resized")
        if (list.nameBudgetPlain === root.plainBefore)
            root.fail("resized keeps budget " + list.nameBudgetPlain + ", want a new one for width 400")
        if (root.failures.length > 0) { root.report(); return }
        root.resizedBudget = list.nameBudgetPlain
        list.width = 700
        root.stubPane.dualMode = true
        t3.start()
    }

    function phaseDual() {
        checkShared("dual")
        if (list.rowHiddenCols.indexOf("mode") < 0)
            root.fail("dual hides " + JSON.stringify(list.rowHiddenCols))
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.dualMode = false
        // Stored widths, hidden columns, tight density and pinned-20 text size still budget off exact drawn geometry.
        Flea.ViewState.state = { columns: ["name", "size"], columnWidths: { size: 200 }, density: "tight", display: { textSize: { mode: TextSize.nearest(20) } } }
        t4.start()
    }

    function phaseHidden() {
        if (Flea.Theme.baseSize !== 20)
            root.fail("sized draws baseSize " + Flea.Theme.baseSize + ", want pinned 20")
        if (Flea.ViewState.density !== "tight")
            root.fail("sized draws density " + Flea.ViewState.density + ", want tight")
        if (Flea.Theme.densityRatio !== 0)
            root.fail("sized draws densityRatio " + Flea.Theme.densityRatio + ", want 0")
        checkShared("hidden-density-textsize")
        if (root.failures.length > 0) { root.report(); return }
        Flea.ViewState.state = {}
        // Search draws its own loader off searchSlot, never the ordinary name (Row.qml:240,257,270); shared budgets stay supplied but undrawn.
        root.stubPane.searchMode = "files"
        root.stubPane.searchQuery = "avery"
        t7.start()
    }

    function phaseSearch() {
        var d = root.delegateAt(1)
        if (d === null || d.row === null)
            root.fail("search builds no delegate for the long row")
        else {
            if (d.searching !== true)
                root.fail("search leaves the ordinary row standing on " + d.displayName)
            if (d.nameItem().visible !== false)
                root.fail("search still draws the ordinary name on " + d.displayName)
            if (!(d.nameRun.start >= 0))
                root.fail("search marks no run on " + d.displayName)
            if (d.elidedName !== d.decoratedName)
                root.fail("search elides a marked run, want full " + d.decoratedName)
            if (!(d.searchSlot > 0))
                root.fail("search holds no slot of its own on " + d.displayName)
        }
        for (var i = 0; i < root.sampleRows.length; i++) {
            var o = root.delegateAt(i)
            if (o === null || o.row === null) continue
            if (o.searching !== true)
                root.fail("search leaves row " + i + " ordinary")
            if (o.nameItem().visible !== false)
                root.fail("search draws the ordinary name on row " + i)
        }
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.searchMode = ""
        root.stubPane.searchQuery = ""
        // Filter keeps its run: a marked long name stays whole instead of eliding.
        root.stubPane.filterQuery = "averylong"
        root.stubPane.shown = [1]
        t5.start()
    }

    function phaseFilter() {
        var d = root.delegateAt(0)
        if (d === null || d.row === null || d.row.n.indexOf("averylong") !== 0)
            root.fail("filter draws " + (d && d.row ? d.row.n : "nothing") + ", want the long row")
        else {
            if (!(d.nameRun.start >= 0))
                root.fail("filter marks no run on " + d.displayName)
            if (d.elidedName !== d.decoratedName)
                root.fail("filter elides a marked run, want full " + d.decoratedName)
        }
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.filterQuery = ""
        root.stubPane.shown = null
        t6.start()
    }

    function phaseFallback() {
        checkShared("restored")
        // Picker keeps local geometry: no assignment, so the budget is the measured one.
        if (pickerRow.assignedNameBudget !== -2)
            root.fail("picker assigns " + pickerRow.assignedNameBudget + ", want local -2")
        if (pickerRow.nameBudget !== pickerRow.localNameBudget())
            root.fail("picker budgets " + pickerRow.nameBudget + ", want local " + pickerRow.localNameBudget())
        // Drop keeps local measured geometry even with an assigned budget standing by.
        if (dropRow.nameBudget !== dropRow.localNameBudget())
            root.fail("drop budgets " + dropRow.nameBudget + ", want local " + dropRow.localNameBudget())
        if (!dropRow.dropBuilt())
            root.fail("drop builds no frame for its fallback")
        if (root.failures.length === 0)
            console.log("LISTNAMEBUDGET PASS rows=" + root.sampleRows.length + " plain=" + root.plainBefore + " resized=" + root.resizedBudget)
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("LISTNAMEBUDGET FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
