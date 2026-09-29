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
