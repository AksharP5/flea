.import "../../ui/js/ExtThumbs.js" as ExtThumbs
.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/Settings.js" as Settings

// The ExtThumbs board's storage-class gate: network shares and phones are off, USB
// drives are on, and local folders always take today's full path.

function menuState(changes) {
    var value = { hasRow: false, showHidden: false, hiddenActions: [],
        storageClass: "", thumbPreview: {} }
    for (var key in changes) value[key] = changes[key]
    return value
}

function run(check) {
    check("only the three classes name a switch", ["network", "phone", "usb", "", "smb"].map(ExtThumbs.keyForClass).join("|"),
          "thumbNetwork|thumbPhone|thumbUsb||")
    check("and only they hold the menu row", ["network", "phone", "usb", "", "smb"].map(ExtThumbs.present).join("|"),
          "true|true|true|false|false")
    check("network and phone ship off", [ExtThumbs.classOn("network", {}), ExtThumbs.classOn("phone", {})].join("|"), "false|false")
    check("USB ships on", ExtThumbs.classOn("usb", {}), true)
    check("a stored switch reads back", [ExtThumbs.classOn("network", { thumbNetwork: true }), ExtThumbs.classOn("usb", { thumbUsb: false })].join("|"),
          "true|false")
    check("local is always on, whatever the file holds", ExtThumbs.classOn("", { thumbNetwork: true }), true)
    check("an off class is cache-only", [ExtThumbs.cacheOnly("network", {}), ExtThumbs.cacheOnly("phone", {}), ExtThumbs.cacheOnly("usb", {})].join("|"),
          "true|true|false")
    check("a switched-on class decodes", ExtThumbs.cacheOnly("network", { thumbNetwork: true }), false)
    check("local never is", ExtThumbs.cacheOnly("", {}), false)
    check("and a global Off asks for nothing to gate", ExtThumbs.cacheOnly("network", { thumbnails: "off" }), false)
    check("the hold is the same condition as the gate", ExtThumbs.manualHold("phone", {}), ExtThumbs.cacheOnly("phone", {}))
    check("the row names its class going off", [ExtThumbs.label("network", false), ExtThumbs.label("phone", false), ExtThumbs.label("usb", false)].join("|"),
          "Show network thumbnails|Show phone thumbnails|Show USB thumbnails")
    check("and coming on", [ExtThumbs.label("network", true), ExtThumbs.label("phone", true), ExtThumbs.label("usb", true)].join("|"),
          "Hide network thumbnails|Hide phone thumbnails|Hide USB thumbnails")
    check("the menu entry is absent locally", Menu.listingEntries(menuState({})).filter(function (r) { return r.action === "extThumbs" }).length, 0)
    check("and on an unknown class", Menu.listingEntries(menuState({ storageClass: "smb" })).filter(function (r) { return r.action === "extThumbs" }).length, 0)
    var network = Menu.listingEntries(menuState({ storageClass: "network" })).filter(function (r) { return r.action === "extThumbs" })
    check("a NAS background menu carries it", network.map(function (r) { return r.label + "|" + r.glyph }).join(","), "Show network thumbnails|image")
    var shown = Menu.listingEntries(menuState({ storageClass: "network", hiddenActions: [], thumbPreview: { thumbNetwork: true } }))
        .filter(function (r) { return r.action === "extThumbs" })
    check("once shown it reads Hide", shown.map(function (r) { return r.label }).join(","), "Hide network thumbnails")
    var usb = Menu.listingEntries(menuState({ storageClass: "usb" })).filter(function (r) { return r.action === "extThumbs" })
    check("a USB drive at defaults reads Hide", usb.map(function (r) { return r.label }).join(","), "Hide USB thumbnails")
    var phone = Menu.listingEntries(menuState({ storageClass: "phone" })).filter(function (r) { return r.action === "extThumbs" })
    check("a phone at defaults reads Show", phone.map(function (r) { return r.label }).join(","), "Show phone thumbnails")
    check("the hidden switch takes it away like any other row",
          Menu.listingEntries(menuState({ storageClass: "network", hiddenActions: ["extThumbs"] })).filter(function (r) { return r.action === "extThumbs" }).length, 0)
    check("a file row never offers it", Menu.listingEntries(menuState({ hasRow: true, storageClass: "network", hiddenActions: [] }))
          .filter(function (r) { return r.action === "extThumbs" }).length, 0)
    check("the toggle says what it did", [ExtThumbs.statusLine("network", true), ExtThumbs.statusLine("usb", false), ExtThumbs.statusLine("phone", true)].join("|"),
          "Network thumbnails are on|USB thumbnails are off|Phone thumbnails are on")
    check("a cache-only miss leaves and a hit stays", (function () {
        var st = { file: { 3: "", 4: "/c/x.png" }, order: [3, 4] }
        ExtThumbs.forgetMisses(st)
        return st.order.join(",") + "|" + (st.file[3] === undefined) + "|" + st.file[4]
    })(), "4|true|/c/x.png")
    check("text on network and phone reads at most 256 KiB", [ExtThumbs.textLimit("network"), ExtThumbs.textLimit("phone")].join("|"), "262144|262144")
    check("local and USB keep the megabyte", [ExtThumbs.textLimit(""), ExtThumbs.textLimit("usb")].join("|"), "1048576|1048576")

    var preview = Settings.rows("preview", { data: {} })
    function find(rows, id) {
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].id === id) return rows[i]
        }
        return {}
    }
    check("the third cell reads Everything", find(preview, "preview.thumbnails").labels.join("|"), "Off|Images|Everything")
    check("Thumbnail size sits under Thumbnails and the three checks under it",
          preview.map(function (r) { return r.id || "" }).join("|").indexOf("preview.thumbnails|preview.thumbSize|preview.thumbNetwork|preview.thumbPhone|preview.thumbUsb") >= 0, true)
    check("the three class checks draw no glyph", [find(preview, "preview.thumbNetwork").glyph,
          find(preview, "preview.thumbPhone").glyph, find(preview, "preview.thumbUsb").glyph].join("|"), "||")
    check("network and phone ship off, USB on",
          [find(preview, "preview.thumbNetwork").on, find(preview, "preview.thumbPhone").on, find(preview, "preview.thumbUsb").on].join("|"),
          "false|false|true")
    check("a stored switch reads back",
          find(Settings.rows("preview", { data: { preview: { thumbNetwork: true, thumbUsb: false } } }), "preview.thumbNetwork").on
          + "|" + find(Settings.rows("preview", { data: { preview: { thumbNetwork: true, thumbUsb: false } } }), "preview.thumbUsb").on,
          "true|false")
    check("the hint is the board's own sentence",
          preview.filter(function (r) { return r.kind === "hint" }).map(function (r) { return r.label }).join("|"),
          "Automatic follows the cursor.|Off still shows thumbnails that were already made.")
    var off = Settings.rows("preview", { data: { preview: { thumbnails: "off", thumbNetwork: true, thumbUsb: true } } })
    check("Thumbnails Off greys the three and their hint",
          [find(off, "preview.thumbNetwork").available, find(off, "preview.thumbPhone").available,
           find(off, "preview.thumbUsb").available,
           off.filter(function (r) { return r.kind === "hint" && r.label.indexOf("already made") >= 0 })[0].available].join("|"),
          "false|false|false|false")
    check("a greyed check is no focus stop", Settings.focusable(find(off, "preview.thumbNetwork")), false)
    check("but it keeps its values", [find(off, "preview.thumbNetwork").on, find(off, "preview.thumbUsb").on].join("|"), "true|true")
    check("and grid zoom never greys", find(off, "preview.ctrlZoom").available === undefined, true)
}
