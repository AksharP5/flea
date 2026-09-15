.pragma library

.import "Ops.js" as Ops

// MenuAdditions rule 1's two sentences, kept out of ui/PaneMenuActions.qml so the wording is tested
// rather than read off a screenshot. Flea knows the dispatch and nothing else: LocalSend's own
// window is where a transfer is accepted, refused or watched, the same as Taildrop's send.
function sentLine(paths) {
    if (paths.length === 1)
        return "Sending " + Ops.leaf(paths[0]) + " with LocalSend."
    return "Sending " + paths.length + " items with LocalSend."
}

// The row is absent without a binary, so this is the race between opening the menu and losing it.
function missing(provider) {
    return provider && provider.reason ? "LocalSend · " + provider.reason
                                       : "LocalSend is no longer installed."
}
