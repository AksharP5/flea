.pragma library

.import "Swap.js" as Swap
.import "Facts.js" as Facts

// The preview swap's decisions, see AGENTS.md "The preview swap"; ui/PreviewSwap.qml holds the picture and the timer.

// ui/PreviewPdf.qml opens a document only this long after its path settles (issue 117), so a PDF's cap starts after it.
var DOCUMENT_SETTLE_MS = 120

// A capture draws on the next frame; one not drawn in this long means the window is not drawing at all.
var CAPTURE_MS = 100

// How long the new preview may build under the held picture once its own work has started.
function capMs(isPdf) {
    return Swap.HOLD_MS + (isPdf === true ? DOCUMENT_SETTLE_MS : 0)
}

// What a move does to a swap: start a hold, join the one already starting for this key, or, when the
// host lets a burst end it, give up a picture that no longer names anything near the cursor.
var HOLD = "hold"
var JOIN = "join"
var BURST = "burst"

function onMove(state, key, burstEnds) {
    if (!state.capturing && !state.holding)
        return HOLD
    if (state.key === key || burstEnds !== true)
        return JOIN
    return BURST
}

// A frame drawn with the swap in each state: "held" shows the old picture, "mid" is the defect a hold
// exists to prevent, "loading" is the fallback's own state and allowed.
function frameKind(held, ready, fellBack) {
    if (held === true)
        return "held"
    if (ready === true)
        return ""
    return fellBack === true ? "loading" : "mid"
}

// Sample input: { state: "image", thumb: true, frame: 1, noThumbComing: false, pdfDrawn: false,
// pdfFailed: false, linesLoading: false, meta: true } for the preview column's cursor row, where frame is the
// thumbnail Image's status (Image.Null 0, Ready 1, Loading 2, Error 3).
function columnReady(p) {
    switch (p.state) {
    case Facts.LOADING:
        return false
    case Facts.IMAGE:
        // The cache file, or with none coming the original the frame decodes itself, drawn or refused.
        return (p.thumb === true || p.noThumbComing === true) && (p.frame === 1 || p.frame === 3)
    case Facts.VIDEO:
        // The poster drawn or refused, or none coming at all and the kind's mark standing in.
        return p.thumb === true ? p.frame === 1 || p.frame === 3 : p.noThumbComing === true
    case Facts.PDF:
        return p.pdfDrawn === true || p.pdfFailed === true
    case Facts.TEXT:
    case Facts.CODE:
        return p.linesLoading !== true
    case Facts.ARCHIVE:
        return p.meta === true
    }
    return true
}

// Quick Look's answer: nothing loading, and a PDF with a page on screen or refused.
function lookReady(status, isPdf, pdfShown, pdfFailed) {
    if (status === "loading")
        return false
    return isPdf !== true || pdfShown === true || pdfFailed === true
}
