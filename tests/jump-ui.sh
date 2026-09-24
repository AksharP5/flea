#!/usr/bin/env bash
# The path bar's folder jump through the real ChromeBar and PathJump, offscreen: what one open asks for,
# a held Enter, a stale answer, a Tab-completed path, a name with no match, a backend that never answers.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo "jump-ui.sh: qs is not installed, cannot load the bar"; exit 1; }
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "jump-ui.sh: build the candidate backend first: $bin"; exit 1; }

fixture="$FIXTURE_ROOT/jump-ui-$$"
sandbox_make "$fixture"
qs_pid=""
cleanup() {
    # Only the qs this run started, found by the fixture path in its own environment, is ever signalled.
    if [ -n "$qs_pid" ] && [ -r "/proc/$qs_pid/environ" ] && tr '\0' '\n' < "/proc/$qs_pid/environ" | grep -qx "HOME=$fixture/home"; then
        kill -KILL -- "-$qs_pid" 2>/dev/null
    fi
    sandbox_remove "$fixture"
}
trap cleanup EXIT

home="$fixture/home"
mkdir -p "$home/Projects" "$home/Documents/claude/flea" "$home/Documents/claude/omarchy" "$home/Downloads" \
    "$home/Pictures/screenshots" "$home/Work/field" "$home/.local/share" "$home/.local/state" "$home/.config" "$fixture/cache"
: > "$home/Pictures/screenshots/shot.png"
: > "$home/Work/field/notes.md"
# The desktop's recent history, the newer bookmark second in file order so the read has to sort it.
cat > "$home/.local/share/recently-used.xbel" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0">
  <bookmark href="file://$home/Work/field/notes.md" added="2026-09-20T10:00:00Z" modified="2026-09-20T10:00:00Z" visited="2026-09-20T10:00:00Z"/>
  <bookmark href="file://$home/Pictures/screenshots/shot.png" added="2026-09-22T10:00:00Z" modified="2026-09-22T10:00:00Z" visited="2026-09-22T10:00:00Z"/>
</xbel>
EOF
for favourite in Projects Documents/claude/flea Documents/claude/omarchy; do
    HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CONFIG_HOME="$home/.config" \
        "$bin" --favourites "{\"op\":\"add\",\"record\":{\"label\":\"${favourite##*/}\",\"path\":\"$home/$favourite\"}}" >/dev/null \
        || { echo "FAIL could not seed the favourite $favourite"; exit 1; }
done

# The real ui/ as the module under test, and the Omarchy modules its qs.* imports resolve to at the config root.
cp -a ui "$fixture/flea"
ln -s "$(readlink -f ui/Commons)" "$fixture/Commons"
ln -s "$(readlink -f ui/Ui)" "$fixture/Ui"
cp tests/jump-ui.qml "$fixture/shell.qml"

log="$fixture/qs.log"
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u YDOTOOL_SOCKET \
    HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_DATA_HOME="$home/.local/share" \
    XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$fixture/cache" FLEA_BIN="$bin" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    setsid qs -p "$fixture/shell.qml" >"$log" 2>&1 </dev/null &
qs_pid=$!

# The held-Enter case waits out the bar's own answer limit, so the whole run takes some seconds.
limit_seconds=40
for _ in $(seq 1 $((limit_seconds * 10))); do
    grep -q 'jump-ui: [0-9]* checks' "$log" && break
    sleep 0.1
done
grep -E ' (ok  |FAIL) |jump-ui:|ERROR|is not a type|Cannot assign|TypeError' "$log" | sed 's/^.*scene[^:]*: //' | uniq
# Sample input, the last line: 'jump-ui: 22 checks, 0 failed'
tally=$(grep -o 'jump-ui: [0-9]* checks, [0-9]* failed' "$log" | tail -1)
[ -n "$tally" ] || { echo "FAIL the harness reported no tally, so it did not run to the end; its log ends:"; tail -20 "$log"; exit 1; }
case "$tally" in
    *" 0 failed") exit 0 ;;
    *) exit 1 ;;
esac
