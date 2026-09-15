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
    check("and it is a send, so it opens no flyout", entry(rows, "localsend").submenu, undefined)
    check("a brand row carries its brand's own mark", entry(rows, "localsend").mark, "localsend")
    check("and never a cut glyph beside it", entry(rows, "localsend").glyph, undefined)
    check("the row is never greyed for an absence it cannot have",
          entry(rows, "localsend").disabled, undefined)
    check("the label is the send group's own vocabulary", entry(rows, "localsend").label,
          "Send with LocalSend")

    // Directive 38: the switch ships off, so the shipped hidden set is what a fresh ui.json holds.
    var hidden = Menu.listingEntries(state({ localSendInstalled: true, hiddenActions: ["localsend"] }))
    check("with the Extras switch off the menu is the one 0.2.1 drew",
          actions(hidden).indexOf("localsend"), -1)
    check("the Settings row wears the same mark the menu draws", Settings.MARKS.localsend, "localsend")
    check("and the same wording", Settings.label("localsend"), "Send with LocalSend")

    // What Flea itself can say: the dispatch and nothing else, because LocalSend's own window is
    // where a transfer is accepted, refused or watched. The same rule as ui/js/Ops.js sendTaildrop.
    check("one file is named", LocalSend.sentLine(["/home/gm/a file.txt"]),
          "Sending a file.txt with LocalSend.")
    check("several are counted", LocalSend.sentLine(["/home/gm/a.txt", "/home/gm/b.txt"]),
          "Sending 2 items with LocalSend.")
    check("and the file is named the way Taildrop's own send names it", LocalSend.sentLine(["/home/gm/b.txt"]),
          "Sending " + Ops.leaf("/home/gm/b.txt") + " with LocalSend.")
    check("a binary that left between the menu opening and the row being chosen says why",
          LocalSend.missing({ installed: false, reason: "localsend or localsend_app is not installed." }),
          "LocalSend · localsend or localsend_app is not installed.")
    check("and a provider with nothing to say still says something",
          LocalSend.missing(null), "LocalSend is no longer installed.")
}
