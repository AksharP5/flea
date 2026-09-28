.import "../../ui/js/RecentDates.js" as RecentDates

// Highlight today's dates (Settings, View, ships off): on, today draws foreground and older stamps keep dimmed ink, with no relative words.

// A file of this tree, read the way tests/js/themes.js reads colors.toml; "" when missing.
function source(path) {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../../" + path), false)
    request.send()
    return String(request.responseText || "")
}

function countRe(text, re) {
    var found = text.match(re)
    return found ? found.length : 0
}

// The board date, 2026-09-23, built from local components so the suite reads the
// same boundary whatever timezone it runs in.
function at(y, mo, d, h, mi, s) {
    return new Date(y, mo - 1, d, h || 0, mi || 0, s || 0).getTime()
}

function run(check) {
    var noon = at(2026, 9, 23, 12, 0, 0)
    var start = RecentDates.dayStart(noon)
    check("today starts at local midnight", start, at(2026, 9, 23, 0, 0, 0))
    check("the start is the same all day",
        RecentDates.dayStart(at(2026, 9, 23, 23, 59, 59)), start)
    check("and the next day starts a day later",
        RecentDates.dayStart(at(2026, 9, 24, 0, 0, 0)) - start, 24 * 60 * 60 * 1000)
    // The boundary is the local wall clock and not UTC midnight: every stock timezone in this harness is off UTC.
    check("local midnight is not UTC midnight",
        start !== Date.UTC(2026, 8, 23, 0, 0, 0), true)
    // The one-second boundary each side of it.
    check("23:59:59 is yesterday",
        RecentDates.isRecent(true, at(2026, 9, 22, 23, 59, 59) / 1000, start), false)
    check("00:00:00 is today",
        RecentDates.isRecent(true, at(2026, 9, 23, 0, 0, 0) / 1000, start), true)
    check("midday is today",
        RecentDates.isRecent(true, at(2026, 9, 23, 12, 0, 0) / 1000, start), true)
    // One boundary and not a band: a future stamp counts as recent too.
    check("a future mtime counts as recent",
        RecentDates.isRecent(true, at(2026, 9, 24, 12, 0, 0) / 1000, start), true)
    // The switch off leaves every date dimmed, even one from today.
    check("the switch off leaves a today date dimmed",
        RecentDates.isRecent(false, at(2026, 9, 23, 12, 0, 0) / 1000, start), false)
    check("and an absent switch does too",
        RecentDates.isRecent(undefined, at(2026, 9, 23, 12, 0, 0) / 1000, start), false)
    // Rows without a real mtime never lift: ShareBrowser's share rows carry null.
    check("a null mtime is never recent", RecentDates.isRecent(true, null, start), false)
    check("a missing mtime is never recent", RecentDates.isRecent(true, undefined, start), false)
    check("the epoch is not recent", RecentDates.isRecent(true, 0, start), false)
    check("a non-number is never recent", RecentDates.isRecent(true, "noon", start), false)

    // The midnight timer's one-shot: the ms to the next local midnight, re-armed on firing.
    check("one second to midnight arms one second",
        RecentDates.msUntilMidnight(at(2026, 9, 23, 23, 59, 59)), 1000)
    check("midnight arms the full day",
        RecentDates.msUntilMidnight(at(2026, 9, 23, 0, 0, 0)), 24 * 60 * 60 * 1000)
    check("midday arms half a day",
        RecentDates.msUntilMidnight(at(2026, 9, 23, 12, 0, 0)), 12 * 60 * 60 * 1000)
    check("a minute past midnight the start is the new day",
        RecentDates.dayStart(at(2026, 9, 24, 0, 1, 0)), at(2026, 9, 24, 0, 0, 0))
    check("and re-arming there waits out the day",
        RecentDates.msUntilMidnight(at(2026, 9, 24, 0, 1, 0)), 24 * 60 * 60 * 1000 - 60000)

    // The wiring the window carries: one midnight timer for the whole window, one numeric compare per row, no per-row timer or Date.
    var rowDate = source("ui/RowDate.qml")
    var viewState = source("ui/ViewState.qml")
    var row = source("ui/Row.qml")
    check("RowDate compares against the window start",
        rowDate.indexOf("todayStart") >= 0, true)
    check("RowDate reads the switch", rowDate.indexOf("highlightToday") >= 0, true)
    check("Row hands the row's own mtime down", row.indexOf("mtime: root.row") >= 0, true)
    check("RowDate holds no timer of its own", countRe(rowDate, /Timer\s*\{/g), 0)
    check("RowDate builds no Date per row", countRe(rowDate, /new Date/g), 0)
    check("and reads no clock per row", rowDate.indexOf("Date.now") < 0, true)
    check("ViewState owns the one midnight timer", countRe(viewState, /Timer\s*\{/g), 1)
    check("and that timer steps in minute stops, so a suspend still lands the day",
        viewState.indexOf("Math.min(60000") >= 0, true)
    check("and the switch restarts it outright",
        viewState.indexOf("root.midnightTimer.running = root.highlightToday") >= 0, true)
    check("the timer re-arms through the same helper",
        viewState.indexOf("msUntilMidnight") >= 0, true)
    check("the switch ships off",
        viewState.indexOf("highlightToday === true") >= 0, true)
}
