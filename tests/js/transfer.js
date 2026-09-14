.import "../../ui/js/Transfer.js" as Transfer

// The card's own model: the count, the file line, the bar, and TransferCard.html's byte line under
// it. ops.js still covers the headline and the fraction; this suite is the line the board added.
function run(check) {
    function drawn(parts) {
        return parts.map(function (part) { return part.text }).join("|")
    }
    function inked(parts) {
        return parts.map(function (part) { return part.figure ? "f" : "w" }).join("")
    }

    // ui/js/Format.js prints the decimal units the Size column prints, so the fixtures are decimal.
    var gigabyte = 1000 * 1000 * 1000
    var megabyte = 1000 * 1000
    var oneFile = { id: 1, n: 1, moving: false, index: 0, name: "big.bin", done: 0,
                    bytes: gigabyte, total: 2 * gigabyte, moved: 0 }

    // Rule 1: one regular file is the only transfer whose total the wire knows, so it is the only
    // one that says "of", and rule 3b's estimate rides the same rate.
    check("one file names what it moved, of what, how fast and how long is left",
          drawn(Transfer.byteParts(oneFile, megabyte)),
          "1.0 GB| of |2.0 GB| · |1.0 MB/s| · |16:40| left")
    check("and the figures are inked apart from the words between them",
          inked(Transfer.byteParts(oneFile, megabyte)), "fwfwfwfw")

    // Rule 3: two seconds with no new bytes reads 0 B/s, and 3b drops the estimate rather than
    // dividing by it. What moved stays, because it did move.
    check("a stall keeps its bytes, reads zero and offers no estimate",
          drawn(Transfer.byteParts(oneFile, 0)), "1.0 GB| of |2.0 GB| · |0 B/s")

    // The wire's n is top-level items, so anything but one file has no total to state.
    var many = { id: 2, n: 21, moving: false, index: 3, name: "plate-17.raw", done: 3,
                 bytes: 12 * megabyte, total: 94 * megabyte, moved: 300 * megabyte }
    check("many items state what has moved and nothing they cannot know",
          drawn(Transfer.byteParts(many, megabyte)), "312.0 MB| copied| · |1.0 MB/s")
    check("and a move says moved",
          drawn(Transfer.byteParts(Object.assign({}, many, { moving: true }), megabyte)),
          "312.0 MB| moved| · |1.0 MB/s")

    // Rule 4: the line is absent, not blank, until the first sample lands.
    check("no byte sample draws no line at all",
          Transfer.byteParts({ id: 3, n: 1, moving: false, index: 0, name: "captures", done: 0,
                               bytes: 0, total: 0, moved: 0 }, 0).length, 0)

    // Rule 2: the running sum the client keeps, because no sweep turns a tree into a byte total.
    var afterFile = Transfer.itemDone(Object.assign({}, oneFile, { bytes: 2 * gigabyte }), 0, "big.bin")
    check("a finished file contributes the size the wire named for it",
          Transfer.movedBytes(afterFile), 2 * gigabyte)
    var tree = { id: 4, n: 2, moving: false, index: 0, name: "captures", done: 0,
                 bytes: 700 * megabyte, total: 0, moved: 0 }
    check("a finished directory contributes the running count it reported",
          Transfer.movedBytes(Transfer.itemDone(tree, 0, "captures")), 700 * megabyte)
    check("and an item that never sampled contributes nothing",
          Transfer.movedBytes(Transfer.itemDone(Transfer.itemDone(tree, 0, "captures"), 1, "empty")),
          700 * megabyte)

    // The file line goes back to naming the item and its size: the bytes are the line under the bar.
    check("the file line states the size and never the running count",
          Transfer.fileLine({ name: "captures", total: 0, bytes: 700 * megabyte }), "captures")
}
