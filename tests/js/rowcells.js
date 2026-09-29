// Row.qml cells diet: the four metadata cells are plain Texts inside Row.qml, each binding straight to the row's own state with no pass-through layer.
.import "sourcefixture.js" as Source

function countRe(text, re) {
    var found = text.match(re)
    return found ? found.length : 0
}

// The text of one cell, from its id line to the brace that closes it.
// Sample input: "    Text {\n        id: size\n        ...\n    }\n".
function cellBlock(row, id) {
    var start = row.indexOf("id: " + id + "\n")
    var end = start < 0 ? -1 : row.indexOf("\n    }\n", start)
    // A missing closer, or one past the next sibling's own Text, reads as no cell rather than as a sibling's lines.
    var next = start < 0 ? -1 : row.indexOf("\n    Text {", start)
    return start < 0 || end < 0 || (next >= 0 && next < end) ? "" : row.slice(start, end)
}

function run(check) {
    var row = Source.source("ui/Row.qml")
    // No component cells are left: each cell is one Text with the row's own ids, and the split files are gone.
    check("Row builds no RowMode", countRe(row, /RowMode\s*\{/g), 0)
    check("Row builds no RowSize", countRe(row, /RowSize\s*\{/g), 0)
    check("Row builds no RowDate", countRe(row, /RowDate\s*\{/g), 0)
    check("Row builds no RowKind", countRe(row, /RowKind\s*\{/g), 0)
    check("Row builds four inline Texts by id",
        (row.indexOf("id: mode") >= 0 ? 1 : 0) + (row.indexOf("id: size") >= 0 ? 1 : 0)
        + (row.indexOf("id: modified") >= 0 ? 1 : 0) + (row.indexOf("id: kind") >= 0 ? 1 : 0), 4)
    check("each inline cell roots one Text", countRe(row, /^    Text\s*\{\s*$/gm), 4)
    // No pass-through property survives: no ink, cellText, modeShown, sizeWidth or dateWidth handed down.
    check("no cell takes an ink handoff", countRe(row, /ink:\s*root\.cell/g), 0)
    check("no cell takes handed text", countRe(row, /cellText:/g), 0)
    check("no cell takes handed flags", countRe(row, /(modeShown|sizeShown|dateShown|kindShown|sizeWidth|dateWidth): root\.(modeShown|sizeShown|dateShown|kindShown|sizeWidth|dateWidth)/g), 0)
    check("no cell takes handed dates", countRe(row, /(highlightToday|todayStart|mtime):\s*/g), 0)
    // One shared ink serves the four cells plus the search location; no cellColor() call is left.
    check("Row defines one shared cell ink", countRe(row, /readonly property color cellInk/g), 1)
    check("no cellColor() call is left", countRe(row, /cellColor\(\)/g), 0)
    check("mode, size and kind bind the shared ink", ["mode", "size", "kind"].every(function (id) { return cellBlock(row, id).indexOf("color: root.cellInk\n") >= 0 }), true)
    check("an older date keeps the shared ink", cellBlock(row, "modified").indexOf("? Theme.color.foreground : root.cellInk\n") >= 0, true)
    // The anchor chain is untouched: every cell still anchors to its right neighbour, and the name still ends at the mode cell.
    check("mode still anchors to size", row.indexOf("anchors.right: size.left") >= 0, true)
    check("size still anchors to modified", row.indexOf("anchors.right: modified.left") >= 0, true)
    check("modified still anchors to kind", row.indexOf("anchors.right: kind.left") >= 0, true)
    check("kind still anchors to the row edge", row.indexOf("id: kind") >= 0 && row.slice(row.indexOf("id: kind"), row.indexOf("id: kind") + 200).indexOf("anchors.right: parent.right") >= 0, true)
    check("the name still ends at the mode cell", row.indexOf("anchors.right: mode.left") >= 0, true)
    // Only the date cell may lift today to the foreground role, through the window's own switch and start.
    check("the date keeps the today lift",
        row.indexOf("RecentDates.isRecent(ViewState.highlightToday") >= 0, true)
    check("and only the date lifts it", countRe(row, /RecentDates\.isRecent/g), 1)
    // The pixels are the same tokens: caption type, right elide, plain text, right-aligned numerics, and the by-key cell() lookup.
    var cells = ["mode", "size", "modified", "kind"]
    check("every cell keeps caption type", cells.every(function (id) { return cellBlock(row, id).indexOf("font.pixelSize: Theme.font.caption") >= 0 }), true)
    check("every cell keeps plain text", cells.every(function (id) { return cellBlock(row, id).indexOf("textFormat: Text.PlainText") >= 0 }), true)
    check("every cell keeps right elide", cells.every(function (id) { return cellBlock(row, id).indexOf("elide: Text.ElideRight") >= 0 }), true)
    check("size and date stay right-aligned", ["size", "modified"].every(function (id) { return cellBlock(row, id).indexOf("horizontalAlignment: Text.AlignRight") >= 0 }), true)
    check("Row.cell still answers all four", row.indexOf('case "mode": return mode') >= 0
        && row.indexOf('case "size": return size') >= 0
        && row.indexOf('case "date": return modified') >= 0
        && row.indexOf('case "kind": return kind') >= 0, true)
}
