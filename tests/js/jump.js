.import "../../ui/js/Jump.js" as Jump

// The folder jump's rows are the whole feature: which folders a name lists, in what order, under which
// separator and with which run washed. The Jump board's own fixture is asserted row for row, and the
// scorer is held to the cases src/backend/fuzzy.rs holds the search scorer to, so the two cannot drift.

var HOME = "/home/gm"
// lib.FAVORITES, the board's FREQUENT and RECENT, as the backend answers them: absolute and existing.
var BOARD = {
    favourites: ["/home/gm/Projects", "/home/gm/Documents/claude/flea", "/home/gm/Documents/claude/omarchy"],
    zoxide: ["/home/gm/Documents", "/home/gm/Downloads"],
    recent: ["/home/gm/Pictures/screenshots", "/home/gm/Work/field"]
}

function drawn(rows) {
    return rows.map(function (row) {
        if (row.separator) {
            return "--"
        }
        var t = row.text
        return row.washLength > 0
            ? t.substring(0, row.washStart) + "[" + t.substr(row.washStart, row.washLength) + "]" + t.substring(row.washStart + row.washLength)
            : t
    }).join(" ")
}

function score(hay, query) {
    var found = Jump.match(hay, query)
    return found === null ? null : found.score
}

function run(check) {
    check("a name is a query", Jump.isQuery("o"), true)
    check("a slash anywhere makes the line a path", Jump.isQuery("cl/fl"), false)
    check("a Tab that completed one name ends in a slash, so Enter opens it", Jump.isQuery("Work/"), false)
    check("home alone is a path", Jump.isQuery("~"), false)
    check("the parent is a path", Jump.isQuery(".."), false)
    check("this folder is a path", Jump.isQuery("."), false)
    check("a dotted name is a name", Jump.isQuery(".config"), true)
    check("a dot inside a name is a name", Jump.isQuery("v1.2"), true)
    check("a dotted name lists its folder", drawn(Jump.rows({ zoxide: ["/home/gm/.config/hypr", "/home/gm/Work"] }, ".config", HOME)),
          "~/[.config]/hypr")
    check("an absolute path is typed as one", Jump.isQuery("/usr/share"), false)
    check("a home path is typed as one", Jump.isQuery("~/Work"), false)
    check("a relative climb is typed as one", Jump.isQuery("../x"), false)
    check("a file URI is typed as one", Jump.isQuery("file:///etc"), false)
    check("the line the bar opens with is a path", Jump.isQuery("/home/gm/Documents/"), false)
    check("an empty line is nothing", Jump.isQuery("  "), false)

    check("home is drawn as a tilde", Jump.display("/home/gm/Work/field", HOME), "~/Work/field")
    check("home itself is the tilde", Jump.display("/home/gm", HOME), "~")
    check("a sibling of home keeps its path", Jump.display("/home/gmx/a", HOME), "/home/gmx/a")
    check("no home, no tilde", Jump.display("/home/gm/a", ""), "/home/gm/a")

    // The board, query o: three sources in order, one separator each, and the washes exactly as drawn.
    check("the board's query o", drawn(Jump.rows(BOARD, "o", HOME)),
          "~/Pr[o]jects ~/D[o]cuments/claude/flea ~/Documents/claude/[o]marchy -- ~/D[o]cuments ~/D[o]wnloads -- ~/Pictures/screensh[o]ts ~/W[o]rk/field")
    check("the cursor opens on the first row", Jump.step(Jump.rows(BOARD, "o", HOME), -1, 1), 0)
    var noZoxide = { favourites: BOARD.favourites, zoxide: [], recent: BOARD.recent }
    check("zoxide with no folders takes its separator with it", drawn(Jump.rows(noZoxide, "o", HOME)),
          "~/Pr[o]jects ~/D[o]cuments/claude/flea ~/Documents/claude/[o]marchy -- ~/Pictures/screensh[o]ts ~/W[o]rk/field")
    check("a source with no match draws nothing", drawn(Jump.rows(BOARD, "shots", HOME)), "~/Pictures/screen[shots]")
    check("a missing source is an empty one", drawn(Jump.rows({ recent: BOARD.recent }, "field", HOME)), "~/Work/[field]")
    check("no source at all draws nothing", Jump.rows({}, "o", HOME).length, 0)
    check("a path line lists nothing", Jump.rows(BOARD, "/home/gm", HOME).length, 0)
    check("the query is trimmed", drawn(Jump.rows(BOARD, " field ", HOME)), "~/Work/[field]")

    // Each source keeps its own order: zoxide's first row stays first though the second scores higher.
    var ranked = { zoxide: ["/home/gm/Work/mynotes", "/home/gm/notes"] }
    check("a source keeps its own order over the score", drawn(Jump.rows(ranked, "notes", HOME)),
          "~/Work/my[notes] ~/[notes]")
    check("the second row does score higher, which is what the order ignores",
          score("~/notes", "notes") > score("~/Work/mynotes", "notes"), true)
    var many = { zoxide: ["/a/x1", "/a/x2", "/a/x3", "/a/x4", "/a/x5", "/a/x6", "/a/x7"] }
    check("a source is cut at its fifth match", Jump.rows(many, "x", HOME).length, Jump.SOURCE_ROWS)
    check("the cut keeps the source's head", Jump.rows(many, "x", HOME)[4].path, "/a/x5")

    // A scattered match is dropped, so an earlier source cannot bury the folder the name was typed for.
    var scattered = { favourites: ["/home/gm/Documents/claude/omarchy"], zoxide: ["/home/gm/Work/claude/flea-013/src"] }
    check("src scattered through a favourite's parents is dropped", drawn(Jump.rows(scattered, "src", HOME)),
          "~/Work/claude/flea-013/[src]")
    var buried = { zoxide: ["/home/gm/Projects/homelab/nix"], recent: ["/home/gm/Documents/tax"] }
    check("a scattered zoxide row does not bury a recent folder", drawn(Jump.rows(buried, "tax", HOME)), "~/Documents/[tax]")
    var abbreviated = { favourites: ["/home/gm/Documents/claude/flea"], zoxide: ["/home/gm/Downloads"] }
    check("an abbreviation on word starts still matches", drawn(Jump.rows(abbreviated, "dl", HOME)), "~/[D]ownloads")
    check("a run through a parent is not scattered", drawn(Jump.rows({ zoxide: ["/home/gm/Documents/claude/flea"] }, "claude", HOME)),
          "~/Documents/[claude]/flea")
    check("one character is never scattered", Jump.rows({ zoxide: ["/home/gm/Work/field"] }, "o", HOME).length, 1)

    // The search scorer's own cases, src/backend/fuzzy.rs tests, so the jump matches what search matches.
    check("the operator's dwnhelp crosses the separator", score("downloads/helper.txt", "dwnhelp") !== null, true)
    check("a query out of order is not a match", score("helper.txt", "pleh"), null)
    check("a query longer than the name is not a match", score("abc", "abcd"), null)
    check("case folds", score("Bench-Notes.md", "bench") !== null && score("BENCH", "bench") !== null, true)
    check("case folds beyond ASCII", score("CAFÉ.txt", "café") !== null && score("café.txt", "CAFÉ") !== null, true)
    check("an empty query matches with no score", score("anything", ""), 0)
    check("a contiguous run beats a scattered one", score("report.txt", "rep") > score("raspberry-pie.txt", "rep"), true)
    check("a boundary start beats one inside a word", score("my-notes.txt", "notes") > score("bignotes.txt", "notes"), true)
    check("a camel hump counts as a boundary", score("SearchStrip.qml", "strip") > score("searchstrip.qml", "strip"), true)
    check("a match in the name beats one in a parent", score("notes/bench.txt", "bench") > score("bench/notes.txt", "bench"), true)
    check("a later start can score better than the first", score("axxab", "ab") > score("axxb", "ab"), true)
    var pathological = ""
    for (var i = 0; i < 4096; i++) pathological += "a"
    check("a pathological name is scored from bounded starts", score(pathological, "aa") !== null, true)

    // SCORES is the_exact_scores_the_jump_port_mirrors in src/backend/fuzzy.rs, value for value, so the
    // port and the scorer it copies cannot drift apart without one of the two suites going red.
    var bounded = ""
    for (var b = 0; b < 16; b++) bounded += "ax"
    var SCORES = [["report.txt", "rep", 34], ["raspberry-pie.txt", "rep", 16], ["my-notes.txt", "notes", 58],
                  ["bignotes.txt", "notes", 52], ["SearchStrip.qml", "strip", 58], ["searchstrip.qml", "strip", 52],
                  ["notes/bench.txt", "bench", 58], ["bench/notes.txt", "bench", 38], ["axxab", "ab", 16], ["axxb", "ab", 12],
                  [bounded + "ab", "ab", 6], ["downloads/helper.txt", "dwnhelp", 53], ["~/Documents/claude/omarchy", "o", 10],
                  ["~/Documents/claude/omarchy", "src", 5], ["~/Projects/homelab/nix", "tax", -7]]
    for (var t = 0; t < SCORES.length; t++) {
        check("the Rust scorer's own score for " + SCORES[t][1] + " against " + SCORES[t][0], score(SCORES[t][0], SCORES[t][1]), SCORES[t][2])
    }

    // The wash is the best alignment's longest run, and it lands where the scorer's bonuses put it.
    check("the leaf's word start wins the wash over a letter inside a parent",
          Jump.match("~/Documents/claude/omarchy", "o").positions[0], 19)
    check("a scattered match washes its longest run", JSON.stringify(Jump.run([2, 5, 6, 7, 9])), '{"start":5,"length":3}')
    check("a tie washes the first run", JSON.stringify(Jump.run([1, 2, 5, 6])), '{"start":1,"length":2}')
    check("no positions wash nothing", Jump.run([]).start, -1)

    // The label: muted parent, foreground leaf, and the wash cut out wherever it falls.
    var omarchy = Jump.rows(BOARD, "o", HOME)[2]
    check("a wash in the leaf splits the leaf", JSON.stringify(Jump.segments(omarchy)),
          '[{"text":"~/Documents/claude/","leaf":false,"wash":false},{"text":"o","leaf":true,"wash":true},{"text":"marchy","leaf":true,"wash":false}]')
    var flea = Jump.rows(BOARD, "o", HOME)[1]
    check("a wash in the parent keeps the parent muted", JSON.stringify(Jump.segments(flea)),
          '[{"text":"~/D","leaf":false,"wash":false},{"text":"o","leaf":false,"wash":true},{"text":"cuments/claude/","leaf":false,"wash":false},{"text":"flea","leaf":true,"wash":false}]')
    var across = { text: "/w/claude/flea", leafStart: 10, washStart: 8, washLength: 3 }
    check("a wash across the last slash is cut in two", JSON.stringify(Jump.segments(across).map(function (s) { return s.text + (s.leaf ? "L" : "") + (s.wash ? "W" : "") })),
          '["/w/claud","e/W","fLW","leaL"]')
    check("a separator has no label", Jump.segments({ separator: true }).length, 0)

    // The cursor skips separators and stays put at either end, as the menu's own does.
    var rows = Jump.rows(BOARD, "o", HOME)
    check("down from the third row crosses the separator", Jump.step(rows, 2, 1), 4)
    check("up from after a separator crosses it", Jump.step(rows, 4, -1), 2)
    check("down from the last row stays", Jump.step(rows, rows.length - 1, 1), rows.length - 1)
    check("up from the first row stays", Jump.step(rows, 0, -1), 0)
    check("an empty dropdown has no cursor", Jump.step([], -1, 1), -1)
}
