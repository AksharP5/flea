.pragma library

// A selection is a set of row indices over the current listing; a new list clears it, because an index
// into a directory that has changed means nothing. Task 8 declined ScriptModel plus ItemSelectionModel
// on measured memory (see AGENTS.md "The list model"), so this is a hand-rolled index set instead.
function create() {
    var rows = {}
    var n = 0
    // True while the set is one row a plain tap or a landing anchor made, which a plain move carries along.
    var lone = false

    function has(i) {
        return rows[i] === true
    }

    function add(i) {
        if (!has(i)) { rows[i] = true; n += 1 }
    }

    function remove(i) {
        if (has(i)) { delete rows[i]; n -= 1 }
    }

    function dropLone() { lone = false }

    return {
        has: has,
        count: function () { return n },
        // A lone row follows a plain move; any deliberate mark drops that promise at once.
        follows: function () { return lone && n === 1 },
        toggle: function (i) { dropLone(); has(i) ? remove(i) : add(i) },
        only: function (i) { rows = {}; n = 0; add(i); lone = true },
        extendTo: function (i, anchor) {
            dropLone()
            var lo = Math.min(i, anchor)
            var hi = Math.max(i, anchor)
            rows = {}
            n = 0
            for (var r = lo; r <= hi; r++)
                add(r)
        },
        all: function (total) {
            dropLone()
            rows = {}
            n = 0
            for (var r = 0; r < total; r++)
                add(r)
        },
        clear: function () { rows = {}; n = 0; dropLone() },
        indices: function () {
            var out = []
            for (var k in rows)
                out.push(Number(k))
            out.sort(function (a, b) { return a - b })
            return out
        }
    }
}
