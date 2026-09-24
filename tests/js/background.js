.import "../../ui/js/Tap.js" as Tap

// ui/js/Tap.js onBackground, the one test of whether a right click in a listing landed on a row or on
// the directory's own ground. It is driven against a real view here and not a stub, because the
// defect it guards lived in which item Qt hands a TapHandler's position to.

// ui/List.qml, ui/GridArea.qml and ui/ColumnPane.qml each declare their background TapHandler inside
// the view itself, so this builds that shape for real: 30 rows of 20 px under a 100 px viewport, plus
// the one row of bare ground at the end that ui/List.qml keeps.
function listing(type) {
    var parent = Qt.createComponent("QtQuick", "Item").createObject(null)
    return Qt.createQmlObject("import QtQuick\n" + type + " {\n"
        + "    width: 100; height: 100; model: 30\n"
        + (type === "GridView" ? "    cellWidth: 100; cellHeight: 20\n" : "")
        + "    delegate: Item { width: 100; height: 20 }\n"
        + "    footer: Item { width: 100; height: 20 }\n"
        + "    readonly property var background: tap\n"
        + "    TapHandler { id: tap }\n"
        + "}\n", parent, Qt.resolvedUrl("listing.qml"))
}

// A TapHandler reports a tap in the item that holds it, so a point in the viewport is mapped there.
function tapAt(view, y) {
    return { position: view.background.parent.mapFromItem(view, 50, y) }
}

function run(check) {
    // Issue 195: past the first screenful of a scrolled listing, a right click on a row raised the
    // background menu instead of the row's, in every view. At the top nothing is scrolled, which is
    // why the upper rows always answered correctly.
    var types = ["ListView", "GridView"]
    for (var v = 0; v < types.length; v++) {
        var view = listing(types[v])
        check(types[v] + ": a TapHandler declared inside the view belongs to its contentItem",
              view.background.parent === view.contentItem, true)
        check(types[v] + ": unscrolled, a right click on the first row is on a row",
              Tap.onBackground(view, tapAt(view, 10)), false)
        view.positionViewAtEnd()
        check(types[v] + ": the listing really scrolled to its end", view.contentY, 520)
        check(types[v] + ": scrolled, a right click on the last row is on a row",
              Tap.onBackground(view, tapAt(view, 70)), false)
        check(types[v] + ": scrolled, a right click on the top row in view is on a row",
              Tap.onBackground(view, tapAt(view, 10)), false)
        check(types[v] + ": scrolled, the bare ground under the last row is still the background",
              Tap.onBackground(view, tapAt(view, 90)), true)
    }
}
