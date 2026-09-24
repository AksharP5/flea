#!/usr/bin/env bash
# Every settings hint and the Display ruler start on their control's label column; 0.3.4 indented them.
# Offscreen and with no compositor, so this needs neither the display nor the display lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "settings-columns.sh: qs is not installed, cannot draw a settings row"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-settings-columns-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/settings-columns.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: SETTINGS_COLUMNS PASS label=41.85 labels=60 hints=9 rulers=1 footer=14"
pass_count=$(printf '%s\n' "$output" | grep -c 'SETTINGS_COLUMNS PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'SETTINGS_COLUMNS FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a settings hint or ruler left the label column\n'
    printf '%s\n' "$output" | grep -aE 'SETTINGS_COLUMNS|ERROR|error' | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'SETTINGS_COLUMNS PASS.*'
