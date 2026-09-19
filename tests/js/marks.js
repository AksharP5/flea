.import "../../ui/js/Marks.js" as Marks
.import "filterfixture.js" as Fixture

// Marking rows over whatever the filter left drawn: ctrl+A, the shift range in both forms, and
// ctrl+click. Split out of tests/js/filter.js with ui/js/Marks.js; the stub pane is shared.

function run(check) {
    var all = Fixture.pane("scr")
    Marks.selectAll(all)
    check("select all takes what is drawn, never the rows the filter hid", Fixture.picks(all), "0,1,5,6")
    var allPlain = Fixture.pane()
    Marks.selectAll(allPlain)
    check("and with no filter it still takes the whole listing", Fixture.picks(allPlain), "0,1,2,3,4,5,6")

    var span = Fixture.pane("scr")
    span.cursorIndex = 6
    Marks.extendTo(span, 1)
    check("extending over a filtered view skips the rows it hid", Fixture.picks(span), "1,5,6")
    var spanPlain = Fixture.pane()
    spanPlain.cursorIndex = 3
    Marks.extendTo(spanPlain, 1)
    check("and with no filter it is still a plain range", Fixture.picks(spanPlain), "1,2,3")

    // Shift+J whole: the anchor latches, the cursor steps through what is drawn and the selection
    // follows. "o" keeps 2, 3, 5 and 6, so two steps from row 2 reach 5 and not 4.
    var chain = Fixture.pane("o")
    chain.cursorIndex = 2
    Marks.extend(chain, 1)
    Marks.extend(chain, 1)
    check("shift J walks the selection down the rows that are drawn", Fixture.picks(chain), "2,3,5")
    check("and the cursor is on the last of them", chain.cursorIndex, 5)
    check("and the anchor stayed where the chain started", chain.selectionAnchor, 2)
    check("and the version moved once per step", chain.selectionVersion, 2)
    var chainPlain = Fixture.pane()
    chainPlain.cursorIndex = 2
    Marks.extend(chainPlain, 1)
    check("with no filter it is still a plain one-row range", Fixture.picks(chainPlain), "2,3")

    // Ctrl+click whole: an empty set means the cursor row is the selection, so it joins first.
    var joined = Fixture.pane()
    joined.cursorIndex = 2
    Marks.toggleRow(joined, 4)
    check("ctrl click on another row keeps the cursor row in the selection", Fixture.picks(joined), "2,4")
    check("and the cursor moved to the clicked row", joined.cursorIndex, 4)
    check("and the anchor is the clicked row", joined.selectionAnchor, 4)
    var held = Fixture.pane()
    held.cursorIndex = 1
    held.selection.toggle(1)
    Marks.toggleRow(held, 4)
    check("a set already holding the cursor row keeps it, marked once", Fixture.picks(held), "1,4")
    var same = Fixture.pane()
    same.cursorIndex = 3
    Marks.toggleRow(same, 3)
    check("ctrl click on the cursor row with nothing selected marks it once", Fixture.picks(same), "3")
}
