#!/usr/bin/env bash
# e52 scroll-fill: list and column state fills paint under the reserved lane, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "scroll-fill.sh: qs is not installed, cannot build the rows"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-scrollfill.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/scroll-fill.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input, one probe line: "  INFO qml: SCROLLFILL PASS list=700 col=400 pick=700"
# Sample input, the receipt: "  INFO qml: SCROLLFILL DONE failures=0".
# The owned termination is the probe's own self-kill (SIGTERM, 143) after its one DONE receipt; a PASS beside any other status is a double's, never a proof.
pass_count=$(printf '%s\n' "$output" | grep -c 'SCROLLFILL PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'SCROLLFILL FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'SCROLLFILL DONE')
verdict=0
if [ "$qs_status" -ne 143 ]; then
    printf 'FAIL qs exited %s, want the owned self-kill 143 after DONE\n' "$qs_status"
    verdict=1
fi
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL completion receipts %s, want exactly 1 DONE beside the PASS\n' "$done_count"
    verdict=1
fi
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL state fills stop before the lane, content moved, a clip hides the paint, or the engine warned\n'
    printf '%s\n' "$output" | grep -aE 'SCROLLFILL|ERROR|error'
    verdict=1
fi
# Any engine warning fails even beside a PASS, so a clean log is part of the gate.
warn_count=$(printf '%s\n' "$output" | grep -c -E 'WARN|TypeError|ReferenceError|ERROR')
if [ "$warn_count" -ne 0 ]; then
    printf 'FAIL the engine warned %s times beside the verdict\n' "$warn_count"
    printf '%s\n' "$output" | grep -aE 'WARN|TypeError|ReferenceError|ERROR'
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'SCROLLFILL PASS.*'
printf 'SCROLLFILL STATUS qs_exit=%s done=1\n' "$qs_status"
