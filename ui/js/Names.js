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

// Text.Wrap breaks at word boundaries, so a short first line pushes the tail past ElideRight: the first line budgets whole, each continuation half.
// Sample input: gridBudget(128, 7.8, 2) is 24.
function gridBudget(width, advance, lines) {
    if (!(width > 0) || !(advance > 0))
        return -1
    var per = Math.floor(width / advance)
    if (!(lines > 1))
        return per
    return per + Math.floor(per / 2) * (lines - 1)
}
