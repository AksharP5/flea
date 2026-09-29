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
    var st = isFastText(text) ? fastStoreOf(text) : storeOf(charsOf(text))
    if (rangeCells(st, 0, st.n) <= max) return text
    // The head takes the odd cell, so a 49-wide board keeps 24 and 24.
    var h = spanFrom(st, 0, Math.ceil((max - 1) / 2)), t = tailSpan(st, Math.floor((max - 1) / 2))
    return pieceOf(st, 0, h) + "…" + pieceOf(st, st.n - t, st.n)
}

// A caption break stays behind a separator, so a word is never split when a break fits.
var CAPTION_BREAKS = " -_."

// Display cells: East Asian Wide and Fullwidth paint two columns, emoji paint two, all else one.
// Sample input: cellWidthOf("🎉") is 2, cellWidthOf("A") is 1.
var WIDE_RANGES = [[0x1100, 0x115F], [0x2E80, 0x303E], [0x3041, 0x33FF], [0x3400, 0x4DBF], [0x4E00, 0xA4CF], [0xAC00, 0xD7A3], [0xF900, 0xFAFF], [0xFE10, 0xFE19], [0xFE30, 0xFE4F], [0xFF00, 0xFF60], [0xFFE0, 0xFFE6], [0x20000, 0x3FFFD]]
var EMOJI_RANGES = [[0x2600, 0x26FF], [0x2700, 0x27BF], [0x2B00, 0x2BFF], [0x1F000, 0x1FAFF]]

function isBreakAfter(ch) {
    return CAPTION_BREAKS.indexOf(ch) >= 0
}

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

// Cells of the caption's last line, so a mark sits past the glyphs it follows.
// Sample input: lastLineCells("ab\nc🎉") is 3.
function lastLineCells(text) {
    var s = String(text)
    if (isFastText(s)) return s.length - s.lastIndexOf("\n") - 1
    return cellsOf(charsOf(s.split("\n").pop()))
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
    return elideCore(storeOf(chars), capacity, perLine)
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
    if (rangeCells(st, 0, st.n) <= capacity) return st.widths === null ? [st.seq] : st.seq.slice(0)
    var ext = extensionLength(st.seq)
    var split = elideSplit(capacity, ext, ext > 0 ? rangeCells(st, st.n - ext, st.n) : 0, perLine)
    var h = spanFrom(st, 0, split[0]), t = tailSpan(st, split[1])
    if (st.widths === null) return [pieceOf(st, 0, h), "…", pieceOf(st, st.n - t, st.n)]
    return st.seq.slice(0, h).concat(["…"], st.seq.slice(st.n - t))
}

// Wraps a char array into at most count lines of perLine cells, breaking after the last separator that still leaves the rest fitting.
function wrapChars(chars, perLine, count) {
    return wrapCore(storeOf(chars), perLine, count)
}

// The break a line takes: the last separator whose rest still fits, the extension dot losing to any earlier one.
function breakCut(st, far, pos, left, perLine, extDot) {
    var cut = -1, extCut = -1
    for (var i = far - 1; i > pos; i--) {
        if (!isBreakAfter(st.seq[i]) || rangeCells(st, i + 1, st.n) > (left - 1) * perLine) continue
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
        if (rangeCells(st, pos, st.n) <= perLine) { out.push(pieceOf(st, pos, st.n)); break }
        if (ln === count - 1) { out.push(pieceOf(st, pos, pos + spanFrom(st, pos, perLine))); break }
        var far = pos + spanFrom(st, pos, perLine)
        if (far <= pos) far = pos + 1
        var cut = breakCut(st, far, pos, left, perLine, extDot)
        out.push(pieceOf(st, pos, cut))
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
    var st = isFastText(text) ? fastStoreOf(text) : storeOf(charsOf(text))
    if (st.n === 0) return text
    // A wide glyph never straddles a line and wastes a cell, so elide until Flea's own wrap holds every char.
    var capacity = per * count
    if (st.widths === null) {
        var fast = elideCore(st, capacity, per).join("")
        while (capacity > 1 && wrapCore(fastStoreOf(fast), per, count).join("") !== fast)
            fast = elideCore(st, --capacity, per).join("")
        return wrapCore(fastStoreOf(fast), per, count).join("\n")
    }
    var shown = elideCore(st, capacity, per)
    while (capacity > 1 && wrapCore(storeOf(shown), per, count).join("") !== shown.join(""))
        shown = elideCore(st, --capacity, per)
    return wrapCore(storeOf(shown), per, count).join("\n")
}
