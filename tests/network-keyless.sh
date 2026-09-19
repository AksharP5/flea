#!/usr/bin/env bash
# A public key mounts an sftp place with no password, and only a refused mount asks for one.
# 0.2.1 demanded a credential for every sftp://user@host before it ever ran gio, so no key could
# ever open one; see AGENTS.md "A public key mounts sftp, and a password is asked only after".
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

test_root="$FIXTURE_ROOT/flea-network-keyless-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/bin" "$test_root/home/.config" "$test_root/config" "$test_root/state"
ln -s "$PWD/ui/NetworkMounts.qml" "$test_root/config/NetworkMounts.qml"
# The Service instantiates both of these, so a config directory without them resolves neither.
ln -s "$PWD/ui/MountListing.qml" "$test_root/config/MountListing.qml"
ln -s "$PWD/ui/NetworkPlaces.qml" "$test_root/config/NetworkPlaces.qml"
ln -s "$PWD/ui/js" "$test_root/config/js"
ln -s "$PWD/tests/network-keyless.qml" "$test_root/config/shell.qml"
call_log="$test_root/state/calls.log"
helper_log="$test_root/state/helper.log"
: > "$call_log"
: > "$helper_log"

# Only the submitted fixture token and expected URI may authenticate this location.
cat > "$test_root/bin/flea-gio-auth" <<'EOS'
#!/bin/sh
[ "$#" -eq 1 ] || exit 2
[ "$1" = "sftp://pw@slot.test/home" ] || exit 60
IFS= read -r password || exit 3
[ "$password" = "fixture-secret" ] || exit 4
password=
printf 'auth uri=%s token=accepted\n' "$1" >> "$FLEA_TEST_CALL_LOG"
printf 'uri=%s token=accepted\n' "$1" >> "$FLEA_TEST_HELPER_LOG"
: > "$FLEA_TEST_AUTH_MARKER"
EOS
chmod +x "$test_root/bin/flea-gio-auth"

cat > "$test_root/bin/gio" <<'EOS'
#!/bin/sh
if [ "$1 ${2:-}" != "mount -li" ]; then
  printf 'gio %s\n' "$*" >> "$FLEA_TEST_CALL_LOG"
fi
case "$1 ${2:-}" in
  "mount -li") exit 2 ;;
  # A key authenticates this one, the way gvfsd-sftp's own ssh does, so no prompt ever appears.
  "mount sftp://key@slot.test/home") exit 0 ;;
  "info sftp://key@slot.test/home") printf 'local path: %s\n' "$FLEA_TEST_KEY_PATH" ;;
  # These two refused locations must both reach gio mount before their credential prompt.
  "mount sftp://ask@slot.test/home") exit 2 ;;
  "info sftp://ask@slot.test/home") exit 2 ;;
  "mount sftp://ask@slot.test/") exit 2 ;;
  "info sftp://ask@slot.test/") exit 2 ;;
  # A server root that a password would open has no path of its own and no shares without one.
  "list sftp://ask@slot.test/") exit 2 ;;
  # The remembered-password location refuses its keyless attempt, then opens only after auth.
  "mount sftp://pw@slot.test/home") exit 2 ;;
  "info sftp://pw@slot.test/home")
    [ -e "$FLEA_TEST_AUTH_MARKER" ] || exit 2
    printf 'local path: %s\n' "$FLEA_TEST_AUTH_PATH"
    ;;
  # An SMB root whose info refuses but whose list enumerates must still be tried.
  "mount --anonymous") [ "$3" = "smb://nas.test/" ] && exit 2 || exit 64 ;;
  "info smb://nas.test/") exit 2 ;;
  "list smb://nas.test/") printf 'docs\nmedia\n' ;;
  # Everything else wants a password: measured against a real host, gio answers this in 171 ms
  # with exit 2 rather than waiting on a stdin nobody is reading.
  *) exit 64 ;;
esac
EOS
chmod +x "$test_root/bin/gio"

output=$(env \
    FLEA_TEST_KEY_PATH="/key-should-open" \
    FLEA_TEST_AUTH_PATH="/password-should-open" \
    FLEA_TEST_AUTH_MARKER="$test_root/state/authenticated" \
    FLEA_TEST_CALL_LOG="$call_log" \
    FLEA_TEST_HELPER_LOG="$helper_log" \
    FLEA_GIO_AUTH="$test_root/bin/flea-gio-auth" \
    HOME="$test_root/home" \
    PATH="$test_root/bin:/usr/bin:/bin" \
    QT_QPA_PLATFORM=offscreen \
    QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

failures=0
pass_count=$(printf '%s\n' "$output" | grep -c 'NETWORK_KEYLESS passwordless=open needs-password=asked bare-root=asked remembered=kept smb-root=listed')
fail_count=$(printf '%s\n' "$output" | grep -c 'NETWORK_KEYLESS FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL sftp keyless mount changed its answer\n%s\n' "$output"
    failures=1
fi

expected_calls=$(cat <<'EOF'
gio mount sftp://key@slot.test/home
gio info sftp://key@slot.test/home
gio mount sftp://ask@slot.test/home
gio info sftp://ask@slot.test/home
gio mount sftp://ask@slot.test/
gio info sftp://ask@slot.test/
gio mount sftp://key@slot.test/home
gio info sftp://key@slot.test/home
gio mount sftp://pw@slot.test/home
gio info sftp://pw@slot.test/home
auth uri=sftp://pw@slot.test/home token=accepted
gio info sftp://pw@slot.test/home
gio mount --anonymous smb://nas.test/
gio info smb://nas.test/
gio list smb://nas.test/
EOF
)
actual_calls=$(<"$call_log")
if [ "$actual_calls" != "$expected_calls" ]; then
    printf 'FAIL network call sequence changed\nexpected:\n%s\nactual:\n%s\n' "$expected_calls" "$actual_calls"
    failures=1
fi

expected_helper='uri=sftp://pw@slot.test/home token=accepted'
actual_helper=$(<"$helper_log")
if [ "$actual_helper" != "$expected_helper" ]; then
    printf 'FAIL authenticated helper route was not one exact nonsecret call\nexpected: %s\nactual: %s\n' \
        "$expected_helper" "$actual_helper"
    failures=1
fi
if grep -Fq 'fixture-secret' "$call_log" "$helper_log" 2>/dev/null; then
    printf 'FAIL fixture password reached a durable call log\n'
    failures=1
fi

if [ "$failures" -ne 0 ]; then
    exit 1
fi

printf 'network-keyless: passwordless opens, only a refused mount asks\n'
