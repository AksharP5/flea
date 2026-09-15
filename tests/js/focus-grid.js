.import "../../ui/js/Grid.js" as Grid
.import "../../ui/js/Focus.js" as Focus
.import "filterfixture.js" as Fixture

// The grid's own geometry: which cell a key means when the rows are tiles. Split out of
// tests/js/focus.js with ui/js/Grid.js, and driving the same stub pane the filter suites use.

function run(check) {
    var none = 0
    function key(code, text, modifiers) {
        return { key: code, text: text, modifiers: modifiers }
    }
    var gridPane = Fixture.pane()
    gridPane.viewMode = "grid"
    gridPane.cursorStride = 3
    gridPane.wrapAtEnds = true
    gridPane.cursorIndex = 2
    Focus.act("cursorDown", gridPane)
    check("grid j follows row-major order across a row boundary", gridPane.cursorIndex, 3)
    Focus.act("cursorUp", gridPane)
    check("grid k follows the previous item", gridPane.cursorIndex, 2)
    check("grid j is not a physical arrow", Grid.arrow(key(Qt.Key_J, "j", none), "cursorDown", gridPane), false)
    for (var move of [
        [Qt.Key_Right, "cursorRight", 2, 2], [Qt.Key_Left, "cursorLeft", 3, 3],
        [Qt.Key_Down, "cursorDown", 2, 5], [Qt.Key_Down, "cursorDown", 5, 5],
        [Qt.Key_Down, "cursorDown", 3, 6], [Qt.Key_Up, "cursorUp", 6, 3],
        [Qt.Key_Up, "cursorUp", 0, 0], [Qt.Key_Right, "cursorRight", 6, 6]
    ]) {
        gridPane.cursorIndex = move[2]
        Grid.arrow(key(move[0], "", none), move[1], gridPane)
        check("grid visual neighbour from " + move[2] + " with " + move[1], gridPane.cursorIndex, move[3])
    }
    // The letters clamp at the row's edge exactly as the arrows do, which is the whole of issue 114.
    gridPane.cursorIndex = 3
    Grid.arrow(key(0, "h", none), "cursorLeft", gridPane)
    check("h at the start of a tile row stays on it", gridPane.cursorIndex, 3)
    gridPane.cursorIndex = 4
    Grid.arrow(key(0, "h", none), "cursorLeft", gridPane)
    check("h inside a tile row steps one tile left", gridPane.cursorIndex, 3)
    gridPane.cursorIndex = 5
    Grid.arrow(key(0, "l", none), "cursorRight", gridPane)
    check("l at the end of a tile row stays on it", gridPane.cursorIndex, 5)
    gridPane.cursorIndex = 4
    Grid.arrow(key(0, "l", none), "cursorRight", gridPane)
    check("l inside a tile row steps one tile right", gridPane.cursorIndex, 5)

    gridPane.cursorStride = 2
    gridPane.cursorIndex = 3
    Grid.arrow(key(Qt.Key_Down, "", none), "cursorDown", gridPane)
    check("grid arrows use the reflowed column count", gridPane.cursorIndex, 5)

    gridPane.filterQuery = "screen"
    gridPane.refresh()
    gridPane.cursorIndex = 0
    gridPane.cursorStride = 2
    Grid.arrow(key(Qt.Key_Down, "", none), "cursorDown", gridPane)
    check("filtered grid arrows address visible cells", gridPane.cursorIndex, 6)
    Grid.arrow(key(Qt.Key_Right, "", none), "cursorRight", gridPane)
    check("filtered final row has no right cell", gridPane.cursorIndex, 6)
}
