#!/usr/bin/env bash
# A list header builds its resize accents and fit metrics only while used, counted offscreen with no display or display lock. The fit loader stays empty until a double click or F4, persists one widths-map update per fit, and releases after; refusals persist nothing.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "headercost.sh: qs is not installed, cannot build a header"
    exit 1
fi
if ! command -v sha256sum >/dev/null; then
    echo "headercost.sh: sha256sum is not installed, cannot receipt staged sources"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-headercost.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The write spy is supplied before construction: a shadow module where every entry links
# the tree file except ViewState.qml, which is the test-only double. Header code under test stays
# the identical inode; the receipts below prove the bytes. ln never follows sources, so the OEM
# boot links stay dangling outside the root without copying them.
stage="$test_root/stage"
mkdir -p "$stage/ui" || exit 1
for src in "$PWD"/ui/*; do
    base=${src##*/}
    [ "$base" = "ViewState.qml" ] && continue
    ln -s "$src" "$stage/ui/$base" || exit 1
done
cp tests/headercost-viewstate.qml "$stage/ui/ViewState.qml" || exit 1
ln -s "$stage/ui" "$test_root/config/flea" || exit 1
# readlink -m, not -f: identical where the OEM shell exists, and a dangling link where it does not, so a box without it still reaches qs and fails with qs's own error in the log.
ln -s "$(readlink -m ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/headercost.qml "$test_root/config/shell.qml" || exit 1

# Sample input, one probe line: "  INFO qml: HEADERCOST PASS accents=0 metrics=0 hot=1 fit=42".
# HEADERCOST_TIMEOUT shortens the bound for iteration only; the default stays 20.
log="$test_root/headercost.log"
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout "${HEADERCOST_TIMEOUT:-20}" qs -p "$test_root/config" > "$log" 2>&1; exit $? ) 2>/dev/null
status=$?

# Byte-exact receipts for every production source under test plus both fixture files.
receipts=$(sha256sum "$PWD/ui/Header.qml" "$PWD/ui/FitMetrics.qml" "$PWD/ui/ViewState.qml" "$PWD/ui/js/ColumnFit.js" "$PWD/ui/js/Columns.js" tests/headercost.qml tests/headercost-viewstate.qml) || exit 1
printf '%s\n' "$receipts" >> "$log"

pass_count=$(grep -ac 'HEADERCOST PASS' "$log")
fail_count=$(grep -ac 'HEADERCOST FAIL' "$log")
done_count=$(grep -ac 'HEADERCOST DONE' "$log")
# Offscreen platform mask warning is the platform's, never the guard's.
platform_warning='This plugin does not support setting window masks'
warnings=$(grep -aE 'TypeError|ReferenceError|ERROR|WARN|Cannot|is not a type|failed to load' "$log" | grep -vF "$platform_warning" || true)

# The DONE receipt is verified before the status is trusted: only a finished fixture proves its counts.
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL headercost: no completion receipt (qs exit %s, done=%s)\n' "$status" "$done_count"
    cat "$log"
    exit 1
fi
# 143 is the fixture's owned self-kill (SIGTERM through execDetached kill), not a crash; 124 is the timeout.
if [ "$status" -eq 124 ]; then
    printf 'FAIL headercost: qs timed out with no completion\n'
    cat "$log"
    exit 1
fi
if [ "$status" -ne 0 ] && [ "$status" -ne 143 ]; then
    printf 'FAIL headercost: qs exited %s, not 0 or the owned 143\n' "$status"
    cat "$log"
    exit 1
fi
if [ "$fail_count" -ne 0 ] || [ "$pass_count" -ne 1 ]; then
    printf 'FAIL headercost: want one PASS and no FAIL (qs exit %s, pass=%s fail=%s)\n' "$status" "$pass_count" "$fail_count"
    cat "$log"
    exit 1
fi
if [ -n "$warnings" ]; then
    printf 'FAIL headercost: engine warnings with a passing fixture (qs exit %s)\n' "$status"
    printf '%s\n' "$warnings"
    cat "$log"
    exit 1
fi
grep -a 'HEADERCOST PASS' "$log" | tail -1
grep -a 'HEADERCOST DONE' "$log" | tail -1
printf '%s\n' "$receipts"
printf 'headercost: qs exit %s\n' "$status"
