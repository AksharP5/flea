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
              (columns + 1) * Math.max(MIN_CELL, THUMB_PX + 2 * PAD_X) > width - GAP, true)
        // The frame clearance is measured, not computed: tests/grid-gap.qml reads the real frame.
    }

    // Empty, unreadable and huge: a window narrower than the gap still draws one column.
    check("a width the gap already spent still draws one column",
          GridGeometry.columnsFor(GAP - 1, MIN_CELL, THUMB_PX, PAD_X, GAP), 1)
    check("that column is never narrower than a pixel",
          GridGeometry.cellWidthFor(GAP - 1, 1, GAP), 1)
    check("zero columns never divide",
          GridGeometry.cellWidthFor(800, 0, GAP), 800 - GAP)

    // The grid keeps the same lane clear on its right: tiles are counted and sized on the width less the gap and the lane.
    // Sample input: (738, 146, 96, 7, 8, 7) is 4, four 180 px cells beside a 7 px lane, while the lane-blind count is 5.
    var laneWidths = [500, 738, 1200]
    for (var l = 0; l < laneWidths.length; l++) {
        var laneWidth = laneWidths[l]
        var laneColumns = GridGeometry.columnsFor(laneWidth, MIN_CELL, THUMB_PX, PAD_X, GAP, PAD_X)
        var laneCell = GridGeometry.cellWidthFor(laneWidth, laneColumns, GAP, PAD_X)
        check("columns at " + laneWidth + " leave the gap and the lane out",
              laneColumns, Math.max(1, Math.floor((laneWidth - GAP - PAD_X) / Math.max(MIN_CELL, THUMB_PX + 2 * PAD_X))))
        check("cell width at " + laneWidth + " divides the width less the gap and the lane",
              laneCell, Math.max(1, Math.floor((laneWidth - GAP - PAD_X) / Math.max(1, laneColumns))))
        check("cells at " + laneWidth + " fit the width they were divided from",
              laneColumns * laneCell <= laneWidth - GAP - PAD_X, true)
        check("one more column at " + laneWidth + " would not fit beside them",
              (laneColumns + 1) * Math.max(MIN_CELL, THUMB_PX + 2 * PAD_X) > laneWidth - GAP - PAD_X, true)
    }
    // At 738 the lane costs a column, so a lane-blind columnsFor fails here.
    check("at 738 the lane costs a column",
          GridGeometry.columnsFor(738, MIN_CELL, THUMB_PX, PAD_X, GAP, PAD_X)
          + "|" + GridGeometry.columnsFor(738, MIN_CELL, THUMB_PX, PAD_X, GAP), "4|5")
    // Five arguments keep the old shape: no lane named is no lane kept, so the callers that never name one cannot change what they draw.
    check("an unnamed lane keeps nothing back",
          GridGeometry.columnsFor(800, MIN_CELL, THUMB_PX, PAD_X, GAP),
          GridGeometry.columnsFor(800, MIN_CELL, THUMB_PX, PAD_X, GAP, 0))
    check("an unnamed lane sizes nothing down",
          GridGeometry.cellWidthFor(800, 5, GAP),
          GridGeometry.cellWidthFor(800, 5, GAP, 0))
}
