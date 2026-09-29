// A source slice between two markers, so a renamed or reordered function fails loudly.
// Sample input: slice("ab function f() {} function g() {}", "function f", "function g").
function slice(src, fromMarker, toMarker) {
    var text = String(src)
    var from = text.indexOf(fromMarker)
    if (from < 0)
        throw new Error("sourcefixture: missing marker " + fromMarker)
    if (toMarker === undefined)
        return text.substring(from)
    var end = text.indexOf(toMarker, from + fromMarker.length)
    if (end < 0 && text.indexOf(toMarker) >= 0)
        throw new Error("sourcefixture: out-of-order markers " + fromMarker + " before " + toMarker)
    if (end < 0)
        throw new Error("sourcefixture: missing marker " + toMarker)
    return text.substring(from, end)
}
// One file reader for every suite that greps this tree, so a renamed file fails loudly.
// Sample input: Source.source("ui/Backend.qml") answers that file's text.
function source(path) {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../../" + path), false)
    request.send()
    var body = String(request.responseText || "")
    if (body.length === 0)
        throw new Error("sourcefixture: cannot read " + path)
    return body
}
