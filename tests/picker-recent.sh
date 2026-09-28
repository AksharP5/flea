#!/usr/bin/env bash
# An absent recently-used.xbel answers no rows with no warning; a present one lists its bookmarks.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo "picker-recent.sh: qs is not installed, cannot load the reader"; exit 1; }

fixture="$FIXTURE_ROOT/picker-recent-$$"
sandbox_make "$fixture"
qs_pid=""
cleanup() {
    if [ -n "$qs_pid" ] && [ -r "/proc/$qs_pid/environ" ] && tr '\0' '\n' < "/proc/$qs_pid/environ" | grep -qx "HOME=$fixture/home"; then
        kill -KILL -- "-$qs_pid" 2>/dev/null
    fi
    sandbox_remove "$fixture"
}
trap cleanup EXIT

home="$fixture/home"
mkdir -p "$home" "$fixture/data" "$fixture/flea/js"
# No xbel here on purpose: the absent case is the first refresh.
cp ui/PickerRecent.qml "$fixture/flea/"
cp ui/js/Recent.js ui/js/Format.js "$fixture/flea/js/"
printf 'module flea\nPickerRecent 1.0 PickerRecent.qml\n' > "$fixture/flea/qmldir"
cp tests/picker-recent.qml "$fixture/shell.qml"

log="$fixture/qs.log"
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u YDOTOOL_SOCKET \
    HOME="$home" XDG_DATA_HOME="$fixture/data" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    setsid qs -p "$fixture/shell.qml" >"$log" 2>&1 </dev/null &
qs_pid=$!

limit_seconds=30
for _ in $(seq 1 $((limit_seconds * 10))); do
    grep -q 'picker-recent: [0-9]* checks' "$log" && break
    sleep 0.1
done
grep -E ' (ok  |FAIL) |picker-recent:|ERROR|is not a type|Cannot assign|TypeError' "$log" | sed 's/^.*scene[^:]*: //' | uniq
# Sample input, the last line: 'picker-recent: 4 checks, 0 failed'
tally=$(grep -o 'picker-recent: [0-9]* checks, [0-9]* failed' "$log" | tail -1)
[ -n "$tally" ] || { echo "FAIL the harness reported no tally, so it did not run to the end; its log ends:"; tail -20 "$log"; exit 1; }
# The warning this unit removes: Qt opening the absent file itself, once per read.
if grep -qi 'failed to open file.*recently-used.xbel' "$log"; then
    echo "FAIL an absent history printed a warning"
    grep -i 'failed to open file' "$log" | head -5
    exit 1
fi
case "$tally" in
    *" 0 failed") exit 0 ;;
    *) exit 1 ;;
esac
