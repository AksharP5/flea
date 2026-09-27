.import "../../ui/js/RailKeys.js" as RailKeys

// The rail's own keys, split out of tests/js/focus.js at its 300-line cap the way focus-lines.js
// was: ui/js/Focus.js decides which surface owns a key, and this suite drives the rail surface.

function closed() {
    return { active: false, isMedia: false, isPdf: false }
}

function pane() {
    return { focusView: "list", viewMode: "list", searchMode: "", preview: closed() }
}

// The rail with focus, carrying the sink for what its menu case answers.
function railPane() {
    var p = pane()
    p.focusView = "rail"
    p.said = ""
    p.message = function (text, isError) { p.said = text }
    return p
}

// Only the members RailKeys.act's menu case reads, and a counter for the call it makes.
function rail(entries, cursor) {
    return { entries: entries, cursorIndex: cursor, opened: 0,
             openCursorMenu: function () { this.opened += 1 } }
}

// A pane and a rail for the eject key: the rail's rows and cursor, and a sink for what releaseChosen
// is handed, since that call is the whole of what the key must produce.
function ejectPane(path, entries, cursor) {
    var p = railPane()
    p.opened = 0
    p.openCursorMenu = function () { p.opened += 1; return true }
    p.path = path
    p.sidebar = { entries: entries, cursorIndex: cursor, released: [],
                  releaseChosen: function (action, key) { this.released.push(action + ":" + key) } }
    return p
}

function run(check) {
    var volume = { label: "128GB", group: "device", kind: "volume", device: "/dev/sda1", mounted: true, removable: true }
    var home = { label: "Home", group: "favorite", kind: "favorite", path: "/home/user" }

    // The rail is a cursored list, so g and G mean there what the sheet says they mean. Both
    // answered nothing until v0.1.3, which is why tests/ui.sh sharebrowser pressed g to reset the
    // rail cursor, landed one row below the entry it wanted, and activated the wrong one.
    var railCursor = { entries: [1, 2, 3, 4], cursorIndex: 2 }
    RailKeys.act("cursorFirst", railPane(), railCursor)
    check("g takes the rail to its first row", railCursor.cursorIndex, 0)
    RailKeys.act("cursorLast", railPane(), railCursor)
    check("G takes the rail to its last row", railCursor.cursorIndex, 3)
    var emptyRail = { entries: [], cursorIndex: 0 }
    RailKeys.act("cursorLast", railPane(), emptyRail)
    check("and an empty rail has no last row to reach", emptyRail.cursorIndex, 0)

    // #181: opening a rail row hands focus to the folder it opened, and an empty rail opens nothing.
    var opening = railPane()
    opening.open = function (path) {}
    // A local place opens inside activate, through the same opened signal PaneRail routes to openFrom.
    var places = { entries: [home, volume], cursorIndex: 1, activated: [],
                   activate: function (i) { this.activated.push(i); RailKeys.openFrom(opening, "/run/media/gm/USB", this) } }
    RailKeys.act("open", opening, places)
    check("Enter or l on a rail row opens that row", places.activated.join(","), "1")
    check("and moves focus into the folder it opened", opening.focusView + "|" + places.focusOnOpen, "list|false")
    var inert = railPane()
    var nothing = { entries: [home, volume], cursorIndex: 1, activate: function (i) {} }
    RailKeys.act("open", inert, nothing)
    check("a row whose activate opens nothing leaves focus on the rail", inert.focusView, "rail")
    var mounting = railPane()
    var share = { label: "nas", group: "network", kind: "share", uri: "smb://nas/media", mounted: false }
    var network = { entries: [home, share], cursorIndex: 1, activated: [], activate: function (i) { this.activated.push(i) } }
    RailKeys.act("open", mounting, network)
    check("an unmounted row starts its mount, keeps focus off the old folder, and asks the open to take it",
          network.activated.join(",") + "|" + mounting.focusView + "|" + network.focusOnOpen, "1|rail|true")
    RailKeys.act("cursorUp", mounting, network)
    check("another rail key withdraws that claim", network.focusOnOpen, false)
    // activate can answer before it returns: a mount that fails or opens at once must still spend or land the claim.
    var quick = railPane()
    var failsAtOnce = { entries: [home, share], cursorIndex: 1, activate: function (i) { RailKeys.messaged(this, true) } }
    RailKeys.act("open", quick, failsAtOnce)
    check("a mount that fails inside activate spends the claim and leaves focus on the rail",
          failsAtOnce.focusOnOpen + "|" + quick.focusView, "false|rail")
    var instant = railPane()
    instant.open = function (path) {}
    var opensAtOnce = { entries: [home, share], cursorIndex: 1,
                        activate: function (i) { RailKeys.openFrom(instant, "/run/user/1000/gvfs/smb", this) } }
    RailKeys.act("open", instant, opensAtOnce)
    check("a mount that opens inside activate lands focus in the folder", opensAtOnce.focusOnOpen + "|" + instant.focusView, "false|list")
    var mountedPane = railPane()
    var mountedShare = { label: "nas", group: "network", kind: "share", uri: "smb://nas/media", path: "/run/user/1000/gvfs/smb", mounted: true }
    mountedPane.open = function (path) {}
    var ready = { entries: [home, mountedShare], cursorIndex: 1, activated: [], activate: function (i) { this.activated.push(i) } }
    RailKeys.act("open", mountedPane, ready)
    check("a mounted share whose gio info has not answered keeps focus on the rail and the claim armed",
          mountedPane.focusView + "|" + ready.focusOnOpen + "|" + ready.activated.join(","), "rail|true|1")
    RailKeys.openFrom(mountedPane, mountedShare.path, ready)
    check("and focus follows when the share's open lands", mountedPane.focusView + "|" + ready.focusOnOpen, "list|false")
    var waiting = railPane()
    var claimed = { focusOnOpen: true }
    RailKeys.landed(waiting, claimed)
    check("the open that lands takes focus off the rail and spends the claim", waiting.focusView + "|" + claimed.focusOnOpen, "list|false")
    var moved = pane()
    moved.focusView = "preview"
    var stale = { focusOnOpen: true }
    RailKeys.landed(moved, stale)
    check("a landing after the user left the rail moves nothing and still spends the claim", moved.focusView + "|" + stale.focusOnOpen, "preview|false")
    var unclaimed = railPane()
    RailKeys.landed(unclaimed, { focusOnOpen: false })
    check("an open with no claim behind it leaves focus where it is", unclaimed.focusView, "rail")
    var target = railPane()
    target.opened = []
    target.open = function (path) { this.opened.push(path) }
    var mountRail = { focusOnOpen: true }
    RailKeys.openFrom(target, "/run/user/1000/gvfs/mtp", mountRail)
    check("a Sidebar open opens in the pane that asked and lands the claim there",
          target.opened.join(",") + "|" + target.focusView + "|" + mountRail.focusOnOpen, "/run/user/1000/gvfs/mtp|list|false")
    var orphan = { focusOnOpen: true }
    RailKeys.openFrom(null, "/run/user/1000/gvfs/mtp", orphan)
    check("an open with no pane opens nothing and spends the claim", orphan.focusOnOpen, false)
    var failing = { focusOnOpen: true }
    RailKeys.messaged(failing, false)
    check("an ordinary message keeps the claim", failing.focusOnOpen, true)
    RailKeys.messaged(failing, true)
    check("a mount error spends the claim", failing.focusOnOpen, false)
    var after = railPane()
    after.opened = []
    after.open = function (path) { this.opened.push(path) }
    RailKeys.openFrom(after, "/home/user", failing)
    check("a later open after the failed mount opens and leaves focus on the rail",
          after.opened.join(",") + "|" + after.focusView, "/home/user|rail")
    var nothing = railPane()
    var bare = { entries: [], cursorIndex: 0, activated: [], activate: function (i) { this.activated.push(i) } }
    RailKeys.act("open", nothing, bare)
    check("an empty rail opens nothing and keeps focus", bare.activated.length + "|" + nothing.focusView, "0|rail")

    var railing = railPane()
    var mounted = rail([volume], 0)
    RailKeys.act("menu", railing, mounted)
    check("m opens the menu on a mounted volume, and says nothing over it",
          mounted.opened + "|" + railing.said, "1|")
    var favourite = rail([home], 0)
    RailKeys.act("menu", railing, favourite)
    check("a row with nothing to release says why instead of swallowing the key",
          favourite.opened + "|" + railing.said, "0|Home has nothing to eject or unmount.")
    var empty = rail([], 0)
    railing.said = ""
    RailKeys.act("menu", railing, empty)
    check("an empty rail answers nothing at all rather than throwing",
          empty.opened + "|" + railing.said, "0|")

    // Finder's Cmd+E on the rail's own cursor row. The release goes through the same releaseChosen a
    // chosen menu row takes, carrying the row's key and not its index.
    // RailAdditions rule 1's switch builds this row, so it carries the board's own menu
    // (Open, Unmount, Eject) rather than the single Eject 0.2.1 drew: without volumeMenu the
    // release below cannot tell rows[0] from the release.
    var stick = { label: "128GB", group: "device", kind: "volume", device: "/dev/sda1", path: "/run/media/user/128GB", mounted: true, removable: true, volumeMenu: true }
    var ejecting = ejectPane("/home/user", [home, stick], 1)
    RailKeys.act("eject", ejecting, ejecting.sidebar)
    check("ctrl e in the rail ejects the cursor row by its key",
          ejecting.sidebar.released.join(",") + "|" + ejecting.said, "eject:/dev/sda1|")
    var favouriteRail = ejectPane("/home/user", [home, stick], 0)
    RailKeys.act("eject", favouriteRail, favouriteRail.sidebar)
    check("ctrl e on a favourite says why, and releases nothing",
          favouriteRail.sidebar.released.length + "|" + favouriteRail.said, "0|Home has nothing to eject or unmount.")
    // The release is picked by name, never by position: a share offers only Unmount, and a
    // phone leads with Open beside its Unmount the way a volume does, so rows[0] would open both.
    var share = { label: "isos", group: "network", kind: "share", uri: "smb://example.com/isos/", path: "", mounted: true }
    var onShare = ejectPane("/home/user", [home, share], 1)
    RailKeys.act("eject", onShare, onShare.sidebar)
    check("ctrl e on a share unmounts it rather than opening it",
          onShare.sidebar.released.join(","), "unmount:smb://example.com/isos/")
    var phone = { label: "Pixel", group: "device", kind: "phone", uri: "mtp://Google_Pixel_7_1A2B/", path: "", mounted: true }
    var onPhone = ejectPane("/home/user", [home, phone], 1)
    RailKeys.act("eject", onPhone, onPhone.sidebar)
    check("ctrl e on a phone unmounts it rather than opening it",
          onPhone.sidebar.released.join(","), "unmountPhone:mtp://Google_Pixel_7_1A2B/")
}
