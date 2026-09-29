#!/usr/bin/env bash
# The real ui/ContextMenu.qml refuses an empty locked menu and closes a stale frame; offscreen, so no display and no lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "lockedmenu.sh: qs is not installed, cannot open a menu"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-lockedmenu-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/lockedmenu.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: LOCKEDMENU PASS 24 checks"
pass_count=$(printf '%s\n' "$output" | grep -c 'LOCKEDMENU PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'LOCKEDMENU FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the locked menu guard or its stale-frame close broke\n'
    printf '%s\n' "$output" | grep -a 'LOCKEDMENU FAIL'
    printf '%s\n' "$output" | grep -aE 'ERROR|error' | grep -av 'LOCKEDMENU' | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'LOCKEDMENU PASS.*'
