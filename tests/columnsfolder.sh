#!/usr/bin/env bash
# w24 folder data hold: the real ColumnsArea keeps the old column by data while a folder
# peek is out, hands a live picture hold to that wait, and lands empty folders settled.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "columnsfolder.sh: qs is not installed, cannot drive the columns view"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-columnsfolder-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/columnsfolder.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: COLUMNSFOLDER PASS folder=data-held preview=kept file=reshown empty=settled w25=kept-landed-bounded"
pass_count=$(printf '%s\n' "$output" | grep -c 'COLUMNSFOLDER PASS')
manual_count=$(printf '%s\n' "$output" | grep -c 'COLUMNSFOLDER MANUAL')
fail_count=$(printf '%s\n' "$output" | grep -c 'COLUMNSFOLDER FAIL')
if [ "$pass_count" -ne 1 ] || [ "$manual_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the folder data hold blanks, holds, or animates its landing\n'
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'COLUMNSFOLDER PASS.*'
printf '%s\n' "$output" | grep -o 'COLUMNSFOLDER MANUAL.*'
