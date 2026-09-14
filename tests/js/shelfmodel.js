.import "../../shelf/Model.js" as Shelf

// The shelf plugin's own pure half. It lives here while the plugin lives in this tree; it moves with
// shelf/ when GM splits it into its own repository, which is why it imports across rather than up.

function run(check) {
    check("nothing read yet is an empty pile rather than an undefined one",
          Shelf.empty().count + "|" + Shelf.empty().items.length + "|" + Shelf.empty().ok, "0|0|false")

    var one = Shelf.parse('{"items":[{"path":"/home/gm/Work/a.txt","bytes":1024}]}')
    check("a pile of one names its row from the path", one.items[0].name, "a.txt")
    check("and carries the bytes the writer answered", one.items[0].bytes, 1024)
    check("and counts what it holds", one.count + "|" + one.ok, "1|true")

    var folder = Shelf.parse('{"items":[{"path":"/home/gm/Work/","folder":true}]}')
    check("a folder is named by its own leaf and wears its separator", folder.items[0].name, "Work/")
    check("and a size the writer did not answer is not a zero", folder.items[0].bytes, -1)

    // The file is written by another process, so every one of these is a real state the bar can read.
    check("a file that is not there at all is the empty pile", Shelf.parse("").count, 0)
    check("a file caught half written is the empty pile", Shelf.parse('{"items":[{"pa').ok, false)
    check("and so is one that parses into something else", Shelf.parse('"a string"').ok, false)
    check("an items list that is not a list is refused too", Shelf.parse('{"items":{}}').ok, false)

    var mixed = Shelf.parse('{"items":[{"path":"/a"},{"bytes":3},{"path":""},{"path":"/b/c"}]}')
    check("an entry with no path of its own is dropped, and the rest stand",
          mixed.count + "|" + mixed.items[0].path + "|" + mixed.items[1].path, "2|/a|/b/c")

    // Main rule 4: a size nobody has answered yet is one dot, and a walk cut short keeps its prefix.
    check("a size not yet answered is a dot", Shelf.sizeText(folder.items[0]), "\u00b7")
    check("a size that is known reads as Flea's own", Shelf.sizeText({ bytes: 4600000 }), "4.6 MB")
    check("and a walk cut short keeps its own prefix", Shelf.sizeText({ bytes: 138, partial: true }), ">138 B")
    // Rule 5: one slot, one voice, in the order the card draws them.
    check("the footer says the error before anything else", Shelf.footerText("/x/a", "Copied", "That failed."), "That failed.")
    check("then the hovered row's own path", Shelf.footerText("/x/a", "Copied", ""), "/x/a")
    check("then the last result, and nothing at all when there is none", 
          Shelf.footerText("", "Copied", "") + "|" + Shelf.footerText("", "", ""), "Copied|")

    // Main rule 4's budget: one request per drawn path, never twice, and never for a path off the card.
    var pile = Shelf.parse('{"items":[{"path":"/a","bytes":12},{"path":"/b/big","folder":true},{"path":"/c"}]}')
    check("the first ask is the first row the writer left without a size", Shelf.nextSize(pile, {}), "/b/big")
    var answered = { "/b/big": { bytes: 4096, partial: true } }
    check("an answered path is never asked again, so the ask moves on", Shelf.nextSize(pile, answered), "/c")
    answered["/c"] = { bytes: -1, partial: false }
    check("a path that could not be read is answered too, so nothing loops", Shelf.nextSize(pile, answered), "")
    var drawn = Shelf.sized(pile, answered)
    check("the writer's own bytes stand where it had them", drawn.items[0].bytes, 12)
    check("the answer fills the row that had none, prefix and all", Shelf.sizeText(drawn.items[1]), ">4.1 kB")
    check("and a path that could not be read draws the same dot a pending one does", Shelf.sizeText(drawn.items[2]), "\u00b7")
    check("the drawn pile keeps its own shape", drawn.count + "|" + drawn.items[1].name, "3|big/")
    var pruned = Shelf.keep(answered, Shelf.parse('{"items":[{"path":"/c"}]}'))
    check("a size the card is no longer drawing is not kept",
          (pruned["/b/big"] === undefined) + "|" + pruned["/c"].bytes, "true|-1")

    check("the tooltip says what is held, because the bar itself never draws a count",
          Shelf.tooltip(Shelf.empty()) + " / " + Shelf.tooltip(one) + " / " + Shelf.tooltip(mixed),
          "Flea shelf is empty / Flea shelf is holding 1 item / Flea shelf is holding 2 items")
}
