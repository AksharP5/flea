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

function middleElide(name, maxCells) {
    var chars = charsOf(String(name))
    var max = Math.max(0, Math.floor(maxCells))
    if (cellsOf(chars) <= max) {
        return String(name)
    }
    // The head takes the odd cell, so a 49-wide board keeps 24 and 24.
    var head = Math.ceil((max - 1) / 2)
    var tail = Math.floor((max - 1) / 2)
    return headByCells(chars, head).join("") + "…"
        + (tail > 0 ? tailByCells(chars, tail).join("") : "")
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
    for (var i = 0; i < WIDE_RANGES.length; i++)
        if (cp >= WIDE_RANGES[i][0] && cp <= WIDE_RANGES[i][1]) return true
    for (var j = 0; j < EMOJI_RANGES.length; j++)
        if (cp >= EMOJI_RANGES[j][0] && cp <= EMOJI_RANGES[j][1]) return true
    return false
}

// Cells one char paints: 2 for a wide code point, 1 for all else.
function cellWidthOf(ch) {
    var cp = String(ch).codePointAt(0)
    return isWideCode(cp) ? 2 : 1
}

// Cells a char array paints.
function cellsOf(chars) {
    var n = 0
    for (var i = 0; i < chars.length; i++) n += cellWidthOf(chars[i])
    return n
}

// A head that fits in this many cells, never splitting a code point.
function headByCells(chars, budget) {
    var out = []
    var used = 0
    for (var i = 0; i < chars.length; i++) {
        var w = cellWidthOf(chars[i])
        if (used + w > budget) break
        out.push(chars[i])
        used += w
    }
    return out
}

// A tail that fits in this many cells, never splitting a code point.
function tailByCells(chars, budget) {
    var out = []
    var used = 0
    for (var i = chars.length - 1; i >= 0; i--) {
        var w = cellWidthOf(chars[i])
        if (used + w > budget) break
        out.unshift(chars[i])
        used += w
    }
    return out
}

// Cells of the caption's last line, so a mark sits past the glyphs it follows.
// Sample input: lastLineCells("ab\nc🎉") is 3.
function lastLineCells(text) {
    var parts = String(text).split("\n")
    return cellsOf(charsOf(parts[parts.length - 1]))
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
    if (capacity <= 1)
        return ["…"]
    if (cellsOf(chars) <= capacity)
        return chars.slice(0)
    var ext = extensionLength(chars)
    var extCells = ext > 0 ? cellsOf(chars.slice(chars.length - ext)) : 0
    var head = Math.ceil((capacity - 1) / 2)
    var tail = Math.floor((capacity - 1) / 2)
    // An extension longer than one line, or with no room for the mark beside it, cannot stay whole.
    if (ext > 0 && extCells <= perLine && extCells + 1 <= capacity) {
        tail = Math.max(extCells, tail)
        head = capacity - 1 - tail
    }
    return headByCells(chars, head).concat(["…"], tailByCells(chars, tail))
}

// Wraps a char array into at most count lines of perLine cells, breaking after the last separator that still leaves the rest fitting.
function wrapChars(chars, perLine, count) {
    var out = []
    var pos = 0
    // The extension's own dot, so a break there never wins while an earlier separator fits.
    var extDot = chars.length - extensionLength(chars)
    for (var ln = 0; ln < count && pos < chars.length; ln++) {
        var restCells = cellsOf(chars.slice(pos))
        var left = count - ln
        if (restCells <= perLine) {
            out.push(chars.slice(pos).join(""))
            break
        }
        if (ln === count - 1) {
            out.push(headByCells(chars.slice(pos), perLine).join(""))
            break
        }
        // The farthest char index fitting in this line's cells.
        var far = pos
        var used = 0
        while (far < chars.length && used + cellWidthOf(chars[far]) <= perLine) {
            used += cellWidthOf(chars[far])
            far += 1
        }
        if (far <= pos)
            far = pos + 1
        var cut = -1
        var extCut = -1
        for (var i = far - 1; i > pos; i--) {
            if (!isBreakAfter(chars[i]) || cellsOf(chars.slice(i + 1)) > (left - 1) * perLine)
                continue
            if (i === extDot) {
                extCut = i + 1
                continue
            }
            cut = i + 1
            break
        }
        if (cut < 0)
            cut = extCut >= 0 ? extCut : far
        out.push(chars.slice(pos, cut).join(""))
        pos = cut
    }
    return out
}

// The caption Flea hands to Text already holds its line breaks, so Qt never wraps.
// Sample input: gridCaption("screenshot-2026-08-30-final-review-for-gm-after-the-bench-v3.png", 16, 2) answers "screenshot-2026-\n…he-bench-v3.png".
function gridCaption(name, perLine, lines) {
    var text = String(name)
    var per = Math.floor(perLine)
    var count = Math.floor(lines)
    // A dead width budgets nothing: hand Qt the whole name and let ElideRight say so.
    if (!(per >= 1) || !(count >= 1))
        return text
    var chars = charsOf(text)
    if (chars.length === 0)
        return text
    // A wide glyph never straddles a line and wastes a cell, so elide until Flea's own wrap holds every char.
    var capacity = per * count, shown = elideChars(chars, capacity, per)
    while (capacity > 1 && wrapChars(shown, per, count).join("") !== shown.join(""))
        shown = elideChars(chars, --capacity, per)
    return wrapChars(shown, per, count).join("\n")
}
