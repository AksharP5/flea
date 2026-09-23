.import "../../ui/js/Anchor.js" as Anchor
.import "../../ui/js/Collide.js" as Collide
.import "../../ui/js/Drag.js" as Drag
.import "../../ui/js/Ops.js" as Ops
.import "../../ui/js/Swap.js" as Swap
.import "collidefixture.js" as Fixture

// The collision card's decisions, and that every paste and drop asks it before anything is sent.

function names(list) {
    return list.map(function (n) { return { n: n, d: false, i: "image-x-generic" } })
}

function run(check) {
    // The board's two titles, word for word.
    check("one name says which and where", Collide.title(names(["screenshot.png"]), 1, "/home/gm/Pictures"),
          "screenshot.png already exists in Pictures")
    check("several say how many", Collide.title(names(["a", "b", "c"]), 3, "/home/gm/Downloads"),
          "3 items already exist in Downloads")
    check("a count past the list still says the whole count", Collide.title(names(["a", "b", "c"]), 12, "/home/gm/Downloads"),
          "12 items already exist in Downloads")
    check("the root has no leaf, so it names itself", Collide.folderName("/"), "/")
    check("a trailing name is the folder", Collide.folderName("/home/gm/Pictures"), "Pictures")

    // The row under the list: absent while every collision is on it.
    check("three of three needs no more line", Collide.more(3, 3), "")
    check("one past the list", Collide.more(4, 3), "and 1 more")
    check("many past it", Collide.more(40, 3), "and 37 more")
    check("the explanation is one sentence", Collide.EXPLAIN, "Replaced items go to Trash, and Undo restores them.")

    // Focus: Keep both first, h and l stop at the ends, Tab and Backtab come round.
    check("the card opens on Keep both", Collide.START, "keep")
    check("the buttons read left to right", Collide.BUTTONS.map(function (b) { return Collide.LABELS[b] }).join("|"),
          "Cancel|Skip|Keep both|Replace")
    check("l steps right", Collide.moved("keep", Qt.Key_L), "replace")
    check("Right is l", Collide.moved("skip", Qt.Key_Right), "keep")
    check("l stops at Replace", Collide.moved("replace", Qt.Key_L), "replace")
    check("h steps left", Collide.moved("keep", Qt.Key_H), "skip")
    check("Left is h", Collide.moved("skip", Qt.Key_Left), "cancel")
    check("h stops at Cancel", Collide.moved("cancel", Qt.Key_H), "cancel")
    check("Tab comes round from Replace", Collide.moved("replace", Qt.Key_Tab), "cancel")
    check("Backtab comes round from Cancel", Collide.moved("cancel", Qt.Key_Backtab), "replace")
    check("Tab walks every button left to right", ["cancel", "skip", "keep"].map(function (b) { return Collide.moved(b, Qt.Key_Tab) }).join("|"),
          "skip|keep|replace")
    check("and Backtab walks them back", ["skip", "keep", "replace"].map(function (b) { return Collide.moved(b, Qt.Key_Backtab) }).join("|"),
          "cancel|skip|keep")
    check("any other key leaves the focus", Collide.moved("skip", Qt.Key_J), "skip")
    check("Enter takes the focused choice", Collide.activates(Qt.Key_Return) && Collide.activates(Qt.Key_Enter), true)
    check("and so does Space", Collide.activates(Qt.Key_Space), true)
    check("Escape is not an activation, it cancels", Collide.activates(Qt.Key_Escape), false)

    // The question names the same sources the transfer will.
    var byPath = { c: "transfer", op: "copy", paths: ["/a/x.png"], dest: "/b" }
    check("a paste asks about its paths", JSON.stringify(Collide.question(byPath, null, 4)),
          JSON.stringify({ c: "collisions", id: 4, dest: "/b", paths: ["/a/x.png"] }))
    var byRows = { c: "transfer", op: "move", rows: [2, 3], dest: "/d/omarchy" }
    check("a row drop asks about its rows", JSON.stringify(Collide.question(byRows, null, 5)),
          JSON.stringify({ c: "collisions", id: 5, dest: "/d/omarchy", rows: [2, 3] }))
    var shelf = { c: "transfer", op: "", paths: [], dest: "/e", shelf: "tok" }
    check("a shelf drop asks about the paths its drag carries", JSON.stringify(Collide.question(shelf, ["/s/a.txt"], 6)),
          JSON.stringify({ c: "collisions", id: 6, dest: "/e", paths: ["/s/a.txt"] }))
    var copyTo = { c: "transfer", op: "copy", menuId: 31, dest: "/f" }
    check("Copy to asks about the menu's own selection", JSON.stringify(Collide.question(copyTo, null, 7)),
          JSON.stringify({ c: "collisions", id: 7, dest: "/f", menuId: 31 }))
    var dropbox = { c: "transfer", op: "move", rows: [1, 2], dest: "/dropbox", menuId: 32 }
    check("and so does Move to Dropbox, whose rows the backend never reads beside a menu",
          JSON.stringify(Collide.question(dropbox, null, 8)), JSON.stringify({ c: "collisions", id: 8, dest: "/dropbox", menuId: 32 }))
    check("the answer rides on the transfer it was asked for", JSON.stringify(Collide.transfer(byPath, "replace", 4)),
          JSON.stringify({ c: "transfer", op: "copy", paths: ["/a/x.png"], dest: "/b", collide: "replace", collideId: 4 }))
    check("and the waiting request itself is not changed", byPath.collide, undefined)
    check("nothing colliding still says refuse", Collide.NONE, "refuse")
    check("a question still in flight refuses a second ask out loud", Collide.refusal(false, byPath), Collide.WAITING)
    check("and so does an open card", Collide.refusal(true, byPath), Collide.WAITING)
    check("even with nothing waiting behind it", Collide.refusal(true, null), Collide.WAITING)
    check("with nothing waiting a question may go", Collide.refusal(false, null), "")
    // A refused question ends the wait the same way an answered one does: the card never opens.
    check("a refused collisions question drops the wait, so the next paste may ask again",
          Collide.droppedPending("stale", "collisions"), true)
    check("any other refusal holds nothing of the card's",
          Collide.droppedPending("stale", "transfer") + "|" + Collide.droppedPending("scan", "collisions"), "false|false")

    // ui/CollideHost.qml ask() stamps rows read under listing 4; a rows line in listing 5 lands before the choice sends them.
    var captured = Collide.waiting(byRows, 4)
    check("rows the card holds keep the numbering they were read in", captured.listing, 4)
    check("and the question about them names it", Collide.question(captured, null, 9).listing, 4)
    check("so ui/Backend.qml send() in listing 5 still sends the transfer as 4, which the backend refuses",
          Swap.named(Collide.transfer(captured, "replace", 9), 5).listing, 4)
    check("an unstamped row request takes the numbering in force", Swap.named(byRows, 5).listing, 5)
    check("while a request naming no rows, or one before any rows line, is never stamped",
          Swap.named(byPath, 4).listing + "|" + Swap.named(byRows, 0).listing, "undefined|undefined")
    check("and the request the card was handed is not changed", byRows.listing, undefined)
    check("a menu's transfer is the menu's own capture, so its unread rows take the numbering in force at the send",
          Collide.waiting(dropbox, 4).listing + "|" + Swap.named(Collide.transfer(Collide.waiting(dropbox, 4), "keep", 8), 5).listing,
          "undefined|5")

    // A paste asks rather than sends, and leaves a cut on the clipboard until the transfer goes out.
    var asked = []
    var pane = { path: "/dest", clipboard: { paths: ["/src/a.txt"], moving: true },
                 collide: { ask: function (request, probe, cut) { asked.push([request, probe, cut]) } } }
    Ops.paste(pane)
    check("a paste asks the question first", asked.length === 1 ? asked[0][0].c + " " + asked[0][0].op + " " + asked[0][0].dest : "none",
          "transfer move /dest")
    check("a cut paste is marked as spending the cut", asked[0][2], true)
    check("and the cut stays until the answer sends it", pane.clipboard.paths.length, 1)
    pane.clipboard = { paths: ["/src/a.txt"], moving: false }
    Ops.paste(pane)
    check("a copy paste asks a copy that spends nothing", asked[1][0].op + " " + asked[1][2], "copy false")

    // Drops ask too, and a shelf drop asks about the paths its drag carries while its token names what moves.
    var sent = []
    var answer = false
    asked = []
    var drops = { path: "/d", rowFor: function () { return { n: "omarchy", d: true } }, join: function (a, b) { return a + "/" + b },
                  backend: { send: function (msg) { sent.push(msg) } },
                  collide: { ask: function (request, probe) { asked.push([request, probe]); return answer } } }
    check("a row drop answers the card's refusal", Drag.drop(drops, [2], 0, false), false)
    check("a path drop does too", Drag.dropInto(drops, "", ["file:///x/a.txt"], "/e", 0), false)
    check("a shelf drop asks with the paths its drag carries",
          Drag.dropInto(drops, "", ["file:///s/a.txt"], "/e", 0, "tok\nmove") + " " + (asked[2] ? JSON.stringify(asked[2][1]) : "not asked"), "false [\"/s/a.txt\"]")
    answer = true
    check("and each answers the card's acceptance, not a false of its own",
          Drag.drop(drops, [2], 0, false, 7) + " " + Drag.dropInto(drops, "", ["file:///x/a.txt"], "/e", 0), "true true")
    check("a row drop names the listing it is handed rather than none", asked[3][0].listing, 7)
    check("every drop asked and none went straight to the backend", asked.length + " " + sent.length, "5 0")
    var lifted = { c: "transfer", op: "move", rows: [2], dest: "/d/omarchy", listing: 7 }
    check("a request already stamped, a drag lifted in 7, keeps 7 when the card asks while the pane holds 8",
          Collide.waiting(lifted, 8).listing + "|" + Collide.question(Collide.waiting(lifted, 8), null, 10).listing, "7|7")

    wired(check)
}

// The real ui/FileDrag.qml, ui/RowDrag.qml and ui/CollideHost.qml: a row lifted in 7, a re-list to 8 while it is up, the drop, Replace.
function wired(check) {
    var at = Fixture.scene(7)
    var backend = at.backend, p = at.pane, session = at.session, target = at.target
    check("a pane at rest holds no watched re-read back", Anchor.busy(p), false)
    var taken = false
    // Every payload field is fixed once the lift sets its feedback, and offscreen's platform drag returns at once, so the drop lands here.
    session.feedbackChanged.connect(function () {
        if (session.feedback === null)
            return
        backend.heldListing = 8
        taken = target.dropped(session.dragMime[Drag.ROWS_MIME], [], "")
    })
    session.liftBegan(0, { modifiers: Qt.NoModifier })
    check("a row lifted in 7 and dropped on a folder after a re-list to 8 asks about its rows in 7",
          taken + " " + JSON.stringify(backend.sent),
          "true " + JSON.stringify([{ c: "collisions", id: 1, dest: "/d/omarchy", rows: [0], listing: 7 }]))
    check("the watched re-read waits while the card holds the transfer", Anchor.busy(p), true)
    var released = ""
    // The first moment it lets go, since a var property signals every null written to it.
    p.collide.pendingChanged.connect(function () {
        if (p.collide.pending === null && released === "")
            released = Fixture.verbs(backend) + "|" + Anchor.busy(p)
    })
    p.collide.decide("replace")
    var transfer = backend.sent[1] || {}
    check("Replace sends it in 7 while 8 is in force, so the backend refuses it rather than moving another file",
          transfer.c + " " + JSON.stringify(transfer.rows) + " " + transfer.listing + " " + transfer.collide, "transfer [0] 7 replace")
    check("and writes it before the card lets go of it, which is what frees the re-read", released, "collisions,transfer|false")
    p.collide.ask({ c: "transfer", op: "move", paths: ["/s/a.txt"], dest: "/d" }, null, true)
    p.collide.decide("cancel")
    check("a Cancel writes only its question, lets go, and leaves the cut on the clipboard",
          Fixture.verbs(backend) + "|" + (p.collide.pending === null) + "|" + p.clipboard.paths.length, "collisions,transfer,collisions|true|1")
    at.parent.destroy()
}
