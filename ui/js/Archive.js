.pragma library

// Which rows get an Extract, and what a new archive is called. The backend never sends an is-archive
// flag: the client is given the icon name and never the MIME type, so this is the whole mechanism.

// Longest form first, so ".tar.gz" is matched before ".gz" could be. Flea reads rar and cannot write
// one, so .rar is here, where Extract is decided, and never in the compress submenu, which is the
// table src/backend/archive.rs probed.
var EXTENSIONS = [".tar.zst", ".tar.bz2", ".tar.gz", ".tar.xz", ".tgz", ".tar", ".zip", ".7z", ".rar"]

function isArchive(name) {
    var lower = String(name).toLowerCase()
    for (var i = 0; i < EXTENSIONS.length; i++) {
        if (lower.length > EXTENSIONS[i].length && lower.indexOf(EXTENSIONS[i], lower.length - EXTENSIONS[i].length) !== -1) {
            return true
        }
    }
    return false
}

// The name an extract unpacks into: the archive's own, with every archive extension taken off.
function extractDir(name) {
    var text = String(name)
    var lower = text.toLowerCase()
    for (var i = 0; i < EXTENSIONS.length; i++) {
        if (lower.length > EXTENSIONS[i].length && lower.indexOf(EXTENSIONS[i], lower.length - EXTENSIONS[i].length) !== -1) {
            return text.substring(0, text.length - EXTENSIONS[i].length)
        }
    }
    return text
}

// One row compresses under its own name; several compress under the directory holding them.
function archiveStem(names, parentLeaf) {
    if (names.length === 1) {
        return stripExtension(names[0])
    }
    return parentLeaf.length > 0 ? parentLeaf : "archive"
}

function stripExtension(name) {
    var text = String(name)
    var cut = text.lastIndexOf(".")
    return cut > 0 ? text.substring(0, cut) : text
}

// The compress submenu is exactly the table the backend probed, never a fixed list, so a box with
// no 7zip installed simply never offers .7z.
function formatEntries(formats) {
    var out = []
    for (var i = 0; i < formats.length; i++) {
        out.push({ id: formats[i], label: "." + formats[i] })
    }
    return out
}

// Whether an installed tool reads this archive: .7z needs 7z, .zip/.rar either tool, tar bsdtar.
function canExtract(name, extraction) {
    var lower = String(name).toLowerCase()
    var caps = extraction || ({})
    if (hasSuffix(lower, ".7z")) return caps.sevenZip === true
    if (hasSuffix(lower, ".zip") || hasSuffix(lower, ".rar")) return caps.zip === true
    return caps.archive === true
}

// The missing program for a disabled Extract: only bsdtar offers "tar" and only 7z offers "7z".
function extractHint(formats) {
    var table = formats || []
    if (table.indexOf("7z") >= 0) return "bsdtar is not installed"
    if (table.indexOf("tar") >= 0) return "7-Zip is not installed"
    return "No archive tool is installed"
}

// Ui/js/Menu.js's Extract row: absent for none, disabled with its reason for no reader.
function extractEntry(entry, p, count) {
    if (!p.rowIsArchive || count !== 1) return false
    if (p.canExtract !== true) {
        entry.disabled = true
        entry.hint = extractHint(p.archiveFormats)
        entry.hintWrap = true
    }
    return true
}

function hasSuffix(lower, suffix) {
    return lower.length >= suffix.length && lower.indexOf(suffix, lower.length - suffix.length) !== -1
}
