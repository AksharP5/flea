.pragma library

// Elides in the middle so the extension stays visible; truncation costs a slice, never a relayout.
// Sample input: "screenshot-2026-08-30-final-review-for-gm-after-the-bench-v3.png", 49.

// The walk pairs surrogates by hand, so a cut never splits a code point.
function charsOf(text) {
    var out = []
    for (var i = 0; i < text.length; i++) {
        var lead = text.charCodeAt(i)
        if (lead >= 0xD800 && lead <= 0xDBFF && i + 1 < text.length) {
            var trail = text.charCodeAt(i + 1)
            if (trail >= 0xDC00 && trail <= 0xDFFF) {
                out.push(text.substring(i, i + 2))
                i += 1
                continue
            }
        }
        // A combining mark rides with the char before it, so an NFD accent never orphans.
        if (lead >= 0x0300 && lead <= 0x036F && out.length > 0) {
            out[out.length - 1] += text.charAt(i)
            continue
        }
        out.push(text.charAt(i))
    }
    return out
}

// Every fast unit sits below U+0300, so a fast name holds no surrogate, no combining mark and no wide glyph.
var FAST_LIMIT = 0x0300

// True when every UTF-16 unit is fast: each char paints one cell and slices never split a point.
function isFastText(text) {
    for (var i = 0; i < text.length; i++)
        if (text.charCodeAt(i) >= FAST_LIMIT) return false
    return true
}

function middleElide(name, maxCells) {
    var text = String(name), max = Math.max(0, Math.floor(maxCells))
    // A non-finite budget names no width, so the name goes through untouched.
    if (!isFinite(max)) return text
    // One scan serves the fit check and the store below, so a fitting fast name builds nothing.
    var fast = isFastText(text)
    // A fast name counts one cell a char, so a short one already fits untouched.
    if (fast && text.length <= max) return text
    var st = fast ? fastStoreOf(text) : storeOf(charsOf(text))
    if (rangeCells(st, 0, st.n) <= max) return text
    // The head takes the odd cell, so a 49-wide board keeps 24 and 24.
    var h = spanFrom(st, 0, Math.ceil((max - 1) / 2)), t = tailSpan(st, Math.floor((max - 1) / 2))
    return pieceOf(st, 0, h) + "…" + pieceOf(st, st.n - t, st.n)
}

// Display cells: East Asian Wide and Fullwidth paint two columns, emoji paint two, all else one.
// Sample input: cellWidthOf("🎉") is 2, cellWidthOf("A") is 1.
var WIDE_RANGES = [[0x1100, 0x115F], [0x2E80, 0x303E], [0x3041, 0x33FF], [0x3400, 0x4DBF], [0x4E00, 0xA4CF], [0xAC00, 0xD7A3], [0xF900, 0xFAFF], [0xFE10, 0xFE19], [0xFE30, 0xFE4F], [0xFF00, 0xFF60], [0xFFE0, 0xFFE6], [0x20000, 0x3FFFD]]
var EMOJI_RANGES = [[0x2600, 0x26FF], [0x2700, 0x27BF], [0x2B00, 0x2BFF], [0x1F000, 0x1FAFF]]

// True when a code point paints two columns rather than one.
function isWideCode(cp) {
    // Every wide range starts at U+1100, so a smaller code point never scans.
    if (cp < 0x1100) return false
    for (var i = 0; i < WIDE_RANGES.length; i++)
        if (cp >= WIDE_RANGES[i][0] && cp <= WIDE_RANGES[i][1]) return true
    for (var j = 0; j < EMOJI_RANGES.length; j++)
        if (cp >= EMOJI_RANGES[j][0] && cp <= EMOJI_RANGES[j][1]) return true
    return false
}

// The code point one charsOf element starts with, read without wrapping it in a string.
// Sample input: codeOf("🎉") is 0x1F389, codeOf("A") is 0x41.
function codeOf(ch) {
    var s = String(ch), lead = s.charCodeAt(0)
    if (lead >= 0xD800 && lead <= 0xDBFF && s.length > 1) {
        var trail = s.charCodeAt(1)
        if (trail >= 0xDC00 && trail <= 0xDFFF) return 0x10000 + ((lead - 0xD800) << 10) + (trail - 0xDC00)
    }
    return lead
}

// Cells one char paints: 2 for a wide code point, 1 for all else.
function cellWidthOf(ch) {
    return isWideCode(codeOf(ch)) ? 2 : 1
}

// One layout per call: widths plus prefix sums, so every range below is one subtraction.
// Sample input: storeOf(["a", "🎉"]) carries widths [1, 2].
function storeOf(chars) {
    var widths = new Array(chars.length), prefix = new Array(chars.length + 1)
    prefix[0] = 0
    for (var i = 0; i < chars.length; i++) {
        widths[i] = isWideCode(codeOf(chars[i])) ? 2 : 1
        prefix[i + 1] = prefix[i] + widths[i]
    }
    return { seq: chars, widths: widths, prefix: prefix, n: chars.length }
}

// The same layout over a fast string: no arrays, every range counts chars as cells.
function fastStoreOf(text) {
    return { seq: text, widths: null, prefix: null, n: text.length }
}

// Cells of elements [a..b).
function rangeCells(st, a, b) {
    return st.widths === null ? b - a : st.prefix[b] - st.prefix[a]
}

// Elements from pos fitting in this many cells.
function spanFrom(st, pos, budget) {
    if (st.widths === null) return Math.min(Math.max(budget, 0), st.n - pos)
    var used = 0, i = pos
    while (i < st.widths.length && used + st.widths[i] <= budget) { used += st.widths[i]; i += 1 }
    return i - pos
}

// Trailing elements fitting in this many cells.
function tailSpan(st, budget) {
    if (st.widths === null) return Math.min(Math.max(budget, 0), st.n)
    var used = 0, i = st.widths.length
    while (i > 0 && used + st.widths[i - 1] <= budget) { used += st.widths[i - 1]; i -= 1 }
    return st.widths.length - i
}

// Text of elements [a..b): a slice for a fast string, a join for a char array.
function pieceOf(st, a, b) {
    return st.widths === null ? st.seq.slice(a, b) : st.seq.slice(a, b).join("")
}

// Cells a char array paints.
function cellsOf(chars) {
    return rangeCells(storeOf(chars), 0, chars.length)
}

// A head that fits in this many cells, never splitting a code point.
function headByCells(chars, budget) {
    return chars.slice(0, spanFrom(storeOf(chars), 0, budget))
}

// A tail that fits in this many cells, never splitting a code point.
function tailByCells(chars, budget) {
    return chars.slice(chars.length - tailSpan(storeOf(chars), budget))
}
