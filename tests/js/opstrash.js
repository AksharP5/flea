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

    // trashone: every confirm and status string naming a count or a scope is singular for one.
    check("one item is 'item' and two are 'items'",
          Ops.itemWord(1) + " / " + Ops.itemWord(2) + " / " + Ops.itemWord(0),
          "item / items / items")
    check("one scope is 'This Trash item is' and two are 'These Trash items are'",
          Ops.deleteScopeLine("Trash items", 1) + " // " + Ops.deleteScopeLine("Trash items", 2),
          "This Trash item is deleted from disk. This cannot be undone. // These Trash items are deleted from disk. This cannot be undone.")
    check("a menu delete names its own scope the same way",
          Ops.deleteScopeLine("items", 1),
          "This item is deleted from disk. This cannot be undone.")
    check("an empty-trash body deletes 'it' for one and 'them' otherwise",
          Ops.deleteAllLine(1, "4 KiB", "^z") + " // " + Ops.deleteAllLine(2, "4 KiB", "^z"),
          "1 item, 4 KiB. This deletes it from disk. ^z cannot undo it and the undo journal does not cover it. // 2 items, 4 KiB. This deletes them from disk. ^z cannot undo it and the undo journal does not cover it.")
    check("a finished Trash delete names its total",
          Ops.doneOf("Deleted", 1, 1) + " // " + Ops.doneOf("Deleted", 1, 2) + " // " + Ops.doneOf("Restored", 0, 1),
          "Deleted 1 of 1 item // Deleted 1 of 2 items // Restored 0 of 1 item")
    check("a non-item noun keeps its own singular",
          Ops.pluralWord(1, "operation", "operations") + " / " + Ops.pluralWord(3, "operation", "operations"),
          "operation / operations")
}
