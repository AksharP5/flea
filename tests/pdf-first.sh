#!/bin/bash
# A turn before the first page lands must leave the cap alone and still land the turned-to page; offscreen, so no display and no lock.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

for tool in qs magick; do
    command -v "$tool" >/dev/null || { echo "pdf-first.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_forbidden /tmp && sandbox_refuse "pdf-first: /tmp is inside a forbidden test target"
first_root=$(mktemp -d /tmp/flea-pdf-first.XXXXXXXX) || exit 1
FIXTURE_ROOT=$first_root
sandbox_root_ok
first_root=$SANDBOX_ROOT
readonly first_root
printf 'Flea PDF first sandbox\n' > "$first_root/$SANDBOX_MARKER" || exit 1
first_work="$first_root/work"
readonly first_work
cleanup() {
    local result=$?
    trap - EXIT
    # sandbox_remove verifies an absolute, non-empty path contained in this run's marked root before rm.
    sandbox_remove "$first_work"
    # A failed run keeps its root, so the log path each FAIL line prints still points at a file.
    [ "$result" -ne 0 ] && exit "$result"
    # The marker goes last, because it is what stands between this directory and rm.
    sandbox_remove "$first_root/column.log"
    sandbox_remove "$first_root/$SANDBOX_MARKER"
    [ -z "$(ls -A "$first_root")" ] && rmdir "$first_root"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sandbox_scratch "$first_work"
mkdir -p "$first_work"/{config,home,runtime,tmp} || exit 1
chmod 700 "$first_work/runtime" || exit 1
ln -s "$PWD/tests/pdf-first.qml" "$first_work/config/shell.qml" || exit 1
ln -s /usr/share/omarchy/shell/Commons "$first_work/config/Commons" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$first_work/config/Ui" || exit 1

# Two pages: a 54-megapixel noise JPEG that renders past any turn, then a light page that lands at once.
pdf="$first_work/first.pdf"
magick \( -size 6600x8250 xc:gray50 +noise Random -fill black -draw 'rectangle 0,0 6599,6187' -quality 80 \) \
       \( -size 2400x3000 xc:white -fill black -draw 'rectangle 0,0 2399,449' \) \
       -compress jpeg "$pdf" || { echo "pdf-first.sh: fixture generation failed"; exit 1; }

log="$first_root/column.log"
# Software rendering offscreen; the harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$first_work/home" XDG_RUNTIME_DIR="$first_work/runtime" TMPDIR="$first_work/tmp" \
    XDG_CONFIG_HOME="$first_work/home/.config" XDG_STATE_HOME="$first_work/home/.local/state" \
    XDG_CACHE_HOME="$first_work/home/.cache" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 \
    QT_FORCE_STDERR_LOGGING=1 \
    PDF_FIRST_UI="$PWD/ui" PDF_FIRST_PDF="$pdf" \
    timeout 30 qs -p "$first_work/config" > "$log" 2>&1; exit $? ) 2>/dev/null
status=$?
if grep -q 'PDFFIRST FAIL' "$log" || ! grep -q 'PDFFIRST DONE' "$log"; then
    bad "the harness did not finish (qs exit $status): $(grep -a 'PDFFIRST FAIL' "$log" | head -1) (log $log)"
else
    # Sample input: 'PDFFIRST TURN page=1 shown=-1 fellBack=0', the state at the moment of the turn.
    turn_line=$(grep -a -m1 'PDFFIRST TURN' "$log")
    case "$turn_line" in
    *shown=-1*) ok "the turn left while the first render was still in flight" ;;
    *) bad "the turn found a page already shown: $turn_line (log $log)" ;;
    esac
    # Every state with no page shown must carry fellBack=0: the cap never stood in for a page never drawn.
    bad_states=$(grep -a 'PDFFIRST STATE.*shown=-1' "$log" | grep -av 'fellBack=0' || true)
    if [ -z "$bad_states" ]; then
        ok "fellBack never stood in while no page was shown"
    else
        bad "fellBack stood in with no page shown: $(printf '%s' "$bad_states" | head -1) (log $log)"
    fi
    if grep -aq 'PDFFIRST STATE.*shown=1' "$log"; then
        ok "the turned-to page landed"
    else
        bad "the turned-to page never showed (log $log)"
    fi
fi

printf 'pdf-first: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
