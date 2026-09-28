// Row.qml cells split: the four metadata Texts live in ui/RowMode/Size/Date/Kind.qml, each rooting one Text with no wrapper Item.

// A file of this tree, read the way tests/js/themes.js reads colors.toml; "" when missing.
function source(path) {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../../" + path), false)
    request.send()
    return String(request.responseText || "")
}

function countRe(text, re) {
    var found = text.match(re)
    return found ? found.length : 0
}

var CELLS = ["ui/RowMode.qml", "ui/RowSize.qml", "ui/RowDate.qml", "ui/RowKind.qml"]

function run(check) {
    var row = source("ui/Row.qml")
    // Red on the base: these files do not exist there, so every check below fails there first.
    var bodies = CELLS.map(function (path) { return source(path) })
    for (var i = 0; i < CELLS.length; i++) {
        check(CELLS[i] + " exists", bodies[i].length > 0, true)
    }
    if (bodies.some(function (body) { return body.length === 0 })) {
        return
    }
    // One Text object per cell file and no other primitive beside it: no wrapper Item, Rectangle, Image, Loader, Glyph or MatchText.
    for (var c = 0; c < CELLS.length; c++) {
        check(CELLS[c] + " roots one Text", countRe(bodies[c], /^Text\s*\{/gm), 1)
        check(CELLS[c] + " holds one Text total", countRe(bodies[c], /Text\s*\{/g), 1)
        check(CELLS[c] + " adds no Item wrapper", countRe(bodies[c], /Item\s*\{/g), 0)
        check(CELLS[c] + " adds no Rectangle", countRe(bodies[c], /Rectangle\s*\{/g), 0)
        check(CELLS[c] + " adds no Image", countRe(bodies[c], /Image\s*\{/g), 0)
        check(CELLS[c] + " adds no Loader", countRe(bodies[c], /Loader\s*\{/g), 0)
        check(CELLS[c] + " adds no Glyph", countRe(bodies[c], /Glyph\s*\{/g), 0)
        check(CELLS[c] + " runs nothing on completed", bodies[c].indexOf("Component.onCompleted") < 0, true)
    }
    // Row builds one of each and no inline cell Text is left: 4 before, 4 after, 0 wrappers.
    check("Row builds one RowMode", countRe(row, /RowMode\s*\{/g), 1)
    check("Row builds one RowSize", countRe(row, /RowSize\s*\{/g), 1)
    check("Row builds one RowDate", countRe(row, /RowDate\s*\{/g), 1)
    check("Row builds one RowKind", countRe(row, /RowKind\s*\{/g), 1)
    check("no inline mode Text is left", countRe(row, /Text\s*\{\s*id:\s*mode\b/g), 0)
    check("no inline size Text is left", countRe(row, /Text\s*\{\s*id:\s*size\b/g), 0)
    check("no inline modified Text is left", countRe(row, /Text\s*\{\s*id:\s*modified\b/g), 0)
    check("no inline kind Text is left", countRe(row, /Text\s*\{\s*id:\s*kind\b/g), 0)
    // The anchor chain is untouched: every cell still anchors to its right neighbour, and the name still ends at the mode cell.
    check("mode still anchors to size", row.indexOf("anchors.right: size.left") >= 0, true)
    check("size still anchors to modified", row.indexOf("anchors.right: modified.left") >= 0, true)
    check("modified still anchors to kind", row.indexOf("anchors.right: kind.left") >= 0, true)
    check("kind still anchors to the row edge", row.indexOf("id: kind") >= 0 && row.slice(row.indexOf("id: kind"), row.indexOf("id: kind") + 200).indexOf("anchors.right: parent.right") >= 0, true)
    check("the name still ends at the mode cell", row.indexOf("anchors.right: mode.left") >= 0, true)
    // Every drawn property stays a binding: Row hands down flags, ink and text, and only RowDate may lift today to the foreground role.
    check("mode hands down its ink and text", row.indexOf("ink: root.cellColor()") >= 0, true)
    check("size hands down its width", row.indexOf("sizeWidth: root.sizeWidth") >= 0, true)
    check("date hands down its width", row.indexOf("dateWidth: root.dateWidth") >= 0, true)
    check("date hands down the switch, the start and the stamp",
        row.indexOf("highlightToday: ViewState.highlightToday") >= 0
        && row.indexOf("todayStart: ViewState.todayStart") >= 0
        && row.indexOf("mtime: root.row") >= 0, true)
    check("cells draw the handed text", bodies.every(function (body) { return body.indexOf("text: root.cellText") >= 0 }), true)
    check("mode, size and kind draw the handed ink",
        bodies[0].indexOf("color: root.ink") >= 0
        && bodies[1].indexOf("color: root.ink") >= 0
        && bodies[3].indexOf("color: root.ink") >= 0, true)
    check("the date keeps the handed ink for older stamps",
        bodies[2].indexOf("root.ink") >= 0, true)
    check("and lifts today to the foreground role",
        bodies[2].indexOf("Theme.color.foreground") >= 0, true)
    // The pixels are the same tokens: caption type, right elide, plain text, right-aligned numerics, and the by-key cell() lookup.
    check("cells keep caption type", bodies.every(function (body) { return body.indexOf("font.pixelSize: Theme.font.caption") >= 0 }), true)
    check("cells keep right elide", bodies.every(function (body) { return body.indexOf("elide: Text.ElideRight") >= 0 }), true)
    check("cells keep plain text", bodies.every(function (body) { return body.indexOf("textFormat: Text.PlainText") >= 0 }), true)
    check("Row.cell still answers all four", row.indexOf('case "mode": return mode') >= 0
        && row.indexOf('case "size": return size') >= 0
        && row.indexOf('case "date": return modified') >= 0
        && row.indexOf('case "kind": return kind') >= 0, true)
}
