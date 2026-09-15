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

    // ShelfEmpty rules 2, 4, 5 and 7: the tray, what it says, and the routes the empty card names.
  var shots = Shelf.parseCaptures("1757890932000 /home/gm/Pictures/screenshot-2026-09-14_19-02-11.png\n"
                                  + "1757889660000 /home/gm/Videos/screenrecording-2026-09-14_18-41-00.mp4\n"
                                  + "bad line with no time\n")
  check("a capture line is its time and its path, and a line that is neither is dropped", shots.length, 2)
  check("a recording is known by its own extension and never decoded",
        shots[0].recording + "|" + shots[1].recording, "false|true")
  check("the tray says the time of day, in the one clock this project draws",
        Shelf.captureTime(shots[0].at).length + "|" + Shelf.captureTime(shots[0].at).charAt(2), "5|:")
  check("a time that is not one draws nothing", Shelf.captureTime("not a time"), "")

  check("the empty card names only the routes that are on",
        Shelf.routesHint({ edge: "right", mark: false, bind: "super+d" }),
        "throw at the right edge \u00b7 super+d opens")
  check("and with only the mark on, it names that one", Shelf.routesHint({ edge: "", mark: true, bind: "" }),
        "the bar mark opens")
  check("with every route off it advertises no gesture at all", Shelf.routesHint({}), "")
  check("an empty shelf with shots to hand says what the tray does",
        Shelf.emptyHint(Shelf.empty(), shots, { mark: true }), "click to add \u00b7 drag to take it straight out")
  check("an empty shelf with nothing recent names the routes instead",
        Shelf.emptyHint(Shelf.empty(), [], { edge: "right", mark: true, bind: "" }),
        "throw at the right edge \u00b7 the bar mark opens")
  check("and a shelf that is holding says none of it", Shelf.emptyHint(one, shots, { mark: true }), "")
  check("the header says an empty shelf is empty", Shelf.headerText(Shelf.empty()), "Shelf  empty")
  check("the hint is the footer's last voice, behind the hovered row and the error",
        Shelf.footerText("", "", "", "click to add") + "|" + Shelf.footerText("/x/a", "", "", "click to add"),
        "click to add|/x/a")

  // Summon: the bell, the cleared transient, and what the Recent piles rows say.
  check("a summon file nobody has written yet has rung nothing", Shelf.ringsOf(""), 0)
  check("and one that is half written is not a ring either", Shelf.ringsOf('{"summ'), 0)
  check("each write of the file is one more ring", Shelf.ringsOf('{"summon":7}'), 7)
  check("the cleared transient says how to get it back",
        Shelf.clearedText(4) + "|" + Shelf.clearedText(1),
        "Cleared 4 items \u00b7 z restores|Cleared 1 item \u00b7 z restores")
  check("clearing an empty shelf says nothing at all", Shelf.clearedText(0), "")

  var kept = Shelf.parsePiles("1789426925000 4\n1789420000000 2\nnot a pile\n")
  check("a kept pile is its time and its count, and a line that is neither is dropped", kept.length, 2)
  var row = Shelf.pileText({ count: 4, at: 1789426925000 })
  check("a pile row says how many and when, in the one date format this project draws",
        row.slice(0, 10) + "|" + row.slice(10).length + "|" + row.charAt(14) + row.charAt(17) + row.charAt(23),
        "4 items \u00b7 |16|--:")
  check("a time that is not one leaves the stamp out rather than printing nonsense",
        Shelf.stamp("never"), "")
  check("and one item is one item", Shelf.pileText({ count: 1, at: 1789426925000 }).slice(0, 7), "1 item ")

  // EdgeRail: what a drop on the wall is offering, and what the header says while it hovers.
  var uris = Shelf.pathsFromUris("file:///home/gm/Pictures/one%20two.png\r\nfile:///tmp/a.txt\r\n")
  check("a uri list is read as paths, percent escapes and all", uris.join("|"),
        "/home/gm/Pictures/one two.png|/tmp/a.txt")
  check("a comment line and a foreign scheme are not paths",
        Shelf.pathsFromUris("# a comment\nhttps://example.com/x\nfile:///tmp/b\n").join("|"), "/tmp/b")
  check("and a drop carrying nothing is no paths at all", Shelf.pathsFromUris("").length, 0)
  check("the header says what letting go would do, and the way out when nothing is coming",
        Shelf.headerRight(2) + "|" + Shelf.headerRight(0), "drop to add 2|esc")

  check("the tooltip says what is held, because the bar itself never draws a count",
          Shelf.tooltip(Shelf.empty()) + " / " + Shelf.tooltip(one) + " / " + Shelf.tooltip(mixed),
          "Flea shelf is empty / Flea shelf is holding 1 item / Flea shelf is holding 2 items")
}
