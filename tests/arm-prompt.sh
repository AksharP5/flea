#!/usr/bin/env bash
# A dd prompt lives exactly as long as its arm and leaves nothing stale, timed on the harness's own clock; offscreen, so no display and no lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "arm-prompt.sh: qs is not installed, cannot build the status bar"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-arm-prompt-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/arm-prompt.qml "$test_root/config/shell.qml" || exit 1

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

# Sample input, the verdict line: "  INFO qml: ARM_PROMPT DONE 17 checks, 0 failed"
if ! printf '%s\n' "$output" | grep -q 'ARM_PROMPT DONE [0-9]* checks, 0 failed' || printf '%s\n' "$output" | grep -q 'ARM_PROMPT FAIL'; then
    printf 'FAIL a dd prompt outlived its arm or left something stale\n'
    printf '%s\n' "$output" | grep -aE 'ARM_PROMPT (FAIL|DONE)|ERROR|error' | head -20
    exit 1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the bar's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the arm harness logged a warning\n'
    printf '%s\n' "$warnings" | head -10
    exit 1
fi
printf '%s\n' "$output" | grep -o 'ARM_PROMPT DONE.*'
