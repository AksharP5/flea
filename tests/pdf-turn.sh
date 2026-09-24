#!/bin/bash
# A page turn keeps the page on screen until the next one has rendered, in the preview column's
# PreviewPdf.qml and in Quick Look's PdfViewer.qml; a render past Swap.js HOLD_MS takes the old page
# down for the loading mark, and a second document never brings the first one back or logs a conflict.
# Before this, Qt dropped the old pixmap at the turn and the paper drew white for the whole render:
# about 35 ms a turn here on a light page and 130 on a photographic one. Offscreen, so it needs no
# display and no lock.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

for tool in qs magick; do
    command -v "$tool" >/dev/null || { echo "pdf-turn.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_forbidden /tmp && sandbox_refuse "pdf-turn: /tmp is inside a forbidden test target"
turn_root=$(mktemp -d /tmp/flea-pdf-turn.XXXXXXXX) || exit 1
FIXTURE_ROOT=$turn_root
sandbox_root_ok
turn_root=$SANDBOX_ROOT
readonly turn_root
printf 'Flea PDF turn sandbox\n' > "$turn_root/$SANDBOX_MARKER" || exit 1
turn_work="$turn_root/work"
readonly turn_work
cleanup() {
    local result=$?
    trap - EXIT
    # sandbox_remove verifies an absolute, non-empty path contained in this run's marked root before rm.
    sandbox_remove "$turn_work"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sandbox_scratch "$turn_work"
mkdir -p "$turn_work"/{config,home,runtime,tmp} || exit 1
chmod 700 "$turn_work/runtime" || exit 1
ln -s "$PWD/tests/pdf-turn.qml" "$turn_work/config/shell.qml" || exit 1
ln -s /usr/share/omarchy/shell/Commons "$turn_work/config/Commons" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$turn_work/config/Ui" || exit 1

# Four light pages whose top 15, 30, 45 and 60 percent is black, so the share of black pixels in a
# frame says which page is drawn; the fifth is a 54-megapixel JPEG that renders past the cap.
pdf="$turn_work/turn.pdf"
magick \( -size 2400x3000 xc:white -fill black -draw 'rectangle 0,0 2399,449' \) \
       \( -size 2400x3000 xc:white -fill black -draw 'rectangle 0,0 2399,899' \) \
       \( -size 2400x3000 xc:white -fill black -draw 'rectangle 0,0 2399,1349' \) \
       \( -size 2400x3000 xc:white -fill black -draw 'rectangle 0,0 2399,1799' \) \
       \( -size 6600x8250 xc:gray50 +noise Random -fill black -draw 'rectangle 0,0 6599,6187' -quality 80 \) \
       -compress jpeg "$pdf" || { echo "pdf-turn.sh: fixture generation failed"; exit 1; }
# The second document: one page whose top 90 percent is black, a share no page of the first has.
other="$turn_work/other.pdf"
magick -size 2400x3000 xc:white -fill black -draw 'rectangle 0,0 2399,2699' "$other" \
    || { echo "pdf-turn.sh: second fixture generation failed"; exit 1; }

# Milliseconds: a frame before the cap must still hold the old page, one past the cap plus a timer's
# slack must not; Swap.js HOLD_MS is 150 and a QTimer may fire up to 5 percent either side of it.
cap_early_ms=140
cap_late_ms=180
# A frame whose black share, in parts per ten thousand, is within this of a page's settled share is that page.
level_tolerance=200

run_surface() {
    local surface="$1" out="$turn_work/frames-$1" log="$turn_root/$1.log" status
    mkdir -p "$out" || exit 1
    # Software rendering with a 1 ms update interval samples a frame every few milliseconds.
    # The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$turn_work/home" XDG_RUNTIME_DIR="$turn_work/runtime" TMPDIR="$turn_work/tmp" \
        XDG_CONFIG_HOME="$turn_work/home/.config" XDG_STATE_HOME="$turn_work/home/.local/state" \
        XDG_CACHE_HOME="$turn_work/home/.cache" \
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 \
        QT_FORCE_STDERR_LOGGING=1 \
        PDF_TURN_UI="$PWD/ui" PDF_TURN_SURFACE="$surface" PDF_TURN_PDF="$pdf" PDF_TURN_OTHER="$other" PDF_TURN_OUT="$out" \
        timeout 90 qs -p "$turn_work/config" > "$log" 2>&1; exit $? ) 2>/dev/null
    status=$?
    if grep -q 'PDFTURN FAIL' "$log" || ! grep -q 'PDFTURN DONE' "$log"; then
        bad "$surface: the harness did not finish (qs exit $status): $(grep -a 'PDFTURN FAIL' "$log" | head -1)"
        return
    fi
    judge "$surface" "$out" "$log"
}

# Sample input, one line per frame from magick, the black share in parts per ten thousand: 'f-2-00041.png 751'
black_shares() {
    magick "$1"/f-*.png -colorspace Gray -threshold 3% -negate -format '%f %[fx:round(mean*10000)]\n' info:
}

judge() {
    local surface="$1" out="$2" log="$3" shares step frames last old new t share kind line
    local blank=0 held_late=0 dropped_early=0 heavy_landed=0 heavy_after_cap=0 landed_ms=none
    local left_old=0 old_after_gap=0 other_landed=0 level earlier conflicts
    shares=$(black_shares "$out") || { bad "$surface: magick could not read the frames"; return; }
    declare -A share_of settled
    while read -r file share; do share_of[$file]=$share; done <<< "$shares"
    # Sample input: 'PDFTURN FRAME 2 41 17', the step, the frame's sequence and its milliseconds into the step.
    declare -A frames_of
    while read -r _ _ step seq t; do
        frames_of[$step]+="$seq:$t "
    done < <(grep -a 'PDFTURN FRAME' "$log" | sed 's/.*PDFTURN/PDFTURN/')
    for step in 0 1 2 3 4 5 6 7; do
        [[ -n "${frames_of[$step]:-}" ]] || { bad "$surface: step $step drew no frame"; return; }
        last=${frames_of[$step]% }
        last=${last##* }
        settled[$step]=${share_of[f-$step-$(printf '%05d' "${last%%:*}").png]}
    done
    for step in 1 2 3 4 5 6; do
        old=${settled[$((step - 1))]}
        new=${settled[$step]}
        frames=0
        for line in ${frames_of[$step]}; do
            t=${line##*:}
            share=${share_of[f-$step-$(printf '%05d' "${line%%:*}").png]}
            frames=$((frames + 1))
            kind=other
            if (( share - new < level_tolerance && new - share < level_tolerance )); then
                kind=new
            elif (( share - old < level_tolerance && old - share < level_tolerance )); then
                kind=old
            fi
            if (( step < 6 )); then
                [[ "$kind" == other ]] && blank=$((blank + 1))
                continue
            fi
            # The slow page: the old one until the cap, never after it, then the new one.
            if [[ "$kind" == new && $heavy_landed -eq 0 ]]; then heavy_landed=1; landed_ms=$t; fi
            if (( t < cap_early_ms )) && [[ "$kind" != old && $heavy_landed -eq 0 ]]; then dropped_early=$((dropped_early + 1)); fi
            if (( t > cap_late_ms )) && [[ "$kind" == old ]]; then held_late=$((held_late + 1)); fi
            if (( t > cap_late_ms )) && [[ "$kind" == other && $heavy_landed -eq 0 ]]; then heavy_after_cap=$((heavy_after_cap + 1)); fi
        done
        printf '  %s step %s: %s frames, settled black share %s after %s\n' "$surface" "$step" "$frames" "$new" "$old"
    done
    # The switch: once a frame stops showing the first document it never shows it again.
    for line in ${frames_of[7]}; do
        share=${share_of[f-7-$(printf '%05d' "${line%%:*}").png]}
        level=gap
        if (( share - settled[7] < level_tolerance && settled[7] - share < level_tolerance )); then
            level=new
            other_landed=1
        else
            for earlier in 0 1 2 3 4 5 6; do
                if (( share - settled[$earlier] < level_tolerance && settled[$earlier] - share < level_tolerance )); then level=first; fi
            done
        fi
        if [[ "$level" != first ]]; then left_old=1
        elif (( left_old )); then old_after_gap=$((old_after_gap + 1)); fi
    done
    if [[ $blank -eq 0 ]]; then ok "$surface: five turns drew only the old page or the new one, never a blank"
    else bad "$surface: five turns drew $blank frame(s) with neither page on them"; fi
    if [[ $dropped_early -eq 0 ]]; then ok "$surface: a slow render held the old page until the cap"
    else bad "$surface: a slow render drew $dropped_early frame(s) without the old page before the cap"; fi
    if [[ $held_late -eq 0 && $heavy_after_cap -gt 0 ]]; then ok "$surface: past the cap the old page gave way to the loading state"
    else bad "$surface: past the cap $held_late frame(s) still held the old page, $heavy_after_cap drew the loading state"; fi
    if [[ $heavy_landed -eq 1 ]]; then ok "$surface: the slow page landed after $landed_ms ms"
    else bad "$surface: the slow page never landed"; fi
    if [[ $other_landed -eq 1 && $old_after_gap -eq 0 ]]; then ok "$surface: the next document replaced the last one without it coming back"
    else bad "$surface: opening the next document drew the last one $old_after_gap more frame(s) after it had gone, landed=$other_landed"; fi
    # Sample input: 'WARN scene: QML PdfPageImage at file:///.../PreviewPdf.qml[105:5]: document and source
    # properties in conflict: preferring document source QUrl("file:///.../other.pdf")', which tests/ui.sh's log gate fails on.
    conflicts=$(sed -n '/PDFTURN STEP 7 /,$p' "$log" | grep -ac 'document and source properties in conflict')
    if [[ $conflicts -eq 0 ]]; then ok "$surface: opening the next document logged no source conflict"
    else bad "$surface: opening the next document logged $conflicts document and source conflict warning(s)"; fi
}

run_surface column
run_surface quicklook

printf 'pdf-turn: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
