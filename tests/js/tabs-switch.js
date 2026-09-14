.import "../../ui/js/Tabs.js" as Tabs
.import "tabsfixture.js" as Fixture

// What a tab switch restores and what it must re-list: issues 91 and 93, nixfred. The stub pane
// is tests/js/tabsfixture.js, shared with tests/js/tabs.js.

function run(check) {
    // Issue 93, nixfred: a search begun in home walks home, so its scope is where the user already
    // was. Dropping it leaves the pane's rows on the walk's results, and a destination equal to that
    // scope used to look like the one switch that re-lists nothing: the new tab showed search rows.
    var scoped = Fixture.pane("/home/gm")
    scoped.searchMode = "results"
    scoped.searchFrom = "/home/gm"
    Tabs.openNew(scoped)
    check("a tab opened onto the scope its search walked lists it again",
          scoped.listed.join(","), "/home/gm")

    var switching = Fixture.pane("/home/gm")
    Tabs.openNew(switching)
    switching.listed = []
    switching.searchMode = "results"
    switching.searchFrom = "/home/gm"
    Tabs.selectAt(switching, 0)
    check("switching to a tab standing on that scope lists it again",
          switching.listed.join(","), "/home/gm")

    var closing = Fixture.pane("/home/gm")
    Tabs.openNew(closing)
    closing.listed = []
    closing.searchMode = "results"
    closing.searchFrom = "/home/gm"
    Tabs.closeAt(closing, 1)
    check("closing a searching tab onto one on that scope lists it again",
          closing.listed.join(","), "/home/gm")

    // Issue 94, nixfred: a selection is row indices, and the one switch that re-lists nothing was
    // restoring it verbatim. Two things renumber the rows under a hidden tab and neither was checked.
    var same = Fixture.pane("/home/gm/Work")
    same.selection.toggle(3)
    same.selection.toggle(4)
    var unchanged = Tabs.snapshot(same)
    same.clearSelection()
    Tabs.apply(same, unchanged)
    check("an unchanged directory restores the selection it recorded",
          same.selectedIndices().join(","), "3,4")

    var reread = Fixture.pane("/home/gm/Work")
    reread.selection.toggle(3)
    reread.selection.toggle(4)
    var stale = Tabs.snapshot(reread)
    reread.backend.listRequests += 1
    Tabs.apply(reread, stale)
    check("a listing re-read while the tab was hidden carries none of it back",
          reread.selectedIndices().join(","), "")

    var reordered = Fixture.pane("/home/gm/Work")
    reordered.selection.toggle(3)
    reordered.thumbState = "stale"
    reordered.dirSizeState = "stale"
    reordered.tabs = { items: [], index: 0, pendingCursor: -1, pendingSortBy: "", pendingSortDesc: false }
    var otherOrder = Tabs.snapshot(reordered)
    otherOrder.sortBy = "size"
    otherOrder.sortDesc = true
    Tabs.apply(reordered, otherOrder)
    check("a different order in the other tab drops the selection and both row-indexed caches",
          reordered.selectedIndices().length + "|" + (reordered.thumbState === "stale") + "|" + (reordered.dirSizeState === "stale"),
          "0|false|false")
    check("and the order that tab recorded is the one asked for, with its first window",
          reordered.sorted.join(",") + "|" + reordered.backend.sortBy + ":" + reordered.backend.sortDesc
          + "|" + reordered.windows.join(","), "size:true|size:true|0:40")

    // A half-typed search or a filter leaves the pane's own rows in place, so only "results" re-lists:
    // widening that test would drop a selection and re-read a directory on every switch with one open.
    var typing = Fixture.pane("/home/gm")
    Tabs.openNew(typing)
    typing.listed = []
    typing.searchMode = "typing"
    typing.selection.toggle(2)
    Tabs.selectAt(typing, 0)
    check("switching with the search field open but no results re-lists nothing",
          typing.listed.join(","), "")

    // Issue 91, nixfred: an order the fresh listing already has is spent on that same reply, cursor
    // and all. Left pending it revived on the reply answering the user's next sort and reverted it.
    var already = Fixture.pane("/home/gm/a")
    already.tabs = { items: [], index: 0, pendingCursor: 9, pendingSelected: null,
                     pendingSortBy: "name", pendingSortDesc: false }
    Tabs.applyPending(already)
    check("an order the listing already has asks for no sort", already.sorted.length, 0)
    check("and the cursor is restored on that same reply", already.cursorIndex, 9)
    check("and the pending order is spent", already.tabs.pendingSortBy, "")
    already.backend.sort("size", true)
    already.sorted = []
    already.tabs.pendingCursor = -1
    Tabs.applyPending(already)
    check("so a later user sort survives the reply that answers it",
          already.sorted.length + "|" + already.backend.sortBy + ":" + already.backend.sortDesc, "0|size:true")
}
