.pragma library

// The grid's tile maths, split out of ui/GridArea.qml so tests/js/gridgeometry.js can pin it.

// Width less one gap and the scroll lane, so no tile sits under the bar.
// Sample input: columnsFor(800, 146, 96, 7, 8) is 5, five tiles across an 800 px grid.
function columnsFor(width, minCellWidth, tilePixels, rowPaddingX, gap, lane) {
    var cell = Math.max(minCellWidth, tilePixels + 2 * rowPaddingX)
    return Math.max(1, Math.floor((width - gap - (Number(lane) || 0)) / cell))
}

// Sample input: cellWidthFor(800, 5, 8) is 158, five cells filling the 792 beside the gap.
function cellWidthFor(width, columns, gap, lane) {
    return Math.max(1, Math.floor((width - gap - (Number(lane) || 0)) / Math.max(1, columns)))
}

// A cell is its slot plus the name gap plus two caption lines plus the pad above and below.
// Sample input: cellHeightFor(128, 9, 33, 14) is 198, the board tile.
function cellHeightFor(thumbPixels, gap, captionHeight, padY) {
    return Math.max(1, thumbPixels + gap + captionHeight + 2 * padY)
}
