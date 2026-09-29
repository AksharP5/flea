#!/usr/bin/env bash
# A list row and a grid tile build no more than they need: one Row and one GridTile
# are built the way the list and the grid build them, and their object trees are counted.
# Offscreen and with no compositor, so this needs neither the display nor the display lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "rowcost.sh: qs is not installed, cannot build a row or a tile"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-rowcost-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/rowcost.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: ROWCOST PASS row=24 grid=18"
pass_count=$(printf '%s\n' "$output" | grep -c 'ROWCOST PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'ROWCOST FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a delegate built more than its ceiling, or its rename wiring broke\n'
    printf '%s\n' "$output" | grep -aE 'ROWCOST|ERROR|error' | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'ROWCOST PASS.*'
