.import "../../ui/js/Names.js" as Names
.import "sourcefixture.js" as Source
.import "namesreference.js" as Ref

// Names040 board: a long name elides in the middle so the extension stays visible; the 64-character sample elides to 49 keeping ".png".
function run(check) {
    var full = "screenshot-2026-08-30-final-review-for-gm-after-the-bench-v3.png"
    check("the board sample elides to the board string",
          Names.middleElide(full, 49), "screenshot-2026-08-30-fi…m-after-the-bench-v3.png")
    check("the board sample keeps its extension",
          Names.middleElide(full, 49).slice(-4), ".png")
    check("a name shorter than the width is untouched",
          Names.middleElide("IMG_4121.jpg", 49), "IMG_4121.jpg")
    check("a name exactly at the width is untouched",
          Names.middleElide("1234567890", 10), "1234567890")
    check("a name without an extension still elides in the middle",
          Names.middleElide("a-very-long-filename-with-no-extension-at-all", 20),
          "a-very-lon…on-at-all")
    check("a dotfile shorter than the width keeps its full ink",
          Names.middleElide(".bashrc", 20), ".bashrc")
    check("a long dotfile keeps its leading dot",
          Names.middleElide(".a-very-long-hidden-config-name", 20)[0], ".")
    check("a long dotfile still elides in the middle",
          Names.middleElide(".a-very-long-hidden-config-name", 20),
          ".a-very-lo…nfig-name")
    check("an empty name stays empty",
          Names.middleElide("", 20), "")
    check("a multi-byte name never splits a surrogate pair",
          Names.middleElide("photo-📷-2026-08-30-final-review-v3.png", 20),
          "photo-📷-2…ew-v3.png")
    check("a CJK name elides to its cell budget",
          Names.cellsOf(Names.charsOf(Names.middleElide("写".repeat(30) + ".jpg", 20))) <= 20, true)
    check("a pair straddling the cut stays whole",
          Names.middleElide("ab📷cdefghij", 6), "ab…ij")
    check("a combining mark rides with its base through the cut",
          Names.elideChars(Names.charsOf("abcde\u0301x"), 5, 16).join(""), "ab…e\u0301x")
    check("a tiny width keeps one character each side",
          Names.middleElide("abcdefghij", 3), "a…j")
    check("a two-wide budget keeps the head and the mark",
          Names.middleElide("abcdefghij", 2), "a…")
    runGridCaption(check)
    runEquivalence(check)
    runNonFinite(check)
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
            if (Names.cellsOf(Names.charsOf(out[i])) > per)
                return false
        return true
    }
    var board = Names.gridCaption(full, 16, 2)
    check("the board sample breaks deterministically",
          board, "screenshot-2026-\n…he-bench-v3.png")
    check("every board line fits one line", fits(board, 16), true)
    check("the extension's dot never breaks when an earlier separator fits",
          Names.gridCaption("my-vacation-1.jpeg", 16, 2), "my-vacation-\n1.jpeg")
    var token = Names.gridCaption("a verylongnamewithoutanyspacesatall.png", 16, 2)
    check("a short word then a long token keeps the extension",
          token, "a verylongnamewi\n…spacesatall.png")
    check("every token line fits one line", fits(token, 16), true)
    check("a name that fits in one line gains no break",
          Names.gridCaption("IMG_4121.jpg", 16, 2), "IMG_4121.jpg")
    check("an empty name stays empty",
          Names.gridCaption("", 16, 2), "")
    var plain = Names.gridCaption("a-very-long-filename-with-no-extension-at-all", 20, 2)
    check("a name with no extension still breaks and fits", fits(plain, 20), true)
    check("a name with no extension elides only when it cannot fit",
          plain.indexOf("…") >= 0, true)
    var tiny = Names.gridCaption("abcd", 1, 2)
    check("a line length of 1 fits every line", fits(tiny, 1), true)
    check("a line length of 1 still answers two lines", linesOf(tiny).length, 2)
    var single = Names.gridCaption(full, 16, 1)
    check("one line takes no break", single.indexOf("\n") >= 0, false)
    check("one line fits and keeps the extension",
          fits(single, 16) && single.slice(-4) === ".png", true)
    var party = Names.gridCaption("🎉birthdaypartyphotos.jpg", 16, 2)
    check("an emoji stem keeps its extension on the last line",
          linesOf(party)[linesOf(party).length - 1].slice(-4), ".jpg")
    check("no emoji line exceeds its cells", fits(party, 16), true)
    var cjkStem = "中中中中中中中中中中中中中中中中中中中中"
    var cjk = Names.gridCaption(cjkStem + ".pdf", 16, 2)
    check("a CJK stem keeps its extension on the last line",
          linesOf(cjk)[linesOf(cjk).length - 1].slice(-4), ".pdf")
    check("no CJK line exceeds its cells", fits(cjk, 16), true)
    check("a wide glyph counts two cells", Names.cellWidthOf("🎉"), 2)
    check("a CJK glyph counts two cells", Names.cellWidthOf("中"), 2)
    check("a narrow glyph counts one cell", Names.cellWidthOf("a"), 1)
    check("the last line counts its cells, not its chars",
          Names.lastLineCells("ab\nc🎉"), 3)
    check("a dead width hands the whole name back",
          Names.gridCaption(full, 0, 2), full)
    check("a dead line count hands the whole name back",
          Names.gridCaption(full, 16, 0), full)
    check("gridBudget is gone", typeof Names.gridBudget, "undefined")
    var tile = Source.source("ui/GridTile.qml")
    check("the caption breaks through the wrap-safe helper",
          tile.indexOf("Names.gridCaption") >= 0, true)
    check("the wrap guess is gone",
          tile.indexOf("Names.gridBudget") >= 0, false)
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
          tile.indexOf("Names.lastLineCells(nameLabel.text)") >= 0, true)
    check("the widest-line guess is gone",
          tile.indexOf("nameLabel.contentWidth") < 0, true)
    // A wide glyph that cannot straddle the first line's end must not cost the extension its last chars.
    var wide = [["中".repeat(13) + ".png", 15, ".png"], ["a" + "中".repeat(13) + "b.pdf", 16, ".pdf"], ["abc" + "中".repeat(12) + "x.jpg", 16, ".jpg"]]
    for (var w = 0; w < wide.length; w++) {
        var cap = Names.gridCaption(wide[w][0], wide[w][1], 2), parts = cap.split("\n")
        check("a straddling wide name keeps " + wide[w][2], parts[parts.length - 1].slice(-wide[w][2].length), wide[w][2])
        check("and every line fits its cells for " + wide[w][2], parts.every(function (l) { return Names.cellsOf(Names.charsOf(l)) <= wide[w][1] }), true)
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
            same(Names.middleElide(names[n], budgets[b]), Ref.middleElide(names[n], budgets[b]), "middleElide")
        for (var p = 0; p < pers.length; p++)
            for (var c = 0; c < counts.length; c++)
                same(Names.gridCaption(names[n], pers[p], counts[c]), Ref.gridCaption(names[n], pers[p], counts[c]), "gridCaption")
        same(Names.lastLineCells(names[n]), Ref.lastLineCells(names[n]), "lastLineCells")
        same(Names.lastLineCells("ab\n" + names[n]), Ref.lastLineCells("ab\n" + names[n]), "lastLineCells-cut")
    }
    check("every output equals the frozen reference over " + total + " cases", mism, 0)
    check("first mismatch", first, "none")
}

// A non-finite budget names no width, so both paths hand the name through untouched.
function runNonFinite(check) {
    check("middleElide hands NaN through", Names.middleElide("abcdef", NaN), "abcdef")
    check("middleElide hands undefined through", Names.middleElide("abcdef", undefined), "abcdef")
    check("middleElide hands Infinity through", Names.middleElide("a".repeat(40), Infinity), "a".repeat(40))
    check("gridCaption hands a NaN width through", Names.gridCaption("abcdef", NaN, 2), "abcdef")
    check("gridCaption hands a NaN line count through", Names.gridCaption("abcdef", 16, NaN), "abcdef")
    check("gridCaption hands Infinity through", Names.gridCaption("a".repeat(40), Infinity, 2), "a".repeat(40))
    check("gridCaption hands an infinite line count through", Names.gridCaption("a".repeat(40), 16, Infinity), "a".repeat(40))
    runColumnRowCost(check)
}

// A Columns row lays its name out once: the column hands one budget, no row measures its own text.
function runColumnRowCost(check) {
    var row = Source.source("ui/ColumnRow.qml")
    check("a column row takes its budget from the column, not its own text width",
        row.indexOf("property int nameBudget: -1") >= 0, true)
    check("no row derives its budget from its own laid-out width",
        row.indexOf("nameText.width / Theme.bodyAdvance") < 0, true)
    check("the pane computes one budget per column",
        Source.source("ui/ColumnPane.qml").indexOf("readonly property int nameBudget") >= 0, true)
    check("and hands it to every row it builds",
        Source.source("ui/ColumnPane.qml").indexOf("nameBudget: root.nameBudget") >= 0, true)
    check("one content carries the dim",
        row.split("opacity: root.dimOpacity").length - 1, 1)
    check("the middle-elision backstop stays",
        row.indexOf("elide: Text.ElideMiddle") >= 0, true)
    var list = Source.source("ui/Row.qml")
    check("a list row with an empty clipboard reads no name geometry",
        list.indexOf("x: root.clipMark.length > 0 ? name.x") >= 0, true)
}
