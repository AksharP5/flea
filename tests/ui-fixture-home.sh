#!/usr/bin/env bash
# Focused control: the fixture must carry the launcher's real HOME icons.theme bytes too.
set -u
set -o pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/tools/flea-sandbox-guard"

fail() {
    printf 'FAIL ui-fixture-home: %s\n' "$*" >&2
    exit 1
}

# Sample input, one extracted line: '    cp "$real_state_dir/theme/shell.toml" "$theme/theme/shell.toml"'
fixture_def=$(sed -n '/^fixture_home_make() {/,/^}/p' "$repo/tests/ui.sh")
[[ -n "$fixture_def" ]] || fail "could not extract fixture_home_make from tests/ui.sh"
eval "$fixture_def"

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-e54-XXXXXXXX") || fail "mktemp under $SANDBOX_ROOT failed"
: > "$test_root/$SANDBOX_MARKER" || fail "could not mark $test_root"
cleanup() {
    sandbox_remove "$test_root" 2>/dev/null || true
}
trap cleanup EXIT

fake_real="$test_root/fake-real"
sandbox_scratch "$fake_real"
mkdir -p "$fake_real/.local/state/omarchy/current/theme" "$fake_real/.config/omarchy"
# Sample input, the whole icons.theme file: "Yaru-blue\n"
printf 'foreground = "#c8ccd0"\n' > "$fake_real/.local/state/omarchy/current/theme/colors.toml"
printf 'base-size = 14\n' > "$fake_real/.local/state/omarchy/current/theme/shell.toml"
printf 'live-theme\n' > "$fake_real/.local/state/omarchy/current/theme.name"
printf 'Yaru-blue\n' > "$fake_real/.local/state/omarchy/current/theme/icons.theme"
printf 'base-size = 14\n' > "$fake_real/.config/omarchy/shell.toml"
real_state_dir="$fake_real/.local/state/omarchy/current"
real_user_shell_toml="$fake_real/.config/omarchy/shell.toml"

home_present="$test_root/home-present"
fixture_home_make "$home_present"
dest="$home_present/.local/state/omarchy/current/theme/icons.theme"
[[ -f "$dest" ]] || fail "present icons.theme was not copied to $dest"
[[ ! -L "$dest" ]] || fail "dest $dest is a symlink, must be regular bytes"
cmp -s "$fake_real/.local/state/omarchy/current/theme/icons.theme" "$dest" \
    || fail "dest icons.theme bytes differ from the source"
[[ "$fake_real/.local/state/omarchy/current/theme/icons.theme" -ef "$dest" ]] \
    && fail "dest icons.theme is the same file as the source, must be an independent copy"
cmp -s "$fake_real/.local/state/omarchy/current/theme/colors.toml" "$home_present/.local/state/omarchy/current/theme/colors.toml" \
    || fail "colors.toml was altered by the icons.theme copy"
cmp -s "$fake_real/.local/state/omarchy/current/theme/shell.toml" "$home_present/.local/state/omarchy/current/theme/shell.toml" \
    || fail "shell.toml was altered by the icons.theme copy"
cmp -s "$fake_real/.local/state/omarchy/current/theme.name" "$home_present/.local/state/omarchy/current/theme.name" \
    || fail "theme.name was altered by the icons.theme copy"
cmp -s "$fake_real/.config/omarchy/shell.toml" "$home_present/.config/omarchy/shell.toml" \
    || fail "user shell.toml was altered by the icons.theme copy"
echo "ok present icons.theme copied byte-equal as regular bytes, rest unaltered"

victim="$fake_real/.local/state/omarchy/current/theme/icons.theme"
case "$victim/" in "$test_root/"*) ;; *) fail "refusing to delete outside $test_root" ;; esac
rm -f "$victim" || fail "could not remove the fake icons.theme"
home_absent="$test_root/home-absent"
fixture_home_make "$home_absent"
[[ ! -e "$home_absent/.local/state/omarchy/current/theme/icons.theme" ]] \
    || fail "absent icons.theme was synthesized at $home_absent"
cmp -s "$fake_real/.local/state/omarchy/current/theme/colors.toml" "$home_absent/.local/state/omarchy/current/theme/colors.toml" \
    || fail "colors.toml was altered when icons.theme was absent"
cmp -s "$fake_real/.config/omarchy/shell.toml" "$home_absent/.config/omarchy/shell.toml" \
    || fail "user shell.toml was altered when icons.theme was absent"
echo "ok absent icons.theme stays absent, rest unaltered"
