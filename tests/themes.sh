#!/usr/bin/env bash
# The render sweep half of the theme battery: the candidate launched once per stock theme, with the
# surfaces the colour rules govern shot and measured. tests/js/themes.js asserts the rules over the
# palettes; this asserts that the roles the window really carries still satisfy them, which is what
# catches ui/Theme.qml and that suite drifting apart, and it leaves one PNG per theme per surface.
set -u
set -o pipefail
# Hard rule 9's own guard owns every create and delete here, the way tests/mount-listing.sh does it:
# a fixture lives outside $HOME and carries a marker, and nothing unmarked is ever removed.
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
repo=$PWD
themes_dir=${THEMES_DIR:-/usr/share/omarchy/themes}
flea_ui="$repo/ui"
flea_bin=${FLEA_BIN:-$repo/target/debug/flea}
class=com.thisisgm.flea
failures=0
# The same floors tests/js/themes.js names, and the same rules behind them.
text_min=4.5      # body text on its own ground, WCAG AA
caption_min=3     # a muted caption, large-text AA
mark_min=3        # a drawn mark or frame is a graphical object, AA at 3:1
role_steps=4      # how far a screenshot's round trip may move a role, measured over all 22 themes

command -v omarchy-drive >/dev/null || { echo "themes.sh: omarchy-drive is not installed"; exit 1; }
command -v magick >/dev/null || { echo "themes.sh: magick is not installed, and the pixel reads need it"; exit 1; }
[ -x "$flea_bin" ] || { echo "themes.sh: no candidate at $flea_bin"; exit 1; }
eval "$(omarchy-drive env)"

# The pure suite pins the same list; a theme shipped since then reddens here rather than being skipped.
# Sample input, the block this reads out of tests/js/themes.js:
#   var THEMES = ["catppuccin", "catppuccin-latte", "ethereal",
#                 "everforest", ...]
installed=$(ls -1 "$themes_dir" | sort | tr '\n' ' ')
pinned=$(sed -n '/^var THEMES = \[/,/\]$/p' tests/js/themes.js | grep -o '"[a-z0-9-]*"' | tr -d '"' | sort | tr '\n' ' ')
if [ "$installed" != "$pinned" ]; then
    printf 'FAIL the installed themes are not the ones tests/js/themes.js pins\n  installed: %s\n  pinned:    %s\n' "$installed" "$pinned"
    failures=$((failures + 1))
fi

sandbox="$FIXTURE_ROOT/flea-themes-$$"
sandbox_make "$sandbox"
# The PNGs outlive the run as its record, so they take one path the next run replaces rather than a
# fresh mktemp nobody ever removes.
shots="$FIXTURE_ROOT/flea-themeshots"
sandbox_make "$shots"
# Only what this run launched: the candidate is started with setsid, so its own process group holds
# it and the qs it spawns, and nothing the operator started is signalled.
launched=""
stop() {
    [ -n "$launched" ] && kill -TERM -- "-$launched" 2>/dev/null
    launched=""
    sleep 1
}
cleanup() {
    stop
    sandbox_remove "$sandbox"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$sandbox/files" "$sandbox/state/flea" "$sandbox/config"
printf 'one\n' > "$sandbox/files/alpha.txt"
printf 'two\n' > "$sandbox/files/beta.txt"
printf 'three\n' > "$sandbox/files/gamma-needle.txt"
printf '{"view":"list","places":{"driveSize":true,"trashCount":true}}\n' > "$sandbox/state/flea/ui.json"

ipc() { omarchy-drive ipc -p "$flea_ui" flea "$@"; }
key() { omarchy-drive key "$@" >/dev/null; }
window_xy() { hyprctl clients -j | jq -r --arg c "$class" '[.[]|select(.class==$c)][0] | "\(.at[0]) \(.at[1])"'; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }

# WCAG 2.1 relative luminance, the same arithmetic ui/js/Contrast.js does, so a rule can be asserted
# on the colours the running window reports rather than on a screenshot somebody looked at.
ratio() {
python3 - "$1" "$2" <<'PY'
import sys
def channel(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def luminance(hex_colour):
    h = hex_colour.lstrip('#')
    h = h[2:] if len(h) == 8 else h
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
a, b = luminance(sys.argv[1]), luminance(sys.argv[2])
print(round((max(a, b) + 0.05) / (min(a, b) + 0.05), 3))
PY
}
at_least() {
    local theme="$1" rule="$2" got="$3" floor="$4"
    awk -v g="$got" -v f="$floor" 'BEGIN { exit !(g >= f) }' \
        || fail "$theme: $rule is $got, under $floor"
}
# The first of these keys colors.toml sets, as "#rrggbb". Sample input, one line of the file:
#   background = "#1e1e2e"   # the canvas
colour_for() {
    local file="$1" key line hex
    shift
    for key in "$@"; do
        line=$(grep -m1 -E "^$key[[:space:]]*=" "$file")
        hex=$(printf '%s\n' "$line" | grep -o '#[0-9A-Fa-f]\{6\}' | tr 'A-F' 'a-f')
        if [ -n "$hex" ]; then
            printf '%s' "$hex"
            return
        fi
    done
}
# One pixel of a shot, as "#rrggbb": a fill and a frame are solid, so a pixel is the colour itself.
pixel_at() {
    magick "$1" -format "%[hex:p{$2,$3}]" info: | tr 'A-F' 'a-f' | cut -c1-6
}
# A screenshot is not bit exact: measured over all 22 themes the compositor's own round trip moves a
# role by up to three steps a channel, so a role matches within role_steps and never by string.
same_colour() {
    local theme="$1" rule="$2" got="${3#\#}" want="$4" near
    near=$(python3 -c '
import sys
def channels(value):
    h = value.lstrip("#")
    h = h[2:] if len(h) == 8 else h
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]
got, want, steps = channels(sys.argv[1]), channels(sys.argv[2]), int(sys.argv[3])
print("near" if all(abs(a - b) <= steps for a, b in zip(got, want)) else "off")
' "$got" "$want" "$role_steps")
    [ "$near" = "near" ] || fail "$theme: $rule draws #$got, not $want"
}

for colours in "$themes_dir"/*/colors.toml; do
    theme=$(basename "$(dirname "$colours")")
    # One theme at a time while a rule is being written; the battery runs them all.
    [ -n "${THEMES_ONLY:-}" ] && [ "$theme" != "${THEMES_ONLY}" ] && continue
    home="$sandbox/home"
    sandbox_scratch "$home"
    mkdir -p "$home/.local/state/omarchy/current/theme" "$home/.config/omarchy"
    cp "$colours" "$home/.local/state/omarchy/current/theme/colors.toml"
    [ -f "$(dirname "$colours")/shell.toml" ] && cp "$(dirname "$colours")/shell.toml" "$home/.local/state/omarchy/current/theme/"
    printf '%s\n' "$theme" > "$home/.local/state/omarchy/current/theme.name"
    [ -f "$HOME/.config/omarchy/shell.toml" ] && cp "$HOME/.config/omarchy/shell.toml" "$home/.config/omarchy/"

    stop
    real_home=$HOME
    export HOME="$home"
    FLEA_UI="$flea_ui" FLEA_BIN="$flea_bin" XDG_STATE_HOME="$sandbox/state" XDG_CONFIG_HOME="$sandbox/config" \
        setsid nohup "$flea_bin" --gui "$sandbox/files" >"$sandbox/flea-$theme.log" 2>&1 </dev/null &
    launched=$!
    export HOME="$real_home"
    if ! omarchy-drive wait window "$class" --timeout 20 >/dev/null; then
        fail "$theme: the candidate never opened a window"
        continue
    fi
    omarchy-drive focus "$class" >/dev/null
    sleep 3
    [ "$(ipc themeLoaded)" = "true" ] || fail "$theme: the window did not load a palette"
    read -r bg surface fg muted accent error symlink executable accentframe <<< "$(ipc palette)"
    case "$bg$fg$muted$accent$accentframe" in *"#"*) ;; *) fail "$theme: the window reports no palette"; continue ;; esac
    case "$accentframe" in "#"*) ;; *) fail "$theme: the window reports no accentFrame field"; continue ;; esac
    # The keys Commons/Color.qml maps, first match wins, each anchored to its own key so background_dim
    # cannot answer for background. Sample input, one line of colors.toml: background = "#1e1e2e"
    want_bg=$(colour_for "$colours" background color0)
    want_fg=$(colour_for "$colours" foreground color7)
    want_muted=$(colour_for "$colours" muted)
    # An unreadable file is the sweep losing its binding, so it reddens rather than skipping quietly.
    [ -n "$want_bg" ] && [ -n "$want_fg" ] \
        || fail "$theme: colors.toml names no background or foreground this sweep can bind to"
    [ -z "$want_bg" ] || [ "$want_bg" = "$bg" ] \
        || fail "$theme: the window is on $bg, not this theme's own $want_bg"
    [ -z "$want_fg" ] || [ "$want_fg" = "$fg" ] \
        || fail "$theme: the window draws $fg, not this theme's own $want_fg"

    # The rules, on the roles the running window carries rather than on the file it read.
    at_least "$theme" "foreground on background" "$(ratio "$fg" "$bg")" "$text_min"
    at_least "$theme" "foreground on surface" "$(ratio "$fg" "$surface")" "$text_min"
    at_least "$theme" "muted caption on background" "$(ratio "$muted" "$bg")" "$caption_min"
    at_least "$theme" "error on background" "$(ratio "$error" "$bg")" "$text_min"
    at_least "$theme" "symlink on background" "$(ratio "$symlink" "$bg")" "$text_min"
    at_least "$theme" "executable on background" "$(ratio "$executable" "$bg")" "$text_min"
    at_least "$theme" "the primary frame on the card's surface" "$(ratio "$accentframe" "$surface")" "$mark_min"
    # The role is the accent lifted onto the card, so a theme whose accent already clears the floor
    # reports that accent itself, exactly: both come from one palette read, with no shot between them.
    if awk -v r="$(ratio "$accent" "$surface")" -v f="$mark_min" 'BEGIN { exit !(r >= f) }'; then
        [ "$accentframe" = "$accent" ] \
            || fail "$theme: the primary frame is $accentframe, not this theme's own accent $accent"
    fi
    # The caption is the palette's own muted lifted to that same floor, so a theme already clearing it
    # reports that muted itself: this is what binds the role tests/js/themes.js mirrors to the file.
    if [ -n "$want_muted" ] && awk -v r="$(ratio "$want_muted" "$bg")" -v f="$caption_min" 'BEGIN { exit !(r >= f) }'; then
        [ "$want_muted" = "$muted" ] \
            || fail "$theme: the caption draws $muted, not this theme's own $want_muted"
    fi

    # The cursor row's own accent edge, marked and hovered rows beside it: a shot of all three.
    key j; sleep 0.5
    key v; sleep 0.5
    key j; sleep 0.5
    read -r wx wy <<< "$(window_xy)"
    read -r cx cy <<< "$(ipc rowCentre 2)"
    [ -n "${cx:-}" ] && omarchy-drive move "$((wx + cx))" "$((wy + cy))" >/dev/null
    sleep 1
    omarchy-drive shot "$shots/$theme-list.png" "$class" >/dev/null
    # The edge is a solid bar at the cursor row's leading corner, so its own pixel is the accent itself.
    read -r rx ry rw rh <<< "$(ipc rowRect "$(ipc cursor)")"
    if [ -n "${rx:-}" ]; then
        same_colour "$theme" "the cursor's accent edge" "$(pixel_at "$shots/$theme-list.png" "$((rx + 1))" "$((ry + rh / 2))")" "$accent"
    else
        fail "$theme: the cursor row has no rectangle to measure"
    fi

    # The settings card, whose checkbox draws in the foreground and muted roles the rules above already
    # measure; it is shot for the reviewer rather than measured a second time here.
    key ,; sleep 2
    omarchy-drive shot "$shots/$theme-settings.png" "$class" >/dev/null
    key -k Escape; sleep 1

    # The dialog is the reviewer's record: the seam publishes no rectangle for a button, and a search
    # of the whole window passes on any accent pixel in it, so the role check above is the rule.
    key a; sleep 2
    omarchy-drive key --window "$class" nas >/dev/null
    sleep 1
    omarchy-drive shot "$shots/$theme-dialog.png" "$class" >/dev/null
    key -k Escape; sleep 1

    # A search run, whose matches carry the one wash, and the strip that reports it.
    key f; sleep 1
    omarchy-drive key --window "$class" needle >/dev/null
    key -k Return; sleep 3
    omarchy-drive shot "$shots/$theme-search.png" "$class" >/dev/null
    key -k Escape; sleep 1

    printf 'THEME %s bg=%s fg=%s muted=%s accent=%s error=%s\n' "$theme" "$bg" "$fg" "$muted" "$accent" "$error"
done

stop
printf 'SHOTS %s\n' "$shots"
printf '%s theme checks failed\n' "$failures"
exit "$((failures > 0))"
