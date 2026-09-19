.import "../../ui/js/Filter.js" as Filter
.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/Ops.js" as Ops
.import "filterfixture.js" as Fixture

// Issue 92, nixfred: what the cursor is worth while a filter is running, which is the rule the
// fallback target reads when nothing is selected. The fixtures and the stub pane are filter.js's own.

function run(check) {
    var nomatch = Fixture.pane("zzz")
    nomatch.cursorIndex = 3
    check("a cursor the filter hides is not a row the pane can act on", Filter.cursorShown(nomatch), false)
    check("and its target list is empty rather than that hidden row", JSON.stringify(Ops.targetIndices(nomatch)), "[]")
    nomatch.join = function (base, name) { return base + "/" + name }
    nomatch.path = "/fixture"
    nomatch.message = function (text, failed) { nomatch.said = text }
    // The two a rename reaches once its guard lets it through, so the mutation reddens as a check
    // rather than throwing on a stub that is not there.
    nomatch.setCursor = function (i) { nomatch.cursorIndex = i }
    nomatch.renameError = ""
    nomatch.renamingIndex = -1
    Ops.startRename(nomatch)
    check("a rename opens no editor over a row with no delegate", nomatch.renamingIndex, -1)
    check("and says so rather than ignoring the key", nomatch.said, "That row is hidden by the filter.")
    nomatch.said = ""
    nomatch.backend = { trash: function () { nomatch.trashed = true } }
    Ops.trash(nomatch, 0)
    check("an operation on that cursor says so too", nomatch.said, "That row is hidden by the filter.")
    check("and no request went out", nomatch.trashed, undefined)
    // The same stub on a drawn row: a negative assertion a misspelled method satisfies is not one.
    var acts = Fixture.pane("2026")
    acts.cursorIndex = Filter.at(acts.shown, 0)
    acts.backend = { trash: function (idx) { acts.trashed = idx.join(",") } }
    acts.message = function (text, failed) { acts.said = text }
    Ops.trash(acts, 0)
    check("and the same call does go out for a row the filter draws", acts.trashed, String(acts.cursorIndex))
    // No filter at all and no cursor: the sentence must not blame a filter that is not running.
    var bare = Fixture.pane()
    bare.cursorIndex = -1
    bare.message = function (text, failed) { bare.said = text }
    bare.backend = { trash: function () { bare.trashed = true } }
    Ops.trash(bare, 0)
    check("an empty listing is not the filter's doing", bare.said, "There is nothing to act on.")
    check("and nothing went out for it either", bare.trashed, undefined)
    // A filter is running and there is no cursor under it at all, which is not the filter's doing.
    var under = Fixture.pane("zzz")
    under.cursorIndex = -1
    under.message = function (text, failed) { under.said = text }
    Ops.trash(under, 0)
    check("a filter with no cursor at all is nothing to act on", under.said, "There is nothing to act on.")
    // The window moved off the cursor, which is the third reason and the one Enter already names.
    var away = Fixture.pane("2026", 400)
    away.cursorIndex = 3
    away.message = function (text, failed) { away.said = text }
    Ops.trash(away, 0)
    check("a cursor outside the loaded window has not loaded yet", away.said, "That row has not loaded yet.")
    // Cleared first, and the opener writes its own field: the sentence below is the one Enter produced
    // rather than one the rename left, and a navigation cannot answer for it.
    nomatch.said = ""
    nomatch.opened = ""
    Nav.openCursor(nomatch, { open: function (path) { nomatch.opened = path } })
    check("and Enter says so rather than navigating away", nomatch.said, "That row is hidden by the filter.")
    check("and nothing was opened", nomatch.opened, "")

    var visible = Fixture.pane("2026")
    visible.cursorIndex = Filter.at(visible.shown, 0)
    check("a cursor the filter draws is still a row to act on", Filter.cursorShown(visible), true)
    check("and it is still the fallback target", JSON.stringify(Ops.targetIndices(visible)), "[" + visible.cursorIndex + "]")

    var hidden = Fixture.pane()
    hidden.cursorIndex = 3
    Fixture.typeInto(hidden, "2026")
    check("a cursor the filter hides lands on the first row it left standing", hidden.cursorIndex, 5)
    check("and the view scrolls to the top of the narrowed listing", hidden.scrolled, 0)

    var kept = Fixture.pane()
    kept.cursorIndex = 6
    Fixture.typeInto(kept, "2026")
    check("a cursor the filter keeps does not move", kept.cursorIndex, 6)
    check("and nothing scrolled on its account", kept.scrolled, -1)
}
