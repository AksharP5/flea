.import "../../ui/js/Transfer.js" as Transfer
.import "../../ui/js/Ops.js" as Ops

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

    // GM on 0.3.5: the bar never moved while the line under it counted. One folder is n === 1 with no total of
    // its own, so the bar must read the sweep's total the line reads. Sample: {"t":"transferprogress","id":3,
    // "index":0,"name":"Photos","bytes":1200000000,"total":0,"scanned":3400000000}
    var oneFolder = Transfer.sampled(Ops.started(3, false, 1, false), 0, "Photos", 1200000000, 0, 3400000000)
    check("one folder's bar follows the bytes against the sweep's total",
          Math.round(Transfer.fraction(oneFolder) * 1000) / 1000, 0.353)
    var twoFolders = Object.assign(Transfer.sampled(Ops.started(4, false, 2, false), 1, "Music", 720000000, 0, 3400000000),
                                   { moved: 2000000000 })
    check("the second of two folders counts the first one's bytes, not half the bar per folder",
          Transfer.fraction(twoFolders), 0.8)
    check("the line under the bar names the same total the bar fills against",
          drawn(Transfer.byteParts(oneFolder, 0)).indexOf("3.4 GB") >= 0, true)
    check("a copy's headline is unchanged", Transfer.head(oneFile), "Copying 1 of 1")
    check("a four-figure transfer groups its headline",
          Transfer.head({ moving: false, n: 1204, index: 203 }), "Copying 204 of 1,204")

    // Durability: the final flush. Sample progress line:
    // {"t":"transferprogress","id":12,"index":0,"name":"","bytes":0,"total":0,"scanned":0,"phase":"writing","drive":"128GB"}
    var copying = { id: 12, n: 5, moving: false, index: 4, name: "clip-05.mp4", done: 4,
                    bytes: 1300000000, total: 1300000000, moved: 2100000000, scanned: 3400000000,
                    running: true }
    var flushed = Transfer.markWriting(Transfer.itemDone(copying, 4, "clip-05.mp4"), "128GB")
    check("the final flush headlines the drive instead of a count",
          Transfer.head(flushed), "Writing to 128GB")
    check("with no drive named it says the drive rather than nothing",
          Transfer.head(Transfer.markWriting(Transfer.itemDone(copying, 4, "clip-05.mp4"), "")),
          "Writing to the drive")
    check("the flush carries no file line",
          Transfer.fileLine(flushed), "")
    check("the byte line counts the confirmed bytes and waits for the drive",
          drawn(Transfer.byteParts(flushed, megabyte)),
          "3.4 GB| copied · waiting for the drive")
    check("and a move says moved",
          drawn(Transfer.byteParts(Transfer.markWriting(
              Transfer.itemDone(Object.assign({}, copying, { moving: true }), 4, "clip-05.mp4"), "128GB"), megabyte)),
          "3.4 GB| moved · waiting for the drive")
    check("the bar is full and flat",
          Transfer.fraction(flushed), 1)
    check("the card stays up through the flush",
          flushed.running, true)
    check("Cancel is dimmed there because every file is already complete",
          Transfer.cancelEnabled(flushed), false)
    check("while a running copy still offers it",
          Transfer.cancelEnabled(copying), true)
    check("and an idle transfer has nothing to cancel",
          Transfer.cancelEnabled({ running: false }), false)
    check("the flush keeps the counted bytes and spends the sample",
          flushed.moved + "|" + flushed.bytes + "|" + flushed.total + "|" + flushed.name,
          "3400000000|0|0|")
}
