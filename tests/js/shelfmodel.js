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

    var folder = Shelf.parse('{"items":[{"path":"/home/gm/Work/"}]}')
    check("a folder's trailing separator is not its name", folder.items[0].name, "Work")
    check("and a size the writer did not answer is not a zero", folder.items[0].bytes, -1)

    // The file is written by another process, so every one of these is a real state the bar can read.
    check("a file that is not there at all is the empty pile", Shelf.parse("").count, 0)
    check("a file caught half written is the empty pile", Shelf.parse('{"items":[{"pa').ok, false)
    check("and so is one that parses into something else", Shelf.parse('"a string"').ok, false)
    check("an items list that is not a list is refused too", Shelf.parse('{"items":{}}').ok, false)

    var mixed = Shelf.parse('{"items":[{"path":"/a"},{"bytes":3},{"path":""},{"path":"/b/c"}]}')
    check("an entry with no path of its own is dropped, and the rest stand",
          mixed.count + "|" + mixed.items[0].path + "|" + mixed.items[1].path, "2|/a|/b/c")

    check("the tooltip says what is held, because the bar itself never draws a count",
          Shelf.tooltip(Shelf.empty()) + " / " + Shelf.tooltip(one) + " / " + Shelf.tooltip(mixed),
          "Flea shelf is empty / Flea shelf is holding 1 item / Flea shelf is holding 2 items")
}
