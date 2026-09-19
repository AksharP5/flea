.pragma library

// The pile file the bar plugin writes, read here for the Settings panel's Pinned list. Sample input:
// {"items":[{"path":"/home/gm/Invoices","name":"Invoices","folder":true,"pinned":true}]}
function pinned(text) {
    var doc = {}
    try {
        doc = JSON.parse(String(text || "")) || {}
    } catch (e) {
        return []
    }
    var items = doc.items instanceof Array ? doc.items : []
    var out = []
    for (var i = 0; i < items.length; i++) {
        if (items[i] && items[i].pinned === true && typeof items[i].path === "string") {
            out.push({ path: items[i].path, name: leaf(items[i].path),
                       folder: items[i].folder === true, missing: items[i].missing === true })
        }
    }
    return out
}

function leaf(path) {
    var trimmed = String(path).replace(/\/+$/, "")
    var at = trimmed.lastIndexOf("/")
    return at < 0 ? trimmed : trimmed.substring(at + 1)
}
