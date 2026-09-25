#!/usr/bin/env bash
# The Columns preview frame: an office thumbnail with no "no preview" over it, and a small original at its own
# size. Offscreen, so it needs neither the display nor the display lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "preview-frame.sh: qs is not installed, cannot draw the preview frame"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-preview-frame-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/preview-frame.qml "$test_root/config/shell.qml" || exit 1
mkdir -p "$test_root/fixture" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    FLEA_PREVIEW_FRAME_DIR="$test_root/fixture" HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: PREVIEW_FRAME PASS office=fitted small=own-size"
pass_count=$(printf '%s\n' "$output" | grep -c 'PREVIEW_FRAME PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'PREVIEW_FRAME FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the preview frame drew a picture wrong\n'
    printf '%s\n' "$output" | grep -aE 'PREVIEW_FRAME|ERROR|error' | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'PREVIEW_FRAME PASS.*'
