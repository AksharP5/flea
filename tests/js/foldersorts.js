.import "../../ui/js/FolderSorts.js" as FolderSorts
.import "../../ui/js/Settings.js" as Settings
.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/Sort.js" as Sort
.import "../../ui/js/Tabs.js" as Tabs
.import "tabsfixture.js" as Fixture

// A file of this tree, read the way tests/js/themes.js reads colors.toml; "" when missing.
function source(path) {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../../" + path), false)
    request.send()
    return String(request.responseText || "")
}

// Per-folder sorts (issue 179) and Hidden files last (issue 70): map, Settings rows, flyout forget row, tab-kept sorts.
function sortPane(path, sorts, remember) {
    var p = {
        path: path,
        sorts: sorts || {},
        remember: remember,
        windowSize: 200,
        remembered: [],
        forgotten: [],
        sent: []
    }
    p.backend = {
        sortBy: "name",
        sortDesc: false,
        sort: function (by, desc) { p.sent.push("sort " + by); this.sortBy = by; this.sortDesc = desc },
        window: function (start, count) { p.sent.push("window") },
        // Sample input: rememberFolderSort("/a", "size", false) records "/a|size:false" while remembering is on.
        rememberFolderSort: function (folder, key, desc) { p.remembered.push(folder + "|" + key + ":" + desc) },
        forgetFolderSort: function (folder) { p.forgotten.push(folder) }
    }
    p.thumbState = {}
    p.dirSizeState = {}
    p.clearSelection = function () {}
    p.setCursor = function () {}
    p.openWithoutHistory = function (next) { p.sent.push("list " + next); p.path = next }
    return p
}

function run(check) {
    // The map holds a folder's sort by path, and nothing else.
    check("a folder with no entry has no sort", FolderSorts.get({}, "/a"), null)
    check("and neither does a missing map", FolderSorts.get(null, "/a"), null)
    var one = FolderSorts.set({}, "/a", "size", true)
    check("a write records the key and the direction", JSON.stringify(FolderSorts.get(one, "/a")),
          JSON.stringify({ key: "size", reverse: true }))
    check("and leaves the other folders alone", FolderSorts.has(one, "/b"), false)
    check("a second write in another folder keeps the first", FolderSorts.has(FolderSorts.set(one, "/b", "name", false), "/a"), true)
    // A re-sort moves its folder to the most recent end, so the cap drops the one sorted longest ago.
    var two = FolderSorts.set(one, "/a", "kind", false)
    check("a re-sort keeps one entry per folder", FolderSorts.count(two), 1)
    check("and records the new order", FolderSorts.get(two, "/a").key, "kind")
    var full = {}
    for (var i = 0; i < FolderSorts.MAX; i++)
        full = FolderSorts.set(full, "/d" + i, "name", false)
    check("the map holds the cap", FolderSorts.count(full), FolderSorts.MAX)
    var over = FolderSorts.set(full, "/new", "size", false)
    check("past the cap the oldest entry goes", FolderSorts.has(over, "/d0"), false)
    check("and the newest stays", FolderSorts.has(over, "/new"), true)
    check("at exactly the cap", FolderSorts.count(over), FolderSorts.MAX)
    var touched = FolderSorts.set(full, "/d0", "size", true)
    check("a re-sort of a held folder evicts nothing", FolderSorts.count(touched), FolderSorts.MAX)
    var afterTouch = FolderSorts.set(touched, "/new2", "name", false)
    check("and moves its folder to the most recent end", FolderSorts.has(afterTouch, "/d1"), false)
    check("so the touched folder survives the next eviction", FolderSorts.has(afterTouch, "/d0"), true)
    check("forgetting drops that folder alone", FolderSorts.has(FolderSorts.forget(two, "/a"), "/a"), false)
    check("and keeps the rest", FolderSorts.count(FolderSorts.forget(FolderSorts.set(two, "/b", "name", false), "/a")), 1)
    check("forgetting a folder with no entry changes nothing", FolderSorts.count(FolderSorts.forget({}, "/a")), 0)
    // The fallback differs from /a's stored size-descending sort, so a branch answering the wrong one fails.
    var fallback = { key: "name", reverse: false }
    check("a folder's own sort wins while remembering is on",
          JSON.stringify(FolderSorts.orderFor(one, "/a", fallback, true)), JSON.stringify({ key: "size", reverse: true }))
    check("and when the flag is absent, which is how an old file reads",
          JSON.stringify(FolderSorts.orderFor(one, "/a", fallback)), JSON.stringify({ key: "size", reverse: true }))
    check("elsewhere the default applies", JSON.stringify(FolderSorts.orderFor(one, "/b", fallback, true)),
          JSON.stringify({ key: "name", reverse: false }))
    check("and with remembering off every folder takes the default",
          JSON.stringify(FolderSorts.orderFor(one, "/a", fallback, false)), JSON.stringify({ key: "name", reverse: false }))
    check("a stored key no order knows reads as the default",
          JSON.stringify(FolderSorts.orderFor({ "/a": { key: "mode", reverse: true } }, "/a", fallback, true)),
          JSON.stringify({ key: "name", reverse: false }))
    check("and a missing default reads as name ascending",
          JSON.stringify(FolderSorts.orderFor({}, "/a", null, true)), JSON.stringify({ key: "name", reverse: false }))
    // Settings stores Modified as "date" while Sort.ORDERS spells it "mtime": either spelling reads as the live order.
    check("a date default reads as the live mtime order",
          JSON.stringify(FolderSorts.orderFor({}, "/a", { key: "date", reverse: false }, true)),
          JSON.stringify({ key: "mtime", reverse: false }))
    check("and a stored date entry wins while remembering is on",
          JSON.stringify(FolderSorts.orderFor({ "/a": { key: "date", reverse: true } }, "/a", { key: "name" }, true)),
          JSON.stringify({ key: "mtime", reverse: true }))

    // A user sort writes its folder; browsing writes nothing.
    var pane = sortPane("/a", {}, true)
    Sort.column(pane, "size")
    check("choosing a sort writes its folder", pane.remembered.join(","), "/a|size:false")
    check("and still sends the sort and the window", pane.sent.join(","), "sort size,window")
    var changed = sortPane("/a", {}, true)
    Sort.resort(changed, "size", true)
    check("a changed order writes its folder", changed.remembered.join(","), "/a|size:true")
    var off = sortPane("/a", {}, false)
    Sort.column(off, "size")
    check("but still sends the sort and the window", off.sent.join(","), "sort size,window")
    check("with remembering off nothing writes", FolderSorts.shouldRemember(false, "/a"), false)
    check("with remembering on a folder writes", FolderSorts.shouldRemember(true, "/a"), true)
    check("an empty path writes nothing", FolderSorts.shouldRemember(true, ""), false)
    check("Backend gates folder writes through FolderSorts", source("ui/Backend.qml").indexOf("FolderSorts.shouldRemember") >= 0, true)
    var same = sortPane("/a", {}, true)
    Sort.resort(same, "name", false)
    check("asking for the order already shown writes nothing", same.remembered.length, 0)
    var picked = sortPane("/a", {}, true)
    Sort.column(picked, "__default__")
    check("the flyout's forget row forgets its folder", picked.forgotten.join(","), "/a")
    check("and lists the folder again on the default", picked.sent.join(","), "list /a")

    // The flyout gains its forget row only where the folder has its own sort, and marks nothing.
    var plain = Menu.sortEntries(false)
    check("without a folder sort the flyout lists the four orders alone",
          plain.map(function (r) { return r.label || "sep" }).join(","), "Name,Size,Modified,Kind")
    var owned = Menu.sortEntries(true)
    check("with one it gains Use the default sort after a separator",
          owned.map(function (r) { return r.separator === true ? "sep" : r.label }).join(","),
          "Name,Size,Modified,Kind,sep,Use the default sort")
    check("and the flyout marks no current sort, as shipped",
          owned.filter(function (r) { return r.selected || r.current || r.checked }).length, 0)

    // A tab keeps its own sort across a switch, and neither opening nor switching writes a folder sort.
    var tabs = Fixture.pane("/home/gm/Work")
    tabs.remembered = []
    tabs.backend.rememberFolderSort = function (folder, key, desc) { tabs.remembered.push(folder + "|" + key + ":" + desc) }
    check("a snapshot carries its tab's sort", tabs.backend.sortBy + ":" + tabs.backend.sortDesc, "name:false")
    Tabs.openNew(tabs, "/home/gm/Pictures")
    check("opening a tab writes no folder sort", tabs.remembered.length, 0)
    check("and tabs still count", Tabs.count(tabs), 2)
    check("and the left tab's snapshot keeps its sort", tabs.tabs.items[0].sortBy + ":" + tabs.tabs.items[0].sortDesc, "name:false")
    tabs.backend.sortBy = "size"
    tabs.backend.sortDesc = true
    Tabs.selectAt(tabs, 0)
    check("a tab switch writes no folder sort", tabs.remembered.length, 0)
    Tabs.applyPending(tabs)
    check("and the switch still writes no folder sort", tabs.remembered.length, 0)
    check("while the tab's own sort is restored", tabs.backend.sortBy + ":" + tabs.backend.sortDesc, "name:false")

    // Settings View Sorting: Hidden files last sits under Show hidden files with no hint; Remember each folder's sort is last and on.
    var view = Settings.rows("view", { data: {} })
    var labels = view.map(function (r) { return r.label || r.id }).join("|")
    check("Hidden files last sits directly under Show hidden files",
          labels.indexOf("Show hidden files|Hidden files last") >= 0, true)
    var hiddenLast = view.filter(function (r) { return r.id === "hiddenLast" })[0] || {}
    check("it draws no hint of its own",
          view.filter(function (r) { return r.kind === "hint" && (r.label || "").toLowerCase().indexOf("hidden") >= 0 }).length, 0)
    check("and it is greyed while hidden files are off", hiddenLast.available, false)
    var shown = Settings.rows("view", { data: { hidden: true } })
    var shownLast = shown.filter(function (r) { return r.id === "hiddenLast" })[0] || {}
    check("and live once they are shown", shownLast.available !== false, true)
    var remember = view.filter(function (r) { return r.id === "rememberSort" })[0] || {}
    var cursorAt = -1
    for (var c = 0; c < view.length; c++) {
        if (view[c].kind === "group" && view[c].label === "Cursor")
            cursorAt = c
    }
    check("Remember each folder's sort is the Sorting group's last row", cursorAt > 0 ? view[cursorAt - 1].id : "", "rememberSort")
    check("and ships on", remember.on, true)
}
