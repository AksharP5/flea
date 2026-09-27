.import "../../ui/js/ClipMarks.js" as ClipMarks

// ClipMarks board: a row on the clipboard carries a mark after its name,
// copy for copied and scissors for cut, and the mark follows the clipboard.
function run(check) {
    function pane(path) {
        return { path: path, join: function (base, name) { return base === "/" ? "/" + name : base + "/" + name } }
    }
    var home = pane("/home/gm/Pictures/phone")

    // An empty clipboard costs nothing: no lookup, no path built, no mark.
    check("an empty clipboard marks nothing",
          ClipMarks.markForRow(home, "IMG_4121.jpg", { paths: [], moving: false }), "")
    check("a null clipboard marks nothing",
          ClipMarks.markForRow(home, "IMG_4121.jpg", null), "")
    check("an unnamed row marks nothing even with a full clipboard",
          ClipMarks.markForRow(home, "", { paths: ["/home/gm/Pictures/phone/IMG_4121.jpg"], moving: false }), "")

    var copied = { paths: ["/home/gm/Pictures/phone/IMG_4121.jpg",
                            "/home/gm/Pictures/phone/IMG_4122.jpg",
                            "/home/gm/Pictures/phone/IMG_4123.jpg"], moving: false }
    check("a copied row carries the copy mark",
          ClipMarks.markForRow(home, "IMG_4121.jpg", copied), "copy")
    check("a row outside the clipboard carries no mark",
          ClipMarks.markForRow(home, "IMG_4124.jpg", copied), "")
    check("a same-named row in another folder carries no mark",
          ClipMarks.markForRow(pane("/home/gm/Pictures/other"), "IMG_4121.jpg", copied), "")

    var cut = { paths: ["/home/gm/Pictures/phone/IMG_4121.jpg"], moving: true }
    check("a cut row carries the scissors mark",
          ClipMarks.markForRow(home, "IMG_4121.jpg", cut), "scissors")

    // The mark follows the clipboard: a new copy clears the old cut at once.
    var afterCopy = { paths: ["/home/gm/Pictures/phone/IMG_4124.jpg"], moving: false }
    check("a new copy clears the old cut mark",
          ClipMarks.markForRow(home, "IMG_4121.jpg", afterCopy)
          + "/" + ClipMarks.markForRow(home, "IMG_4124.jpg", afterCopy), "/copy")
    // And a new cut clears the old copy.
    var afterCut = { paths: ["/home/gm/Pictures/phone/IMG_4124.jpg"], moving: true }
    check("a new cut clears the old copy mark",
          ClipMarks.markForRow(home, "IMG_4121.jpg", afterCut)
          + "/" + ClipMarks.markForRow(home, "IMG_4124.jpg", afterCut), "/scissors")

    // A paste that spends a cut clears the marks; a copy paste keeps them.
    check("spending a cut empties the clipboard",
          JSON.stringify(ClipMarks.spent(cut, true)), JSON.stringify({ paths: [], moving: false }))
    check("a copy paste keeps the clipboard",
          JSON.stringify(ClipMarks.spent(copied, false)), JSON.stringify(copied))

    // The row path is the pane's own join, so a search result resolves against
    // the scope the pane is standing on, which Search.run made its path.
    check("a row path joins the pane path",
          ClipMarks.rowPath(home, "IMG_4121.jpg"), "/home/gm/Pictures/phone/IMG_4121.jpg")
    check("a row path off the root keeps its single separator",
          ClipMarks.rowPath(pane("/"), "boot"), "/boot")
    check("an unnamed row has no path",
          ClipMarks.rowPath(home, ""), "")
}
