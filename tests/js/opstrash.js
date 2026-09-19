.import "../../ui/js/Ops.js" as Ops

// What a trash says and which row it leaves the cursor on. Split out of tests/js/ops.js, which sits
// at its recorded line count, the same way tests/js/marks.js was split out of tests/js/filter.js.

function pane(cursor, picked) {
    var rows = []
    for (var i = 0; i < 5; i++)
        rows.push({ n: "f" + i })
    return {
        path: "/d", cursorIndex: cursor, rows: rows, shown: null, trashedFirst: -1,
        selectedIndices: function () { return picked },
        rowFor: function (i) { return (i < 0 || i >= rows.length) ? null : rows[i] },
        join: function (a, b) { return a + "/" + b },
        message: function () {}, sticky: function () {},
        backend: { trash: function () {} }
    }
}

function run(check) {
    // The canvas draws this one verbatim on the Operations artboard's status strip.
    check("trash reads exactly as the canvas draws it",
          Ops.trashed(4, 0),
          "Moved 4 items to Trash \u00b7 z undoes")
    check("a trash that failed outright does not offer an undo",
          Ops.trashed(0, 1),
          "That item could not be moved to Trash.")
    check("a partly failed trash reports both halves",
          Ops.trashed(3, 1),
          "Moved 3 items to Trash, 1 failed \u00b7 z undoes")
    check("undoing a trash says where it came back from",
          Ops.undone("trash"),
          "Put it back from Trash.")

    // PR 53, W4HO-ham: the row the request went out with is the block's own first, so the cursor
    // lands where the block was and not below wherever it sat inside it.
    var block = pane(3, [2, 3])
    Ops.trash(block, 0)
    check("a block trash records the row the block leaves behind", block.trashedFirst, 2)
    var one = pane(4, [])
    Ops.trash(one, 0)
    check("one row records itself", one.trashedFirst, 4)
}
