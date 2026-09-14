.import "../../ui/js/Palette.js" as Palette
.import "../../ui/js/Contrast.js" as Contrast

// The stock themes installed under /usr/share/omarchy/themes, read live rather than fixtured, so a
// palette that changes under a theme update is caught here. tests/themes.sh compares this list with
// the directory itself, which is where a newly shipped theme reddens.
var THEMES = ["catppuccin", "catppuccin-latte", "ethereal", "everforest", "flexoki-light", "gruvbox",
              "hackerman", "kanagawa", "last-horizon", "lumon", "lupine", "matte-black", "miasma",
              "nord", "osaka-jade", "retro-82", "ristretto", "rose-pine", "solitude", "tokyo-night",
              "vantablack", "white"]
var THEME_DIR = "file:///usr/share/omarchy/themes/"

// Every threshold carries the rule it answers to; none of them is fitted to what the palettes do.
var TEXT_MIN = 4.5          // HANDOFF rule 2: body text on its own ground, WCAG AA.
var CAPTION_MIN = 3.0       // A muted caption is large-text AA against the ground it sits on.
var DISABLED_MIN = 1.5      // Containers: a disabled row still reads as a row, never as an empty one.
var WASH_MIN = 1.06         // A 14 percent wash has to be visible against the ground it washes.
var MARK_MIN = 3.0          // A drawn mark or frame is a graphical object, AA at 3:1.
var EDGE_MIN = 1.5          // The cursor's accent edge borders the unselected ground, see the KB.
var WASH = 0.14             // Theme.washActive, the one wash strength on every surface.
var SELECTED_FILL = 0.18    // Style.selectedFillAlpha, the OEM default a theme's shell.toml may raise.
var DISABLED = 0.55         // Theme.disabledOpacity.

// gvfs-free file read: qml6 allows it only with QML_XHR_ALLOW_FILE_READ, which tests/js.sh sets.
function read(url) {
    var request = new XMLHttpRequest()
    request.open("GET", url, false)
    request.send()
    return String(request.responseText || "")
}

// The roles Omarchy's own Commons/Color.qml derives from colors.toml, key for key, plus the ones
// ui/Theme.qml derives on top of them, lifts included. This file mirrors that derivation rather than
// importing it, because Theme.qml is a QML singleton; tests/themes.sh measures the real pixels, which
// is what catches the two drifting apart.
function roles(body) {
    var found = Palette.parse(body)
    var foreground = Palette.pick(found, ["foreground", "color7"], "#cacccc")
    var background = Palette.pick(found, ["background", "color0"], "#101315")
    var accent = Palette.pick(found, ["accent", "color4"], "#cacccc")
    var urgent = Palette.pick(found, ["red", "color1"], "#a55555")
    var surface = Palette.pick(found, Palette.SURFACE_KEYS, "#181825")
    return { foreground: foreground, background: background, accent: accent, urgent: urgent,
             // ui/Theme.qml's own rule, key for key: the palette's muted or a darkened foreground, lifted
             // to the caption floor on the ground it sits on.
             muted: Contrast.ensureRatio(Palette.pick(found, ["muted"], darker(foreground)), background, CAPTION_MIN),
             surface: surface,
             accentFrame: Contrast.ensureRatio(accent, surface, MARK_MIN),
             // ui/Theme.qml: a red with no chroma of its own reads as switched off, so it is dropped
             // for the foreground; every other red is lifted to AA the way symlink and executable are.
             error: saturation(urgent) > 0.2 ? Contrast.ensureRatio(urgent, background, TEXT_MIN) : foreground }
}

// Qt.darker(c, 1.4) in the value channel, which is ui/Theme.qml's fallback when a palette sets no
// muted of its own. Every stock palette does set one, so this is the path no installed theme takes.
function darker(hex) {
    var c = Contrast.parse(hex)
    var hi = Math.max(c[0], Math.max(c[1], c[2]))
    if (hi <= 0)
        return hex
    var scale = (hi / 1.4) / hi
    return Contrast.hexOf([c[0] * scale, c[1] * scale, c[2] * scale])
}

function saturation(hex) {
    var c = Contrast.parse(hex)
    var hi = Math.max(c[0], Math.max(c[1], c[2]))
    var lo = Math.min(c[0], Math.min(c[1], c[2]))
    return hi <= 0 ? 0 : (hi - lo) / hi
}

function washed(colour, alpha, ground) {
    return Contrast.hexOf(Contrast.over(colour, alpha, ground))
}

// No slack: ui/js/Contrast.js delivers the ratio it was asked for after rounding, so a lift that lands
// at 2.99 for a requested 3 is the defect this suite exists to catch rather than a tolerance to grant.
function atLeast(check, theme, rule, got, floor) {
    check(theme + ": " + rule + " is " + got.toFixed(2) + ", at least " + floor.toFixed(2),
          got >= floor ? "ok" : "under " + floor.toFixed(2) + " at " + got.toFixed(2), "ok")
}

function run(check) {
    for (var i = 0; i < THEMES.length; i++) {
        var name = THEMES[i]
        var body = read(THEME_DIR + name + "/colors.toml")
        check(name + ": colors.toml parses to a palette", Palette.isPalette(Palette.parse(body)), true)
        // A theme that did not read is one red check, not a throw that leaves the rest unmeasured.
        if (body.length === 0)
            continue
        var r = roles(body)

        // Text, on both grounds a listing row can sit on.
        atLeast(check, name, "foreground on background", Contrast.ratio(r.foreground, r.background), TEXT_MIN)
        atLeast(check, name, "foreground on surface", Contrast.ratio(r.foreground, r.surface), TEXT_MIN)
        atLeast(check, name, "muted caption on background", Contrast.ratio(r.muted, r.background), CAPTION_MIN)

        // Disabled is muted at 0.55 on the ground: still legible, and visibly weaker than muted.
        var disabled = washed(r.muted, DISABLED, r.background)
        atLeast(check, name, "disabled on background", Contrast.ratio(disabled, r.background), DISABLED_MIN)
        check(name + ": disabled reads below muted",
              Contrast.ratio(disabled, r.background) < Contrast.ratio(r.muted, r.background), true)

        // The one wash, on both of its grounds, and the search match run drawn with the same recipe.
        atLeast(check, name, "accent wash clears background", Contrast.ratio(washed(r.accent, WASH, r.background), r.background), WASH_MIN)
        atLeast(check, name, "accent wash clears surface", Contrast.ratio(washed(r.accent, WASH, r.surface), r.surface), WASH_MIN)
        atLeast(check, name, "a matched run still reads on its wash",
                Contrast.ratio(r.foreground, washed(r.accent, WASH, r.background)), TEXT_MIN)

        // The checkbox draws in the two roles above and nothing of its own: a foreground fill with the
        // ground cut out for its tick, and the muted frame when empty. tests/themes.sh measures the
        // fill's own pixel, which is where a checkbox that stopped using them would show.

        // The error role, on the ground, and beside the caption it must never read as the quieter of.
        // Two inks compared to each other would measure the two floors above rather than the palette,
        // and a theme with an unusually bright muted, ethereal's is 4.90, would fail for being good at
        // captions; what an error must never be is dimmer than one.
        atLeast(check, name, "error on background", Contrast.ratio(r.error, r.background), TEXT_MIN)
        atLeast(check, name, "error is never dimmer than a caption",
                Contrast.ratio(r.error, r.background), Contrast.ratio(r.muted, r.background))

        // The cursor's edge borders the unselected ground, which is what a low-chroma theme breaks.
        atLeast(check, name, "cursor edge on the unselected ground", Contrast.ratio(r.accent, r.background), EDGE_MIN)
        atLeast(check, name, "cursor edge against the selected fill",
                Contrast.ratio(r.accent, washed(r.accent, SELECTED_FILL, r.background)), EDGE_MIN)

        // The primary button carries its identity in a frame, on the card's own surface.
        atLeast(check, name, "primary frame on surface", Contrast.ratio(r.accentFrame, r.surface), MARK_MIN)
    }
}
