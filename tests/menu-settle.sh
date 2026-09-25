#!/usr/bin/env bash
# A menu placed again while open with nothing new to draw still ends its pointer settle; offscreen, so no display and no lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "menu-settle.sh: qs is not installed, cannot place a menu"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-menu-settle-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/menu-settle.qml "$test_root/config/shell.qml" || exit 1

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

# Sample input, the verdict line: "  INFO qml: MENU_SETTLE PASS the second place settled in 17 ms"
if [ "$(printf '%s\n' "$output" | grep -c 'MENU_SETTLE PASS')" -ne 1 ] || printf '%s\n' "$output" | grep -q 'MENU_SETTLE FAIL'; then
    printf 'FAIL a menu placed again with nothing to draw kept its pointer settle\n'
    printf '%s\n' "$output" | grep -aE 'MENU_SETTLE|ERROR|error' | head -20
    exit 1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the menu's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the menu harness logged a warning\n'
    printf '%s\n' "$warnings" | head -10
    exit 1
fi
printf '%s\n' "$output" | grep -o 'MENU_SETTLE PASS.*'
