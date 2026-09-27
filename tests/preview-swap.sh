#!/bin/bash
# The preview swap keeps the old picture until the new preview is whole, in the
# columns view and in Quick Look; a hold past the cap falls back to loading.
# Before it, a cursor move drew the next preview half-built: v0.3.4 shows 145 to 151
# mid frames over 18 column moves and 13 to 15 over 16 Quick Look moves, measured
# headless through the atomic-evidence harness (see preview-moves.txt in the plan).
# Offscreen, so it needs no display and no lock.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

for tool in qs; do
    command -v "$tool" >/dev/null || { echo "preview-swap.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_forbidden /tmp && sandbox_refuse "preview-swap: /tmp is inside a forbidden test target"
swap_root=$(mktemp -d /tmp/flea-preview-swap.XXXXXXXX) || exit 1
FIXTURE_ROOT=$swap_root
sandbox_root_ok
swap_root=$SANDBOX_ROOT
readonly swap_root
printf 'Flea preview swap sandbox\n' > "$swap_root/$SANDBOX_MARKER" || exit 1
swap_work="$swap_root/work"
readonly swap_work
cleanup() {
    local result=$?
    trap - EXIT
    sandbox_remove "$swap_work"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sandbox_scratch "$swap_work"
mkdir -p "$swap_work"/{config,home,runtime,tmp} "$swap_work"/frames-column "$swap_work"/frames-quicklook || exit 1
chmod 700 "$swap_work/runtime" || exit 1
ln -s "$PWD/tests/preview-swap.qml" "$swap_work/config/shell.qml" || exit 1
ln -s /usr/share/omarchy/shell/Commons "$swap_work/config/Commons" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$swap_work/config/Ui" || exit 1

run_surface() {
    # One local per line: bash expands every word of a local before assigning any, so out would read an unset surface.
    local surface="$1" direct="${2:-0}" status
    local out="$swap_work/frames-$surface" log="$swap_root/$surface.log"
    [ "$direct" == 1 ] && out="$swap_work/frames-$surface-direct" && log="$swap_root/$surface-direct.log"
    mkdir -p "$out" || exit 1
    # Software rendering with a 16 ms update interval samples about one frame per vsync.
    # The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$swap_work/home" XDG_RUNTIME_DIR="$swap_work/runtime" TMPDIR="$swap_work/tmp" \
        XDG_CONFIG_HOME="$swap_work/home/.config" XDG_STATE_HOME="$swap_work/home/.local/state" \
        XDG_CACHE_HOME="$swap_work/home/.cache" \
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=16 \
        QT_FORCE_STDERR_LOGGING=1 \
        PREVIEW_SWAP_UI="$PWD/ui" PREVIEW_SWAP_SURFACE="$surface" PREVIEW_SWAP_OUT="$out" \
        PREVIEW_SWAP_DIRECT="$direct" \
        timeout 90 qs -p "$swap_work/config" > "$log" 2>&1; exit $? ) 2>/dev/null
    status=$?
    if grep -q 'PREVIEWSWAP FAIL' "$log" || ! grep -q 'PREVIEWSWAP DONE' "$log"; then
        bad "$surface: the harness did not finish (qs exit $status): $(grep -a 'PREVIEWSWAP FAIL' "$log" | head -1)"
        return
    fi
    judge "$surface" "$direct" "$out" "$log"
}

# Sample input, one harness line: 'PREVIEWSWAP DONE holds=18 fallbacks=0 bursts=0 held=210 mid=0 loading=0'.
judge() {
    local surface="$1" direct="$2" out="$3" log="$4" done holds fallbacks bursts held mid loading
    done=$(grep -a 'PREVIEWSWAP DONE' "$log" | tail -1)
    [ -n "$done" ] || { bad "$surface: no DONE line to judge"; return; }
    holds=$(printf '%s' "$done" | sed -n 's/.*holds=\([0-9]*\).*/\1/p')
    fallbacks=$(printf '%s' "$done" | sed -n 's/.*fallbacks=\([0-9]*\).*/\1/p')
    bursts=$(printf '%s' "$done" | sed -n 's/.*bursts=\([0-9]*\).*/\1/p')
    held=$(printf '%s' "$done" | sed -n 's/.*held=\([0-9]*\).*/\1/p')
    mid=$(printf '%s' "$done" | sed -n 's/.*mid=\([0-9]*\).*/\1/p')
    loading=$(printf '%s' "$done" | sed -n 's/.*loading=\([0-9]*\).*/\1/p')
    printf '  %s direct=%s holds=%s fallbacks=%s bursts=%s held=%s mid=%s loading=%s\n' \
        "$surface" "$direct" "$holds" "$fallbacks" "$bursts" "$held" "$mid" "$loading"
    if [ "$direct" == 1 ]; then
        # The control: mutating without a hold draws half-built frames, the defect itself.
        if [ "${mid:-0}" -gt 0 ]; then ok "$surface: mutating without a hold drew $mid mid frame(s), so the harness sees the defect";
        else bad "$surface: mutating without a hold drew no mid frame, so the harness cannot see the defect"; fi
        return
    fi
    [ "${holds:-0}" -ge 18 ] || { bad "$surface: took $holds hold(s), not one per move"; return; }
    if [ "${mid:-1}" -eq 0 ]; then ok "$surface: 18 moves drew no half-built frame";
    else bad "$surface: 18 moves drew $mid half-built frame(s)"; fi
    if [ "${fallbacks:-1}" -eq 0 ]; then ok "$surface: no hold ran past the cap";
    else bad "$surface: $fallbacks hold(s) fell back on fast decodes"; fi
    [ -f "$out/settled.png" ] || bad "$surface: the settled grab never landed"
}

run_surface column 0
run_surface quicklook 0
run_surface column 1
run_surface quicklook 1

printf 'preview-swap: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
