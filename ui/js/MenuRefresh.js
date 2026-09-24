.pragma library

// What a provider refresh does to an open menu: the answers it draws, whether a rebuild changes anything, where the cursor lands.

// The provider inputs off ui/ContextMenu.qml's own properties; the peers are the service's, not gated by the row.
function live(menu) {
    return { refreshing: menu.providersRefreshing === true,
             taildropInstalled: menu.taildropInstalled === true, taildropPeers: menu.taildropPeers || [],
             dropboxInstalled: menu.dropboxInstalled === true, dropboxPath: menu.dropboxPath || "",
             localSendChecking: menu.localSend.checking === true, localSendAnswered: menu.localSend.answeredOnce === true }
}

// A finished refresh's answer, which the menu keeps drawing while the next refresh runs behind it.
function settle(answer) {
    return { taildrop: { installed: answer.taildropInstalled, peers: answer.taildropPeers },
             dropbox: { installed: answer.dropboxInstalled, path: answer.dropboxPath } }
}

// A kept answer for the same install state stands in while a refresh runs, e.g. now { refreshing: true, taildropPeers: [], dropboxPath: "", ... }.
function providerView(known, now) {
    var taildrop = now.refreshing && known && known.taildrop.installed === now.taildropInstalled ? known.taildrop : null
    var dropbox = now.refreshing && known && known.dropbox.installed === now.dropboxInstalled ? known.dropbox : null
    return { taildropPeers: taildrop ? taildrop.peers : now.taildropPeers,
             taildropRefreshing: now.refreshing && !taildrop,
             dropboxPath: dropbox ? dropbox.path : now.dropboxPath,
             dropboxRefreshing: now.refreshing && !dropbox,
             localSendChecking: now.localSendChecking && !now.localSendAnswered }
}

// Whether a rebuilt inventory is exactly what is drawn, so an answer that changed nothing resets no row.
function unchanged(previous, next) {
    return JSON.stringify(previous) === JSON.stringify(next)
}

// Preserve action and peer identity when refreshed capabilities change the inventory beneath the keyboard cursor.
function refreshedCursor(previous, next, cursor, submenuRow, submenuCursor) {
    var action = previous[cursor] ? previous[cursor].action : ""
    var selected = action ? next.findIndex(function(entry) { return entry.action === action }) : -1
    if (selected < 0) {
        selected = Math.min(Math.max(0, cursor), next.length - 1)
        while (selected < next.length && selected >= 0 && (next[selected].separator || next[selected].disabled)) selected++
        if (selected === next.length) {
            selected--
            while (selected >= 0 && (next[selected].separator || next[selected].disabled)) selected--
        }
    }
    var oldSubmenu = previous[submenuRow]
    var subRow = oldSubmenu ? next.findIndex(function(entry) { return entry.action === oldSubmenu.action }) : -1
    var sub = subRow >= 0 ? next[subRow] : null
    var oldTarget = oldSubmenu && oldSubmenu.submenu ? oldSubmenu.submenu[submenuCursor] : null
    var target = sub && !sub.disabled && oldTarget ? (sub.submenu || []).findIndex(function(entry) { return entry.id === oldTarget.id && !entry.disabled }) : -1
    return { cursor: selected, submenuRow: target >= 0 ? subRow : -1, submenuCursor: Math.max(0, target) }
}
