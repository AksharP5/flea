.import "../../ui/js/Columns.js" as Columns
.import "../../ui/js/ColumnFit.js" as ColumnFit
.import "../../ui/js/Picker.js" as Picker
.import "../../ui/js/Nav.js" as Nav
.import "sourcefixture.js" as Source

// Below about 659 px of window the four fixed columns claimed the whole row and the filename had a
// negative slot, so ui/Row.qml drew every column except the one a file manager exists for. These
// are the floors that stop it: the name never loses, the metadata drops instead.

// This box's own resolved tokens, read off the running app's tokens() seam at base-size 14:
//   rowPaddingX=14 gap=9 iconSize=23 columnMode=70 columnSize=70 columnDate=125 columnKind=130
// nameMin is 20 characters of the same 7.8125 px advance the fixed columns are sized from.
var BOX = { rowPaddingX: 14, gap: 9, iconSize: 23, nameMin: 156, mode: 70, size: 70, date: 125, kind: 130 }

// A second set that shares no number with the first, so nothing here can pass on a constant.
var OTHER = { rowPaddingX: 6, gap: 4, iconSize: 16, nameMin: 100, mode: 40, size: 50, date: 80, kind: 60 }

// The chooser's own tokens: BOX with Theme.column.pickerDate in place of the window's date, which
// the seam resolves to 80 at base-size 14, SendPicker.html's own slot.
var PICKER = { rowPaddingX: 14, gap: 9, iconSize: 23, nameMin: 156, mode: 70, size: 70, date: 80, kind: 130 }

// The chooser's list area on this box: Hyprland floats the picker at 875 px and ui/PickerPlaces.qml
// takes Theme.space(150), 175 px of it, measured off the window Hyprland reported for flea --pick.
var PICKER_SLOT = 700

// The anchor chain in ui/Row.qml, walked here independently of ui/js/Columns.js: the row, less its
// padding either side, the mark and the gap after it, and every drawn column with its own gap.
function nameSlot(width, s, t) {
    var used = t.rowPaddingX + t.iconSize + t.gap + t.rowPaddingX
    if (s.mode) used += t.mode + t.gap
    if (s.size) used += t.size + t.gap
    if (s.date) used += t.date + t.gap
    if (s.kind) used += t.kind + t.gap
    return width - used
}

function run(check) {

    var dual = {rowPaddingX: 14, gap: 9, iconSize: 13 * 1.45, nameMin: 180, size: 70, date: 125}
    check("dual date fits the board's 431px floor", Columns.names(Columns.dualSet(431, dual, [])), "name,size,date")
    check("dual date drops below its name floor", Columns.names(Columns.dualSet(430, dual, [])), "name,size")
    check("hidden dual size releases its actual width", Columns.names(Columns.dualSet(361, dual, ["size"])), "name,date")
    check("dual minimum still keeps Name", Columns.names(Columns.dualSet(200, dual, [])), "name")
    runHidden(check)
    runPicker(check)
    var f = Columns.floors(BOX)
    // 216 is the name at its floor with no metadata at all: 14 + 23 + 9 + 156 + 14.
    check("mode needs the name's floor plus its own column and gap", f.mode, 295)
    check("size needs mode's floor plus its own", f.size, 374)
    check("date needs size's floor plus its own", f.date, 508)
    check("kind needs date's floor plus its own", f.kind, 647)
    // A wider column can never outlive a narrower one, which is what makes the drop order an order.
    check("the four floors nest, widest last",
          f.mode < f.size && f.size < f.date && f.date < f.kind, true)

    // 732 is the list area of the 900 px window Flea asks for, beside this box's 168 px rail.
    check("the default window draws every column",
          Columns.names(Columns.set(732, BOX)), "name,mode,size,date,kind")
    check("a column is kept at exactly its floor",
          Columns.set(647, BOX).kind, true)
    check("and dropped one pixel under it",
          Columns.set(646, BOX).kind, false)
    check("kind goes first and the other three stay",
          Columns.names(Columns.set(646, BOX)), "name,mode,size,date")
    check("date goes second",
          Columns.names(Columns.set(507, BOX)), "name,mode,size")
    check("size goes third",
          Columns.names(Columns.set(373, BOX)), "name,mode")
    check("mode goes last, and the last layout is the mark and the name",
          Columns.names(Columns.set(294, BOX)), "name")
    // 453 is the list area at the 621 px window Hyprland handed Flea beside three terminals.
    check("the width that drew no name at all now draws the name, mode and size",
          Columns.names(Columns.set(453, BOX)), "name,mode,size")

    // The whole point: at no width does a column survive that would put the name under its floor.
    var everyWidthKeepsTheName = true
    var neverGrowsAsItNarrows = true
    var previous = null
    for (var w = 2000; w >= 216; w--) {
        var s = Columns.set(w, BOX)
        if (nameSlot(w, s, BOX) < BOX.nameMin)
            everyWidthKeepsTheName = false
        if (previous !== null) {
            if ((s.mode && !previous.mode) || (s.size && !previous.size)
                || (s.date && !previous.date) || (s.kind && !previous.kind))
                neverGrowsAsItNarrows = false
        }
        previous = s
    }
    check("every width from the name's own floor up keeps the name at or above it",
          everyWidthKeepsTheName, true)
    check("no column ever comes back as the row narrows",
          neverGrowsAsItNarrows, true)

    // Under the name's own floor there is nothing left to drop, so the name takes what is left
    // rather than the layout inventing a column to lose. ui/MatchText.qml clamps the rest.
    check("under the last rung the set is empty rather than undefined",
          Columns.names(Columns.set(100, BOX)), "name")
    check("a zero width answers rather than throwing", Columns.names(Columns.set(0, BOX)), "name")
    check("a negative width answers the same", Columns.names(Columns.set(-500, BOX)), "name")

    // Nothing above is a constant: the same arithmetic on a token set sharing none of those numbers.
    var g = Columns.floors(OTHER)
    check("another token set moves every floor with it",
          g.mode + "|" + g.size + "|" + g.date + "|" + g.kind, "176|230|314|378")
    check("and keeps them nested",
          g.mode < g.size && g.size < g.date && g.date < g.kind, true)
    check("and keeps the name above its own floor there too",
          nameSlot(g.kind, Columns.set(g.kind, OTHER), OTHER) >= OTHER.nameMin, true)

    // The seam ui/Ipc.qml reads is this string, and the header and a row must produce the same one.
    check("the set names the columns left to right, not in drop order",
          Columns.names({ mode: true, size: true, date: true, kind: true }),
          "name,mode,size,date,kind")
    check("the name is in the set even when everything else is gone",
          Columns.names({ mode: false, size: false, date: false, kind: false }), "name")

    runColumnCount(check)
    runListWidths(check)
    runStoredWidths(check)
    runPeekKey(check)
    runPeekPending(check)
    runHeaderDrag(check)
    runColumnsLimitWire(check)
    runColRoot(check)
}

// ColumnsWidth board (#167, #69): the columns count follows the window width, 2 below 900 up to 5 from 2300, capped by the View limit shipping at 3.
function runColumnCount(check) {
    check("a default install at 2560 px shows 3 columns", Columns.columnCountForWidth(2560), 3)
    check("a stored 5 still opens 5 on a wide window", Columns.columnCountForWidth(2560, 5), 5)
    check("a narrow window still shows 2 on the shipped default", Columns.columnCountForWidth(800), 2)
    check("below 900 px the view draws 2 columns", Columns.columnCountForWidth(899, 5), 2)
    check("at 900 px the view draws 3 columns", Columns.columnCountForWidth(900, 5), 3)
    check("at 1700 px the view draws 4 columns", Columns.columnCountForWidth(1700, 5), 4)
    check("at 2300 px the view draws 5 columns", Columns.columnCountForWidth(2300, 5), 5)
    check("just under each step stays down", Columns.columnCountForWidth(1699, 5)
        + "|" + Columns.columnCountForWidth(2299, 5), "3|4")
    check("the limit caps a wide window", Columns.columnCountForWidth(2300, 3), 3)
    check("the limit caps a narrow window too", Columns.columnCountForWidth(1200, 2), 2)
    check("a limit below the floor still draws 2", Columns.columnCountForWidth(2300, 1), 2)
    check("a missing limit reads as the shipped 3", Columns.columnCountForWidth(2300), 3)
    check("an empty limit reads as the shipped 3, not the floor", Columns.cappedLimit(""), 3)
    check("a false limit reads as the shipped 3, not the floor", Columns.cappedLimit(false), 3)
    check("2 columns need no ancestor", Columns.ancestorsForCount(2), 0)
    check("3 columns read one ancestor", Columns.ancestorsForCount(3), 1)
    check("4 columns read two ancestors", Columns.ancestorsForCount(4), 2)
    check("5 columns read three ancestors", Columns.ancestorsForCount(5), 3)
}

// ListColumns040 board: a dragged edge clamps, and a double click fits the widest held value, never a directory scan.
function runListWidths(check) {
    check("a drag inside the rails lands as drawn", Columns.clampListWidth(100), 100)
    check("a drag under the floor clamps to it", Columns.clampListWidth(10), Columns.MIN_LIST_WIDTH)
    check("a drag past the ceiling clamps to it", Columns.clampListWidth(9999), Columns.MAX_LIST_WIDTH)
    check("a drag rounds to whole pixels", Columns.clampListWidth(100.6), 101)
    check("autofit takes the widest held cell", Columns.autofitWidth([70, 120, 90], 70), 120)
    check("autofit narrows a dragged-wide column to the widest held cell",
        Columns.autofitWidth([60, 80], 300), 80)
    check("autofit clamps a wide cell to the ceiling",
        Columns.autofitWidth([9999], 70), Columns.MAX_LIST_WIDTH)
    check("autofit on no held rows keeps the column", Columns.autofitWidth([], 70), 70)

    runColumnFit(check)
}

// ui.json carries whatever a hand edit wrote, so storedWidth takes only a finite number here.
function runStoredWidths(check) {
    check("a stored number lands as drawn", Columns.storedNumber(120), 120)
    check("and rounds to whole pixels", Columns.storedNumber(120.6), 121)
    check("null keeps the measured width", isNaN(Columns.storedNumber(null)), true)
    check("an empty string keeps it too", isNaN(Columns.storedNumber("")), true)
    check("false keeps it too", isNaN(Columns.storedNumber(false)), true)
    check("an empty array keeps it too", isNaN(Columns.storedNumber([])), true)
    check("true is not a width", isNaN(Columns.storedNumber(true)), true)
    check("a numeric string is not a width", isNaN(Columns.storedNumber("120")), true)
    check("a negative is not a width", isNaN(Columns.storedNumber(-40)), true)
    check("NaN is not a width", isNaN(Columns.storedNumber(NaN)), true)
    check("Infinity is not a width", isNaN(Columns.storedNumber(Infinity)), true)
}

// The peek cache key: path plus what ordered it, so a stale ancestor column never survives the hidden-last toggle.
function runPeekKey(check) {
    check("the plain order keys plain", Columns.peekKey("/a", false, false), "/a\n00")
    check("hidden keys apart", Columns.peekKey("/a", true, false), "/a\n10")
    check("hidden-last keys apart too", Columns.peekKey("/a", false, true), "/a\n01")
    check("both keys apart together", Columns.peekKey("/a", true, true), "/a\n11")
    check("an absent flag reads as off", Columns.peekKey("/a"), "/a\n00")
    check("a repair count asks apart from the pane's own",
        Columns.sentKey(Columns.peekKey("/a", false, false), 1) !== Columns.sentKey(Columns.peekKey("/a", false, false), 35), true)
    check("the same count asks the same", Columns.sentKey("/a\n00", 35), "/a\n00\n35")
    var area = Source.source("ui/ColumnsArea.qml")
    check("the columns view matches a reply on its sent count",
        area.indexOf("Columns.peekKey(path, hidden, hiddenLast), sent = Columns.sentKey(key, first)") >= 0, true)
    check("and asks with the pane's window size",
        area.indexOf("sent = Columns.sentKey(key, root.pane.windowSize)") >= 0, true)
    check("while stored rows keep no count, so a resize orphans no column",
        area.indexOf("ViewState.state.hiddenLast === true, root.pane.windowSize)") < 0, true)
}

// Live cover: tests/ui.sh columns. Only a reply this view asked for lands in it, so a repair peek or a path-bar Tab never fills a column with wrong rows.
function runPeekPending(check) {
    var key = Columns.peekKey("/a", true, false), other = Columns.peekKey("/b", true, false)
    check("an ask is outstanding once tracked", Columns.hasAsk(Columns.trackAsk({}, key), key), true)
    check("anything else is another client's", Columns.hasAsk({}, key), false)
    check("a stored reply drops its own ask", Columns.hasAsk(Columns.dropAsk(Columns.trackAsk({}, key), key), key), false)
    check("a stored reply keeps a sibling ask", Columns.hasAsk(Columns.dropAsk(Columns.trackAsk(Columns.trackAsk({}, key), other), key), other), true)
    // A repair peek for the same path and flags is another client's when the count differs.
    var own = Columns.sentKey(Columns.peekKey("/a", false, false), 35), repair = Columns.sentKey(Columns.peekKey("/a", false, false), 1)
    var held = Columns.trackAsk({}, own)
    check("a first-1 reply for the same path and flags is refused while the pane's own ask stands",
        Columns.hasAsk(held, repair), false)
    check("while the pane's own reply is kept", Columns.hasAsk(held, own), true)
    check("and the repair reply drops no ask of its own",
        Columns.hasAsk(Columns.dropAsk(held, repair), own), true)
    var area = Source.source("ui/ColumnsArea.qml")
    check("the columns view tracks its own asks", area.indexOf("Columns.trackAsk(root.pending, sent)") >= 0, true)
    check("and stores only a reply it asked for", area.indexOf("if (!Columns.hasAsk(root.pending, sent)) return") >= 0, true)
    check("and drops the ask it stored", area.indexOf("Columns.dropAsk(root.pending, sent)") >= 0, true)
    check("and forgets every ask with the listing", area.indexOf("root.pending = ({})") >= 0, true)
    var orderAt = area.indexOf("onPeekOrderChanged")
    var orderBody = orderAt >= 0 ? area.substring(orderAt, orderAt + 200) : ""
    check("and re-asks the shown ancestors under the new key", orderBody.indexOf("refreshNeighbours") >= 0, true)
    var peekAt = area.indexOf("readonly property string peekOrder")
    var peekBody = peekAt >= 0 ? area.substring(peekAt, peekAt + 300) : ""
    check("and the order it watches carries both flags",
        peekBody.indexOf("showHidden") >= 0 && peekBody.indexOf("hiddenLast") >= 0, true)
}

// The header drag writes once on release after a real move, so a click pins nothing and a fit survives its own release.
function runHeaderDrag(check) {
    var header = Source.source("ui/Header.qml")
    var beginBody = header.substring(header.indexOf("function beginDrag"), header.indexOf("}", header.indexOf("function beginDrag")))
    check("a press that never travels marks nothing to write",
        beginBody.indexOf("root.dragMoved = false") >= 0, true)
    var moveBody = header.substring(header.indexOf("function moveDrag"), header.indexOf("}", header.indexOf("function moveDrag")))
    var guardAt = moveBody.indexOf("Math.abs(x - root.dragStartX) < 1"), armAt = moveBody.indexOf("root.dragMoved = true")
    check("only a travelled pointer arms the write",
        guardAt >= 0 && armAt > guardAt, true)
    check("and the release writes only when armed",
        header.substring(header.indexOf("function endDrag"), header.indexOf("}", header.indexOf("function endDrag"))).indexOf("if (root.dragMoved)") >= 0, true)
    var fitAt = header.indexOf("function autofitColumn")
    var fitBody = header.substring(fitAt, header.indexOf("}", header.indexOf("{", fitAt)))
    check("a fit ends the drag so its release writes nothing",
        fitBody.indexOf('root.dragKey = ""') >= 0, true)
}

// The window passes the raw stored limit through, so a hand-edited false or "" reaches cappedLimit instead of coercing to 0.
function runColumnsLimitWire(check) {
    var area = Source.source("ui/ColumnsArea.qml")
    check("the limit is not an int property",
        area.indexOf("readonly property var columnsLimit") >= 0, true)
}

// ColumnFit.cellText names the strings ui/Row.qml draws, so autofit measures them: a link fits "link", a folder its walk size.
function runColumnFit(check) {
    check("a file fits its size", ColumnFit.cellText("size", {p: 33188, d: false, s: 18000}, [], null), "18.0 kB")
    check("a link fits its kind, not its target length",
        ColumnFit.cellText("size", {p: 41453, d: false, s: 18}, [], null), "link")
    check("a folder without a walk fits the bare mark",
        ColumnFit.cellText("size", {p: 16877, d: true, s: 60}, [], null), "·")
    check("a folder with a walk fits its size",
        ColumnFit.cellText("size", {p: 16877, d: true, s: 60}, [], {bytes: 124700000, partial: false}), "124.7 MB")
    check("a partial walk keeps its mark",
        ColumnFit.cellText("size", {p: 16877, d: true, s: 60}, [], {bytes: 1000, partial: true}), ">1.0 kB")
    check("a row with no mtime fits the bare mark",
        ColumnFit.cellText("date", {m: null}, [], null), "--")
    check("a kind past the dictionary reads empty, never a crash",
        ColumnFit.cellText("kind", {k: 99}, ["File"], null), "")
}

// SendPicker.html draws a chooser row as the name, a 70 px size and an 80 px date, and nothing
// else, so ui/PickerList.qml hands ui/Row.qml Picker.HIDDEN_COLS instead of the window's own set.
// Without it the chooser inherited whatever the header menu had switched on for the browser window.

function runPicker(check) {
    // The negative control: the chooser's slot affords all five, which is what it drew with the
    // window's set and Mode and Kind switched on.
    check("the chooser's own slot is wide enough for every column",
          Columns.names(Columns.set(PICKER_SLOT, PICKER)), "name,mode,size,date,kind")
    check("the chooser draws the board's three and nothing else",
          Columns.names(Columns.set(PICKER_SLOT, PICKER, Picker.HIDDEN_COLS)), "name,size,date")

    // Not only at that width: no width brings a column the chooser's board does not have.
    var everDrawn = false
    for (var w = 3000; w >= 0; w--) {
        var s = Columns.set(w, PICKER, Picker.HIDDEN_COLS)
        if (s.mode || s.kind)
            everDrawn = true
    }
    check("no width at all draws Mode or Kind in the chooser", everDrawn, false)
}

// w8 colroot: at / no ancestor column repeats the active one, so the parent slot stays
// blank and Left stays a no-op; each depth below adds one distinct ancestor.
function runColRoot(check) {
    check("at / no ancestor column is shown", Columns.ancestors("/", 3).join("|"), "")
    check("at /home only the parent (/) is", Columns.ancestors("/home", 3).join("|"), "/")
    check("at /home/gm parent and grandparent are", Columns.ancestors("/home/gm", 3).join("|"), "/|/home")
    check("one ancestor asked is the parent", Columns.ancestors("/home/gm", 1).join("|"), "/home")
    check("three deep names three ancestors", Columns.ancestors("/a/b/c", 3).join("|"), "/|/a|/a/b")
    check("the root shows no parent", Columns.ancestorShown("/", 1), false)
    check("a child of the root shows its parent", Columns.ancestorShown("/home", 1), true)
    check("a child of the root shows no grandparent", Columns.ancestorShown("/home", 2), false)
    check("depth two shows two ancestors", Columns.ancestorShown("/home/gm", 2), true)
    check("depth two shows no third ancestor", Columns.ancestorShown("/home/gm", 3), false)
    var distinct = true
    var paths = ["/", "/home", "/home/gm", "/a/b/c/d"]
    for (var i = 0; i < paths.length; i++) {
        var chain = Columns.ancestors(paths[i], 3).concat([paths[i]])
        for (var j = 0; j + 1 < chain.length; j++)
            if (chain[j] === chain[j + 1])
                distinct = false
    }
    check("no shown ancestor ever equals the column to its right", distinct, true)
    var atRoot = { path: "/", listingPath: "", listingState: "", listInFlight: false, pendingSelect: "kept", opened: [] }
    atRoot.open = function (target) { atRoot.opened.push(target) }
    Nav.parent(atRoot)
    check("left at / opens nothing", atRoot.opened.length, 0)
    check("and plants no select on the climb that did not happen", atRoot.pendingSelect, "kept")
    var area = Source.source("ui/ColumnsArea.qml")
    check("the area gates the parent column on its ancestor",
        area.indexOf("root.showParent && root.parentShown") >= 0, true)
    check("the area gates the grandparent column on its ancestor",
        area.indexOf("root.showGrandparent && root.grandparentShown") >= 0, true)
    check("the area gates the great-grandparent column on its ancestor",
        area.indexOf("root.showGreatGrandparent && root.greatGrandparentShown") >= 0, true)
    check("the area asks no ancestor it does not show",
        area.indexOf("root.showParent && root.parentShown") >= 0
        && area.indexOf("root.showGrandparent && root.grandparentShown") >= 0
        && area.indexOf("root.showGreatGrandparent && root.greatGrandparentShown") >= 0, true)
    check("the parent reader answers null while its ancestor is hidden",
        area.indexOf("(root.showParent && root.parentShown) ? parentColumn.itemAtIndex(index) : null") >= 0, true)
}

// The user's own hidden set, subtracted from what the width affords: a hidden column never draws,
// and width still wins, so a column shown while the pane is too narrow stays dropped. The keys are
// the same "mode"/"size"/"date"/"kind" the header menu's col:<key> actions carry.
function runHidden(check) {
    var none = Columns.set(2000, BOX, [])
    check("an empty hidden set draws every column the width affords",
          [none.mode, none.size, none.date, none.kind].join(","), "true,true,true,true")

    var hid = Columns.set(2000, BOX, ["size", "kind"])
    check("a hidden column does not draw at a width that would afford it",
          [hid.mode, hid.size, hid.date, hid.kind].join(","), "true,false,true,false")

    var narrow = Columns.set(200, BOX, ["kind"])
    check("width still wins over a column the user wants back, Mode's own floor included",
          [narrow.mode, narrow.size, narrow.date, narrow.kind].join(","), "false,false,false,false")

    var undefinedSet = Columns.set(2000, BOX)
    check("a caller that passes no hidden set draws as before",
          [undefinedSet.mode, undefinedSet.size, undefinedSet.date, undefinedSet.kind].join(","), "true,true,true,true")
}
