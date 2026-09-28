#!/usr/bin/env bash
# Bridge and wrapper arrive off launch; the host builds with the window, so its Loader stays active.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
tree=${1:-$PWD}
for f in ui/NetworkMounts.qml ui/Preview.qml ui/WindowBody.qml ui/js/Mounts.js tests/lazy-live.qml tests/lazy-swap-live.qml; do [ -f "$tree/$f" ] || { printf 'FAIL missing %s\n' "$f"; exit 1; }; done
# Upper-case property names never load, so every .qml under ui/ is swept, boot included.
upper=$(grep -rnE 'property[[:space:]]+[^[:space:]]+[[:space:]]+[A-Z][A-Za-z0-9_]*' "$tree/ui" --include='*.qml' || true)
[ -z "$upper" ] || { printf 'FAIL upper-case QML property name (must start lower-case):\n%s\n' "$upper"; exit 1; }
# Static wiring no live probe replaces: async mountinfo poll, bookmarks pushed on arrival, null-guarded bridge reads.
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
have() { grep -qF "$2" "$tree/$1" || fail "$1 misses $2"; }
missing() { grep -qF "$2" "$tree/$1" && fail "$1 still carries $2"; }
missing ui/NetworkMounts.qml 'cloudFile.waitForJob()'
have ui/Sidebar.qml 'onServiceChanged: { root.arrive(); root.pushBookmarks() }'
missing ui/NetworkMounts.qml '|| bridge.flow.waiter'
# f036net: the host builds with the window again, so no gate orders it after rows.
missing ui/WindowBody.qml 'NetworkHostGate'
have ui/WindowBody.qml 'id: networkHost'
# Sample input: "    Loader {", "        id: networkHost", "        active: true", then "    }" closing the Loader.
body=$tree/ui/WindowBody.qml
id_line=$(grep -n 'id: networkHost$' "$body" | head -n 1 | cut -d: -f1)
[ -n "$id_line" ] || fail 'ui/WindowBody.qml has no networkHost id'
open_line=$(head -n "$id_line" "$body" | grep -n 'Loader {$' | tail -n 1 | cut -d: -f1)
[ -n "$open_line" ] || fail 'ui/WindowBody.qml has no Loader line above the networkHost id'
indent=$(sed -n "${open_line}p" "$body" | sed 's/Loader {$//')
host=$(tail -n +"$open_line" "$body" | sed "/^${indent}}\$/q")
printf '%s\n' "$host" | grep -q "^${indent}    id: networkHost\$" || fail 'ui/WindowBody.qml Loader read above the networkHost id is not the networkHost Loader'
printf '%s\n' "$host" | grep -q "^${indent}    active: true\$" || fail 'ui/WindowBody.qml networkHost Loader misses active: true'
printf '%s\n' "$host" | grep "^${indent}    asynchronous:" | grep -qv "asynchronous: false\$" && fail 'ui/WindowBody.qml networkHost Loader must not build asynchronously'
command -v qs >/dev/null 2>&1 || { printf 'lazy-objects: no qs here, live halves not run\n'; exit 0; }
test_root="$FIXTURE_ROOT/flea-lazy-objects-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root/home" "$test_root/bridge-config" "$test_root/swap-config"
ln -s "$tree/ui/NetworkMounts.qml" "$test_root/bridge-config/NetworkMounts.qml"
ln -s "$tree/ui/MountListing.qml" "$test_root/bridge-config/MountListing.qml"
ln -s "$tree/ui/NetworkPlaces.qml" "$test_root/bridge-config/NetworkPlaces.qml"
ln -s "$tree/ui/GvfsBridge.qml" "$test_root/bridge-config/GvfsBridge.qml"
ln -s "$tree/ui/js" "$test_root/bridge-config/js"
ln -s "$tree/tests/lazy-live.qml" "$test_root/bridge-config/shell.qml"
bridge_out=$(env HOME="$test_root/home" PATH="/usr/bin:/bin" QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 20 qs -p "$test_root/bridge-config" 2>&1)
printf '%s\n' "$bridge_out" | grep -q 'LAZY_OBJECTS bridge=absent-then-built served-on-same-call' || { printf 'FAIL bridge did not arrive whole on first use\n%s\n' "$bridge_out"; exit 1; }
printf '%s\n' "$bridge_out" | grep -q 'LAZY_OBJECTS FAIL' && { printf 'FAIL bridge live refused\n%s\n' "$bridge_out"; exit 1; }
printf 'lazy-objects: live bridge absent before first use, built and serving after\n'
# The same probe in a tree without GvfsBridge.qml: the ensure answers null and the
# request finishes failed naming that file, with no password retry.
mkdir -p "$test_root/absent-config"
ln -s "$tree/ui/NetworkMounts.qml" "$test_root/absent-config/NetworkMounts.qml"
ln -s "$tree/ui/MountListing.qml" "$test_root/absent-config/MountListing.qml"
ln -s "$tree/ui/NetworkPlaces.qml" "$test_root/absent-config/NetworkPlaces.qml"
ln -s "$tree/ui/js" "$test_root/absent-config/js"
ln -s "$tree/tests/lazy-live.qml" "$test_root/absent-config/shell.qml"
absent_out=$(env HOME="$test_root/home" PATH="/usr/bin:/bin" QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 LAZY_BRIDGE_ABSENT=1 timeout 20 qs -p "$test_root/absent-config" 2>&1)
printf '%s\n' "$absent_out" | grep -q 'LAZY_OBJECTS bridge-absent-fails-naming-file' || { printf 'FAIL missing bridge did not fail naming its file\n%s\n' "$absent_out"; exit 1; }
printf '%s\n' "$absent_out" | grep -q 'LAZY_OBJECTS FAIL' && { printf 'FAIL missing bridge live refused\n%s\n' "$absent_out"; exit 1; }
printf 'lazy-objects: missing bridge fails naming GvfsBridge.qml with no retry\n'
ln -s /usr/share/omarchy/shell/Commons "$test_root/swap-config/Commons"
ln -s /usr/share/omarchy/shell/Ui "$test_root/swap-config/Ui"
ln -s "$tree/tests/lazy-swap-live.qml" "$test_root/swap-config/shell.qml"
swap_out=$(env HOME="$test_root/home" PATH="/usr/bin:/bin" QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 LAZY_SWAP_UI="$tree/ui" timeout 20 qs -p "$test_root/swap-config" 2>&1)
printf '%s\n' "$swap_out" | grep -q 'LAZY_SWAP wrapper=absent-then-built' || { printf 'FAIL wrapper did not arrive whole on first open\n%s\n' "$swap_out"; exit 1; }
printf '%s\n' "$swap_out" | grep -q 'LAZY_SWAP FAIL' && { printf 'FAIL swap live refused\n%s\n' "$swap_out"; exit 1; }
printf 'lazy-objects: live wrapper absent before first open, whole after\n'
