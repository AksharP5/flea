#!/usr/bin/env bash
# p036lazy: the launch builds neither the GVFS bridge nor Quick Look's swap wrapper, and both
# arrive whole on first use. Static wiring checks run everywhere; the offscreen live probe of
# the bridge Loader needs qs and runs wherever one is installed.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
# Optional $1 checks another tree, so the red half runs against an export of the base commit.
tree=${1:-$PWD}

failures=0
static=0
fail() { printf 'FAIL %s\n' "$*"; failures=1; }
have() { static=$((static + 1)); grep -qF "$2" "$tree/$1" || fail "$1 misses $2"; }
missing() { static=$((static + 1)); grep -qF "$2" "$tree/$1" && fail "$1 still carries $2"; }

# 1. The bridge arrives through a Loader with a source: URL on the first ensure, never at launch.
have ui/NetworkMounts.qml 'source: "GvfsBridge.qml"'
have ui/NetworkMounts.qml 'function ensureBridge()'
have ui/NetworkMounts.qml 'readonly property bool bridgeBuilt'
missing ui/NetworkMounts.qml '    GvfsBridge {'
# 1b. Every reader null-guards it, including the poll-hold line the brief names.
have ui/NetworkMounts.qml 'root.bridgeWaiting'
missing ui/NetworkMounts.qml '|| bridge.flow.waiter'
# 3. The five second poll answers unchanged text with no reparse.
have ui/NetworkMounts.qml 'function pollAnswered()'
have ui/NetworkMounts.qml '_lastMountinfo'
# 2. The host waits for the primary pane's first rows, with a fallback for a listing that never lands.
have ui/WindowBody.qml 'function orderNetworkHost()'
have ui/WindowBody.qml 'networkHostFallback'
missing ui/Sidebar.qml 'meetHost() { if (root.navigationPane)'
have ui/Sidebar.qml 'onServiceChanged: { root.arrive(); root.pushBookmarks() }'
# 3b. The poll's mountinfo read never blocks the GUI thread.
missing ui/NetworkMounts.qml 'cloudFile.waitForJob()'
# 5. Quick Look's panes stay eager while only the swap wrapper waits for the first open.
have ui/Preview.qml 'source: "QuickLookSwap.qml"'
have ui/Preview.qml 'function ensureSwap()'
have ui/Preview.qml 'readonly property bool swapBuilt'
missing ui/Preview.qml 'Flea.PreviewSwap {'
have ui/QuickLookSwap.qml 'captureSource: panesSource'
have ui/PreviewSwap.qml 'property Item captureSource'
have ui/qmldir 'QuickLookSwap 1.0 QuickLookSwap.qml'

if [ "$failures" -ne 0 ]; then
    exit 1
fi
printf 'lazy-objects: %d static wiring checks hold\n' "$static"

# Live half: the Loader answers item on the same call that sets active, and a local path is
# ready on that same ensure with no bridge start. Needs qs; anywhere without one keeps the static verdict.
command -v qs >/dev/null 2>&1 || { printf 'lazy-objects: no qs here, live probe not run\n'; exit 0; }

test_root="$FIXTURE_ROOT/flea-lazy-objects-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/home" "$test_root/config"
ln -s "$PWD/ui/NetworkMounts.qml" "$test_root/config/NetworkMounts.qml"
ln -s "$PWD/ui/MountListing.qml" "$test_root/config/MountListing.qml"
ln -s "$PWD/ui/NetworkPlaces.qml" "$test_root/config/NetworkPlaces.qml"
ln -s "$PWD/ui/GvfsBridge.qml" "$test_root/config/GvfsBridge.qml"
ln -s "$PWD/ui/js" "$test_root/config/js"
ln -s "$PWD/tests/lazy-live.qml" "$test_root/config/shell.qml"

output=$(env \
    HOME="$test_root/home" \
    PATH="/usr/bin:/bin" \
    QT_QPA_PLATFORM=offscreen \
    QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

pass_count=$(printf '%s\n' "$output" | grep -c 'LAZY_OBJECTS bridge=absent-then-built served-on-same-call')
fail_count=$(printf '%s\n' "$output" | grep -c 'LAZY_OBJECTS FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the lazy bridge did not arrive whole on first use\n%s\n' "$output"
    exit 1
fi

printf 'lazy-objects: live bridge absent before first use, built and serving after\n'
