.pragma library

// The path bar's folder jump, and nothing about the field or the dropdown that draw it: ui/ChromeBar.qml
// owns the field and ui/PathJump.qml the dropdown. Pure, so tests/js/jump.js drives all of it with no
// window. The backend answers the three sources once per open (docs/protocol.md "jump"); everything a
// keystroke changes is worked out here, in the window's own thread and with no round trip.

// The sources in the order the dropdown draws them, each one a field of the backend's "jumped" line.
var SOURCES = ["favourites", "zoxide", "recent"]

// A source past its fifth match is a query one letter short, and the next keystroke narrows it; the cap
// also keeps three sources inside a window's height, where every row stays one arrow press away.
var SOURCE_ROWS = 5

// src/backend/fuzzy.rs, weight for weight, so the jump and search agree on what matched and where.
var BONUS_CONSECUTIVE = 8
var BONUS_BOUNDARY = 6
var BONUS_BASENAME = 4
var PENALTY_GAP = 1
var MAX_STARTS = 16

// A line that starts the way a path does is typed as one, as it was before the jump: Enter resolves it
// and Tab completes it. The bar opens holding the whole path, so the dropdown waits for a name.
// Sample input: "o" and "flea" are queries; "/usr/share", "~/Work", "../x" and "file:///etc" are paths.
function isQuery(text) {
    var line = String(text).trim()
    if (line.length === 0) {
        return false
    }
    var first = line.charAt(0)
    return first !== "/" && first !== "~" && first !== "." && line.indexOf("file://") !== 0
}

// The path as the chrome writes it, a tilde for the home directory; this is also the text the query matches.
function display(path, home) {
    var text = String(path)
    var root = String(home || "")
    if (root.length > 0 && (text === root || text.indexOf(root + "/") === 0)) {
        return "~" + text.substring(root.length)
    }
    return text
}

// Where the leaf starts, the character after the last slash; "~" is all leaf and "/" is all parent.
function leafStart(text) {
    return String(text).lastIndexOf("/") + 1
}

function isSeparator(c) {
    return c === "/" || c === "-" || c === "_" || c === "." || c === " "
}

// corner: a character whose lowercase form is longer keeps its first unit, the corner fuzzy.rs documents,
// and a character outside the basic plane counts as two here where Rust counts one, which moves only a gap charge.
function fold(text) {
    var out = []
    for (var i = 0; i < text.length; i++) {
        var c = text.charAt(i)
        var lower = c.toLowerCase().charAt(0)
        out.push({ lower: lower, upper: lower !== c })
    }
    return out
}

function baseStart(hay) {
    var start = 0
    for (var i = 0; i < hay.length; i++) {
        if (hay[i].lower === "/") {
            start = i + 1
        }
    }
    return start
}

function startsAWord(hay, at) {
    if (at === 0) {
        return true
    }
    var before = hay[at - 1]
    return isSeparator(before.lower) || (hay[at].upper && !before.upper)
}

// What one matched character is worth: a run, a boundary and the base name each add, and the
// characters skipped to reach it are charged back.
function characterScore(hay, at, base, previous) {
    var score = 0
    if (previous >= 0) {
        score += at === previous + 1 ? BONUS_CONSECUTIVE : -PENALTY_GAP * (at - previous - 1)
    }
    if (startsAWord(hay, at)) {
        score += BONUS_BOUNDARY
    }
    if (at >= base) {
        score += BONUS_BASENAME
    }
    return score
}

// Greedy from one start: every query character takes the next candidate character that matches it.
function alignFrom(hay, needle, start, base) {
    var total = 0
    var at = start
    var previous = -1
    var positions = []
    for (var k = 0; k < needle.length; k++) {
        if (k > 0) {
            at++
            while (at < hay.length && hay[at].lower !== needle.charAt(k)) {
                at++
            }
            if (at === hay.length) {
                return null
            }
        }
        total += characterScore(hay, at, base, previous)
        positions.push(at)
        previous = at
    }
    return { score: total, positions: positions }
}

// null when the query is not a subsequence of the candidate; otherwise the best alignment's score and
// the positions it matched, which is what the wash is drawn from.
function match(candidate, query) {
    var needle = String(query).toLowerCase()
    if (needle.length === 0) {
        return { score: 0, positions: [] }
    }
    var hay = fold(String(candidate))
    var base = baseStart(hay)
    var best = null
    var starts = 0
    for (var i = 0; i < hay.length; i++) {
        if (hay[i].lower !== needle.charAt(0)) {
            continue
        }
        var found = alignFrom(hay, needle, i, base)
        // A start that cannot finish means no later start can either, the greedy scan's own guarantee.
        if (found === null) {
            return best
        }
        if (best === null || found.score > best.score) {
            best = found
        }
        starts++
        if (starts === MAX_STARTS) {
            break
        }
    }
    return best
}

// The one run the row washes: the longest stretch of consecutive matched positions, the first on a tie.
function run(positions) {
    var best = { start: -1, length: 0 }
    var i = 0
    while (i < positions.length) {
        var j = i
        while (j + 1 < positions.length && positions[j + 1] === positions[j] + 1) {
            j++
        }
        if (j - i + 1 > best.length) {
            best = { start: positions[i], length: j - i + 1 }
        }
        i = j + 1
    }
    return best
}

// The dropdown's entries. Each source keeps its own order and is cut at SOURCE_ROWS, a separator stands
// between two sources that both matched, and a source that matched nothing draws nothing, separator and all.
// Sample sources: { favourites: ["/home/gm/Projects"], zoxide: ["/home/gm/Documents"], recent: [] }
function rows(sources, line, home) {
    var out = []
    if (!isQuery(line)) {
        return out
    }
    var query = String(line).trim()
    for (var s = 0; s < SOURCES.length; s++) {
        var paths = (sources || {})[SOURCES[s]] || []
        var group = []
        for (var i = 0; i < paths.length && group.length < SOURCE_ROWS; i++) {
            var text = display(paths[i], home)
            var found = match(text, query)
            if (found === null) {
                continue
            }
            var wash = run(found.positions)
            group.push({ path: String(paths[i]), text: text, leafStart: leafStart(text),
                         washStart: wash.start, washLength: wash.length })
        }
        if (group.length === 0) {
            continue
        }
        if (out.length > 0) {
            out.push({ separator: true })
        }
        out = out.concat(group)
    }
    return out
}

// A row's label in drawing order: the text cut where the leaf starts and where the wash starts and ends,
// each piece saying whether it is leaf ink and whether it sits on the wash.
function segments(row) {
    var text = String(row.text || "")
    if (text.length === 0) {
        return []
    }
    var cuts = [0, row.leafStart, text.length]
    if (row.washLength > 0) {
        cuts.push(row.washStart, row.washStart + row.washLength)
    }
    cuts.sort(function (a, b) { return a - b })
    var out = []
    for (var i = 0; i + 1 < cuts.length; i++) {
        var from = cuts[i]
        var to = cuts[i + 1]
        if (to <= from) {
            continue
        }
        out.push({ text: text.substring(from, to), leaf: from >= row.leafStart,
                   wash: row.washLength > 0 && from >= row.washStart && to <= row.washStart + row.washLength })
    }
    return out
}

// The cursor's next row, skipping separators and staying put at either end, as the menu's own cursor does.
// step(entries, -1, 1) is the first row, and -1 when there is none.
function step(entries, from, delta) {
    var i = from + delta
    while (i >= 0 && i < entries.length) {
        if (entries[i].separator !== true) {
            return i
        }
        i += delta
    }
    return from
}
