#!/usr/bin/env bash
# The columns child hero survives a cursor-only move onto an empty folder.
# Runs headless under qml6, no Quickshell and no display; the swap's own timing
# stays in preview-swap.sh, this is the re-move wiring tests/colhero.qml drives.
set -u
cd "$(dirname "$0")/.." || exit 1

command -v qml6 >/dev/null || { echo "colhero: qml6 is not installed"; exit 1; }
out=$(QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    timeout 120 qml6 tests/colhero.qml 2>&1)
code=$?
printf '%s\n' "$out" | grep -a 'COLHERO ' || true
[ "$code" -eq 0 ] || { echo "colhero: qml6 did not finish"; exit 1; }
printf '%s' "$out" | grep -aq 'COLHERO PASS' || { echo "colhero: no PASS line, nothing ran"; exit 1; }
