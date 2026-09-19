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

    // Directive 45: a batch has no total only while the sweep beside the copy is still counting, and
    // once it settles the line reads exactly as a single file's does, time left and all.
    var settled = Object.assign({}, many, { scanned: 8400 * megabyte })
    check("a batch still counting states what has moved and nothing it cannot know",
          drawn(Transfer.byteParts(many, megabyte)), "312.0 MB| copied| · |1.0 MB/s")
    check("a batch whose scan has settled names the total and the time left",
          drawn(Transfer.byteParts(settled, megabyte)),
          "312.0 MB| of |8.4 GB| · |1.0 MB/s| · |2:14:48| left")
    check("and a stalled batch keeps its total and drops the estimate, as rule 3b says",
          drawn(Transfer.byteParts(settled, 0)), "312.0 MB| of |8.4 GB| · |0 B/s")
    // The sweep publishes once; a later sample that carries no total must not take it away again.
    var kept = Transfer.sampled(settled, 4, "plate-18.raw", 2 * megabyte, 0, 0)
    check("a sample with no total of its own keeps the one the scan settled on", kept.scanned, 8400 * megabyte)
    check("and a sample that brings one records it", Transfer.sampled(many, 4, "x", 1, 0, 77).scanned, 77)
    // Directive 50: the walk runs beside the copy with no deadline, so the total can arrive at any
    // sample, and the line has to take it then rather than having decided there is none.
    // The same sample twice, so the only thing that changes is the total the walk brings with it.
    var early = Transfer.sampled(many, 0, "one.bin", 100 * megabyte, 0, 0)
    check("a sample before the walk settles carries no total",
          Transfer.byteParts(early, megabyte).map(function (p) { return p.text }).join(""),
          "400.0 MB copied · 1.0 MB/s")
    var late = Transfer.sampled(early, 0, "one.bin", 100 * megabyte, 0, 8400 * megabyte)
    check("and the one that brings the settled total draws it, and the time left with it",
          Transfer.byteParts(late, megabyte).map(function (p) { return p.text }).join(""),
          "400.0 MB of 8.4 GB · 1.0 MB/s · 2:13:20 left")

    // The case GM actually runs: one folder to the NAS. It is n === 1 with no total of its own, so
    // asking about the count rather than about the total would have thrown its sweep away.
    var oneTree = { id: 5, n: 1, moving: false, index: 0, name: "captures", done: 0,
                    bytes: 300 * megabyte, total: 0, moved: 0, scanned: 8400 * megabyte }
    check("one directory names the total its own scan found",
          drawn(Transfer.byteParts(oneTree, megabyte)),
          "300.0 MB| of |8.4 GB| · |1.0 MB/s| · |2:15:00| left")
    // The sweep and the copy count separately, so a file appended mid-copy can pass the total.
    check("a copy that outran its own total offers no negative estimate",
          drawn(Transfer.byteParts(Object.assign({}, oneTree, { bytes: 9000 * megabyte }), megabyte)),
          "9.0 GB| of |8.4 GB| · |1.0 MB/s| · |0:00| left")

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

    // #165: an extract drives this card with no byte sample, so nothing it draws can be invented.
    var extracting = { id: 9, n: 1, moving: false, index: 0, name: "slow.zip", running: true,
                       extract: true, done: 0, bytes: 0, total: 0, moved: 0 }
    check("an extract's headline names its verb alone", Transfer.head(extracting), "Extracting")
    check("and the archive's own name is the row under it", Transfer.fileLine(extracting), "slow.zip")
    check("with no byte sample, so it draws no invented byte line", Transfer.byteParts(extracting, 0).length, 0)
    check("and the bar stays at its no-sample state", Transfer.fraction(extracting), 0)
    check("a copy's headline is unchanged", Transfer.head(oneFile), "Copying 1 of 1")
}
