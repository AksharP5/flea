.pragma library

// Sample input: primaryFor("collide") === "keep", isDestructive("trash", "delete") === true.
// Variant A (Buttons040, GM 2026-09-24): one control for every dialog, card and
// picker button. Geometry mirrors Theme (HEIGHT is rowHeight less one rowPaddingY,
// so 30 at base 14); the fixed primary is the safe or asked-for action Enter takes.

var HEIGHT = 30
var PAD = 9
var GAP = 9
var RING = 2
var DISABLED_OPACITY = 0.55
var WASH_HOVER = 0.08
var WASH_PRESS = 0.14

// One label size for every button: the body Theme sizes from the text stop, so buttons grow with the rows beside them.
function labelSizeFor(body) {
    var n = Math.round(Number(body))
    return n > 0 ? n : LABEL_SIZE
}

// One primary per dialog, fixed: it never moves with focus.
var PRIMARY = {
    trash: "cancel",
    collide: "keep",
    openWith: "open",
    convert: "convert",
    newFile: "create",
    moveTo: "move",
    copyTo: "copy",
    network: "action",
    permissions: "apply",
    picker: "accept"
}

// A destructive action rests as the error label in a muted frame, never primary.
var DESTRUCTIVE = {
    trash: { "delete": true },
    collide: { "replace": true },
    picker: { "replace": true }
}

function primaryFor(dialog) {
    return PRIMARY[dialog] || ""
}

function isDestructive(dialog, name) {
    var set = DESTRUCTIVE[dialog] || {}
    return set[name] === true
}
