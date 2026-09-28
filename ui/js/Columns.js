.pragma library

// Which columns a list row of a given width draws. The name is the one column a file manager
// cannot do without, so it is the one that never loses: each metadata column drops instead, at
// the width where keeping it would push the name under its floor. ui/Header.qml and ui/Row.qml
// both resolve their set here, from the same width, so the header can never head a column the
// rows below it are not drawing.

// The optional columns, widest first, which is the order they drop in. Kind goes first: the row
// already marks its kind with a glyph and most names carry the extension, so it is the most
// redundant column as well as the widest. Mode goes last, because it is the permanent column.
var DROP_ORDER = ["kind", "date", "size", "mode"]

// The row width each optional column needs before it is drawn, keyed by column. t carries the
// tokens ui/Theme.qml resolved: rowPaddingX, gap, iconSize, nameMin, and one width per column.
// A floor includes every column that outlives it, because they drop in order and a wider column
// never survives a narrower one, which is what makes the four floors nest.
function floors(t) {
    // The name's own slot at its floor: the row padding either side, the mark and the gap after it.
    var running = t.rowPaddingX + t.iconSize + t.gap + t.nameMin + t.rowPaddingX
    var out = {}
    for (var i = DROP_ORDER.length - 1; i >= 0; i--) {
        var key = DROP_ORDER[i]
        running += t[key] + t.gap
        out[key] = running
    }
    return out
}

// One boolean per optional column, for a row of this width. hidden is the user's own set (keys
// "mode"/"size"/"date"/"kind", from qs module ViewState), subtracted from what the width
// affords: a hidden column never draws, and width still wins over a column the user wants back,
// so the name cannot be crowded out by a column the pane is too narrow to carry.
function set(width, t, hidden) {
    var f = floors(t)
    var h = {}
    var list = hidden || []
    for (var i = 0; i < list.length; i++) h[list[i]] = true
    return {
        mode: width >= f.mode && !h["mode"],
        size: width >= f.size && !h["size"],
        date: width >= f.date && !h["date"],
        kind: width >= f.kind && !h["kind"]
    }
}

// DualPane protects its name floor without reserving absent Mode and Kind columns.
function dualSet(width, t, hidden) {
    var base = 2 * t.rowPaddingX + t.iconSize + t.gap + t.nameMin
    var showSize = (hidden || []).indexOf("size") < 0 && width >= base + t.size
    var showDate = (hidden || []).indexOf("date") < 0
        && width >= base + (showSize ? t.size : 0) + t.date
    return {mode: false, kind: false, size: showSize, date: showDate}
}

// A peeked reply is keyed by what ordered it, so a stale ancestor column never survives the hidden-last toggle: path plus hidden plus hiddenLast.
// Sample input: peekKey("/a", true, true) is "/a\n11".
function peekKey(path, hidden, hiddenLast) {
    return String(path) + "\n" + (hidden === true ? "1" : "0") + (hiddenLast === true ? "1" : "0")
}

// An ask this view made and still awaits, keyed by peekKey, so a reply another client asked for never lands in its column.
// Sample input: trackAsk({}, "/a\n10") holds that key.
function trackAsk(pending, key) {
    var next = {}
    var src = pending || {}
    for (var k in src) next[k] = true
    next[String(key)] = true
    return next
}

// True only for a reply this view asked for; anything else is another client's.
// Sample input: hasAsk(trackAsk({}, "/a\n10"), "/a\n10") is true.
function hasAsk(pending, key) {
    return !!((pending || {})[String(key)])
}

// One ask answered or superseded; a new listing drops them all.
// Sample input: dropAsk(trackAsk({}, "/a\n10"), "/a\n10") holds nothing.
function dropAsk(pending, key) {
    var next = {}
    var want = String(key)
    var src = pending || {}
    for (var k in src) if (k !== want) next[k] = true
    return next
}

// The columns view's count follows the window width, capped by Settings View's limit.
// Sample input: (899, 5) answers 2.
var COUNT_4_AT = 1700
var COUNT_5_AT = 2300
var COUNT_NARROW_AT = 900
var COUNT_MIN = 2
var COUNT_MAX = 5

// A stored number clamps to 2 to 5, anything else reads as the shipped 5.
function cappedLimit(limit) {
    if (typeof limit !== "number")
        return COUNT_MAX
    var n = Math.floor(limit)
    if (!(n >= COUNT_MIN) && !(n <= COUNT_MAX))
        return COUNT_MAX
    if (n < COUNT_MIN)
        return COUNT_MIN
    if (n > COUNT_MAX)
        return COUNT_MAX
    return n
}

// One integer for a window of this width, never above the limit. Resizing re-lays the
// columns in one frame and re-reads nothing: the listing is untouched, only ancestors peek.
function columnCountForWidth(width, limit) {
    var count = width < COUNT_NARROW_AT ? 2 : width < COUNT_4_AT ? 3
        : width < COUNT_5_AT ? 4 : 5
    var cap = cappedLimit(limit)
    if (count > cap)
        count = cap
    if (count < COUNT_MIN)
        count = COUNT_MIN
    return count
}

// Extra columns are ancestors, read with the same viewport-scoped peek as the parent today.
function ancestorsForCount(count) {
    var n = Math.floor(Number(count))
    if (!(n >= COUNT_MIN))
        return 0
    return Math.min(n, COUNT_MAX) - 2
}

// ui.json carries whatever a hand edit wrote, so only a finite number is a stored width; anything else keeps the measured one.
// Sample input: storedNumber("120") is NaN, storedNumber(120.6) is 121.
function storedNumber(raw) {
    if (typeof raw !== "number" || !isFinite(raw) || raw < 0)
        return NaN
    return Math.round(raw)
}

// ListColumns040 board: a dragged edge clamps to the rails, and a double click fits the
// widest value the window holds, never a directory-wide scan. Sample input: 9999 clamps.
var MIN_LIST_WIDTH = 48
var MAX_LIST_WIDTH = 480

// One whole pixel inside the rails, whatever the drag handed in.
function clampListWidth(px) {
    var n = Math.round(Number(px))
    if (!(n >= 0))
        return MIN_LIST_WIDTH
    if (n < MIN_LIST_WIDTH)
        return MIN_LIST_WIDTH
    if (n > MAX_LIST_WIDTH)
        return MAX_LIST_WIDTH
    return n
}

// The widest held cell, clamped; an empty window keeps the column it has, so a fit can narrow as well as widen.
function autofitWidth(widths, fallback) {
    var cells = widths || []
    if (cells.length === 0)
        return clampListWidth(fallback)
    var best = MIN_LIST_WIDTH
    for (var i = 0; i < cells.length; i++) {
        var w = Math.round(Number(cells[i]))
        if (w >= 0 && w > best)
            best = w
    }
    return clampListWidth(best)
}

function names(s) {
    var out = ["name"]
    for (var i = DROP_ORDER.length - 1; i >= 0; i--) {
        var key = DROP_ORDER[i]
        if (s[key])
            out.push(key)
    }
    return out.join(",")
}
