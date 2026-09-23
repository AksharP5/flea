.pragma library

// The listing swap's decisions, see AGENTS.md "The listing swap"; ui/PaneSwap.qml holds the state and the timer.

// The loading mark's own hold-off, ui/LoadingState.qml: a listing slower than this shows the mark when it always did.
var HOLD_MS = 150

// Answered while a listing is out: the navigations refuse themselves, escape touches no row, the rest change the window.
var ANSWERED_WHILE_LISTING = ["open", "parent", "historyBack", "historyForward", "escape",
                              "viewList", "viewColumns", "viewGrid", "sidebar", "windowNew", "togglePreview"]

// What a swallowed key says, the sentence every refused navigation already gives.
var LOADING = "A directory is already loading."

// What a listed or rows line does: dropped, kept for the rows behind it, applied alone, or landed with the kept line.
var DROP = "drop"
var KEEP = "keep"
var APPLY = "apply"
var LAND = "land"

function idle() {
    return { holding: false, listed: null, fellBack: false, walk: false, query: "", since: 0 }
}

// Only a settled directory listing is held: a walk's matches or another view's rows would show half of each.
function begin(state, listingState, searchMode, ask, now) {
    var holding = ask.clearAtOnce !== true && listingState !== "loading" && searchMode === "" && state.walk !== true
    return { holding: holding, listed: null, fellBack: false, walk: state.walk, query: ask.keptQuery || "", since: now }
}

// While a list is out, only a listed line naming the directory asked for answers it; an earlier sort's or search's is dropped.
function onListed(state, inFlight, path, asked) {
    if (inFlight === true && path.length > 0 && path !== asked)
        return DROP
    return state.holding || state.fellBack ? KEEP : APPLY
}

// A rows line ahead of its listed line answers a listing already replaced; one behind a kept listed line lands with it.
function onRows(state, inFlight, listedSeen) {
    if (inFlight === true && listedSeen !== true)
        return DROP
    return state.listed !== null ? LAND : APPLY
}

function kept(state, listed) {
    return Object.assign({}, state, { listed: listed })
}

// Every listed line that is applied rather than kept says whether the rows it brings are a walk's.
function heard(state, walk) {
    return Object.assign({}, state, { walk: walk === true })
}

// A held listing is only ever a directory's, which is what begin() asked for.
function landed(state) {
    return Object.assign({}, state, { holding: false, listed: null, fellBack: false, walk: false })
}

// The cap ran out: the pane shows the loading state until the rows land, and a listed line already kept waits for them.
function expired(state) {
    return Object.assign({}, state, { holding: false, fellBack: true })
}

// A failed or refused listing ends the hold without a swap; the failure draws what it always did.
function dropped(state) {
    return Object.assign({}, state, { holding: false, listed: null, fellBack: false })
}

// The listing is no longer out, however it ended.
function ended(state) {
    return Object.assign({}, state, { holding: false, listed: null, fellBack: false })
}

// A stale refusal ended only its own request; any other failure ends the listing, letting held rows go while it is still out.
function failListing(pane, where) {
    if (where === "stale")
        return false
    pane.swap.drop()
    pane.listInFlight = false
    pane.listedSeen = false
    return true
}

// Sample input: {"c":"transfer","op":"move","rows":[3],"dest":"/home/gm/omarchy"} with held 7 gains "listing":7, unless it names one.
function named(request, held) {
    if (request.rows === undefined || request.listing !== undefined || !(held > 0))
        return request
    return Object.assign({}, request, { listing: held })
}

// A key swallowed while a listing is out, held or loading: the backend already numbers rows for the directory asked for.
function swallows(inFlight, action) {
    return inFlight === true && action.length > 0 && ANSWERED_WHILE_LISTING.indexOf(action) < 0
}

// A re-sort renumbers every row without a new list, so a selection made while it was in flight names other files once the new numbering lands.
function clearsSelection(oldHeld, listing) {
    return oldHeld > 0 && listing > 0 && listing !== oldHeld
}

// A frame drawn empty while a listing is out: "blank" before the cap is the defect, "loading" after it is allowed.
function frameKind(inFlight, listingState, fellBack) {
    if (inFlight !== true || listingState !== "loading") {
        return ""
    }
    return fellBack === true ? "loading" : "blank"
}
