.pragma library

.import "Menu.js" as Menu
.import "Errors.js" as Errors

// The Locked tile's own menu, issue 193 follow-up (GM, 2026-09-24). A right click on the
// tile names the locked folder itself, never the parent behind it, so only rows that act
// on that folder without listing it are offered: terminal, permissions and path. Kept in
// ui/js/Menu.js INVENTORY order, one group, so the menu never reorders under its caller.
var LOCKED_IDS = ["openTerminal", "permissions", "copypath"]

// Sample input: { lockedMode: 0o040700, hiddenActions: [] }
function lockedEntries(p) {
    var out = [], group = ""
    var scoped = { rowMode: p.lockedMode, selectionCount: 1, hiddenActions: p.hiddenActions }
    for (var i = 0; i < Menu.INVENTORY.length; i++) {
        var spec = Menu.INVENTORY[i]
        if (LOCKED_IDS.indexOf(spec[0]) < 0 || Menu.isHidden(p.hiddenActions, spec[0])) continue
        var entry = { id: spec[0], action: spec[5] || spec[0], label: spec[1], glyph: spec[2] }
        if (!Menu.availableEntry(entry, scoped, "F")) continue
        if (entry.action === "permissions") {
            var permission = lockedPermissions(p.lockedMode)
            entry.disabled = permission.disabled
            if (permission.errored) entry.errored = true
            else delete entry.errored
        }
        if (out.length && group !== spec[4]) out.push({ separator: true })
        group = spec[4]
        out.push(entry)
    }
    return out
}

// The mode is the locked directory's own, so ownership decides: a denial on owner-readable
// owner-executable proves somebody else owns it, and nobody but the owner can chmod it back,
// which reads red the way a provider that cannot answer does. An owner locked out too may
// still be the owner, so that row stays plain: it is the way back in.
function lockedPermissions(mode) {
    var kind = (Number(mode) || 0) & 0o170000
    if (kind !== 0o100000 && kind !== 0o040000) return { disabled: true, errored: true }
    if (Errors.notYours(mode)) return { disabled: true, errored: true }
    return { disabled: false }
}
