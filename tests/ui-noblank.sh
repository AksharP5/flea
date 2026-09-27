# Defines the native listing-swap case; tests/ui.sh supplies the guarded fixture and IPC helpers.

# The stub's two late directories: 80 ms is inside Swap.js HOLD_MS and still swaps, 2.5 s outlasts the cap and its IPC reads.
noblank_held_delay_s=0.08
noblank_held_min_ms=80
noblank_slow_delay_s=2.5
# The cap is a QTimer, which may fire up to 5 percent early at this interval.
noblank_cap_min_ms=140

# One read of ui/PaneSwap.qml describe() through ui/Ipc.qml swapState, the record noblank_expect parses.
noblank_state() {
    ipc swapState
}

# A listing that has landed in whichever view is up: the path, the count, and nothing left in flight.
noblank_landed() {
    local want_path="$1" want_total="$2" path=unavailable total=unavailable flight=unavailable
    for _attempt in $(seq 1 300); do
        path=$(ipc path 2>/dev/null || printf unavailable)
        total=$(ipc total 2>/dev/null || printf unavailable)
        flight=$(ipc listInFlight 2>/dev/null || printf true)
        [[ "$path" == "$want_path" && "$total" == "$want_total" && "$flight" == false ]] && return 0
        sleep 0.05
    done
    fail "noblank: the listing never landed on $want_path with $want_total rows; path=$path total=$total inFlight=$flight"
}

# The two records either side of one navigation, held to a jq condition over $b (before) and $a (after).
# Sample input, each of $b and $a: {"holding":false,"fellBack":false,"holds":2,"fallbacks":0,"blankFrames":0,"loadingFrames":0,"last":{"ms":38,"end":"landed"}}
noblank_expect() {
    local name="$1" before="$2" after="$3" condition="$4"
    jq -e -n --argjson b "$before" --argjson a "$after" "$condition" >/dev/null \
        || fail "noblank: $name broke '$condition'; before $before after $after"
}

# One navigation, shot issued and landed: held for at least minimum ms, swapped before the cap, and no frame drawn with no row.
noblank_step() {
    local name="$1" want_path="$2" want_total="$3" minimum="$4" before after
    shift 4
    before=$(noblank_state)
    "$@" >/dev/null
    shot "noblank-$name-issued"
    noblank_landed "$want_path" "$want_total"
    shot "noblank-$name-landed"
    after=$(noblank_state)
    noblank_expect "$name" "$before" "$after" \
        "\$a.holds == \$b.holds + 1 and \$a.last.end == \"landed\" and \$a.last.ms >= $minimum
         and \$a.fallbacks == \$b.fallbacks and \$a.blankFrames == \$b.blankFrames and (\$a.holding | not)"
    printf 'NOBLANK %s held_ms=%s\n' "$name" "$(jq -r '.last.ms' <<< "$after")"
}

# The listing swap, AGENTS.md "The listing swap". Before it, opening a folder cleared the pane at the
# request and drew 3 to 4 frames of an empty list before the rows came back; the pane now holds the
# old rows until the new listing's rows land and swaps path, rows, cursor and selection in one turn.
# ui/PaneSwap.qml counts, from the window's own afterAnimating, every frame handed to the scene graph
# while a listing was out and the pane was drawn in the loading state, and the case requires that
# count not to move across Enter, a double click and BackSpace in a 300-file folder, in all three
# views. The stub backend below answers two directories late: one inside the cap, which must be held
# for its whole wait, and one past it, which must fall back to the loading state and is the control
# that proves the counter sees frames at all, since the loading frames it counts are drawn empty too.
case_noblank() {
    local dir="$fixture_root/noblank" bin="$fixture_root/noblank-bin" real_bin="$flea_bin" i
    local before after
    sandbox_scratch "$dir"
    mkdir -p "$dir/inner" "$dir/held" "$dir/slow"
    for i in $(seq -w 1 300); do printf 'x\n' > "$dir/inner/file-$i.txt"; done
    for i in $(seq -w 1 40); do printf 'x\n' > "$dir/outer-$i.txt"; printf 'x\n' > "$dir/held/held-$i.txt"; done
    for i in 1 2 3; do printf 'x\n' > "$dir/slow/slow-$i.txt"; done

    # A relay to the real binary that holds back the two late directories' list requests and ends on quit.
    sandbox_scratch "$bin"
    cat > "$bin/flea" <<'SH'
#!/usr/bin/env bash
set -u
[[ "${1:-}" == --backend ]] || exec "$NOBLANK_REAL_BIN" "$@"
while IFS= read -r line; do
    case "$line" in
        *'"c":"list"'*"\"path\":\"$NOBLANK_HELD\""*) sleep "$NOBLANK_HELD_DELAY" ;;
        *'"c":"list"'*"\"path\":\"$NOBLANK_SLOW\""*) sleep "$NOBLANK_SLOW_DELAY" ;;
    esac
    printf '%s\n' "$line"
    [[ "$line" == *'"c":"quit"'* ]] && break
done | "$NOBLANK_REAL_BIN" --backend
SH
    chmod +x "$bin/flea"

    seed_ui_state "$fixture_root/noblank-state" '{"keys":"default","view":"list"}'
    local -x NOBLANK_REAL_BIN="$real_bin" NOBLANK_HELD="$dir/held" NOBLANK_SLOW="$dir/slow"
    local -x NOBLANK_HELD_DELAY="$noblank_held_delay_s" NOBLANK_SLOW_DELAY="$noblank_slow_delay_s"
    flea_bin="$bin/flea"
    launch "$dir"
    flea_bin="$real_bin"
    # held, inner, slow, then outer-01 to outer-40.
    wait_listing 43
    settle
    printf 'NOBLANK launch %s\n' "$(noblank_state)"

    goto_row 1
    noblank_step enter "$dir/inner" 300 0 key -k Return
    noblank_step backspace "$dir" 43 0 key -k BackSpace
    # The parent listing put the cursor back on inner, row 1, which is the row the double click lands on.
    noblank_step doubleclick "$dir/inner" 300 0 click_row 1 left --double
    noblank_step doubleclick-back "$dir" 43 0 key -k BackSpace

    key k >/dev/null
    settle
    noblank_step held "$dir/held" 40 "$noblank_held_min_ms" key -k Return
    noblank_step held-back "$dir" 43 0 key -k BackSpace

    # Past the cap: held first, then the loading state at once rather than after its own hold-off.
    key j >/dev/null
    key j >/dev/null
    settle
    before=$(noblank_state)
    key -k Return >/dev/null
    shot noblank-slow-issued
    for _attempt in $(seq 1 100); do
        [[ "$(noblank_state | jq -r '.fellBack')" == true ]] && break
        sleep 0.05
    done
    [[ "$(ipc state)" == loading && "$(noblank_state | jq -r '.fellBack')" == true ]] \
        || fail "noblank: the late listing never fell back to the loading state; $(noblank_state), state $(ipc state)"
    shot noblank-slow-loading
    noblank_landed "$dir/slow" 3
    shot noblank-slow-landed
    after=$(noblank_state)
    noblank_expect slow "$before" "$after" \
        "\$a.holds == \$b.holds + 1 and \$a.fallbacks == \$b.fallbacks + 1 and \$a.last.end == \"expired\"
         and \$a.last.ms >= $noblank_cap_min_ms and \$a.blankFrames == \$b.blankFrames
         and \$a.loadingFrames > \$b.loadingFrames and (\$a.fellBack | not)"
    printf 'NOBLANK slow held_ms=%s loading_frames=%s\n' "$(jq -r '.last.ms' <<< "$after")" \
        "$(jq -n --argjson b "$before" --argjson a "$after" '$a.loadingFrames - $b.loadingFrames')"
    noblank_step slow-back "$dir" 43 0 key -k BackSpace

    key k >/dev/null
    settle
    switch_view grid
    noblank_step grid-enter "$dir/inner" 300 0 key -k Return
    noblank_step grid-back "$dir" 43 0 key -k BackSpace
    switch_view columns
    noblank_step columns-enter "$dir/inner" 300 0 key -k Return
    noblank_step columns-back "$dir" 43 0 key -k BackSpace
    switch_view list

    printf 'NOBLANK enter=ok doubleclick=ok backspace=ok held=ok slow=ok grid=ok columns=ok %s\n' "$(noblank_state)"
    kill_flea
}

# The preview swap, AGENTS.md "The preview swap". Before it, a cursor move drew the
# next preview half-built: v0.3.4 shows 145 to 151 mid frames over 18 column moves and
# 13 to 15 over 16 Quick Look moves headless. The column holds the old picture until
# the new preview is whole and falls back to loading past Swap.HOLD_MS; Quick Look
# holds in follow() the same way. This reads ui/Ipc.qml previewSwapState, the same
# record tests/preview-swap.sh judges headless: holds, fallbacks and midFrames.
case_previewswap() {
    local dir="$fixture_root/previewswap"
    sandbox_scratch "$dir"
    mkdir -p "$dir/0-folder"
    : > "$dir/a-image.jpg"
    : > "$dir/b-video.mp4"
    : > "$dir/c-doc.pdf"
    printf 'hello from flea\n' > "$dir/d-notes.txt"
    printf 'fn main() {}\n' > "$dir/e-main.rs"
    : > "$dir/f-report.odt"
    : > "$dir/g-font.ttf"
    : > "$dir/h-archive.zip"
    : > "$dir/i-photo.png"

    seed_ui_state "$fixture_root/previewswap-state" '{"keys":"default","view":"columns"}'
    launch "$dir"
    wait_listing 10
    settle
    [[ "$(ipc viewMode)" == columns ]] || fail "previewswap: fixture did not open its columns view"

    local before after before_mid after_mid
    before=$(ipc previewSwapState)
    # Walk the whole preview row: each j holds the old picture until the new one is whole.
    goto_row 0
    settle
    local i
    for i in $(seq 1 9); do
        key j >/dev/null
        settle
    done
    for i in $(seq 1 9); do
        key k >/dev/null
        settle
    done
    shot previewswap-column-landed
    after=$(ipc previewSwapState)
    before_mid=$(jq -r '.column.midFrames // 0' <<< "$before")
    after_mid=$(jq -r '.column.midFrames // 0' <<< "$after")
    [[ "$(jq -r '.column.holds // 0' <<< "$after")" -gt "$(jq -r '.column.holds // 0' <<< "$before")" ]] \
        || fail "previewswap: the column walk took no hold; before $before after $after"
    [[ "$after_mid" == "$before_mid" ]] \
        || fail "previewswap: the column walk drew $((after_mid - before_mid)) half-built frame(s); before $before after $after"
    printf 'PREVIEWSWAP column holds=%s mid=%s fallbacks=%s\n' \
        "$(jq -r '.column.holds' <<< "$after")" "$after_mid" "$(jq -r '.column.fallbacks' <<< "$after")"

    # Quick Look follows the cursor the same way: Space opens, j/k move under the held picture.
    goto_row 1
    settle
    key -k space >/dev/null
    settle
    [[ "$(ipc previewOpen)" == "true" ]] || fail "previewswap: space did not open Quick Look"
    before=$(ipc previewSwapState)
    key j >/dev/null
    settle
    key j >/dev/null
    settle
    key k >/dev/null
    settle
    shot previewswap-look-landed
    key -k Escape >/dev/null
    settle
    after=$(ipc previewSwapState)
    before_mid=$(jq -r '.look.midFrames // 0' <<< "$before")
    after_mid=$(jq -r '.look.midFrames // 0' <<< "$after")
    [[ "$(jq -r '.look.holds // 0' <<< "$after")" -gt "$(jq -r '.look.holds // 0' <<< "$before")" ]] \
        || fail "previewswap: Quick Look took no hold across its moves; before $before after $after"
    [[ "$after_mid" == "$before_mid" ]] \
        || fail "previewswap: Quick Look drew $((after_mid - before_mid)) half-built frame(s); before $before after $after"
    printf 'PREVIEWSWAP look holds=%s mid=%s fallbacks=%s\n' \
        "$(jq -r '.look.holds' <<< "$after")" "$after_mid" "$(jq -r '.look.fallbacks' <<< "$after")"

    printf 'PREVIEWSWAP column=ok look=ok %s\n' "$(ipc previewSwapState)"
    kill_flea
}
