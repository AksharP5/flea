#!/usr/bin/env bash
# w61 footer hint: the real StatusBar keeps a long error's whole dismissal hint, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "statusbar-hint.sh: qs is not installed, cannot lay out the footer"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-statusbar-hint.XXXXXX") || exit 1
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/statusbar-hint.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input, one probe line: "  INFO qml: STATUSHINT PASS checks=30"
# Sample input, one metric line: "  INFO qml: STATUSHINT METRICS hint12 px=12 metricsWidth=114 advance=115 implicit=115 hintWidth=115"
pass_count=$(printf '%s\n' "$output" | grep -c 'STATUSHINT PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'STATUSHINT FAIL')
metrics12=$(printf '%s\n' "$output" | grep -c 'STATUSHINT METRICS hint12 .*advance=')
metrics14=$(printf '%s\n' "$output" | grep -c 'STATUSHINT METRICS hint14 .*advance=')
verdict=0
# The resident qs holds past its verdict, so 124 beside those predicates is the known timeout, never a proof on its own.
case "$qs_status" in
    0|124) ;;
    *) printf 'FAIL qs exited %s, want 0 or the known resident 124 beside the verdict\n' "$qs_status"; verdict=1 ;;
esac
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL hint verdicts pass=%s (want 1) fail=%s (want 0)\n' "$pass_count" "$fail_count"
    printf '%s\n' "$output" | grep -a 'STATUSHINT'
    verdict=1
fi
if [ "$metrics12" -ne 1 ] || [ "$metrics14" -ne 1 ]; then
    printf 'FAIL metric receipts hint12=%s hint14=%s, want one nonempty each\n' "$metrics12" "$metrics14"
    verdict=1
fi
# Bad QML errors only: driver WARN noise (Vulkan, drm) is environmental and never gated here.
bad_count=$(printf '%s\n' "$output" | grep -aE -c 'TypeError|ReferenceError|Cannot anchor|Failed to load')
if [ "$bad_count" -ne 0 ]; then
    printf 'FAIL the engine raised %s bad QML error(s) beside the verdict\n' "$bad_count"
    printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|Cannot anchor|Failed to load' | head -20
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'STATUSHINT PASS.*'
printf 'STATUSHINT STATUS qs_exit=%s metrics=hint12,hint14\n' "$qs_status"
