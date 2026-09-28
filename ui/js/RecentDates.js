.pragma library

// One window-level day boundary, so no Date is built and no timer ticks per row.

// Sample input: Date.now() on the board date, 2026-09-23 11:40 local.
var DAY_MS = 24 * 60 * 60 * 1000
// The midnight timer's minute step, so a suspend still lands the day within a minute of resume.
var MINUTE_MS = 60 * 1000

// Local midnight starting the day nowMs falls in, in ms since the epoch.
function dayStart(nowMs) {
    var now = new Date(nowMs)
    return new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
}

// One boundary, not a band: off reads dimmed and a future stamp counts.
function isRecent(highlight, mtimeSec, todayStartMs) {
    if (highlight !== true)
        return false
    if (typeof mtimeSec !== "number" || !isFinite(mtimeSec))
        return false
    return mtimeSec * 1000 >= todayStartMs
}

// Built from components, so a daylight-saving night still lands on midnight.
function msUntilMidnight(nowMs) {
    var now = new Date(nowMs)
    return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime() - nowMs
}
