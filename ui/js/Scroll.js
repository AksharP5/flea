.pragma library

// The wheel's arithmetic, kept pure so tests/js/scroll.js can drive it without a Flickable.

// One discrete notch is 120 units of angleDelta, Qt's own convention for a wheel click.
var NOTCH_UNITS = 120
// Qt's own lines per notch when the platform reports none: the one fallback, so the handler passes the raw hint.
var DEFAULT_LINES = 3
// A scrollbar sits above a view's delegates and its FastScrollHandler (z 1000), so it takes its own presses.
var BAR_Z = 2000
// A dragged handle's MouseArea moves onto the window's content item, above everything that window draws.
var GRAB_Z = 1000000
// Less than half a pixel of range is rounding in the layout, not content worth a bar.
var OVERFLOW_PX = 0.5

// How far a wheel event moves the content: a touchpad's pixels one to one, like every other
// application, and a wheel notch as the platform's lines times notchPx times the multiplier.
// Sample input: pixelDeltaY 0, angleDeltaY -120, lines 3, notchPx 24, multiplier 4 gives -288.
function distance(pixelDeltaY, angleDeltaY, lines, notchPx, multiplier) {
    var pixels = Number(pixelDeltaY) || 0
    if (pixels !== 0)
        return pixels
    var perNotch = Number(lines) > 0 ? Number(lines) : DEFAULT_LINES
    return (Number(angleDeltaY) || 0) / NOTCH_UNITS * perNotch * notchPx * multiplier
}

// A content position kept inside the Flickable: never above its origin, never past its last page.
// A content shorter than the view pins to the origin.
function bounded(value, originY, contentHeight, viewHeight) {
    var minimum = Number(originY) || 0
    var maximum = Math.max(minimum, minimum + Math.max(0, Number(contentHeight) || 0) - Math.max(0, Number(viewHeight) || 0))
    return Math.max(minimum, Math.min(maximum, value))
}

// The lane every listing reserves at its right edge so rows never reflow under the bar.
// Sample input: lane(14) is 14, the board's own lane at base size 14.
function lane(rowPaddingX) {
    return Math.max(0, Number(rowPaddingX) || 0)
}

// The width a scrolling listing's content may use: the view less the lane it always keeps clear.
// Sample input: contentWidth(700, 14) is 686, a 700 px listing holding 686 px of rows.
function contentWidth(viewWidth, rowPaddingX) {
    return Math.max(0, (Number(viewWidth) || 0) - lane(rowPaddingX))
}

// Whether a wheel event is consumed: only when it actually moved the content, so an event at the
// edge keeps propagating to whatever holds this Flickable.
function moved(previous, current) {
    return Math.abs(current - previous) > 0.01
}

// Geometry over the Flickable's own range, never its delegates, so a 100,000-row model costs what a short one does.
function range(contentLength, viewportLength) {
    return Math.max(0, (Number(contentLength) || 0) - Math.max(0, Number(viewportLength) || 0))
}

function handleLength(trackLength, contentLength, viewportLength, minimumLength) {
    var track = Math.max(0, Number(trackLength) || 0)
    var content = Math.max(0, Number(contentLength) || 0)
    var viewport = Math.max(0, Number(viewportLength) || 0)
    if (track === 0 || content <= viewport || content === 0)
        return track
    return Math.min(track, Math.max(Math.max(0, Number(minimumLength) || 0), track * viewport / content))
}

// Finder's overlay scroller at base size 14 (the 0.3.3 design canvas): knob widths, its inset from the edge, in px.
var KNOB_REST_PX = 6
var KNOB_WIDE_PX = 10
var KNOB_INSET_PX = 2
// Alphas of the theme's foreground: the knob at rest, with the pointer in the lane, pressed; the track and its inner hairline.
var KNOB_ALPHA = 0.5
var KNOB_HOVER_ALPHA = 0.6
var KNOB_PRESSED_ALPHA = 0.7
var TRACK_ALPHA = 0.05
var TRACK_LINE_ALPHA = 0.12
// Finder's timing: shown this long after the view stops, then faded out over FADE_MS.
var HOLD_MS = 1000
var FADE_MS = 300

// Shown while the view moves, the pointer is in the lane or a press is down, and never over content that fits.
function revealed(overflow, moving, inLane, pressed) {
    return !!overflow && (!!moving || !!inLane || !!pressed)
}

// A track press puts the knob's centre under the pointer, Finder's jump to the spot clicked, clamped to the travel.
function jumpOffset(at, handleLengthValue, travelLength) {
    var room = Math.max(0, Number(travelLength) || 0)
    return Math.max(0, Math.min(room, (Number(at) || 0) - (Number(handleLengthValue) || 0) / 2))
}

// How far the handle can move; none on a track no longer than the minimum handle, where a drag moves nothing.
function travel(trackLength, contentLength, viewportLength, minimumLength) {
    return Math.max(0, (Number(trackLength) || 0) - handleLength(trackLength, contentLength, viewportLength, minimumLength))
}

function handleOffset(contentPosition, origin, contentLength, viewportLength, trackLength, minimumLength) {
    var room = travel(trackLength, contentLength, viewportLength, minimumLength)
    var span = range(contentLength, viewportLength)
    if (room === 0 || span === 0)
        return 0
    var at = Math.max(0, Math.min(span, (Number(contentPosition) || 0) - (Number(origin) || 0)))
    return room * at / span
}

function positionForHandle(handleOffsetValue, origin, contentLength, viewportLength, trackLength, minimumLength) {
    var room = travel(trackLength, contentLength, viewportLength, minimumLength)
    var span = range(contentLength, viewportLength)
    if (room === 0 || span === 0)
        return Number(origin) || 0
    var at = Math.max(0, Math.min(room, Number(handleOffsetValue) || 0))
    return (Number(origin) || 0) + span * at / room
}
