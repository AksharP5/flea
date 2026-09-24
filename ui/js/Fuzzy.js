.pragma library

// src/backend/fuzzy.rs ported, weight for weight, so the path bar's jump and search agree on what matched
// and where. Pure; tests/js/jump.js holds it to the Rust tests' own table of exact scores.
var BONUS_CONSECUTIVE = 8
var BONUS_BOUNDARY = 6
var BONUS_BASENAME = 4
var PENALTY_GAP = 1
var MAX_STARTS = 16

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

