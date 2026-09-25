.pragma library
.import "Fuzzy.js" as Fuzzy

// The path bar's folder jump, and nothing about the field or the dropdown that draw it: ui/ChromeBar.qml
// owns the field and ui/PathJump.qml the dropdown. Pure, so tests/js/jump.js drives all of it with no
// window. The backend answers the three sources once per open (docs/protocol.md "jump"); everything a
// keystroke changes is worked out here, in the window's own thread and with no round trip.

// The sources, each one a field of the backend's "jumped" line, in the order a tie between them goes.
var SOURCES = ["favourites", "zoxide", "recent"]

// A source past its fifth match is a query one letter short, and the next keystroke narrows it; the cap
// also keeps the list inside a window's height, where every row stays a few arrow presses away.
var SOURCE_ROWS = 5

// Past its first character a match has to earn, on average, what one character of a folder's own name
// earns. A run or a word start anywhere clears it, and "src" scattered through ~/Documents/claude/omarchy
// does not, so a folder the name only scatters through is not listed at all. One
// character always clears it, which keeps the board's query o listing every folder with an o in it.
var MIN_SCORE_PER_CHARACTER = Fuzzy.BONUS_BASENAME

// A line with a slash in it, one that starts at home, and "." and ".." are typed as a path, exactly as
// before the jump: Enter resolves it and Tab completes it. The bar opens holding the whole path, and a Tab
// that completes one name ends the line in a slash, so "Wo", Tab, Enter still opens ./Work. A dotted name
// such as ".config" is a name like any other.
// Sample input: "o", "flea" and ".config" are queries; "/usr/share", "Work/", "~", "..", "../x" and "file:///etc" are paths.
function isQuery(text) {
    var line = String(text).trim()
    if (line.length === 0 || line.indexOf("/") >= 0 || line === "." || line === "..") {
        return false
    }
    return line.charAt(0) !== "~"
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

// How many separate runs a match is made of: 1 is the query typed as one unbroken stretch.
function runsIn(positions) {
    var runs = positions.length > 0 ? 1 : 0
    for (var i = 1; i < positions.length; i++) {
        if (positions[i] !== positions[i - 1] + 1) {
            runs++
        }
    }
    return runs
}

// One open's candidates folded once, so a keystroke never displays, folds or lowers anything per
// candidate. The dropdown prepares once per answer; rows() below is the same work in one call.
// Sample sources: { favourites: ["/home/gm/Projects"], zoxide: ["/home/gm/Documents"], recent: [],
//                   frecency: { "/home/gm/Documents": 80 } }
function prepare(sources, home) {
    var given = sources || {}
    var frecency = given.frecency || {}
    var entries = []
    for (var s = 0; s < SOURCES.length; s++) {
        var paths = given[SOURCES[s]] || []
        for (var i = 0; i < paths.length; i++) {
            var path = String(paths[i])
            var text = display(path, home)
            var leaf = leafStart(text)
            var whole = Fuzzy.fold(text)
            var leafFold = whole.slice(leaf)
            entries.push({ path: path, text: text, leaf: leaf, whole: whole,
                           baseWhole: Fuzzy.baseStart(whole), leafFold: leafFold,
                           baseLeaf: Fuzzy.baseStart(leafFold),
                           source: s, at: i, frecency: Number(frecency[path]) || 0 })
        }
    }
    return { entries: entries }
}

// One folder's row out of prepared candidates, or null when the query misses it or only scatters
// through it below the floor. The runs read off the leaf-relative positions, whose offset keeps
// adjacency, and only the wash moves by the leaf.
function rankedPrepared(entry, needle, floor) {
    // A candidate shorter than the needle cannot hold it as a subsequence.
    if (entry.text.length < needle.length) {
        return null
    }
    var whole = Fuzzy.matchFolded(entry.whole, entry.baseWhole, needle)
    if (whole === null || whole.score < floor) {
        return null
    }
    var named = Fuzzy.matchFolded(entry.leafFold, entry.baseLeaf, needle)
    var positions = whole.positions
    if (named !== null) {
        positions = named.positions
    }
    var wash = Fuzzy.run(positions)
    if (named !== null) {
        wash = { start: wash.start + entry.leaf, length: wash.length }
    }
    return { path: entry.path, text: entry.text, leafStart: entry.leaf,
             washStart: wash.start, washLength: wash.length,
             own: named !== null, runs: runsIn(positions),
             source: entry.source, at: entry.at, frecency: entry.frecency }
}

// The controller's ruling, in order: the folder's own name, then contiguity, then frecency, then a favourite
// over the others, and the sources' own orders last so one answer always draws in one order.
function before(a, b) {
    if (a.own !== b.own) {
        return a.own ? -1 : 1
    }
    if (a.runs !== b.runs) {
        return a.runs - b.runs
    }
    if (a.frecency !== b.frecency) {
        return b.frecency - a.frecency
    }
    if (a.source !== b.source) {
        return a.source - b.source
    }
    return a.at - b.at
}

// The dropdown's rows out of prepared candidates: every source's matches in one ranked list, a
// source giving at most SOURCE_ROWS of its best.
function rowsPrepared(prepared, line) {
    if (!isQuery(line)) {
        return []
    }
    var query = String(line).trim()
    var needle = query.toLowerCase()
    var floor = (query.length - 1) * MIN_SCORE_PER_CHARACTER
    var entries = (prepared && prepared.entries) || []
    var found = []
    for (var e = 0; e < entries.length; e++) {
        var row = rankedPrepared(entries[e], needle, floor)
        if (row !== null) {
            found.push(row)
        }
    }
    found.sort(before)
    var out = []
    var taken = [0, 0, 0]
    for (var j = 0; j < found.length; j++) {
        if (taken[found[j].source] < SOURCE_ROWS) {
            taken[found[j].source]++
            out.push(found[j])
        }
    }
    return out
}

// The dropdown's rows: prepare's work in one call, for the callers that rank once.
function rows(sources, line, home) {
    if (!isQuery(line)) {
        return []
    }
    return rowsPrepared(prepare(sources, home), String(line))
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

// The cursor's next row, staying put at either end as the menu's own cursor does; step(rows, -1, 1) is the
// first row, and -1 when there is none.
function step(entries, from, delta) {
    if (entries.length === 0) {
        return -1
    }
    return Math.max(0, Math.min(entries.length - 1, from + delta))
}
