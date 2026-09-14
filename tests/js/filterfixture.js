.pragma library

.import "../../ui/js/Filter.js" as Filter

// The filter narrows the listing already on screen, so every check here is pure or takes a stub
// pane: one that needed a live listing would be checking the wrong feature.

// Directories first is not optional, so the fixture is already in the order the backend produces:
// directories, then files, each run name ascending. Screens is capitalised on purpose.
//   0 Screens  1 scripts  2 tools  3 notes.md  4 readme.txt  5 screenrecording  6 screenshot
function listing() {
    return [
        { n: "Screens", d: true },
        { n: "scripts", d: true },
        { n: "tools", d: true },
        { n: "notes.md", d: false },
        { n: "readme.txt", d: false },
        { n: "screenrecording-2026-08-21.mp4", d: false },
        { n: "screenshot-2026-08-30.png", d: false }
    ]
}

// The same seven reversed the way the backend really returns them: directories still lead, each
// run reversed inside itself (docs/protocol.md, "sort").
//   0 tools  1 scripts  2 Screens  3 screenshot  4 screenrecording  5 readme.txt  6 notes.md
function reversed() {
    return [
        { n: "tools", d: true },
        { n: "scripts", d: true },
        { n: "Screens", d: true },
        { n: "screenshot-2026-08-30.png", d: false },
        { n: "screenrecording-2026-08-21.mp4", d: false },
        { n: "readme.txt", d: false },
        { n: "notes.md", d: false }
    ]
}

// Only the members the filter path touches. showRow records the view position it was asked for,
// because that scroll is the one thing ui/js/Filter.js hands back to ui/Pane.qml.
function pane(query, held) {
    var p = {
        rows: listing(),
        held: held === undefined ? 0 : held,
        total: 7,
        cursorIndex: 0,
        filterQuery: query === undefined ? "" : query,
        filterTyping: false,
        selectionVersion: 0,
        selectionAnchor: 0,
        scrolled: -1,
        picked: {}
    }
    // ui/Pane.qml's own: the window starts at held, and an index outside it has no row at all.
    p.rowFor = function (index) {
        var offset = index - p.held
        return offset < 0 || offset >= p.rows.length ? null : p.rows[offset]
    }
    p.showRow = function (view) { p.scrolled = view }
    p.selection = {
        count: function () { return p.selectedIndices().length },
        toggle: function (i) { if (p.picked[i]) delete p.picked[i]; else p.picked[i] = true },
        clear: function () { p.picked = {} },
        all: function (n) { p.picked = {}; for (var i = 0; i < n; i++) p.picked[i] = true },
        extendTo: function (i, anchor) {
            p.picked = {}
            for (var r = Math.min(i, anchor); r <= Math.max(i, anchor); r++) p.picked[r] = true
        }
    }
    p.selectedIndices = function () {
        var out = []
        for (var k in p.picked) out.push(Number(k))
        out.sort(function (a, b) { return a - b })
        return out
    }
    // The two ui/Pane.qml computes as bindings, recomputed here so a stub can never go stale.
    p.refresh = function () {
        p.shown = Filter.shown(p.rows, p.held, p.filterQuery)
        p.shownTotal = p.shown === null ? p.total : p.shown.length
    }
    p.refresh()
    return p
}

function typeInto(p, text) {
    for (var i = 0; i < text.length; i++) {
        Filter.typed(p, text.charAt(i))
        p.refresh()
    }
}

// Names the match list resolves to, so a check reads what is drawn and never an index.
function nameIn(rows) {
    return function (i) { return rows[i] === undefined ? "?" : rows[i].n }
}

function picks(p) {
    return p.selectedIndices().join(",")
}

