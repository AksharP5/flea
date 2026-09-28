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
        out.push(text.charAt(i))
    }
    return out
}

function middleElide(name, maxChars) {
    var chars = charsOf(String(name))
    var max = Math.max(0, Math.floor(maxChars))
    if (chars.length <= max) {
        return String(name)
    }
    // The head takes the odd character, so a 49-wide board keeps 24 and 24.
    var head = Math.ceil((max - 1) / 2)
    var tail = Math.floor((max - 1) / 2)
    return chars.slice(0, head).join("") + "…"
        + (tail > 0 ? chars.slice(chars.length - tail).join("") : "")
}

// A caption break stays behind a separator, so a word is never split when a break fits.
var CAPTION_BREAKS = " -_."

function isBreakAfter(ch) {
    return CAPTION_BREAKS.indexOf(ch) >= 0
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

// Elides a char array down to capacity, keeping a one-line extension whole on the tail.
function elideChars(chars, capacity, perLine) {
    if (capacity <= 1)
        return ["…"]
    var ext = extensionLength(chars)
    var head = Math.ceil((capacity - 1) / 2)
    var tail = Math.floor((capacity - 1) / 2)
    // An extension longer than one line, or with no room for the mark beside it, cannot stay whole.
    if (ext > 0 && ext <= perLine && ext + 1 <= capacity) {
        tail = Math.max(ext, tail)
        head = capacity - 1 - tail
    }
    return chars.slice(0, head).concat(["…"], chars.slice(chars.length - tail))
}

// Wraps a char array into at most count lines of perLine chars, breaking after the last separator that still leaves the rest fitting.
function wrapChars(chars, perLine, count) {
    var out = []
    var pos = 0
    // The extension's own dot, so a break there never wins while an earlier separator fits.
    var extDot = chars.length - extensionLength(chars)
    for (var ln = 0; ln < count && pos < chars.length; ln++) {
        var rest = chars.length - pos
        var left = count - ln
        if (rest <= perLine) {
            out.push(chars.slice(pos).join(""))
            break
        }
        if (ln === count - 1) {
            out.push(chars.slice(pos, pos + perLine).join(""))
            break
        }
        var cut = -1
        var extCut = -1
        for (var i = pos + perLine - 1; i > pos; i--) {
            if (!isBreakAfter(chars[i]) || chars.length - (i + 1) > (left - 1) * perLine)
                continue
            if (i === extDot) {
                extCut = i + 1
                continue
            }
            cut = i + 1
            break
        }
        if (cut < 0)
            cut = extCut >= 0 ? extCut : pos + perLine
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
    if (chars.length > per * count)
        chars = elideChars(chars, per * count, per)
    return wrapChars(chars, per, count).join("\n")
}
