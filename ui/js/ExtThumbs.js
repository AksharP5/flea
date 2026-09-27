.pragma library

// The ExtThumbs board's storage-class gate: network shares and phones are off, USB
// drives are on, and anything else is local and always gets thumbnails. A class is
// src/backend/extclass.rs's own word, carried beside the fsinfo line once per
// directory change, so nothing here classifies and there is no second classifier.

// Sample input: "network" answers "thumbNetwork", "" answers "".
function keyForClass(storageClass) {
    if (storageClass === "network") return "thumbNetwork"
    if (storageClass === "phone") return "thumbPhone"
    if (storageClass === "usb") return "thumbUsb"
    return ""
}

// The menu row is present only on network, phone or USB storage, never locally.
function present(storageClass) {
    return keyForClass(storageClass) !== ""
}

// Sample input: ("usb", {}) answers true, ("network", {}) answers false.
function classOn(storageClass, preview) {
    var key = keyForClass(storageClass)
    if (key === "") return true
    if (key === "thumbUsb") return !preview || preview.thumbUsb !== false
    return !!preview && preview[key] === true
}

function classOff(storageClass, preview) {
    return present(storageClass) && !classOn(storageClass, preview)
}

// Off is cache-only, not blank: a visible row still asks, and the backend answers from
// the shared cache with one stat and never starts a decoder. Thumbnails already made
// still show, because the cache answers them. Sample input: ("network", {}) answers true.
function cacheOnly(storageClass, preview) {
    if (!classOff(storageClass, preview)) return false
    return !preview || preview.thumbnails !== "off"
}

// In Columns the preview is manual on a class that is off: one condition, two surfaces.
function manualHold(storageClass, preview) {
    return cacheOnly(storageClass, preview)
}

// The menu row's own entrance: absent off the three classes, otherwise labelled for
// the class and its state. Sample input: ({storageClass: "usb"}) answers "Hide USB thumbnails".
function entry(e, p) {
    if (!present(p.storageClass)) return false
    e.label = label(p.storageClass, classOn(p.storageClass, p.thumbPreview))
    return true
}

// Sample input: ("network", false) answers "Show network thumbnails".
function label(storageClass, on) {
    var noun = storageClass === "usb" ? "USB" : storageClass
    return (on ? "Hide " : "Show ") + noun + " thumbnails"
}

// The status bar's own verdict for the toggle, in the board's words.
// Sample input: ("network", true) answers "Network thumbnails are on".
function statusLine(storageClass, on) {
    var noun = storageClass === "usb" ? "USB"
        : storageClass.charAt(0).toUpperCase() + storageClass.slice(1)
    return noun + " thumbnails are " + (on ? "on" : "off")
}

// A class switched on decodes again: its cache-only misses were final answers,
// so they leave the map and the settle re-asks the viewport. Sample input:
// {file: {3: "", 4: "/c/x.png"}, order: [3, 4]} forgets 3 and keeps 4.
function forgetMisses(state) {
    var kept = []
    for (var i = 0; i < state.order.length; i++) {
        var at = state.order[i]
        if (state.file[at] === "") delete state.file[at]
        else kept.push(at)
    }
    state.order = kept
    return { file: state.file, order: state.order }
}

// FileView reads the whole file, so a row over the gate is refused, not truncated, the
// same rule ui/PreviewText.qml already keeps. Text previews on network and phone storage
// read at most the first 256 KiB. Sample input: ("phone") answers 262144.
var TEXT_PREVIEW_MAX = 1048576
var REMOTE_TEXT_PREVIEW_MAX = 262144

function textLimit(storageClass) {
    if (storageClass === "network" || storageClass === "phone") return REMOTE_TEXT_PREVIEW_MAX
    return TEXT_PREVIEW_MAX
}
