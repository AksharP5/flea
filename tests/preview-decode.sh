#!/bin/bash
# The Columns preview as v0.3.4 drew it (the cache file, the original only where none exists) and Quick Look's decode, offscreen; see AGENTS.md "File budget".
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

for tool in qs magick exiv2 inotifywait; do
    command -v "$tool" >/dev/null || { echo "preview-decode.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root="$SANDBOX_ROOT/flea-preview-decode-$$"
sandbox_make "$test_root"
cleanup() {
    local result=$?
    trap - EXIT
    [ -n "${watcher:-}" ] && kill "$watcher" 2>/dev/null
    wait 2>/dev/null
    # A failed run keeps its root, so every log path a FAIL line prints still points at a file.
    if [ "$result" -ne 0 ]; then
        printf 'preview-decode: keeping %s\n' "$test_root"
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
log="$test_root/preview.log"
watchlog="$test_root/watch.log"
mkdir -p "$config_dir" "$photos" "$runtime" || exit 1
chmod 700 "$runtime" || exit 1
ln -s "$PWD/tests/preview-decode.qml" "$config_dir/shell.qml" || exit 1
ln -s /usr/share/omarchy/shell/Commons "$config_dir/Commons" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$config_dir/Ui" || exit 1

# Fifty sweep photos with a cache file each, the 6016x3900 PNG rest row and a text start row; only open events are counted, never pixels.
printf 'preview decode rest row, not an image\n' > "$photos/note.txt" \
    || { echo "preview-decode.sh: text fixture generation failed"; exit 1; }
magick -size 640x480 plasma:fractal -seed 3 "$photos/seed0.jpg" \
    || { echo "preview-decode.sh: seed generation failed"; exit 1; }
magick -size 640x480 plasma:fractal -seed 11 "$photos/seed1.jpg" \
    || { echo "preview-decode.sh: seed generation failed"; exit 1; }
magick "$photos/seed0.jpg" -resize 256x "$photos/thumb.png" \
    || { echo "preview-decode.sh: thumbnail generation failed"; exit 1; }
magick -size 6016x3900 xc:gray50 -fill black -draw 'rectangle 0,0 3007,3899' "$photos/big.png" \
    || { echo "preview-decode.sh: rest-row generation failed"; exit 1; }
for i in $(seq 0 49); do
    cp "$photos/seed$((i % 2)).jpg" "$photos/s$i.jpg" || exit 1
    cp "$photos/thumb.png" "$photos/t$i.png" || exit 1
done
cp "$photos/thumb.png" "$photos/t50.png" || exit 1

# Quick Look's three: 600x400 pixels exiv2 marks RightTop (EXIF 6), since magick writes no EXIF block; a banner; a PNG smaller than any box.
magick -size 600x400 gradient:white-black "$photos/portrait.jpg" \
    && exiv2 -M"set Exif.Image.Orientation Short 6" "$photos/portrait.jpg" \
    || { echo "preview-decode.sh: portrait generation failed"; exit 1; }
[ "$(magick identify -format '%[orientation]' "$photos/portrait.jpg")" = RightTop ] \
    || { echo "preview-decode.sh: the portrait fixture carries no EXIF turn"; exit 1; }
magick -size 3000x100 xc:gray60 "$photos/banner.png" \
    || { echo "preview-decode.sh: banner generation failed"; exit 1; }
magick -size 120x68 xc:gray40 "$photos/small.png" \
    || { echo "preview-decode.sh: small fixture generation failed"; exit 1; }

# Sample input: 'OPEN|t12.png' is a cache file, 'OPEN|s12.jpg' or 'OPEN|big.png' an original, 'CREATE|sentinel-rest' a phase boundary.
inotifywait -m -e open -e create --format '%e|%f' "$photos" > "$watchlog" 2>&1 &
watcher=$!

( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root" XDG_RUNTIME_DIR="$runtime" TMPDIR="$test_root" \
    XDG_CONFIG_HOME="$test_root/.config" XDG_STATE_HOME="$test_root/.local/state" XDG_CACHE_HOME="$test_root/.cache" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 \
    QT_FORCE_STDERR_LOGGING=1 \
    PREVIEW_UI="$PWD/ui" PREVIEW_PHOTOS="$photos" \
    timeout 120 qs -p "$config_dir" > "$log" 2>&1 )
status=$?
# The watch outlives qs by a breath so its last events flush before it is read.
sleep 1
kill "$watcher" 2>/dev/null
watcher=""
wait 2>/dev/null

if grep -q 'PREVIEW FAIL' "$log" || ! grep -q 'PREVIEW DONE' "$log"; then
    bad "the harness did not finish (qs exit $status): $(grep -a 'PREVIEW FAIL' "$log" | head -1) (log $log)"
else
    # Sample input, one inotifywait line per event: 'OPEN|t50.png' is the rest row's cache file and 'CREATE|sentinel-rest' opens the rest window once the sweep one closes.
    got_sweep=0; got_rest=0; got_done=0; phase=0
    sweep_opens=0; sweep_names=""; rest_big=0; rest_cache=0; rest_sweep=0
    events=""; name=""
    while IFS='|' read -r events name || [ -n "$events" ]; do
        case "$events" in
        *CREATE*)
            if [ "$name" = "sentinel-sweep" ]; then phase=1; got_sweep=1
            elif [ "$name" = "sentinel-rest" ]; then [ "$phase" -eq 1 ] && phase=2; got_rest=1
            elif [ "$name" = "sentinel-done" ]; then [ "$phase" -eq 2 ] && phase=3; got_done=1
            fi
            ;;
        *OPEN*)
            # v0.3.4's settle outlasts a 30 ms repeat, so a sweep loads no row: any open but a sentinel's own is a load.
            if [ "$phase" -eq 1 ]; then
                case "$name" in
                sentinel-*) ;;
                *) sweep_opens=$((sweep_opens + 1)); [ "$sweep_opens" -le 3 ] && sweep_names="$sweep_names $name" ;;
                esac
            elif [ "$phase" -eq 2 ]; then
                case "$name" in
                big.png) rest_big=$((rest_big + 1)) ;;
                t50.png) rest_cache=$((rest_cache + 1)) ;;
                s*.jpg) rest_sweep=$((rest_sweep + 1)) ;;
                esac
            fi
            ;;
        esac
    done < "$watchlog"
    if [ "$got_sweep" != 1 ] || [ "$got_rest" != 1 ] || [ "$got_done" != 1 ]; then
        bad "a phase sentinel never arrived (sweep=$got_sweep rest=$got_rest done=$got_done) (log $log)"
    else
        if [ "$sweep_opens" -eq 0 ]; then
            ok "50 moves at key-repeat rate opened no file at all, cache file or original"
        else
            bad "the sweep opened $sweep_opens file(s), first:$sweep_names (log $log)"
        fi
        if [ "$rest_cache" -ge 1 ]; then
            ok "a rest drew the rested row's cache file"
        else
            bad "the rest never opened t50.png, so the column drew nothing of the row (log $log)"
        fi
        if [ "$rest_big" -eq 0 ] && [ "$rest_sweep" -eq 0 ]; then
            ok "and opened no original, the way v0.3.4 drew the column"
        else
            bad "the rest opened big.png $rest_big time(s) and sweep rows $rest_sweep time(s) (log $log)"
        fi
    fi
    # Sample input: 'PREVIEW QL portrait decoded=400x600 drawn=314x471'; Qt decodes a turned photo whole when its stored size fits the box.
    portrait=$(sed -n 's/.*PREVIEW QL portrait decoded=\([0-9]*x[0-9]*\) drawn=\([0-9]*x[0-9]*\).*/\1 \2/p' "$log")
    case "$portrait" in
        "400x600 314x471") ok "Quick Look draws an EXIF-turned photo upright at the exact fit, 314x471" ;;
        *) bad "Quick Look drew the portrait as '$portrait', not 400x600 upright drawn at 314x471 (log $log)" ;;
    esac
    # 3000x100 at the box's width is 754x25; Fit decoded the covering 14130x471 instead.
    banner=$(sed -n 's/.*PREVIEW QL banner decoded=\([0-9]*x[0-9]*\) drawn=\([0-9]*x[0-9]*\).*/\1 \2/p' "$log")
    case "$banner" in
        "754x25 754x25") ok "and decodes a 3000x100 banner at the exact fit, 754x25" ;;
        *) bad "Quick Look drew the banner as '$banner', not 754x25 decoded and drawn (log $log)" ;;
    esac
    small=$(sed -n 's/.*PREVIEW QL small decoded=\([0-9]*x[0-9]*\) drawn=\([0-9]*x[0-9]*\).*/\1 \2/p' "$log")
    case "$small" in
        "120x68 120x68") ok "and a 120x68 PNG at its own size, never enlarged" ;;
        *) bad "Quick Look drew the small PNG as '$small', not 120x68 (log $log)" ;;
    esac
fi

printf 'preview-decode: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
