.pragma library

// A long name elides in the middle so the extension and the end of a version
// number stay visible. Character-budget truncation in a binding costs a
// string slice, never a relayout; the Text item's own ElideMiddle is the
// backstop where rounding leaves one character over. Sample input:
// "screenshot-2026-08-30-final-review-for-gm-after-the-bench-v3.png", 49.

// Code points, not UTF-16 units: a length cut must never split a surrogate
// pair, and this engine's Array.from indexes units rather than iterating
// points, so the walk below pairs them by hand.
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
