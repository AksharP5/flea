#!/usr/bin/env bash
# e34r2 listcost: a real ui/List.qml over a stub pane hoists its shared values and frees its lookup, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "listcost.sh: qs is not installed, cannot build the list"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-listcost.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/listcost.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: LISTCOST PASS delegates=6 calls=6"
pass_count=$(printf '%s\n' "$output" | grep -c 'LISTCOST PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'LISTCOST FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the list builds a width, an array or a mark call per row, or it keeps its lookup\n'
    printf '%s\n' "$output" | grep -a 'LISTCOST'
    printf '%s\n' "$output" | grep -aiE 'ERROR|error'
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'LISTCOST PASS.*'
