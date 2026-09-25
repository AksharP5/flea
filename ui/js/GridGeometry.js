.pragma library

// The grid's tile maths, split out of ui/GridArea.qml so tests/js/gridgeometry.js can pin it.

// Counted on the width less one gap, the inset that keeps a tile frame off both edge lines.
// Sample input: columnsFor(800, 146, 96, 7, 8) is 5, five tiles across an 800 px grid.
function columnsFor(width, minCellWidth, tilePixels, rowPaddingX, gap) {
    var cell = Math.max(minCellWidth, tilePixels + 2 * rowPaddingX)
    return Math.max(1, Math.floor((width - gap) / cell))
}

// Sample input: cellWidthFor(800, 5, 8) is 158, five cells filling the 792 beside the gap.
function cellWidthFor(width, columns, gap) {
    return Math.max(1, Math.floor((width - gap) / Math.max(1, columns)))
}
