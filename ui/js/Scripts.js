.pragma library

// MenuAdditions rule 2's own reading: what find printed becomes the submenu's rows, sorted by name,
// each label the file name without its extension. Sample input, one name a line:
//   convert-to-webp
//   ocr.sh
function parse(text, directory) {
    var names = String(text || "").split("\n").filter(function (name) { return name.trim().length > 0 })
    names.sort()
    return names.map(function (name) {
        var trimmed = name.trim()
        var dot = trimmed.lastIndexOf(".")
        return { id: trimmed, label: dot > 0 ? trimmed.substring(0, dot) : trimmed, path: directory + "/" + trimmed }
    })
}

// The script's own report: its last stderr line, or the status it exited with when it said nothing.
function failure(name, stderr, code) {
    var lines = String(stderr || "").split("\n").filter(function (line) { return line.trim().length > 0 })
    return lines.length > 0 ? name + " · " + lines[lines.length - 1].trim() : name + " exited with status " + code
}
