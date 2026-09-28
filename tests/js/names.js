.import "../../ui/js/Names.js" as Names

// Names040 board: a long name elides in the middle so the extension stays visible; the 64-character sample elides to 49 keeping ".png".
function run(check) {
    var full = "screenshot-2026-08-30-final-review-for-gm-after-the-bench-v3.png"
    check("the board sample elides to the board string",
          Names.middleElide(full, 49), "screenshot-2026-08-30-fi…m-after-the-bench-v3.png")
    check("the board sample keeps its extension",
          Names.middleElide(full, 49).slice(-4), ".png")
    check("a name shorter than the width is untouched",
          Names.middleElide("IMG_4121.jpg", 49), "IMG_4121.jpg")
    check("a name exactly at the width is untouched",
          Names.middleElide("1234567890", 10), "1234567890")
    check("a name without an extension still elides in the middle",
          Names.middleElide("a-very-long-filename-with-no-extension-at-all", 20),
          "a-very-lon…on-at-all")
    check("a dotfile shorter than the width keeps its full ink",
          Names.middleElide(".bashrc", 20), ".bashrc")
    check("a long dotfile keeps its leading dot",
          Names.middleElide(".a-very-long-hidden-config-name", 20)[0], ".")
    check("a long dotfile still elides in the middle",
          Names.middleElide(".a-very-long-hidden-config-name", 20),
          ".a-very-lo…nfig-name")
    check("an empty name stays empty",
          Names.middleElide("", 20), "")
    check("a multi-byte name never splits a surrogate pair",
          Names.middleElide("photo-📷-2026-08-30-final-review-v3.png", 20),
          "photo-📷-20…ew-v3.png")
    check("a tiny width keeps one character each side",
          Names.middleElide("abcdefghij", 3), "a…j")
    check("a two-wide budget keeps the head and the mark",
          Names.middleElide("abcdefghij", 2), "a…")
}
