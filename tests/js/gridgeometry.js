.import "../../ui/js/GridGeometry.js" as GridGeometry

// The grid now insets one gap on the left and top, and counts tiles on the width less it.

// A text size 14 box: minCellWidth 146, thumbnailPixels 96, rowPaddingX 7, gap 8, hairline 1.
var MIN_CELL = 146
var THUMB_PX = 96
var PAD_X = 7
var GAP = 8

function run(check) {
    // Sample input: (800, 146, 96, 7, 8) is 5, five 158 px cells in 792.
    var widths = [500, 800, 1200]
    for (var w = 0; w < widths.length; w++) {
        var width = widths[w]
        var columns = GridGeometry.columnsFor(width, MIN_CELL, THUMB_PX, PAD_X, GAP)
        var cell = GridGeometry.cellWidthFor(width, columns, GAP)
        check("columns at " + width + " leave the edge gap out",
              columns, Math.max(1, Math.floor((width - GAP) / Math.max(MIN_CELL, THUMB_PX + 2 * PAD_X))))
        check("cell width at " + width + " divides the width less the gap",
              cell, Math.max(1, Math.floor((width - GAP) / Math.max(1, columns))))
        check("cells at " + width + " fit the width they were divided from",
              columns * cell <= width - GAP, true)
        check("one more column at " + width + " would not fit beside them",
              (columns + 1) * cell > width - GAP, true)
        // The frame clearance is measured, not computed: tests/grid-gap.qml reads the real frame.
    }

    // Empty, unreadable and huge: a window narrower than the gap still draws one column.
    check("a width the gap already spent still draws one column",
          GridGeometry.columnsFor(GAP - 1, MIN_CELL, THUMB_PX, PAD_X, GAP), 1)
    check("that column is never narrower than a pixel",
          GridGeometry.cellWidthFor(GAP - 1, 1, GAP), 1)
    check("zero columns never divide",
          GridGeometry.cellWidthFor(800, 0, GAP), 800 - GAP)
}
