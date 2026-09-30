.pragma library
.import "Format.js" as Format

// Grid-only captions; GridTile loads this, Row and ColumnRow never do.
// Sample input: gridCaption("screenshot-2026-08-30-final-review-for-gm-after-the-bench-v3.png", 16, 2) answers "screenshot-2026-\n…he-bench-v3.png".

// A caption break stays behind a separator, so a word is never split when a break fits.
var CAPTION_BREAKS = " -_."

function isBreakAfter(ch) {
    return CAPTION_BREAKS.indexOf(ch) >= 0
}

// Cells of the caption's last line, so a mark sits past the glyphs it follows.
// Sample input: lastLineCells("ab\nc🎉") is 3.
function lastLineCells(text) {
    var s = String(text)
    if (Format.isFastText(s)) return s.length - s.lastIndexOf("\n") - 1
    return cellsOf(Format.charsOf(s.split("\n").pop()))
}

// The extension is the last dot's tail, so the last line can keep it whole; a leading dot names a dotfile, not an extension.
function extensionLength(chars) {
    var dot = -1
    for (var i = chars.length - 1; i > 0; i--) {
        if (chars[i] === ".") {
            dot = i
            break
        }
    }
    if (dot < 0 || dot === chars.length - 1)
        return 0
    return chars.length - dot
}

// Elides a char array down to this many cells, keeping a one-line extension whole on the tail.
function elideChars(chars, capacity, perLine) {
    return elideCore(Format.storeOf(chars), capacity, perLine)
}

// The head and tail an elide keeps: the head takes the odd cell, the tail keeps a one-line extension.
function elideSplit(capacity, ext, extCells, perLine) {
    var head = Math.ceil((capacity - 1) / 2), tail = Math.floor((capacity - 1) / 2)
    // An extension longer than one line, or with no room for the mark beside it, cannot stay whole.
    if (ext > 0 && extCells <= perLine && extCells + 1 <= capacity) {
        tail = Math.max(extCells, tail)
        head = capacity - 1 - tail
    }
    return [head, tail]
}

// One elide for both stores: elements for the wrap behind an array, pieces for the join behind a string.
function elideCore(st, capacity, perLine) {
    if (capacity <= 1) return ["…"]
    if (Format.rangeCells(st, 0, st.n) <= capacity) return st.widths === null ? [st.seq] : st.seq.slice(0)
    var ext = extensionLength(st.seq)
    var split = elideSplit(capacity, ext, ext > 0 ? Format.rangeCells(st, st.n - ext, st.n) : 0, perLine)
    var h = Format.spanFrom(st, 0, split[0]), t = Format.tailSpan(st, split[1])
    if (st.widths === null) return [Format.pieceOf(st, 0, h), "…", Format.pieceOf(st, st.n - t, st.n)]
    return st.seq.slice(0, h).concat(["…"], st.seq.slice(st.n - t))
}

// Wraps a char array into at most count lines of perLine cells, breaking after the last separator that still leaves the rest fitting.
function wrapChars(chars, perLine, count) {
    return wrapCore(Format.storeOf(chars), perLine, count)
}

// The break a line takes: the last separator whose rest still fits, the extension dot losing to any earlier one.
function breakCut(st, far, pos, left, perLine, extDot) {
    var cut = -1, extCut = -1
    for (var i = far - 1; i > pos; i--) {
        if (!isBreakAfter(st.seq[i]) || Format.rangeCells(st, i + 1, st.n) > (left - 1) * perLine) continue
        if (i === extDot) { extCut = i + 1; continue }
        cut = i + 1; break
    }
    return cut >= 0 ? cut : (extCut >= 0 ? extCut : far)
}

// One wrap for both stores: lines of pieces, every range counted once off the layout.
function wrapCore(st, perLine, count) {
    var out = [], pos = 0
    // The extension's own dot, so a break there never wins while an earlier separator fits.
    var extDot = st.n - extensionLength(st.seq)
    for (var ln = 0; ln < count && pos < st.n; ln++) {
        var left = count - ln
        if (Format.rangeCells(st, pos, st.n) <= perLine) { out.push(Format.pieceOf(st, pos, st.n)); break }
        if (ln === count - 1) { out.push(Format.pieceOf(st, pos, pos + Format.spanFrom(st, pos, perLine))); break }
        var far = pos + Format.spanFrom(st, pos, perLine)
        if (far <= pos) far = pos + 1
        var cut = breakCut(st, far, pos, left, perLine, extDot)
        out.push(Format.pieceOf(st, pos, cut))
        pos = cut
    }
    return out
}

// The caption Flea hands to Text already holds its line breaks, so Qt never wraps.
// Sample input: gridCaption("screenshot-2026-08-30-final-review-for-gm-after-the-bench-v3.png", 16, 2) answers "screenshot-2026-\n…he-bench-v3.png".
function gridCaption(name, perLine, lines) {
    var text = String(name), per = Math.floor(perLine), count = Math.floor(lines)
    // A dead or non-finite width budgets nothing: hand Qt the whole name and let ElideRight say so.
    if (!isFinite(per) || !isFinite(count) || !(per >= 1) || !(count >= 1)) return text
    // One scan serves the fit check and the store below, so a fitting fast name builds nothing.
    var isFast = Format.isFastText(text)
    var capacity = per * count
    // A fast name counts one cell a char, so one fitting line needs no elide and no wrap.
    // A one-cell caption still elides below, so the early return keeps that mark.
    if (isFast && capacity > 1 && text.length <= per) return text
    var st = isFast ? Format.fastStoreOf(text) : Format.storeOf(Format.charsOf(text))
    if (st.n === 0) return text
    // A wide glyph never straddles a line and wastes a cell, so elide until Flea's own wrap holds every char.
    if (st.widths === null) {
        var fast = elideCore(st, capacity, per).join("")
        while (capacity > 1 && wrapCore(Format.fastStoreOf(fast), per, count).join("") !== fast)
            fast = elideCore(st, --capacity, per).join("")
        return wrapCore(Format.fastStoreOf(fast), per, count).join("\n")
    }
    var shown = elideCore(st, capacity, per)
    while (capacity > 1 && wrapCore(Format.storeOf(shown), per, count).join("") !== shown.join(""))
        shown = elideCore(st, --capacity, per)
    return wrapCore(Format.storeOf(shown), per, count).join("\n")
}

// Array-cell helpers over the common store, kept beside the Grid fits that read them.
// Cells a char array paints.
function cellsOf(chars) {
    return Format.rangeCells(Format.storeOf(chars), 0, chars.length)
}

// A head that fits in this many cells, never splitting a code point.
function headByCells(chars, budget) {
    return chars.slice(0, Format.spanFrom(Format.storeOf(chars), 0, budget))
}

// A tail that fits in this many cells, never splitting a code point.
function tailByCells(chars, budget) {
    return chars.slice(chars.length - Format.tailSpan(Format.storeOf(chars), budget))
}
