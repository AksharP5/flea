.import "../../ui/js/Scroll.js" as Scroll
.import "sourcefixture.js" as Source

// The wheel arithmetic behind ui/FastScrollHandler.qml: notch distance, write bounds, and when an event counts as consumed.
function run(check) {
    // A notch: 120 units, the platform's lines, the pixels a line is worth, and the multiplier.
    check("one notch down moves lines times notch pixels times the multiplier",
          Scroll.distance(0, -120, 3, 24, 4), -288)
    check("one notch up moves the same distance the other way", Scroll.distance(0, 120, 3, 24, 4), 288)
    check("two notches move twice", Scroll.distance(0, -240, 3, 24, 4), -576)
    // The one fallback: the handler passes the platform's hint raw, and no lines means Qt's own three.
    check("a platform that reports no lines moves Qt's three", Scroll.distance(0, -120, 0, 24, 4), -288)
    check("and so does one that reports a negative count", Scroll.distance(0, -120, -1, 24, 4), -288)
    // A touchpad hands pixels, which win over any angle that rides along and move one to one.
    check("a pixel delta moves one to one, no multiplier", Scroll.distance(-10, -120, 3, 24, 4), -10)
    check("a fractional pixel delta keeps its fraction", Scroll.distance(-2.5, 0, 3, 24, 4), -2.5)
    check("no delta at all moves nothing", Scroll.distance(0, 0, 3, 24, 4), 0)
    check("garbage reads as no movement", Scroll.distance("x", undefined, 3, 24, 4), 0)

    // Bounds: the origin and the last page, and a short content pinned to the origin.
    check("a write above the origin lands on it", Scroll.bounded(-50, 0, 1000, 400), 0)
    check("a write past the end lands on the last page", Scroll.bounded(5000, 0, 1000, 400), 600)
    check("a write inside stays where it was asked", Scroll.bounded(250, 0, 1000, 400), 250)
    check("a content shorter than the view pins to the origin", Scroll.bounded(100, 0, 300, 400), 0)
    check("an origin below zero is honoured", Scroll.bounded(-100, -20, 1000, 400), -20)
    check("an unknown content height reads as empty", Scroll.bounded(100, 0, undefined, 400), 0)

    // Consumed only when the content moved, so an event at an edge keeps propagating.
    check("a moved content consumes the event", Scroll.moved(100, 388), true)
    check("a content that did not move does not", Scroll.moved(600, 600), false)
    check("a sub-pixel jitter does not count as movement", Scroll.moved(600, 600.005), false)

    // A scrollbar describes the viewport, so a scale listing keeps the 24 px minimum handle everywhere travel is measured.
    check("fitting content has no scroll range", Scroll.range(400, 400), 0)
    check("a listing shorter than the viewport has no range either", Scroll.range(1, 400), 0)
    check("overflow is the content left below one viewport", Scroll.range(1000, 400), 600)
    check("a proportional handle names the visible fraction", Scroll.handleLength(500, 1000, 400, 24), 200)
    check("the handle travels the track less itself", Scroll.travel(500, 1000, 400, 24), 300)
    check("a track no longer than the minimum handle leaves it no travel", Scroll.travel(20, 1000, 400, 24), 0)
    check("and with no travel the map answers the origin, which the bar never asks for", Scroll.positionForHandle(10, -20, 1000, 400, 20, 24), -20)

    // Finder's reveal: nothing over content that fits, and any one of moving, pointer in the lane or a press shows it.
    check("a scroller over content that fits never shows", Scroll.revealed(false, true, true, true), false)
    check("at rest it hides", Scroll.revealed(true, false, false, false), false)
    check("the view moving shows it", Scroll.revealed(true, true, false, false), true)
    check("the pointer in the lane shows it and keeps it", Scroll.revealed(true, false, true, false), true)
    check("a press down keeps it", Scroll.revealed(true, false, false, true), true)
    // A track press centres the knob on the pointer, clamped to the travel at both ends.
    check("a press mid-track centres the knob there", Scroll.jumpOffset(250, 100, 400), 200)
    check("a press near the top clamps to the top", Scroll.jumpOffset(20, 100, 400), 0)
    check("a press near the bottom clamps to the last page", Scroll.jumpOffset(495, 100, 400), 400)
    check("with no travel the knob stays put", Scroll.jumpOffset(250, 100, 0), 0)
    check("a scale listing keeps a usable minimum handle", Scroll.handleLength(500, 3700000, 500, 24), 24)
    check("the top maps to the top of the track", Scroll.handleOffset(0, 0, 1000, 400, 500, 24), 0)
    check("the last page maps to the end of the track", Scroll.handleOffset(600, 0, 1000, 400, 500, 24), 300)
    // Mid-track, so a mapping that kept the origin would land 10 px off rather than on the same clamp.
    check("a non-zero origin is removed before mapping", Scroll.handleOffset(280, -20, 1000, 400, 500, 24), 150)
    check("a position above the origin maps to the top of the track", Scroll.handleOffset(-100, 0, 1000, 400, 500, 24), 0)
    check("a position past the last page maps to the end of the track", Scroll.handleOffset(900, 0, 1000, 400, 500, 24), 300)
    check("dragging the handle to the middle maps to the middle page",
          Scroll.positionForHandle(150, 0, 1000, 400, 500, 24), 300)
    check("dragging beyond the track clamps to the last page",
          Scroll.positionForHandle(900, 0, 1000, 400, 500, 24), 600)
    check("dragging above the track clamps to the origin",
          Scroll.positionForHandle(-50, -20, 1000, 400, 500, 24), -20)
    // A scale listing (content 100000, viewport 400, track 400) clamps its 1.6 px handle to 24, so travel is 376, not 398.4.
    check("a clamped handle starts at the top of the track", Scroll.handleOffset(0, 0, 100000, 400, 400, 24), 0)
    check("a clamped handle maps the middle page to the middle of the track", Scroll.handleOffset(49800, 0, 100000, 400, 400, 24), 188)
    check("a clamped handle maps the last page to the end of the track", Scroll.handleOffset(99600, 0, 100000, 400, 400, 24), 376)
    check("a clamped handle maps the middle of the track to the middle page", Scroll.positionForHandle(188, 0, 100000, 400, 400, 24), 49800)
    check("a clamped handle clamps a drag past the track to the last page", Scroll.positionForHandle(900, 0, 100000, 400, 400, 24), 99600)
    check("a clamped handle removes a non-zero origin before mapping", Scroll.handleOffset(49900, 100, 100000, 400, 400, 24), 188)
    check("a clamped handle adds the origin back to a dragged position", Scroll.positionForHandle(188, 100, 100000, 400, 400, 24), 49900)

    // The lane stays reserved, so rows never reflow under the bar.
    check("the lane is the row padding itself", Scroll.lane(14), 14)
    check("the lane scales with text size", Scroll.lane(16), 16)
    check("no padding leaves no lane", Scroll.lane(0), 0)
    check("garbage leaves no lane", Scroll.lane("x"), 0)
    // The width content may use: the view less the lane it always keeps clear.
    // Sample input: contentWidth(700, 14) is 686, a 700 px listing holding 686 px of rows.
    check("content ends one lane short of the view", Scroll.contentWidth(700, 14), 686)
    check("content fills a view with no padding", Scroll.contentWidth(700, 0), 700)
    check("a view narrower than its lane holds nothing", Scroll.contentWidth(9, 14), 0)
    check("garbage holds nothing", Scroll.contentWidth("x", "y"), 0)

    // The thumb follows Hyprland rounding: square at 0, clamped at half the thinner side.
    check("square corners stay square", Scroll.knobRadius(0, 6, 100), 0)
    check("rounding clamps at half the thinner side", Scroll.knobRadius(8, 6, 100), 3)
    check("a rounding past half the knob clamps to the knob's own half", Scroll.knobRadius(8, 10, 100), 5)
    check("a rounding below the clamp holds as it is", Scroll.knobRadius(3, 10, 100), 3)
    check("garbage rounding stays square", Scroll.knobRadius("x", 6, 100), 0)
    // GM 2026-09-29: no line or border along the lane in any state, only the space itself.
    check("the bar binds its thumb to Hyprland rounding",
          Source.source("ui/ViewportScrollBar.qml").indexOf("Scroll.knobRadius(Style.cornerRadius, width, height)") >= 0, true)
    check("no track-line constant survives in Scroll.js",
          Source.source("ui/js/Scroll.js").indexOf("TRACK_LINE"), -1)
    check("no track-line reader survives in the bar",
          Source.source("ui/ViewportScrollBar.qml").indexOf("TRACK_LINE"), -1)
    check("no hairline element survives in the bar",
          Source.source("ui/ViewportScrollBar.qml").indexOf("hairline"), -1)
}
