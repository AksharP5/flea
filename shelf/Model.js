.pragma library

// The pile as the bar reads it. Every function here is pure: the Service owns the file and this
// owns what its bytes mean, so a shape nobody has drawn yet can be tested without a shell at all.

// The shape the widget draws when nothing has been read, so no caller ever meets an undefined pile.
function empty() {
    return { items: [], count: 0, ok: false }
}

// Sample input: {"items":[{"path":"/home/gm/Work/a.txt","name":"a.txt","bytes":1024}]}
// A file that is missing, half written or not JSON at all answers the empty shape rather than
// throwing: the pile is written by another process and the bar has to survive reading it mid-write.
function parse(text) {
    var raw = String(text || "")
    if (raw.length === 0) {
        return empty()
    }
    var parsed
    try {
        parsed = JSON.parse(raw)
    } catch (e) {
        return empty()
    }
    if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.items)) {
        return empty()
    }
    var items = []
    for (var i = 0; i < parsed.items.length; i++) {
        var item = parsed.items[i]
        if (!item || typeof item.path !== "string" || item.path.length === 0) {
            continue
        }
        items.push({ path: item.path, name: leaf(item.path), bytes: bytesOf(item) })
    }
    return { items: items, count: items.length, ok: true }
}

// The row's own name, which is the path's last segment; a trailing slash names the folder before it.
function leaf(path) {
    var text = String(path)
    if (text.length > 1 && text.charAt(text.length - 1) === "/") {
        text = text.substring(0, text.length - 1)
    }
    var cut = text.lastIndexOf("/")
    return cut < 0 ? text : text.substring(cut + 1)
}

// A size the writer did not answer is not a zero, so it is carried as -1 and drawn as nothing.
function bytesOf(item) {
    var n = Number(item.bytes)
    return isFinite(n) && n >= 0 ? n : -1
}

// BarMark rule 3: the count is never in the bar itself, so this is what the hover tooltip says.
function tooltip(state) {
    if (!state || state.count === 0) {
        return "Flea shelf is empty"
    }
    return state.count === 1 ? "Flea shelf is holding 1 item" : "Flea shelf is holding " + state.count + " items"
}
