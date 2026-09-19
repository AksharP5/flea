.pragma library

.import "Format.js" as Format

// The model behind ui/TransferCard.qml, kept out of the QML so every state the card can draw is
// checked without a window. The object each function takes is ui/js/Ops.js's transfer.

// The byte sample for the item in flight. done is the count already finished, so it stays where it
// was: a sample fills the item in, it does not complete it.
function sampled(t, index, name, bytes, total, scanned) {
    // A sample carrying none must not unset the total an earlier one already brought.
    var settled = scanned > 0 ? scanned : (t.scanned || 0)
    return Object.assign({}, t, {index: index, name: name, done: index, bytes: bytes, total: total, scanned: settled})
}

// That item's own terminal line: it counts whole from here, and its byte sample is spent. What it
// moved joins the running sum first, as the size the wire last named for it, or as the bytes it
// reported when it never had a total, which is what a directory's own running count is. An item
// that emitted no sample at all adds nothing, which undercounts a small file and never overcounts.
function itemDone(t, index, name) {
    var sampled = t.index === index ? (t.total > 0 ? t.total : t.bytes) : 0
    return Object.assign({}, t, {index: index, name: name, done: index + 1, bytes: 0, total: 0,
                                 moved: (t.moved || 0) + sampled})
}

// TransferCard rule 2: what the whole transfer has moved, the finished items plus the one in flight.
function movedBytes(t) {
    return (t.moved || 0) + (t.bytes || 0)
}

// TransferCard rule 1's line under the bar, as the pieces it is drawn from: a figure the card inks
// in the foreground, or the muted words between them.
function byteParts(t, rate) {
    var moved = movedBytes(t)
    if (moved <= 0) {
        return []
    }
    // t.total is the item in flight's, so it is the transfer's only when the transfer is that one
    // item. One directory is n === 1 with no total of its own, and the sweep is what answers for it.
    var total = t.n === 1 && t.total > 0 ? t.total : (t.scanned || 0)
    var parts = [figure(Format.size(moved))]
    if (total > 0) {
        parts.push(word(" of "), figure(Format.size(total)))
    } else {
        parts.push(word(t.moving ? " moved" : " copied"))
    }
    parts.push(word(" · "), figure(Format.size(rate) + "/s"))
    // Rule 3b: an estimate needs both a total and a rate, and a stall has neither to divide by.
    if (total > 0 && rate > 0) {
        // Clamped: the sweep and the copy count separately, so a file appended mid-copy can pass it.
        parts.push(word(" · "), figure(Format.duration(Math.max(0, total - moved) / rate * 1000)), word(" left"))
    }
    return parts
}

function figure(text) {
    return { text: text, figure: true }
}

function word(text) {
    return { text: text, figure: false }
}

// The card's headline, the count with no name in it: the card gives the name a row of its own, and
// ui/js/Ops.js builds the status bar's one-line form from this same string.
function head(t) {
    return (t.redo ? "Redoing " + t.redo + " " : t.moving ? "Moving " : "Copying ") + (t.index + 1) + " of " + t.n
}

// The card's second row: the item in flight and how big it is. total is 0 for a directory, whose
// size is not known in advance without a sweep, so that one names itself and claims nothing more:
// the running count it does have is the byte line's under the bar, and saying it twice is the thing
// this canvas exists to stop.
function fileLine(t) {
    if (t.name.length === 0) {
        return ""
    }
    return t.total > 0 ? t.name + " · " + Format.size(t.total) : t.name
}

// The bar is the whole transfer, never the one file: done carries the items already finished and
// the byte sample only fills in the one in flight. One large file is then its own byte bar, and
// thirty thousand small ones step it once each instead of restarting it thirty thousand times.
function fraction(t) {
    if (t.n <= 0) {
        return 0
    }
    var part = t.total > 0 ? t.bytes / t.total : 0
    var at = (t.done + part) / t.n
    return at < 0 ? 0 : (at > 1 ? 1 : at)
}
