.import "../../ui/js/Density.js" as Density
.import "../../ui/js/GridGeometry.js" as GridGeometry
.import "../../ui/js/Settings.js" as Settings

// Density040 and GridStops: Tight below Compact, Huge and Largest above Extra large.

function find(rows, id) {
    for (var i = 0; i < rows.length; i++) {
        if (rows[i].id === id)
            return rows[i]
    }
    return {}
}

function run(check) {
    // Sample input: rowHeight(23, 7, "tight") is 23, the line box with no padding.
    check("tight drops the padding", Density.rowHeight(23, 7, "tight"), 23)
    check("compact keeps half the padding", Density.rowHeight(23, 7, "compact"), 31)
    check("normal keeps the full padding", Density.rowHeight(23, 7, "normal"), 37)
    check("comfortable keeps one and a half", Density.rowHeight(23, 7, "comfortable"), 45)
    check("tight at base 16 is the line box", Density.rowHeight(27, 8, "tight"), 27)
    check("compact at base 16", Density.rowHeight(27, 8, "compact"), 35)
    check("normal at base 16", Density.rowHeight(27, 8, "normal"), 43)
    check("comfortable at base 16", Density.rowHeight(27, 8, "comfortable"), 51)
    check("unknown density reads as compact", Density.ratioFor("nope"), 0.5)

    // Sample input: thumbPixelsFor("huge") is 192, glyphCap(192) is 128.
    check("small is 48", Density.thumbPixelsFor("small"), 48)
    check("medium is 64", Density.thumbPixelsFor("medium"), 64)
    check("large is 96", Density.thumbPixelsFor("large"), 96)
    check("xlarge is 128", Density.thumbPixelsFor("xlarge"), 128)
    check("huge is 192", Density.thumbPixelsFor("huge"), 192)
    check("largest is 256", Density.thumbPixelsFor("largest"), 256)
    check("a folder mark never grows past 128", Density.glyphCap(192), 128)
    check("and largest neither", Density.glyphCap(256), 128)
    check("a small mark keeps its size", Density.glyphCap(48), 48)

    // Sample input: cellHeightFor(128, 9, 33, 14) is 198, the board tile.
    check("small cell", GridGeometry.cellHeightFor(48, 9, 33, 14), 118)
    check("medium cell", GridGeometry.cellHeightFor(64, 9, 33, 14), 134)
    check("large cell", GridGeometry.cellHeightFor(96, 9, 33, 14), 166)
    check("extra large cell", GridGeometry.cellHeightFor(128, 9, 33, 14), 198)
    check("huge cell", GridGeometry.cellHeightFor(192, 9, 33, 14), 262)
    check("largest cell", GridGeometry.cellHeightFor(256, 9, 33, 14), 326)
    check("a zero tile still draws one pixel", GridGeometry.cellHeightFor(0, 9, 33, 14) > 0, true)

    var view = Settings.rows("view", { data: {} })
    check("row density offers all four stops", find(view, "density").values.join(","), "tight,compact,normal,comfortable")
    check("and names them in order", find(view, "density").labels.join("|"), "Tight|Compact|Normal|Comfortable")
    check("compact stays the default", find(view, "density").selected, "compact")
    var hinted = false
    for (var i = 0; i < view.length; i++) {
        if (view[i].kind === "hint" && view[i].label === "Compact stays the default.")
            hinted = true
    }
    check("the density hint says compact stays the default", hinted, true)

    var preview = Settings.rows("preview", { data: {} })
    var sizeRow = find(preview, "preview.thumbSize")
    check("thumbnail size offers all six stops", sizeRow.values.join(","), "small,medium,large,xlarge,huge,largest")
    check("and names huge and largest past extra large", sizeRow.labels.join("|"), "Small|Medium|Large|Extra large|Huge|Largest")
    check("medium stays the default", sizeRow.selected, "medium")
    check("thumbnails still read everything", find(preview, "preview.thumbnails").labels.join("|"), "Off|Images|Everything")
}
