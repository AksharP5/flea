.pragma library

.import "Sort.js" as Sort

// Written only on a user sort in that folder, read once per listing, oldest first.

// The cap ui.json holds, oldest first; setting past it drops the folders sorted longest ago.
var MAX = 500

// Settings stores Modified as "date" while Sort.ORDERS and the backend spell it "mtime".
function liveKey(key) {
    return key === "date" ? "mtime" : key
}

function get(sorts, path) {
    var entry = sorts ? sorts[path] : null
    if (!entry || Sort.ORDERS.indexOf(liveKey(entry.key)) < 0)
        return null
    return { key: liveKey(entry.key), reverse: entry.reverse === true }
}

function has(sorts, path) {
    return get(sorts, path) !== null
}

function count(sorts) {
    return sorts ? Object.keys(sorts).length : 0
}

// A re-sort moves its folder to the most recent end; past the cap the oldest entries go.
function set(sorts, path, key, reverse) {
    var next = {}
    if (sorts) {
        for (var k in sorts) {
            if (k !== path)
                next[k] = sorts[k]
        }
    }
    next[path] = { key: key, reverse: reverse === true }
    var keys = Object.keys(next)
    while (keys.length > MAX)
        delete next[keys.shift()]
    return next
}

function forget(sorts, path) {
    var next = {}
    if (sorts) {
        for (var k in sorts) {
            if (k !== path)
                next[k] = sorts[k]
        }
    }
    return next
}

// A user sort writes its folder only while remembering is on.
function shouldRemember(remember, path) {
    return remember !== false && !!path
}

// An unknown stored key reads as the default, so a newer Flea never wedges this one.
function orderFor(sorts, path, fallback, remember) {
    if (remember !== false) {
        var own = get(sorts, path)
        if (own)
            return own
    }
    fallback = fallback || {}
    var key = liveKey(fallback.key)
    return { key: Sort.ORDERS.indexOf(key) >= 0 ? key : "name",
             reverse: fallback.reverse === true }
}
