.import "../../ui/js/Scripts.js" as Scripts
.import "../../ui/js/Menu.js" as Menu

// MenuAdditions rule 2: one row per executable in ~/.config/flea/scripts, sorted by name, the label
// the file name without its extension, absent rather than greyed when there are none.

function file(scripts, hidden) {
    return Menu.listingEntries({ hasRow: true, showHidden: false, selectionCount: 1, rowMode: 0o100644,
        archiveFormats: [], taildropPeers: [], scripts: scripts, hiddenActions: hidden || [] })
}

function row(entries, id) {
    for (var i = 0; i < entries.length; i++)
        if (entries[i].id === id) return entries[i]
    return null
}

function run(check) {
    var parsed = Scripts.parse("ocr.sh\nconvert-to-webp\nupload-to-s3.py\n", "/home/gm/.config/flea/scripts")
    check("the rows are sorted by name whatever order find printed",
          parsed.map(function (s) { return s.id }).join(","), "convert-to-webp,ocr.sh,upload-to-s3.py")
    check("and the label is the name without its extension",
          parsed.map(function (s) { return s.label }).join(","), "convert-to-webp,ocr,upload-to-s3")
    check("each row carries the path it will run", parsed[1].path, "/home/gm/.config/flea/scripts/ocr.sh")
    check("a blank listing is no rows at all", Scripts.parse("\n\n", "/x").length, 0)
    check("and a name that is only an extension keeps it, because that is the file's own name",
          Scripts.parse(".hidden\n", "/x")[0].label, ".hidden")

    check("a script's non-zero exit is reported by its own last stderr line",
          Scripts.failure("ocr.sh", "warming up\nno such page\n", 2), "ocr.sh · no such page")
    check("and one that said nothing is reported by its status",
          Scripts.failure("ocr.sh", "  \n", 3), "ocr.sh exited with status 3")

    var withScripts = file(parsed)
    check("the menu carries Run script after Copy path, with the scripts as its submenu",
          row(withScripts, "runScript").label + "|" + row(withScripts, "runScript").submenu.map(function (s) { return s.label }).join(","),
          "Run script|convert-to-webp,ocr,upload-to-s3")
    check("an empty scripts directory offers no row at all", row(file([]), "runScript"), null)
    check("and the Extras switch takes it away as well", row(file(parsed, ["runScript"]), "runScript"), null)
    check("the submenu's mark is the row's own", Menu.submenuGlyph("runScript"), "terminal")
}
