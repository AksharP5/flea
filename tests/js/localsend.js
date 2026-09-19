.import "../../ui/js/LocalSend.js" as LocalSend
.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/Ops.js" as Ops
.import "../../ui/js/Settings.js" as Settings

// MenuAdditions rule 1, reported as PR 82 (zicochaos): a Send with LocalSend row between Taildrop
// and Dropbox, present only while a localsend binary answered on PATH and absent rather than greyed
// when none did, carrying the brand's own reproduced mark instead of a cut glyph.

function state(changes) {
    var value = { hasRow: true, selectionCount: 1, rowMode: 0o100644, clipboardAvailable: false,
        hiddenActions: [], archiveFormats: ["zip"], canExtract: true, rowIsArchive: false,
        rowIsImage: false, canConvert: true, taildropInstalled: true,
        taildropPeers: [{ id: "box", label: "Box" }],
        dropboxInstalled: true, dropboxPath: "/tmp/Dropbox", rowInDropbox: false }
    for (var key in changes) value[key] = changes[key]
    return value
}

function actions(rows) {
    return rows.filter(function (r) { return !r.separator }).map(function (r) { return r.action }).join(",")
}

function entry(rows, action) {
    return rows.filter(function (r) { return r.action === action })[0] || {}
}

function run(check) {
    var absent = Menu.listingEntries(state({ localSendInstalled: false }))
    check("no binary on PATH means no row at all, not a greyed one",
          actions(absent).indexOf("localsend"), -1)

    var rows = Menu.listingEntries(state({ localSendInstalled: true }))
    var send = actions(rows).split(",").filter(function (a) {
        return a === "taildrop" || a === "localsend" || a === "dropbox"
    })
    check("the row sits between the other two people's destinations", send.join(","),
          "taildrop,localsend,dropbox")
    check("a brand row carries its brand's own mark", entry(rows, "localsend").mark, "localsend")
    check("and never a cut glyph beside it", entry(rows, "localsend").glyph, undefined)
    check("the label is the send group's own vocabulary", entry(rows, "localsend").label,
          "Send with LocalSend")

    // Directive 38: the switch ships off, so the shipped hidden set is what a fresh ui.json holds.
    var hidden = Menu.listingEntries(state({ localSendInstalled: true, hiddenActions: ["localsend"] }))
    check("with the Extras switch off the menu is the one 0.2.1 drew",
          actions(hidden).indexOf("localsend"), -1)
    check("the Settings row wears the same mark the menu draws", Settings.MARKS.localsend, "localsend")
    check("and the same wording", Settings.label("localsend"), "Send with LocalSend")

    // Directive 71: the row is Taildrop's twin, so the flyout is the devices the CLI discovered and
    // a row with none reads as an error the way a Taildrop with no peers does.
    var peers = [{ id: "Clean Lemon", label: "Clean Lemon" }, { id: "minipc", label: "minipc" }]
    var flyout = Menu.listingEntries(state({ localSendInstalled: true, localSendPeers: peers }))
    check("the row carries the devices by name", entry(flyout, "localsend").submenu.map(function (p) { return p.label }).join(","),
          "Clean Lemon,minipc")
    check("and it is not disabled while they are there", entry(flyout, "localsend").disabled, false)
    var empty = Menu.listingEntries(state({ localSendInstalled: true, localSendPeers: [] }))
    check("nothing answering is a row that reads as an error", [entry(empty, "localsend").disabled, entry(empty, "localsend").errored].join(","), "true,true")
    var asking = Menu.listingEntries(state({ localSendInstalled: true, localSendPeers: [], localSendChecking: true }))
    check("and a list still being read is only disabled", [entry(asking, "localsend").disabled, entry(asking, "localsend").errored === true].join(","), "true,false")

    // What Flea itself says: the dispatch, and then the verdict its own CLI came back with.
    check("one file names the file and the device", LocalSend.sending("Clean Lemon", ["/home/gm/a file.txt"]),
          "Sending a file.txt to Clean Lemon with LocalSend.")
    check("several are counted", LocalSend.sending("Clean Lemon", ["/home/gm/a.txt", "/home/gm/b.txt"]),
          "Sending 2 items to Clean Lemon with LocalSend.")
    check("a finished transfer is said once", LocalSend.verdict(true, ""), "LocalSend finished the transfer.")
    check("a refusal is the CLI's own sentence", LocalSend.verdict(false, "Clean Lemon did not accept the transfer."),
          "LocalSend \u00b7 Clean Lemon did not accept the transfer.")
    check("and a refusal with nothing to say still says something", LocalSend.verdict(false, ""),
          "LocalSend could not finish the transfer.")
    check("a CLI that left between the menu and the pick says why",
          LocalSend.missing({ installed: false, reason: "localsend-cli is not installed." }),
          "LocalSend \u00b7 localsend-cli is not installed.")
}
