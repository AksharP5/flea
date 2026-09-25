.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/MenuRefresh.js" as MenuRefresh
.import "../../ui/js/LockedMenu.js" as LockedMenu
.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/Icons.js" as Icons
.import "../../ui/js/Mounts.js" as Mounts

function state(changes) {
    var value = { hasRow: true, selectionCount: 1, rowMode: 0o100644, clipboardAvailable: false,
        hiddenActions: ["delete", "openTerminal", "moveto", "copyto", "properties", "permissions", "copypath"],
        archiveFormats: ["zip"], canExtract: true, rowIsArchive: false, rowIsImage: true, canConvert: true,
        taildropInstalled: true, taildropPeers: [{ id: "box", label: "Box" }],
        dropboxInstalled: true, dropboxPath: "/tmp/Dropbox", rowInDropbox: false }
    for (var key in changes) value[key] = changes[key]
    return value
}
function actions(rows) { return rows.filter(function (r) { return !r.separator }).map(function (r) { return r.action }).join(",") }
function entry(rows, action) { return rows.filter(function (r) { return r.action === action })[0] || {} }
function separated(rows) {
    return !rows.length || !rows[0].separator && !rows[rows.length - 1].separator
        && !rows.some(function (r, i) { return r.separator && i > 0 && rows[i - 1].separator })
}
function run(check) {
    var file = Menu.listingEntries(state({}))
    check("Menus and Places inventory has 36 actions", Menu.INVENTORY.length, 36)
    check("Open with uses the authoritative cut geometry", Icons.pathFor("app-window"), "M3 4h18v16H3z M3 9h18 M6 6.5h.01 M9 6.5h.01")
    check("Restore all uses the authoritative undo geometry", Icons.pathFor("undo"), "M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8 M3 3v5h5")
    check("inventory storage ids are unique", Object.keys(Menu.INVENTORY.reduce(function (out, row) { out[row[0]] = true; return out }, {})).length, 36)
    check("default image menu matches Menus specimen", actions(file),
          "open,openWith,cut,copy,paste,duplicate,rename,compress,convert,addToShelf,taildrop,dropbox,trash,addFavourite,toggleHidden")
    check("empty clipboard leaves Paste visible and disabled", entry(file, "paste").disabled, true)
    check("populated clipboard enables Paste", entry(Menu.listingEntries(state({ clipboardAvailable: true })), "paste").disabled, false)
    check("folder omits conversion and extraction", actions(Menu.listingEntries(state({ rowMode: 0o040755, rowIsImage: false }))),
          "open,openWith,cut,copy,paste,duplicate,rename,compress,addToShelf,taildrop,dropbox,trash,addFavourite,toggleHidden")
    check("background menu includes real creation actions in order", actions(Menu.listingEntries(state({ hasRow: false }))),
          "newFolder,newFile,paste,selectAll,addFavourite,sort,toggleHidden,settings")
    var background = Menu.listingEntries(state({ hasRow: false, updateVersion: "0.3.4" }))
    check("a known newer build adds Update Flea under Settings, in the same group, with the download mark",
          background.slice(-2).map(function (r) { return (r.separator ? "|" : r.action) + ":" + r.glyph }).join(","),
          "settings:sliders,updateFlea:download")
    check("and its hint slot carries that version beside the status square",
          entry(background, "updateFlea").hint + "|" + entry(background, "updateFlea").hintSquare, "0.3.4|true")
    check("the Menus switch takes it away like any other row",
          entry(Menu.listingEntries(state({ hasRow: false, updateVersion: "0.3.4", hiddenActions: ["updateFlea"] })), "updateFlea").action, undefined)
    check("a file row's menu never offers it", entry(Menu.listingEntries(state({ updateVersion: "0.3.4" })), "updateFlea").action, undefined)
    check("and neither does an empty version, which is what every state but available gives",
          entry(Menu.listingEntries(state({ hasRow: false, updateVersion: "" })), "updateFlea").action, undefined)
    check("selected file cannot be pinned as a folder", entry(file, "addFavourite").disabled, true)
    check("Favorites menu uses GM's displayed spelling", entry(file, "addFavourite").label, "Add to Favorites")
    check("selected directory can be pinned", entry(Menu.listingEntries(state({ rowMode: 0o040755 })), "addFavourite").disabled, false)
    check("multi-selection cannot pin a cursor sibling", entry(Menu.listingEntries(state({ rowMode: 0o040755, selectionCount: 2 })), "addFavourite").disabled, true)
    check("symlink metadata cannot pretend to be a directory", entry(Menu.listingEntries(state({ rowMode: 0o120777 })), "addFavourite").disabled, true)
    check("missing metadata cannot be pinned", entry(Menu.listingEntries(state({ rowMode: undefined })), "addFavourite").disabled, true)
    check("background pins the current folder without selected rows", entry(Menu.listingEntries(state({ hasRow: false, selectionCount: 0 })), "addFavourite").disabled, undefined)
    check("direct background builder ignores row eligibility", entry(Menu.backgroundEntries(state({})), "addFavourite").disabled, undefined)
    check("empty Trash retains both disabled actions", actions(Menu.trashEntries(0, false)), "open,restoreAll,emptyTrash")
    check("empty Trash disables restore", entry(Menu.trashEntries(0, false), "restoreAll").disabled, true)
    check("empty Trash disables empty", entry(Menu.trashEntries(0, false), "emptyTrash").disabled, true)
    check("busy Trash disables destructive reactivation", entry(Menu.trashEntries(4, true), "emptyTrash").disabled, true)
    check("full idle Trash enables restore", entry(Menu.trashEntries(4, false), "restoreAll").disabled, false)
    var all = Menu.listingEntries(state({ hiddenActions: [] }))
    check("stored delete id reaches permanent deletion action", entry(all, "deletePermanently").id, "delete")
    check("all optional file controls exist", ["openWith", "moveTo", "copyTo", "properties", "permissions", "copypath", "openTerminal"].every(function (a) { return !!entry(all, a).action }), true)
    check("permanent deletion carries danger role", entry(all, "deletePermanently").danger, true)
    // Issue 133: ui/Pane.qml hands the menu Mounts.trashable of the folder, and on a share the row that would fail is absent.
    var onShare = Menu.listingEntries(state({ hiddenActions: [], canTrash: Mounts.trashable("/run/user/1000/gvfs/smb-share:server=192.168.21.25,share=data") }))
    check("a file on an SMB share is not offered Move to Trash", entry(onShare, "trash").action, undefined)
    check("while Delete permanently, which the share can do, stays and stays enabled",
          entry(onShare, "deletePermanently").action + "|" + entry(onShare, "deletePermanently").disabled, "deletePermanently|undefined")
    check("and a local file keeps Move to Trash", entry(Menu.listingEntries(state({ canTrash: Mounts.trashable("/home/gm/Downloads") })), "trash").action, "trash")
    check("single-item actions stay present but disabled on multi-selection", ["openWith", "properties", "rename", "duplicate", "permissions"].every(function (a) {
        return entry(Menu.listingEntries(state({ hiddenActions: [], selectionCount: 2 })), a).disabled === true
    }), true)
    check("missing converter removes Convert", entry(Menu.listingEntries(state({ canConvert: false })), "convert").action, undefined)
    check("missing archiver removes Compress", entry(Menu.listingEntries(state({ archiveFormats: [] })), "compress").action, undefined)
    var noReader = entry(Menu.listingEntries(state({ rowIsArchive: true, canExtract: false, archiveFormats: ["zip", "tar"] })), "extract")
    check("a recognized archive with no reader keeps its Extract row", noReader.action, "extract")
    check("and the disabled row carries the missing reader as its reason",
          noReader.disabled + "|" + noReader.hint + "|" + noReader.hintWrap, "true|7-Zip is not installed|true")
    check("supported archive offers Extract", entry(Menu.listingEntries(state({ rowIsArchive: true })), "extract").action, "extract")
    check("absent Taildrop provider removes its row", entry(Menu.listingEntries(state({ taildropInstalled: false })), "taildrop").action, undefined)
    var offline = entry(Menu.listingEntries(state({ taildropPeers: [] })), "taildrop")
    check("offline installed Taildrop remains disabled", offline.disabled, true)
    check("offline Taildrop reads as an error, with no sentence beside it", offline.errored + "|" + offline.hint, "true|undefined")
    check("offline Taildrop offers no stale peers", offline.submenu.length, 0)
    check("fresh status disables a cached Taildrop target", entry(Menu.listingEntries(state({taildropRefreshing: true})), "taildrop").disabled, true)
    check("a provider still being read is dimmed, not errored", String(entry(Menu.listingEntries(state({taildropRefreshing: true})), "taildrop").errored), "undefined")
    check("fresh status disables a cached Dropbox directory", entry(Menu.listingEntries(state({dropboxRefreshing: true})), "dropbox").disabled, true)
    check("a Taildrop still being read leaves Dropbox as it was answered", entry(Menu.listingEntries(state({taildropRefreshing: true})), "dropbox").disabled, false)
    check("installed signed-out provider reads as an error", entry(Menu.listingEntries(state({taildropPeers: [], taildropReason: "signed out"})), "taildrop").errored, true)
    var absent = Menu.listingEntries(state({taildropInstalled: false, dropboxInstalled: false}))
    var available = Menu.listingEntries(state({}))
    var trashCursor = absent.findIndex(function(row) { return row.action === "trash" })
    var refreshed = MenuRefresh.refreshedCursor(absent, available, trashCursor, -1, 0)
    check("new provider inventory inserts both actual providers", available.filter(function(row) { return row.action === "taildrop" || row.action === "dropbox" }).length, 2)
    check("new providers do not steal the current action", available[refreshed.cursor].action, "trash")
    refreshed = MenuRefresh.refreshedCursor(available, absent, refreshed.cursor, -1, 0)
    check("removed providers leave the existing action selected", absent[refreshed.cursor].action, "trash")
    check("removed providers are absent from fresh inventory", absent.filter(function(row) { return row.action === "taildrop" || row.action === "dropbox" }).length, 0)
    var oldPeers = [{action: "taildrop", submenu: [{id: "b"}]}]
    var newPeers = [{action: "taildrop", submenu: [{id: "a"}, {id: "b"}]}]
    refreshed = MenuRefresh.refreshedCursor(oldPeers, newPeers, 0, 0, 0)
    check("a submenu keeps its target id when peers reorder", refreshed.submenuCursor, 1)
    check("a retained submenu keeps its parent action", refreshed.submenuRow, 0)
    refreshed = MenuRefresh.refreshedCursor(oldPeers, [{action: "taildrop", submenu: [{id: "a"}]}], 0, 0, 0)
    check("a vanished peer closes rather than retargeting the submenu", refreshed.submenuRow, -1)
    refreshed = MenuRefresh.refreshedCursor([{action: "taildrop"}], [{separator: true}, {action: "copy", disabled: true}, {action: "open"}], 0, -1, 0)
    check("a removed action selects an eligible row rather than a separator", refreshed.cursor, 2)
    check("missing Dropbox removes its row", entry(Menu.listingEntries(state({ dropboxInstalled: false })), "dropbox").action, undefined)
    check("offline Dropbox remains disabled", entry(Menu.listingEntries(state({ dropboxPath: "" })), "dropbox").disabled, true)
    var inside = Menu.listingEntries(state({ rowInDropbox: true }))
    check("inside Dropbox replaces move with share link", entry(inside, "dropbox").action + "|" + entry(inside, "sharelink").action, "undefined|sharelink")
    check("hidden capability rows leave no doubled separators", separated(Menu.listingEntries(state({ hiddenActions: ["compress", "convert", "taildrop", "dropbox"] }))), true)
    check("Open cannot be hidden", Menu.isHidden(["open"], "open"), false)
    check("hidden toggle cannot be hidden", Menu.isHidden(["toggleHidden"], "toggleHidden"), false)
    check("stored lower-case id hides corresponding action", entry(Menu.listingEntries(state({ hiddenActions: ["openwith"] })), "openWith").action, undefined)
    check("hidden files toggle uses inverse wording", Menu.hiddenRow(true).label, "Hide hidden files")
    check("permissions accepts ordinary file", Menu.permissionsEntry(0o100644, 1).disabled, false)
    check("permissions accepts directory", Menu.permissionsEntry(0o040755, 1).disabled, false)
    // Issue 193: a row that cannot act reads red with no sentence beside it, never "Unavailable" (GM, 2026-09-24).
    function refusal(e) { return e.disabled + "|" + e.errored + "|" + e.hint }
    check("permissions on a symlink reads as an error with no sentence", refusal(Menu.permissionsEntry(0o120777, 1)), "true|true|undefined")
    check("permissions on a row whose mode could not be read does too", refusal(Menu.permissionsEntry(0, 1)), "true|true|undefined")
    check("and a file's row can act, so it is not red", refusal(Menu.permissionsEntry(0o100644, 1)), "false|false|undefined")
    var perms = function (changes) { return entry(Menu.listingEntries(state(changes)), "permissions") }
    check("the menu row under a parent without execute reads red with no sentence",
          refusal(perms({ hiddenActions: [], rowMode: 0 })), "true|true|undefined")
    check("the menu row for a multi-selection reads the same way", refusal(perms({ hiddenActions: [], selectionCount: 2 })), "true|true|undefined")
    check("the menu row for a symlink reads the same way", refusal(perms({ hiddenActions: [], rowMode: 0o120777 })), "true|true|undefined")
    check("the menu row for a folder it can change is plain", refusal(perms({ hiddenActions: [], rowMode: 0o040755 })), "false|undefined|undefined")
    check("permissions rejects missing metadata", Menu.permissionsEntry(undefined, 1).disabled, true)
    check("permissions rejects fifo", Menu.permissionsEntry(0o010644, 1).disabled, true)
    check("permissions allows read-only inspection of special bits", Menu.permissionsEntry(0o104755, 1).disabled, false)
    // Issue 193 follow-up (GM, 2026-09-24): a right click on the Locked tile opens the
    // locked folder's own menu, never the parent's background one.
    var locked = LockedMenu.lockedEntries({ lockedMode: 0o040000, hiddenActions: [] })
    check("the Locked tile offers only rows that act without listing the folder",
          actions(locked), "openTerminal,permissions,copypath")
    check("and no row that would create in, paste into or sort the parent",
          ["newFolder", "newFile", "paste", "selectAll", "sort", "toggleHidden", "settings"].every(function (a) {
              return entry(locked, a).action === undefined
          }), true)
    check("Permissions stays plain while its owner may still be the operator, the way back in",
          refusal(entry(locked, "permissions")), "false|undefined|undefined")
    var stranger = LockedMenu.lockedEntries({ lockedMode: 0o040755, hiddenActions: [] })
    check("Permissions for a folder owned by somebody else reads red with no sentence",
          refusal(entry(stranger, "permissions")), "true|true|undefined")
    var unreadable = LockedMenu.lockedEntries({ lockedMode: 0, hiddenActions: [] })
    check("Permissions with no mode to read reads red with no sentence too",
          refusal(entry(unreadable, "permissions")), "true|true|undefined")
    check("hiding Open in terminal takes it off the Locked tile as well",
          entry(LockedMenu.lockedEntries({ lockedMode: 0o040000, hiddenActions: ["openTerminal"] }), "openTerminal").action, undefined)
    check("menu fits at pointer", Menu.clamp(20, 80, 300), 20)
    check("menu flips before shifting", Menu.clamp(270, 80, 300), 190)
    check("oversized menu pins to near edge", Menu.clamp(30, 500, 300), 0)
    check("negative point clamps", Menu.clamp(-20, 80, 300), 0)
    check("submenu array is recognized even when empty", Menu.hasSubmenu({ submenu: [] }), true)
    check("ordinary entry has no submenu", Menu.hasSubmenu({ action: "open" }), false)
    check("missing entry has no submenu", Menu.hasSubmenu(undefined), false)
    check("header keeps required Name column outside toggles", actions(Menu.headerEntries([], false)), "col:mode,col:size,col:date,col:kind,toggleHidden")
    check("sort submenu uses real backend order ids", Menu.sortEntries().map(function (r) { return r.id }).join(","), "name,size,mtime,kind")
    providerRefresh(check)
}

function merged(base, changes) {
    var out = {}
    for (var key in base) out[key] = base[key]
    for (key in changes) out[key] = changes[key]
    return out
}

// The rows a file menu draws from one set of provider inputs, through ui/js/MenuRefresh.js the way ui/ContextMenu.qml builds them.
function drawn(known, live) {
    var view = MenuRefresh.providerView(known, live)
    return Menu.listingEntries(state({ taildropPeers: view.taildropPeers, taildropRefreshing: view.taildropRefreshing,
        dropboxPath: view.dropboxPath, dropboxRefreshing: view.dropboxRefreshing, localSendInstalled: true,
        localSendPeers: [{ id: "Phone", label: "Phone" }], localSendChecking: view.localSendChecking }))
}

// An open refreshes its providers behind the menu; the last answer stands in, so only a changed answer rebuilds rows.
function providerRefresh(check) {
    check("the menu keeps the last provider answer", typeof MenuRefresh.settle + "|" + typeof MenuRefresh.providerView, "function|function")
    if (typeof MenuRefresh.settle !== "function") return
    var answer = { refreshing: false, taildropInstalled: true, taildropPeers: [{ id: "box", label: "Box" }],
        dropboxInstalled: true, dropboxPath: "/tmp/Dropbox", localSendChecking: false, localSendAnswered: true }
    var known = MenuRefresh.settle(answer)
    var before = drawn(known, answer)
    // While the status helpers run, Taildrop has cleared its peers, Dropbox is not ready and LocalSend is looking again.
    var reading = merged(answer, { refreshing: true, taildropPeers: [], dropboxPath: "", localSendChecking: true })
    var during = drawn(known, reading)
    check("a refresh behind the open menu builds exactly the rows drawn", MenuRefresh.unchanged(before, during), true)
    check("so Taildrop keeps its peer and stays live", entry(during, "taildrop").disabled + "|" + entry(during, "taildrop").submenu.length, "false|1")
    check("Dropbox keeps its folder", entry(during, "dropbox").disabled, false)
    check("and LocalSend stays live while it looks again", entry(during, "localsend").disabled, false)
    known = MenuRefresh.settle(answer)
    check("the same answer landing rebuilds nothing", MenuRefresh.unchanged(before, drawn(known, answer)), true)
    var more = merged(answer, { taildropPeers: [{ id: "box", label: "Box" }, { id: "laptop", label: "Laptop" }] })
    known = MenuRefresh.settle(more)
    var after = drawn(known, more)
    check("a changed answer is a change", MenuRefresh.unchanged(before, after), false)
    check("and it moves only the Taildrop row", before.map(function (row, i) {
        return JSON.stringify(row) === JSON.stringify(after[i]) ? "" : row.action }).filter(String).join(","), "taildrop")
    check("which now offers both peers", entry(after, "taildrop").submenu.map(function (peer) { return peer.id }).join(","), "box,laptop")
    var gone = merged(answer, { dropboxPath: "" })
    after = drawn(MenuRefresh.settle(gone), gone)
    check("a Dropbox that stopped answering reads red, and only its row moves", before.map(function (row, i) {
        return JSON.stringify(row) === JSON.stringify(after[i]) ? "" : row.action }).filter(String).join(",") + "|" + entry(after, "dropbox").errored, "dropbox|true")
    var first = drawn(null, merged(reading, { localSendAnswered: false }))
    check("with nothing answered yet the first refresh dims Taildrop, as it always did", entry(first, "taildrop").disabled + "|" + String(entry(first, "taildrop").errored), "true|undefined")
    check("and Dropbox", entry(first, "dropbox").disabled + "|" + String(entry(first, "dropbox").errored), "true|undefined")
    check("and LocalSend", entry(first, "localsend").disabled + "|" + String(entry(first, "localsend").errored), "true|undefined")
    var reinstalled = drawn(MenuRefresh.settle(merged(answer, { taildropInstalled: false, taildropPeers: [] })), reading)
    check("a provider installed since its last answer is read afresh, dimmed rather than red",
          entry(reinstalled, "taildrop").disabled + "|" + String(entry(reinstalled, "taildrop").errored), "true|undefined")
    // The one key step both the menu and its flyout take: separators and disabled rows are skipped, an end holds.
    var steps = [{ action: "open" }, { separator: true }, { action: "cut", disabled: true }, { action: "copy" }]
    check("a step skips a separator and a disabled row", Menu.stepRow(steps, 0, 1), 3)
    check("and back again", Menu.stepRow(steps, 3, -1), 0)
    check("an end keeps the cursor where it is", Menu.stepRow(steps, 3, 1) + "|" + Menu.stepRow(steps, 0, -1), "3|0")
    check("the opening cursor is the first row a step from before the top reaches", Menu.stepRow(steps.slice(1), -1, 1), 2)

    // Issue 193: a Locked tile names the refused folder for its menu; any other state names nothing.
    function lockedAs(path, asked, state) { return Nav.lockedTarget({ path: path, listingPath: asked, listingState: state }) }
    check("refused hop names the ask, re-read names itself, ready and error name nothing", lockedAs("/d", "/d/locked", "locked") + "|" + lockedAs("/d", "/d", "locked") + "|" + lockedAs("/d", "/d", "ready") + "|" + lockedAs("/d", "/d", "error"), "/d/locked|/d||")
    check("a refused bookmark with a trailing slash names the folder without it", lockedAs("/d", "/root/", "locked"), "/root")
}
