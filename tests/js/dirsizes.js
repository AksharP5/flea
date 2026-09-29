.import "../../ui/js/DirSizes.js" as DirSizes

// A held window starting at 10, four rows, the third of which is a file, not a directory.
function heldRows() {
    return [{ n: "a", d: true }, { n: "b", d: true }, { n: "c", d: false }, { n: "d", d: true }]
}

function run(check) {
    var rows = heldRows()
    var s = DirSizes.empty()

    var ask = DirSizes.plan(s, rows, 10, 10, 13)
    check("only directory rows are asked for", ask.join(","), "10,11,13")

    check("a fresh listing has nothing pending to cancel", DirSizes.hasPending(s), false)
    s = DirSizes.applied(s, ask)
    check("a row already asked is not asked twice", DirSizes.plan(s, rows, 10, 10, 13).length, 0)
    check("a row asked and still waiting reports no size", DirSizes.sizeFor(s, 10), null)
    check("a row waiting on an answer is pending", DirSizes.hasPending(s), true)

    s = DirSizes.remember(s, 10, 4096, false, 240)
    check("an answered row reports its bytes", DirSizes.sizeFor(s, 10).bytes, 4096)
    check("and reports whether it is partial", DirSizes.sizeFor(s, 10).partial, false)
    check("and is never asked for again", DirSizes.plan(s, rows, 10, 10, 10).length, 0)
    check("rows 11 and 13 are still pending", DirSizes.hasPending(s), true)

    // A scroll cancels everything still pending, not a diff against the new viewport: the backend's
    // own dirsizecancel always means "everything queued", so the client's pending set must match.
    s = DirSizes.cancelled(s)
    check("a cancelled row can be asked for again", DirSizes.plan(s, rows, 10, 11, 11).join(","), "11")
    check("an answered row survives a cancel", DirSizes.sizeFor(s, 10).bytes, 4096)
    check("the cancelled pending row leaves the order too", s.order.length, 1)
    check("a cancel clears every pending row, so there is nothing left to cancel again", DirSizes.hasPending(s), false)

    check("an unknown row reports no size", DirSizes.sizeFor(DirSizes.empty(), 4), null)
    check("a file row is never asked for", DirSizes.plan(DirSizes.empty(), rows, 10, 12, 12).length, 0)
    check("a row outside the held window is not asked for", DirSizes.plan(DirSizes.empty(), rows, 10, 0, 3).length, 0)

    // The cap bounds a policy bug: normal use only ever records the rows a viewport held.
    var capped = DirSizes.empty()
    for (var i = 0; i < 5; i++) {
        capped = DirSizes.remember(capped, i, 1000 + i, false, 3)
    }
    check("the cap evicts the oldest entry", DirSizes.sizeFor(capped, 0), null)
    check("and keeps the newest", DirSizes.sizeFor(capped, 4).bytes, 1004)
    check("and holds exactly the cap", capped.order.length, 3)

    capped = DirSizes.remember(capped, 4, 2004, true, 3)
    check("answering one row twice does not grow the order", capped.order.length, 3)
    check("and the newer answer wins", DirSizes.sizeFor(capped, 4).bytes, 2004)
    check("including its partial flag", DirSizes.sizeFor(capped, 4).partial, true)

    check("each empty state is its own", DirSizes.empty() === DirSizes.empty(), false)

    // f037sizes: folder sizes are computed only where a size is drawn, never on network/phone.
    check("grid draws no size so it wants none", DirSizes.wantsSizes("grid", [], "", true), false)
    check("a hidden Size column wants none", DirSizes.wantsSizes("list", ["size"], "", true), false)
    check("a network folder wants none", DirSizes.wantsSizes("list", [], "network", true), false)
    check("a phone folder wants none", DirSizes.wantsSizes("list", [], "phone", true), false)
    check("an unknown class holds until fsinfo names it", DirSizes.wantsSizes("list", [], "", false), false)
    check("a visible Size column on a local folder still wants sizes", DirSizes.wantsSizes("list", [], "", true), true)
    check("the columns view on a local folder still wants sizes", DirSizes.wantsSizes("columns", [], "", true), true)
    check("usb keeps sizing", DirSizes.wantsSizes("list", [], "usb", true), true)
}
