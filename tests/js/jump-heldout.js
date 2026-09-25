.import "../../ui/js/Jump.js" as Jump

// The folder jump's headless quality harness: all 22 heldout2 queries through Jump.rows against the
// field fixture's own folders, no window and no box. The fixture is .flea-local/ref/harness/fixture.sh's
// field scenario (favourites, zoxide visits, six recent files) and the queries are tests/fixtures/
// jump-queries.tsv's heldout2 set, copied here so the runner needs no TSV read; that file stays the
// authority and this table must not be tuned against. Frecency uses the fixture's own visit ranks as
// scores, an approximation of zoxide's computed scores, so the box rerun stays authoritative.
// Rivals on the same set, from the jump handoff: Strata 11, zoxide z 10, yazi Z 8 of 22.

var HOME = "/home/gm"

// The field fixture's folders: favourites first, then zoxide visits with their ranks, then the six
// recent files' folders. Sample row: "Work/claude/flea-013" visited at rank 40 an hour ago.
var FIELD = (function () {
    var zoxide = ["Work/claude/flea-013", "Downloads", "Documents/claude/omarchy", "Documents/claude/flea",
        "Documents/claude/flea-release", "Work/claude/flea-013/ui", ".config/hypr", "Work/claude/flea-013/src",
        "Projects/homelab", "Documents", "Work/strata", "Projects/homelab/nix", "Work/field", ".config/omarchy",
        "Work/claude/flea-013/tests", "Projects", "Pictures/screenshots", "Documents/notes",
        "Pictures/wallpapers", "Work/bench", "Music", "Videos", "Pictures/holiday"]
    var ranks = [40, 30, 25, 20, 18, 15, 14, 12, 11, 10, 9, 9, 8, 7, 6, 6, 5, 4, 3, 3, 2, 1, 1]
    var favourites = [HOME + "/Projects", HOME + "/Documents/claude/flea", HOME + "/Documents/claude/omarchy"]
    var zpaths = []
    var frecency = {}
    for (var i = 0; i < zoxide.length; i++) {
        var full = HOME + "/" + zoxide[i]
        zpaths.push(full)
        frecency[full] = ranks[i]
    }
    // The fixture's own extra folders, present on disk but in no source: they draw nothing.
    // Downloads, Pictures/screenshots and Work/field are recent files too, but the backend answers each
    // folder once in its first source, so they rank as zoxide rows here, the same dedup jumped_line does.
    var recent = [HOME + "/Documents/tax", HOME + "/Pictures/raw", HOME + "/Music/albums"]
    return { favourites: favourites, zoxide: zpaths, recent: recent, frecency: frecency }
})()

// Query and the folder that should come first, relative to the fixture home, in TSV order.
var HELDOUT2 = [["doc", "Documents"], ["down", "Downloads"], ["music", "Music"], ["pic", "Pictures"],
    ["proj", "Projects"], ["video", "Videos"], ["wor", "Work"], ["holi", "Pictures/holiday"],
    ["phone", "Pictures/phone"], ["tri", "Pictures/trip"], ["scra", "Documents/scratch"],
    ["tax", "Documents/tax"], ["raw", "Pictures/raw"], ["albu", "Music/albums"],
    ["flea-", "Work/claude/flea-013"], ["fle", "Documents/claude/flea"], ["flea", "Documents/claude/flea-release"],
    ["ui", "Work/claude/flea-013/ui"], ["hyp", ".config/hypr"], ["src", "Work/claude/flea-013/src"],
    ["hmelab", "Projects/homelab"], ["srtata", "Work/strata"]]

function firstFor(query) {
    var rows = Jump.rows(FIELD, query, HOME)
    return rows.length > 0 ? rows[0].path : "(none)"
}

function runQuality(check) {
    var wins = 0
    var misses = []
    for (var i = 0; i < HELDOUT2.length; i++) {
        var query = HELDOUT2[i][0]
        var expected = HOME + "/" + HELDOUT2[i][1]
        var first = firstFor(query)
        // A second run must answer identically: one walk over one set answers in exactly one order.
        var again = firstFor(query)
        if (first === expected) {
            wins++
        } else {
            misses.push(query + ": first " + first + ", want " + expected)
        }
        if (again !== first) {
            misses.push(query + ": unstable, " + first + " then " + again)
        }
    }
    check("heldout2 runs all 22 queries", HELDOUT2.length, 22)
    // The scoreboard, rivals in the file header. It logs rather than asserts a win: a miss here is a
    // report (which queries lose and why, in the return) and never a tuning prompt, the set is frozen.
    console.log("jump-heldout: Flea " + wins + "/22; misses: " + (misses.length > 0 ? misses.join(" | ") : "none"))
    check("heldout2 harness ran every query deterministically", misses.filter(function (m) { return m.indexOf("unstable") >= 0 }).length, 0)
}

// Ranking cost: the dropdown re-ranks every keystroke over one open's candidates, so the fold happens
// once per answer and every keystroke reuses it. The gate is a named share, not an absolute time:
// both arms run back to back in this runner, so host contention stretches them together and the ratio
// stands (measured 0.06 to 0.62 from a quiet box to load average 20). The absolute medians ride in the
// log for the box battery. Repeats keep Date.now's millisecond grain small, a discarded warmup keeps
// engine warmup out, and the median keeps one contended round from deciding the check.
var PERF_SHARE_BUDGET = 0.8
var PERF_CALLS = 400
var PERF_ROUNDS = 3
var PERF_WARMUP = 200
var PERF = (function () {
    var rel = ["Work/claude/flea-013", "Work/claude/flea-013/ui", "Work/claude/flea-013/src",
        "Work/claude/flea-013/tests", "Work/claude/omarchy", "Work/claude/themes", "Work/field",
        "Work/strata", "Work/bench", "Documents/claude/flea", "Documents/claude/flea-release",
        "Documents/claude/omarchy", "Documents/notes", "Documents/tax", "Documents/scratch",
        "Documents", "Downloads", "Music", "Music/albums", "Pictures/screenshots", "Pictures/holiday",
        "Pictures/wallpapers", "Pictures/raw", "Pictures/phone", "Pictures/trip", "Projects",
        "Projects/homelab", "Projects/homelab/nix", "Videos", ".config/hypr", ".config/omarchy", "Music/live"]
    var zoxide = []
    var frecency = {}
    for (var i = 0; i < rel.length; i++) {
        var full = HOME + "/" + rel[i]
        zoxide.push(full)
        frecency[full] = rel.length - i
    }
    return { favourites: [HOME + "/Projects"], zoxide: zoxide, recent: [], frecency: frecency }
})()
var PERF_QUERIES = ["o", "flea", "tax", "src", "ui", "zzz"]

function medianUs(fn) {
    for (var w = 0; w < PERF_WARMUP; w++) {
        fn()
    }
    var samples = []
    for (var r = 0; r < PERF_ROUNDS; r++) {
        var t0 = Date.now()
        for (var c = 0; c < PERF_CALLS; c++) {
            fn()
        }
        samples.push((Date.now() - t0) * 1000 / PERF_CALLS)
    }
    samples.sort(function (a, b) { return a - b })
    return samples[Math.floor(samples.length / 2)]
}

function runPerf(check) {
    var prepared = typeof Jump.prepare === "function" && typeof Jump.rowsPrepared === "function"
    check("Jump folds one open's candidates once and reuses them every keystroke", prepared, true)
    if (prepared) {
        var once = Jump.prepare(PERF, HOME)
        var same = true
        for (var q = 0; q < PERF_QUERIES.length; q++) {
            var a = JSON.stringify(Jump.rows(PERF, PERF_QUERIES[q], HOME))
            var b = JSON.stringify(Jump.rowsPrepared(once, PERF_QUERIES[q]))
            if (a !== b) {
                same = false
            }
        }
        check("prepared rows rank exactly what rows ranks", same, true)
        // Repeated opens stay flat: one open's folds are fresh objects, so poisoning them cannot move
        // the next open, and ranking the same answer twice answers twice the same. The QML half is the
        // same rule: ui/PathJump.qml drops sources and prepared with the edit, so nothing of an open
        // survives it; tests/jump-ui.sh watches historyReads for the reread half.
        once.entries[0].frecency = -999
        once.entries.push({ path: "/nowhere", text: "/nowhere", leaf: 1, whole: [], baseWhole: 0,
                            leafFold: [], baseLeaf: 0, source: 0, at: 999, frecency: 0 })
        var reopened = Jump.prepare(PERF, HOME)
        var flat = reopened.entries.length === once.entries.length - 1
            && JSON.stringify(Jump.rowsPrepared(reopened, "o")) === JSON.stringify(Jump.rows(PERF, "o", HOME))
        check("repeated opens keep no folds", flat, true)
        // Timed on a fresh prepare: the poisoned one above is the retention check's, not this one's.
        var timed = Jump.prepare(PERF, HOME)
        var amortized = medianUs(function () { Jump.rowsPrepared(timed, "o") })
        var whole = medianUs(function () { Jump.rows(PERF, "o", HOME) })
        console.log("jump-perf: rows " + whole.toFixed(1) + " us, prepared " + amortized.toFixed(1)
                    + " us, share budget " + PERF_SHARE_BUDGET)
        check("a reused fold costs less than its share of folding every keystroke",
              amortized <= PERF_SHARE_BUDGET * whole, true)
    } else {
        // Red before the change: the fold happens per keystroke, so even the unprepared path is timed.
        var unprepared = medianUs(function () { Jump.rows(PERF, "o", HOME) })
        console.log("jump-perf: rows " + unprepared.toFixed(1) + " us, no prepared arm yet")
        check("a reused fold costs less than its share of folding every keystroke", false, true)
    }
}

function run(check) {
    runQuality(check)
    runPerf(check)
}
