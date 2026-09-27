.pragma library

// Highlight today's dates: the local-day boundary the date column compares
// against, and the one-shot interval that moves it at midnight. A row compares
// its own stamp against one window-level number, so no Date is built per row
// and no timer ticks per row.

// Sample input: Date.now() on the board date, 2026-09-23 11:40 local.
var DAY_MS = 24 * 60 * 60 * 1000

// Local midnight starting the day nowMs falls in, in ms since the epoch.
function dayStart(nowMs) {
    var now = new Date(nowMs)
    return new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
}

// Whether one backend mtime in seconds (row.m) draws in the foreground role.
// Off reads dimmed whatever the stamp is; a future stamp counts, because the
// rule is one boundary and not a band.
function isRecent(highlight, mtimeSec, todayStartMs) {
    if (highlight !== true)
        return false
    if (typeof mtimeSec !== "number" || !isFinite(mtimeSec))
        return false
    return mtimeSec * 1000 >= todayStartMs
}

// Ms from nowMs to the next local midnight, the one-shot the window arms and
// re-arms on firing. Built from components rather than one DAY_MS step, so a
// daylight-saving night arms 23 or 25 hours and still lands on midnight.
function msUntilMidnight(nowMs) {
    var now = new Date(nowMs)
    return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime() - nowMs
}
