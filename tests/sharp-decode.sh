#!/bin/bash
# The preview column's sharp original, driven through the real ui/SelectionPreview.qml offscreen:
# a sweep of 50 cursor moves at key-repeat rate must open no original, and a rest on a 6016x3900
# PNG must decode it exactly once. Decodes are counted from outside the column, as open events on
# the fixture directory between touch sentinel files the harness drops at each phase boundary, so
# windows follow the event stream's own order instead of comparing two clocks. One decode opens its
# original several times over, so the rest counts decode episodes, runs of big.png opens unbroken by
# any other event, and demands exactly one; a second decode lands its own run and reddens. The same
# instrument runs on the base commit too: this pins the product path, it is not a fix. Offscreen, so
# it needs no display and no lock.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

for tool in qs magick inotifywait; do
    command -v "$tool" >/dev/null || { echo "sharp-decode.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root="$SANDBOX_ROOT/flea-sharp-decode-$$"
sandbox_make "$test_root"
cleanup() {
    local result=$?
    trap - EXIT
    [ -n "${watcher:-}" ] && kill "$watcher" 2>/dev/null
    wait 2>/dev/null
    # A failed run keeps its root, so every log path a FAIL line prints still points at a file.
    if [ "$result" -ne 0 ]; then
        printf 'sharp-decode: keeping %s\n' "$test_root"
        exit "$result"
    fi
    sandbox_remove "$test_root"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

config_dir="$test_root/config"
photos="$test_root/photos"
runtime="$test_root/runtime"
log="$test_root/sharp.log"
watchlog="$test_root/watch.log"
mkdir -p "$config_dir" "$photos" "$runtime" || exit 1
chmod 700 "$runtime" || exit 1
ln -s "$PWD/tests/sharp-decode.qml" "$config_dir/shell.qml" || exit 1
ln -s /usr/share/omarchy/shell/Commons "$config_dir/Commons" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$config_dir/Ui" || exit 1

# Fifty sweep photos as copies of two seeds, one shared 256 px thumbnail each, the 6016x3900 PNG
# rest row, and a text row the initial selection loads so nothing image-like opens before the
# sweep. Content is irrelevant: only open events are counted, never pixels.
printf 'sharp decode rest row, not an image\n' > "$photos/note.txt" \
    || { echo "sharp-decode.sh: text fixture generation failed"; exit 1; }
magick -size 640x480 plasma:fractal -seed 3 "$photos/seed0.jpg" \
    || { echo "sharp-decode.sh: seed generation failed"; exit 1; }
magick -size 640x480 plasma:fractal -seed 11 "$photos/seed1.jpg" \
    || { echo "sharp-decode.sh: seed generation failed"; exit 1; }
magick "$photos/seed0.jpg" -resize 256x "$photos/thumb.png" \
    || { echo "sharp-decode.sh: thumbnail generation failed"; exit 1; }
magick -size 6016x3900 xc:gray50 -fill black -draw 'rectangle 0,0 3007,3899' "$photos/big.png" \
    || { echo "sharp-decode.sh: rest-row generation failed"; exit 1; }
for i in $(seq 0 49); do
    cp "$photos/seed$((i % 2)).jpg" "$photos/s$i.jpg" || exit 1
    cp "$photos/thumb.png" "$photos/t$i.png" || exit 1
done
cp "$photos/thumb.png" "$photos/t50.png" || exit 1

# Sample input: 'OPEN|s12.jpg'. Thumbnails start with t, sentinels with sentinel-, and note.txt is
# the text row the preview reads as text, so only an s photo or big.png is a sharp decode.
inotifywait -m -e open -e create --format '%e|%f' "$photos" > "$watchlog" 2>&1 &
watcher=$!

( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root" XDG_RUNTIME_DIR="$runtime" TMPDIR="$test_root" \
    XDG_CONFIG_HOME="$test_root/.config" XDG_STATE_HOME="$test_root/.local/state" XDG_CACHE_HOME="$test_root/.cache" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 \
    QT_FORCE_STDERR_LOGGING=1 \
    SHARP_UI="$PWD/ui" SHARP_PHOTOS="$photos" \
    timeout 120 qs -p "$config_dir" > "$log" 2>&1 )
status=$?
# The watch is killed only once qs is gone, plus a breath so its last events flush: nothing after
# the done sentinel can enter a window, and nothing before it is still unread.
sleep 1
kill "$watcher" 2>/dev/null
watcher=""
wait 2>/dev/null

if grep -q 'SHARP FAIL' "$log" || ! grep -q 'SHARP DONE' "$log"; then
    bad "the harness did not finish (qs exit $status): $(grep -a 'SHARP FAIL' "$log" | head -1) (log $log)"
else
    # The three sentinels in order open the sweep and rest windows; delivery is causal, so every
    # event of a window is already in the log once its closing sentinel is read.
    # Sample input, one inotifywait line per event: 'OPEN|s12.jpg' opens a sharp original, while
    # 'CREATE|sentinel-rest' closes the sweep window and opens the rest one; thumbnails start with
    # t, sentinels with sentinel-, and note.txt is the text row, so only an s photo or big.png is a
    # sharp decode, and only a run of big.png opens unbroken by any other line is one decode episode.
    got_sweep=0; got_rest=0; got_done=0; phase=0
    sweep_opens=0; rest_big=0; rest_episodes=0; rest_sweep=0; in_big_run=0
    events=""; name=""
    while IFS='|' read -r events name || [ -n "$events" ]; do
        case "$events" in
        *CREATE*)
            if [ "$name" = "sentinel-sweep" ]; then phase=1; got_sweep=1; in_big_run=0
            elif [ "$name" = "sentinel-rest" ]; then [ "$phase" -eq 1 ] && phase=2; got_rest=1; in_big_run=0
            elif [ "$name" = "sentinel-done" ]; then [ "$phase" -eq 2 ] && phase=3; got_done=1
            fi
            ;;
        *OPEN*)
            if [ "$phase" -eq 1 ]; then
                case "$name" in
                s*.jpg|big.png) sweep_opens=$((sweep_opens + 1)) ;;
                esac
                in_big_run=0
            elif [ "$phase" -eq 2 ]; then
                if [ "$name" = "big.png" ]; then
                    rest_big=$((rest_big + 1))
                    if [ "$in_big_run" -eq 0 ]; then rest_episodes=$((rest_episodes + 1)); in_big_run=1; fi
                else
                    in_big_run=0
                    case "$name" in
                    s*.jpg) rest_sweep=$((rest_sweep + 1)) ;;
                    esac
                fi
            fi
            ;;
        *) in_big_run=0 ;;
        esac
    done < "$watchlog"
    if [ "$got_sweep" != 1 ] || [ "$got_rest" != 1 ] || [ "$got_done" != 1 ]; then
        bad "a phase sentinel never arrived (sweep=$got_sweep rest=$got_rest done=$got_done) (log $log)"
    else
        if [ "$sweep_opens" -eq 0 ]; then
            ok "50 moves at key-repeat rate opened no original"
        else
            bad "the sweep opened $sweep_opens original(s) (log $log)"
        fi
        if [ "$rest_episodes" -eq 1 ] && [ "$rest_sweep" -eq 0 ]; then
            ok "a rest decoded exactly the rested original ($rest_big open event(s) in one decode)"
        else
            bad "the rest opened big.png $rest_big time(s) in $rest_episodes decode(s) and sweep rows $rest_sweep time(s) (log $log)"
        fi
    fi
fi

printf 'sharp-decode: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
