.import "../../ui/js/Settings.js" as Settings

// The Shelf section of the settings panel, its own suite because the panel's model is large enough
// without it. SettingsRest rules 1 to 4 and ledger directive 59.

function run(check) {
    runShelfRows(check)
}

function kinds(rows) {
    return rows.map(function (row) { return row.kind }).join("|")
}

function find(rows, id) {
    for (var i = 0; i < rows.length; i++) {
        if (rows[i].id === id)
            return rows[i]
    }
    return {}
}

// SettingsRest rules 1 to 4, ledger directive 59: the Shelf section, the rows it draws and the two
// things its master governs. The pins come from the shelf's own pile, so the panel is handed them.
function runShelfRows(check) {
    var fresh = Settings.rows("shelf", { data: {}, pins: [] })
    check("the Shelf section is the master, the two routes, the captures and Pinned",
          kinds(fresh), "group|check|choice|hint|group|check|check|choice|group")
    check("it opens with the shelf on, the bar on and the rail off",
          [find(fresh, "shelf.enabled").state, find(fresh, "shelf.bar").on,
           find(fresh, "shelf.rail").selected].join("|"), "all|true|off")
    check("the captures group opens on both kinds and three",
          [find(fresh, "shelf.screenshots").on, find(fresh, "shelf.recordings").on,
           find(fresh, "shelf.recent").selected].join("|"), "true|true|3")
    check("and the rail names its four edges in the board's order",
          find(fresh, "shelf.rail").labels.join("|"), "Off|Left|Right|Bottom")
    var off = Settings.rows("shelf", { data: { shelf: { enabled: false } }, pins: [] })
    check("the master greys every row under it, and is still the way back on",
          [find(off, "shelf.enabled").state, find(off, "shelf.bar").available,
           find(off, "shelf.recent").available].join("|"), "none|false|false")
    var pinned = Settings.rows("shelf", { data: {}, pins: [
        { path: "/home/gm/Invoices", name: "Invoices", folder: true },
        { path: "/home/gm/Work/handoff.md", name: "handoff.md", folder: false, missing: true }
    ] })
    check("a pin is a favourite row naming its own path, and a missing one takes the error role",
          kinds(pinned) + " / " + find(pinned, "pin:0").value + " / " + find(pinned, "pin:1").error,
          "group|check|choice|hint|group|check|check|choice|group|favourite|favourite"
          + " / /home/gm/Invoices / missing")
    check("and the Pinned heading carries the shelf's own Add",
          find(pinned, "pinFolder").value, "Pin this folder")
    // A count a hand-edited file left behind is not one of the four the board offers.
    var odd = Settings.rows("shelf", { data: { shelf: { recent: 4 } }, pins: [] })
    check("a stored count off the four falls back to three", find(odd, "shelf.recent").selected, 3)
}
