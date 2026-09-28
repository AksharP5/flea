.pragma library
.import "DirSizes.js" as DirSizes
.import "Format.js" as Format

// The strings an autofit measures, the same ones ui/Row.qml draws.
// Sample input: ("size", {p: 33188, d: false, s: 18000}) answers "18.0 kB".
var FIT_KEYS = ["mode", "size", "date", "kind"]

function cellText(key, row, kindNames, dirSize) {
    if (key === "mode")
        return Format.permissions(row.p)
    if (key === "size") {
        if (Format.isSymlink(row.p))
            return "link"
        if (!row.d)
            return Format.size(row.s)
        if (!dirSize)
            return "·"
        return (dirSize.partial ? ">" : "") + Format.size(dirSize.bytes)
    }
    if (key === "date")
        return row.m === null ? "--" : Format.date(row.m)
    var text = (kindNames || [])[row.k]
    return text !== undefined ? text : ""
}

// The held index behind one held row, for the dirsize the row would draw.
function dirSizeFor(state, held, at) {
    return DirSizes.sizeFor(state, held + at)
}
