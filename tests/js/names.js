.import "../../ui/js/Format.js" as Format
.import "../../ui/js/GridNames.js" as GridNames
.import "sourcefixture.js" as Source
.import "namesreference.js" as Ref

// Names040 board: a long name elides in the middle so the extension stays visible; the 64-character sample elides to 49 keeping ".png".
function run(check) {
    var full = "screenshot-2026-08-30-final-review-for-gm-after-the-bench-v3.png"
    check("the board sample elides to the board string",
          Format.middleElide(full, 49), "screenshot-2026-08-30-fi…m-after-the-bench-v3.png")
    check("the board sample keeps its extension",
          Format.middleElide(full, 49).slice(-4), ".png")
    check("a name shorter than the width is untouched",
          Format.middleElide("IMG_4121.jpg", 49), "IMG_4121.jpg")
    check("a name exactly at the width is untouched",
          Format.middleElide("1234567890", 10), "1234567890")
    check("a name without an extension still elides in the middle",
          Format.middleElide("a-very-long-filename-with-no-extension-at-all", 20),
          "a-very-lon…on-at-all")
    check("a dotfile shorter than the width keeps its full ink",
          Format.middleElide(".bashrc", 20), ".bashrc")
    check("a long dotfile keeps its leading dot",
          Format.middleElide(".a-very-long-hidden-config-name", 20)[0], ".")
    check("a long dotfile still elides in the middle",
          Format.middleElide(".a-very-long-hidden-config-name", 20),
          ".a-very-lo…nfig-name")
    check("an empty name stays empty",
          Format.middleElide("", 20), "")
    check("a multi-byte name never splits a surrogate pair",
          Format.middleElide("photo-📷-2026-08-30-final-review-v3.png", 20),
          "photo-📷-2…ew-v3.png")
    check("a CJK name elides to its cell budget",
          GridNames.cellsOf(Format.charsOf(Format.middleElide("写".repeat(30) + ".jpg", 20))) <= 20, true)
    check("a pair straddling the cut stays whole",
          Format.middleElide("ab📷cdefghij", 6), "ab…ij")
    check("a combining mark rides with its base through the cut",
          GridNames.elideChars(Format.charsOf("abcde\u0301x"), 5, 16).join(""), "ab…e\u0301x")
    check("a tiny width keeps one character each side",
          Format.middleElide("abcdefghij", 3), "a…j")
    check("a two-wide budget keeps the head and the mark",
          Format.middleElide("abcdefghij", 2), "a…")
    runGridCaption(check)
    runEquivalence(check)
    runNonFinite(check)
    runLaziness(check)
}

// The grid caption carries Flea's own breaks, so Qt's word wrap never strands a token on line 2.
function runGridCaption(check) {
    var full = "screenshot-2026-08-30-final-review-for-gm-after-the-bench-v3.png"
    function linesOf(caption) {
        return String(caption).split("\n")
    }
    // Each line holds at most perLine display cells; a wide glyph counts two, a surrogate pair is one char.
    function fits(caption, per) {
        var out = linesOf(caption)
        for (var i = 0; i < out.length; i++)
            if (GridNames.cellsOf(Format.charsOf(out[i])) > per)
                return false
        return true
    }
    var board = GridNames.gridCaption(full, 16, 2)
    check("the board sample breaks deterministically",
          board, "screenshot-2026-\n…he-bench-v3.png")
    check("every board line fits one line", fits(board, 16), true)
    check("the extension's dot never breaks when an earlier separator fits",
          GridNames.gridCaption("my-vacation-1.jpeg", 16, 2), "my-vacation-\n1.jpeg")
    var token = GridNames.gridCaption("a verylongnamewithoutanyspacesatall.png", 16, 2)
    check("a short word then a long token keeps the extension",
          token, "a verylongnamewi\n…spacesatall.png")
    check("every token line fits one line", fits(token, 16), true)
    check("a name that fits in one line gains no break",
          GridNames.gridCaption("IMG_4121.jpg", 16, 2), "IMG_4121.jpg")
    check("an empty name stays empty",
          GridNames.gridCaption("", 16, 2), "")
    var plain = GridNames.gridCaption("a-very-long-filename-with-no-extension-at-all", 20, 2)
    check("a name with no extension still breaks and fits", fits(plain, 20), true)
    check("a name with no extension elides only when it cannot fit",
          plain.indexOf("…") >= 0, true)
    var tiny = GridNames.gridCaption("abcd", 1, 2)
    check("a line length of 1 fits every line", fits(tiny, 1), true)
    check("a line length of 1 still answers two lines", linesOf(tiny).length, 2)
    var single = GridNames.gridCaption(full, 16, 1)
    check("one line takes no break", single.indexOf("\n") >= 0, false)
    check("one line fits and keeps the extension",
          fits(single, 16) && single.slice(-4) === ".png", true)
    var party = GridNames.gridCaption("🎉birthdaypartyphotos.jpg", 16, 2)
    check("an emoji stem keeps its extension on the last line",
          linesOf(party)[linesOf(party).length - 1].slice(-4), ".jpg")
    check("no emoji line exceeds its cells", fits(party, 16), true)
    var cjkStem = "中中中中中中中中中中中中中中中中中中中中"
    var cjk = GridNames.gridCaption(cjkStem + ".pdf", 16, 2)
    check("a CJK stem keeps its extension on the last line",
          linesOf(cjk)[linesOf(cjk).length - 1].slice(-4), ".pdf")
    check("no CJK line exceeds its cells", fits(cjk, 16), true)
    check("a wide glyph counts two cells", Format.cellWidthOf("🎉"), 2)
    check("a CJK glyph counts two cells", Format.cellWidthOf("中"), 2)
    check("a narrow glyph counts one cell", Format.cellWidthOf("a"), 1)
    check("the last line counts its cells, not its chars",
          GridNames.lastLineCells("ab\nc🎉"), 3)
    check("a dead width hands the whole name back",
          GridNames.gridCaption(full, 0, 2), full)
    check("a dead line count hands the whole name back",
          GridNames.gridCaption(full, 16, 0), full)
    check("gridBudget is gone", typeof Format.gridBudget, "undefined")
    var tile = Source.source("ui/GridTile.qml")
    check("the caption breaks through the wrap-safe helper",
          tile.indexOf("GridNames.gridCaption") >= 0, true)
    check("the wrap guess is gone",
          tile.indexOf("Format.gridBudget") >= 0, false)
    check("the caption budgets off the face it draws",
          tile.indexOf("Theme.bodySmallAdvance") >= 0, true)
    check("the caption no longer budgets off the body face",
          tile.indexOf("Theme.bodyAdvance") >= 0, false)
    check("the breaks are Flea's own, Qt only catches wide glyphs",
          tile.indexOf("wrapMode: Text.WrapAnywhere") >= 0, true)
    var labelAt = tile.indexOf("id: nameLabel")
    var tipAt = tile.indexOf("id: tip")
    var wrapAt = tile.indexOf("Text.WrapAnywhere", labelAt)
    check("WrapAnywhere sits on the caption label, ahead of the tooltip",
          labelAt >= 0 && tipAt > labelAt && wrapAt >= labelAt && wrapAt < tipAt, true)
    check("the mark sits past the last line rather than the widest one",
          tile.indexOf("GridNames.lastLineCells(nameLabel.text)") >= 0, true)
    check("the widest-line guess is gone",
          tile.indexOf("nameLabel.contentWidth") < 0, true)
    // A wide glyph that cannot straddle the first line's end must not cost the extension its last chars.
    var wide = [["中".repeat(13) + ".png", 15, ".png"], ["a" + "中".repeat(13) + "b.pdf", 16, ".pdf"], ["abc" + "中".repeat(12) + "x.jpg", 16, ".jpg"]]
    for (var w = 0; w < wide.length; w++) {
        var cap = GridNames.gridCaption(wide[w][0], wide[w][1], 2), parts = cap.split("\n")
        check("a straddling wide name keeps " + wide[w][2], parts[parts.length - 1].slice(-wide[w][2].length), wide[w][2])
        check("and every line fits its cells for " + wide[w][2], parts.every(function (l) { return GridNames.cellsOf(Format.charsOf(l)) <= wide[w][1] }), true)
    }
}

// Seeds covering ASCII, CJK wide, emoji pairs, NFD marks, separators, dotfiles and extensions.
function corpusSeeds() {
    return [
        "screenshot-2026-08-30-final-review-for-gm-after-the-bench-v3.png",
        "a-very-long-filename-with-no-extension-at-all",
        ".bashrc-hidden-config-name",
        ".profile.json",
        "name.",
        "data." + "y".repeat(48),
        "a b-c_d.e f",
        "中写漢字テスト한글αβ",
        "🎉📷🚀🎵",
        "a中🎉-_.Z",
        "e" + String.fromCharCode(769) + "clair-resume" + String.fromCharCode(769),
        "café-naïve-klinik",
        "x"
    ]
}

// One seed stretched to exactly len chars; slicing may cut a pair, which both sides see alike.
function stretched(seed, len) {
    var out = seed
    while (out.length < len) out += out
    return out.slice(0, len)
}

// Every output equals the frozen reference exactly, over lengths 0 to 300 and the full finite option ranges; non-finite budgets stay out by decision, both paths hand them through.
function runEquivalence(check) {
    var lens = [0, 1, 2, 3, 5, 8, 13, 15, 16, 17, 20, 31, 32, 33, 40, 48, 49, 64, 100, 200, 300]
    var pers = [1, 2, 7, 16, 40], counts = [1, 2, 3], budgets = [0, 1, 2, 3, 5, 10, 16, 20, 49, 80]
    var seeds = corpusSeeds(), names = []
    for (var s = 0; s < seeds.length; s++)
        for (var l = 0; l < lens.length; l++) names.push(stretched(seeds[s], lens[l]))
    var mism = 0, total = 0, first = "none"
    function same(a, b, label) {
        total += 1
        if (a !== b) {
            mism += 1
            if (first === "none") first = label + " got " + JSON.stringify(a) + " ref " + JSON.stringify(b)
        }
    }
    for (var n = 0; n < names.length; n++) {
        for (var b = 0; b < budgets.length; b++)
            same(Format.middleElide(names[n], budgets[b]), Ref.middleElide(names[n], budgets[b]), "middleElide")
        for (var p = 0; p < pers.length; p++)
            for (var c = 0; c < counts.length; c++)
                same(GridNames.gridCaption(names[n], pers[p], counts[c]), Ref.gridCaption(names[n], pers[p], counts[c]), "gridCaption")
        same(GridNames.lastLineCells(names[n]), Ref.lastLineCells(names[n]), "lastLineCells")
        same(GridNames.lastLineCells("ab\n" + names[n]), Ref.lastLineCells("ab\n" + names[n]), "lastLineCells-cut")
    }
    check("every output equals the frozen reference over " + total + " cases", mism, 0)
    check("first mismatch", first, "none")
}

// A non-finite budget names no width, so both paths hand the name through untouched.
function runNonFinite(check) {
    check("middleElide hands NaN through", Format.middleElide("abcdef", NaN), "abcdef")
    check("middleElide hands undefined through", Format.middleElide("abcdef", undefined), "abcdef")
    check("middleElide hands Infinity through", Format.middleElide("a".repeat(40), Infinity), "a".repeat(40))
    check("gridCaption hands a NaN width through", GridNames.gridCaption("abcdef", NaN, 2), "abcdef")
    check("gridCaption hands a NaN line count through", GridNames.gridCaption("abcdef", 16, NaN), "abcdef")
    check("gridCaption hands Infinity through", GridNames.gridCaption("a".repeat(40), Infinity, 2), "a".repeat(40))
    check("gridCaption hands an infinite line count through", GridNames.gridCaption("a".repeat(40), 16, Infinity), "a".repeat(40))
    runColumnRowCost(check)
}

// A Columns row lays its name out once: the column hands one budget, no row measures its own text.
function runColumnRowCost(check) {
    var row = Source.source("ui/ColumnRow.qml")
    check("a column row takes its budget from the column, not its own text width",
        row.indexOf("property int nameBudget: -1") >= 0, true)
    check("no row derives its budget from its own laid-out width",
        row.indexOf("nameText.width / Theme.bodyAdvance") < 0, true)
    check("the pane computes a plain budget per column",
        Source.source("ui/ColumnPane.qml").indexOf("readonly property int nameBudgetPlain") >= 0, true)
    check("and a chevron budget per column",
        Source.source("ui/ColumnPane.qml").indexOf("readonly property int nameBudgetChevron") >= 0, true)
    check("and hands the chevron budget to the chosen directory alone",
        Source.source("ui/ColumnPane.qml").indexOf("nameBudget: cell.showChevron ? root.nameBudgetChevron : root.nameBudgetPlain") >= 0, true)
    // The thumbnail keeps its opacity branch; ink and the mark dim in color, so the count names the branch it counts.
    check("the thumbnail keeps its single opacity branch",
        row.split("opacity: root.dimOpacity").length - 1, 1)
    check("ink and the mark glyph both dim through dimmed()",
        row.split("root.dimmed(").length - 1, 2)
    check("the middle-elision backstop stays",
        row.indexOf("elide: Text.ElideMiddle") >= 0, true)
    var list = Source.source("ui/Row.qml")
    check("a list row with an empty clipboard reads no name geometry",
        list.indexOf("id: clipLoader") < 0 && list.indexOf("x: name.x + Math.min(name.implicitWidth") >= 0, true)
}

// The common library is already loaded everywhere; Grid-only code sits behind the Grid loader.
function runLaziness(check) {
    check("Format keeps the shared middle elide", typeof Format.middleElide, "function")
    check("Format answers no grid caption", typeof Format.gridCaption, "undefined")
    check("Format answers no last line", typeof Format.lastLineCells, "undefined")
    check("Format answers no grid elide", typeof Format.elideChars, "undefined")
    check("Format answers no array-cell tail", typeof Format.tailByCells, "undefined")
    check("GridNames answers the grid caption", typeof GridNames.gridCaption, "function")
    check("GridNames answers the last line", typeof GridNames.lastLineCells, "function")
    check("GridNames answers the array-cell helpers", typeof GridNames.cellsOf, "function")
    var shared = Source.source("ui/js/Format.js")
    check("Format never imports the Grid split", shared.indexOf("GridNames") < 0, true)
    check("Format holds no grid caption", shared.indexOf("gridCaption") < 0, true)
    check("Format holds no last-line helper", shared.indexOf("lastLineCells") < 0, true)
    var split = Source.source("ui/js/GridNames.js")
    check("the split imports the common library", split.indexOf('.import "Format.js"') >= 0, true)
    check("the split imports no removed library", split.indexOf('.import "Names.js"') < 0, true)
    check("the split holds the grid caption", split.indexOf("function gridCaption") >= 0, true)
    var tile = Source.source("ui/GridTile.qml")
    check("the tile loads the Grid split", tile.indexOf('js/GridNames.js') >= 0, true)
    check("the tile loads no removed library", tile.indexOf('js/Names.js') < 0, true)
    var row = Source.source("ui/Row.qml")
    check("a list row never loads the Grid split", row.indexOf("GridNames") < 0, true)
    check("a list row loads no removed library", row.indexOf('js/Names.js') < 0, true)
    check("a list row elides through the common library", row.indexOf("Format.middleElide") >= 0, true)
    check("a list row never calls a grid caption", row.indexOf("gridCaption") < 0, true)
    var column = Source.source("ui/ColumnRow.qml")
    check("a column row never loads the Grid split", column.indexOf("GridNames") < 0, true)
    check("a column row loads no removed library", column.indexOf('js/Names.js') < 0, true)
    check("a column row elides through the common library", column.indexOf("Format.middleElide") >= 0, true)
    check("a column row never calls a grid caption", column.indexOf("gridCaption") < 0, true)
}
