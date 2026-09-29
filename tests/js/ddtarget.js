.import "../../ui/js/Selection.js" as Selection
.import "../../ui/js/Filter.js" as Filter
.import "../../ui/js/Marks.js" as Marks
.import "../../ui/js/Focus.js" as Focus
.import "../../ui/js/Grid.js" as Grid
.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/Ops.js" as Ops
.import "../../ui/js/Tap.js" as Tap
.import "../../ui/js/Anchor.js" as Anchor
.import "../../ui/js/Tabs.js" as Tabs
.import "../../ui/js/PreviewKeys.js" as PreviewKeys

// A lone selection the pane made follows a plain move so dd trashes the cursor row; its pane mirrors ui/Pane.qml and moves go through Tap, Focus.act or Grid.arrow, and Ops.trash.
function pane(rows, viewMode, stride) {
    var p = {
        rows: rows, held: 0, total: rows.length, shown: null, shownTotal: rows.length,
        cursorIndex: 0, viewMode: viewMode || "list", cursorStride: stride || 1,
        visibleRows: 10, wrapAtEnds: false, filterQuery: "", filterTyping: false,
        searchMode: "", searchFrom: "", selectionAnchor: 0, selectionVersion: 0, path: "/d",
        kindNames: [], trashedFirst: -1, sent: [], asked: null, askLog: [], moved: null,
        pendingSelect: "", pendingMenu: false, history: [], forwardHistory: [],
        showHidden: false, home: "/home", windowSize: 50, listInFlight: false, openedPath: ""
    }
    p.selection = Selection.create()
    p.rowFor = function (i) { return i < 0 || i >= p.rows.length ? null : p.rows[i] }
    p.showRow = function () {}
    p.setCursor = function (i) { p.cursorIndex = i }
    p.join = function (dir, name) { return dir + "/" + name }
    p.selectedIndices = function () { return p.selection.indices() }
    p.selectOnly = function (i) {
        p.setCursor(i)
        p.selection.only(p.cursorIndex)
        p.selectionAnchor = p.cursorIndex
        p.selectionVersion++
    }
    p.toggleSelect = function () { Marks.toggleSelect(p) }
    p.clearSelection = function () { p.selection.clear(); p.selectionVersion++ }
    p.commitOpenRename = function () {}
    p.act = function () {}
    p.message = function () {}
    p.openWithoutHistory = function (path, opts) { p.openedPath = path }
    p.preview = { revealStrip: function () {}, follow: function () {} }
    p.collide = { ask: function (req) { p.moved = req } }
    p.clipboard = { paths: [], moving: false }
    p.clipPending = null
    p.pathsPending = null
    p.backend = {
        trash: function (idx, menuId) { p.trashedFirst = idx[0]; p.sent.push("trash " + idx.join(",")) },
        askPaths: function (idx) { p.askLog.push(idx.slice()); p.asked = idx.slice() },
        window: function (start, size) {},
        sortBy: "", sortDesc: false, listRequests: 0, dirDev: 0
    }
    return p
}

function files(n) {
    var out = []
    for (var i = 0; i < n; i++) out.push({ n: "f" + i + ".txt", d: false, i: "text" })
    return out
}

function run(check, label) {
    var none = Qt.NoModifier
    function down(p) { Focus.act("cursorDown", p) }

    // List: click f0, Down, dd sends trash 1.
    var list = pane(files(6))
    Tap.tapped(0, 1, none, list)
    down(list)
    Ops.trash(list)
    check(label + " list: click+Down+dd trashes the cursor row f1",
        list.sent.join(";"), "trash 1")

    // Grid: tap tile 0, Down, dd sends trash 3.
    var grid = pane(files(9), "grid", 3)
    Tap.tapped(0, 1, none, grid)
    Grid.arrow({ key: Qt.Key_Down, text: "" }, "cursorDown", grid)
    Ops.trash(grid)
    check(label + " grid: tap+Down+dd trashes the tile below", grid.sent.join(";"), "trash 3")

    // Columns middle: tap, j, dd sends trash 1.
    var mid = pane([{ n: "dir", d: true }, { n: "f1.txt", d: false }])
    Tap.tappedMiddle(0, 1, none, mid)
    down(mid)
    Ops.trash(mid)
    check(label + " columns: tap+j+dd trashes the cursor row", mid.sent.join(";"), "trash 1")

    // A trash lands through Anchor.afterDelete, so dd-j-dd takes each cursor row in turn.
    var twice = pane(files(6))
    twice.setCursor(2)
    Ops.trash(twice)
    twice.sent = []
    twice.clearSelection()
    var anchor = Anchor.afterDelete(twice, true)
    Anchor.apply(twice, anchor)
    check(label + " landing selects its row as lone", twice.selectedIndices().join(",") + "|" + twice.selection.follows(), "2|true")
    down(twice)
    Ops.trash(twice)
    check(label + " dd-j-dd trashes the row the cursor moved to", twice.sent.join(";"), "trash 3")

    // h to the parent re-selects the directory left, so h-j-dd trashes the cursor row.
    var up = pane(files(6))
    up.pendingSelect = "/d/f2.txt"
    Nav.applyPendingSelect(up)
    down(up)
    Ops.trash(up)
    check(label + " h-j-dd trashes the cursor row", up.sent.join(";"), "trash 3")

    // Quick Look j moves the cursor the same way, so dd after it trashes the cursor row.
    var look = pane(files(6))
    Tap.tapped(0, 1, none, look)
    PreviewKeys.act("cursorDown", look)
    Ops.trash(look)
    check(label + " Quick Look j then dd trashes the cursor row", look.sent.join(";"), "trash 1")

    // v on a lone following row promotes it, so tap-j-v-j-v gives 1,2.
    var vv = pane(files(6))
    Tap.tapped(0, 1, none, vv)
    down(vv)
    vv.toggleSelect()
    check(label + " v on the lone row keeps it", vv.selectedIndices().join(","), "1")
    check(label + " v promotes lone to deliberate", vv.selection.follows(), false)
    down(vv)
    vv.toggleSelect()
    check(label + " tap-j-v-j-v gives 1,2", vv.selectedIndices().join(","), "1,2")
    var ctl = pane(files(6))
    Tap.tapped(0, 1, none, ctl)
    Marks.toggleRow(ctl, 0)
    check(label + " ctrl+click on the lone row empties it", ctl.selectedIndices().join(","), "")

    // Every production route names the cursor row after click+Down.
    var mixed = pane(files(6))
    Tap.tapped(0, 1, none, mixed)
    down(mixed)
    check(label + " the mixed list targets the cursor row", Ops.targetIndices(mixed).join(","), "1")
    mixed.sent = []
    Ops.trash(mixed)
    check(label + " trash names the cursor row", mixed.sent.join(";"), "trash 1")
    mixed.clipPending = null
    mixed.askLog = []
    Ops.clip(mixed, false, null)
    check(label + " copy asks for the cursor row", mixed.askLog.map(function (a) { return a.join(",") }).join(";"), "1")
    mixed.clipPending = null
    mixed.askLog = []
    Ops.clip(mixed, true, null)
    check(label + " cut asks for the cursor row", mixed.askLog.map(function (a) { return a.join(",") }).join(";"), "1")
    mixed.pathsPending = null
    mixed.askLog = []
    Ops.compress(mixed, "zip")
    check(label + " compress asks for the cursor row", mixed.askLog.map(function (a) { return a.join(",") }).join(";"), "1")
    mixed.moved = null
    Ops.moveToDropbox(mixed, "/drop", 0)
    check(label + " Move to Dropbox names the cursor row", mixed.moved.rows.join(","), "1")
    check(label + " Move to Dropbox keeps its destination", mixed.moved.dest, "/drop")

    // A tab switch restores the lone row as lone, so Down+dd still trash the cursor.
    var tabSrc = pane(files(6))
    Tap.tapped(0, 1, none, tabSrc)
    var snap = Tabs.snapshot(tabSrc)
    check(label + " snapshot keeps the lone row", snap.selected.join(","), "0")
    check(label + " snapshot keeps follows", snap.follows, true)
    var tabDst = pane(files(6))
    Tabs.restoreSelection(tabDst, snap.selected, snap.follows)
    check(label + " restore keeps the lone row", tabDst.selectedIndices().join(","), "0")
    check(label + " restore keeps follows", tabDst.selection.follows(), true)
    down(tabDst)
    Ops.trash(tabDst)
    check(label + " tab-switch click Down dd trashes the cursor row", tabDst.sent.join(";"), "trash 1")

    // A lone row follows a plain move under a filter, so dd trashes the drawn cursor row; shown [1,2] tells a view index from a row index, since a follow naming the view would select 1.
    var filt = pane([{ n: "b.txt", d: false }, { n: "aa.txt", d: false }, { n: "ab.txt", d: false }])
    filt.filterQuery = "a"
    filt.shown = Filter.shown(filt.rows, filt.held, filt.filterQuery)
    filt.shownTotal = filt.shown.length
    Tap.tapped(1, 1, none, filt)
    down(filt)
    check(label + " filtered follow selects the drawn cursor row", filt.selectedIndices().join(","), "2")
    Ops.trash(filt)
    check(label + " filtered tap-j-dd trashes the drawn cursor row", filt.sent.join(";"), "trash 2")

    // The follow shape: f1 selected after the move, and deliberate marks still span.
    var shape = pane(files(6))
    Tap.tapped(0, 1, none, shape)
    down(shape)
    check(label + " f1 is selected after the move", shape.selectedIndices().join(","), "1")
    Marks.extend(shape, 1)
    check(label + " Shift+J then gives 1,2", shape.selectedIndices().join(","), "1,2")
    Marks.toggleRow(shape, 3)
    check(label + " ctrl+click f3 gives 1,2,3", shape.selectedIndices().join(","), "1,2,3")
    var carried = pane(files(6))
    carried.selectOnly(0)
    Focus.act("cursorLast", carried)
    check(label + " G carries the lone row to the end",
        carried.cursorIndex + "|" + carried.selectedIndices().join(","), "5|5")

    // Green controls: deliberate marks stay targets across a plain move, and none means the cursor.
    var marked = pane(files(6))
    marked.setCursor(0)
    marked.toggleSelect()
    down(marked)
    Ops.trash(marked)
    check(label + " a v mark stays at 0 across Down", marked.sent.join(";"), "trash 0")
    var block = pane(files(6))
    block.setCursor(1)
    Marks.extend(block, 1)
    down(block)
    Ops.trash(block)
    check(label + " a Shift+J block stays across Down", block.sent.join(";"), "trash 1,2")
    var ctrl = pane(files(6))
    ctrl.selection.toggle(0)
    ctrl.selection.toggle(2)
    ctrl.setCursor(0)
    down(ctrl)
    Ops.trash(ctrl)
    check(label + " a ctrl set stays across Down", ctrl.sent.join(";"), "trash 0,2")
    var bare = pane(files(6))
    bare.setCursor(1)
    down(bare)
    Ops.trash(bare)
    check(label + " with no selection dd trashes the cursor row", bare.sent.join(";"), "trash 2")
}
