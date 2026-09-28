import QtQuick

// tests/colhero.sh's harness: the child column's empty-state hero must survive a
// cursor-only move onto an empty folder. Mirrors ui/ColumnsArea.qml's third-column
// wiring verbatim (cited below): a rows/cursor signal can reach moveThird before
// the childPath binding settles, so it early-returns on stale values, and only the
// child's own change carries fresh ones. Without the re-move there, shownChildPath
// keeps the previous folder and the hero never appears (0.3.6 regression, e93e949d).
// The swap's own timing is preview-swap.sh's business; the stub hold runs its apply
// at once, which is what a settled capture does.
Item {
    id: root
    width: 300
    height: 300

    property var cursorRow: null
    property int cursorIndex: -1
    property string panePath: "/fixture"
    property var rows: []
    function rowFor(i) { return (i < 0 || i >= rows.length) ? null : rows[i] }

    // ui/ColumnsArea.qml:33-36.
    property var boundRow: rowFor(cursorIndex)
    property bool cursorIsDir: boundRow !== null && boundRow.d === true
    property string childPath: cursorIsDir ? panePath + "/" + boundRow.n : ""

    // ui/ColumnsArea.qml:25-28, 39-44, 51-53, 60-63.
    property var peeked: ({})
    property int peekVersion: 0
    property bool shownHasRow: false
    property bool shownIsDir: false
    property string shownChildPath: ""
    function rowsFor(path) {
        return peekVersion >= 0 && path.length > 0 && peeked[path] ? peeked[path] : []
    }
    function answered(path) {
        return peekVersion >= 0 && path.length > 0 && peeked[path] !== undefined
    }

    // ui/ColumnPane.qml's empty tile: ui/ColumnsArea.qml:317 draws it off answered().
    property bool tileVisible: answered(shownChildPath) && rowsFor(shownChildPath).length === 0

    // ui/ColumnsArea.qml:65-69.
    function ask(path) {
        if (path.length === 0 || peeked[path])
            return
        asked.push(path)
    }
    property var asked: []
    function refreshNeighbours() { ask(childPath) }
    // ui/ColumnsArea.qml:83-87.
    function showCursorRow() {
        shownHasRow = boundRow !== null
        shownIsDir = cursorIsDir
        shownChildPath = childPath
    }
    // ui/ColumnsArea.qml:93-122 reduced to its decision: hold or land at once both
    // run the apply; only the early return leaves shown behind.
    function moveThird() {
        if (cursorIsDir === shownIsDir && childPath === shownChildPath
                && (boundRow !== null) === shownHasRow)
            return
        holdCount += 1
        showCursorRow()
    }
    property int holdCount: 0
    function followCursor() { moveThird() }
    function onPeeked(path, rows) {
        var next = peeked
        next[path] = rows
        peeked = next
        peekVersion += 1
    }

    // The wiring under test. ui/ColumnsArea.qml:227,232 run followCursor on the
    // rows and cursor signals; the fixed line 224 re-moves on the child's own change.
    onCursorIndexChanged: followCursor()
    onRowsChanged: followCursor()
    onChildPathChanged: { refreshNeighbours(); moveThird() }

    Timer {
        id: driver
        interval: 40
        repeat: false
        property int step: 0
        onTriggered: next()
        function next() {
            step += 1
            if (step === 1) {
                // Settled: cursor on sub (three rows, peek answered), hero correctly hidden.
                root.rows = [{n: "empty", d: true}, {n: "sub", d: true}]
                root.cursorIndex = 1
                onPeeked("/fixture/sub", [{n: "s1.txt"}, {n: "s2.txt"}, {n: "s3.txt"}])
                showCursorRow()
                console.log("COLHERO settled tile=" + tileVisible + " shown=" + shownChildPath)
                driver.restart()
            } else if (step === 2) {
                // A cursor-only move onto the empty folder: no rows change, so no
                // rows signal can rescue a move taken on stale values.
                root.cursorIndex = 0
                driver.restart()
            } else if (step === 3) {
                // The asked peek answers zero rows, the way the backend answers one.
                onPeeked("/fixture/empty", [])
                driver.restart()
            } else if (step === 4) {
                var ok = tileVisible === true && shownChildPath === "/fixture/empty"
                console.log("COLHERO state tile=" + tileVisible + " shown=" + shownChildPath
                    + " holds=" + holdCount + " asked=" + JSON.stringify(asked))
                console.log(ok ? "COLHERO PASS" : "COLHERO FAIL cursor on empty shows no hero")
                Qt.quit()
            }
        }
    }
    Component.onCompleted: driver.start()
}
