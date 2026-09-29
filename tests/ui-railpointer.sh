#!/usr/bin/env bash
# Sourced by ui.sh; a listing click takes the keyboard back from the rail.
# shellcheck disable=SC2154 # ui.sh supplies the fixture root and the native driver helpers.
case_railpointer() {
    local dir="$fixture_root/railpointer" mode before after suite_home="$XDG_STATE_HOME"
    sandbox_scratch "$dir"
    local i
    for i in $(seq -w 1 12); do : > "$dir/f$i.txt"; done
    launch "$dir"
    wait_listing 12
    for mode in list grid columns; do
        switch_view "$mode"
        click_row 5 left
        settle
        key -k Tab >/dev/null
        settle
        [[ "$(ipc focusView)" == "rail" ]] || fail "railpointer: $mode: Tab did not reach the rail"
        click_row 8 left
        settle
        [[ "$(ipc focusView)" == "list" ]] || fail "railpointer: $mode: a click on row 8 left the keyboard on the rail (focusView=$(ipc focusView))"
        [[ "$(ipc cursor)" == "8" ]] || fail "railpointer: $mode: a click on row 8 left the cursor on $(ipc cursor)"
        before=$(ipc cursor)
        key j >/dev/null
        settle
        after=$(ipc cursor)
        [[ "$after" != "$before" ]] || fail "railpointer: $mode: j after a row click stayed on $before"
        key -k Tab >/dev/null
        settle
        click_row 8 right
        settle
        key -k Escape >/dev/null
        settle
        [[ "$(ipc focusView)" == "list" ]] || fail "railpointer: $mode: a right click plus Escape left the keyboard on the rail (focusView=$(ipc focusView))"
        before=$(ipc cursor)
        key j >/dev/null
        settle
        after=$(ipc cursor)
        [[ "$after" != "$before" ]] || fail "railpointer: $mode: j after right click stayed on $before"
        printf 'RAILPOINTER %s left=ok right=ok\n' "$mode"
    done
    # A press on the revealed auto-hide rail is a rail press, so it keeps the rail keyboard.
    seed_ui_state "$fixture_root/railpointer-hide" '{"view":"list","places":{"autoHide":true}}'
    launch "$dir"
    wait_listing 12
    key -k Tab >/dev/null
    settle
    [[ "$(ipc focusView)" == "rail" ]] || fail "railpointer: auto-hide Tab did not reach the rail"
    wait_rail 1
    local wx wy wh
    read -r wx wy _ww wh < <(window_box) || fail "railpointer: native window coordinates unavailable"
    omarchy-drive move "$((wx + 1))" "$((wy + wh / 2))" >/dev/null
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x 1 -y 0 >/dev/null 2>&1
    settle
    click_rail_row 0 left
    settle
    [[ "$(ipc focusView)" == "rail" ]] || fail "railpointer: a press on the revealed rail left the keyboard on $(ipc focusView)"
    printf 'RAILPOINTER autohide=ok\n'
    # In dual view Tab still switches panes, and a row click focuses that pane with the list keyboard.
    local dual="$fixture_root/railpointer-dual" dstate="$fixture_root/railpointer-dual-state" rect rx ry rw rh cx cy ww hh dual_json
    sandbox_scratch "$dual"
    mkdir -p "$dual/left" "$dual/right"
    for i in $(seq -w 1 6); do : > "$dual/left/l$i.txt"; : > "$dual/right/r$i.txt"; done
    seed_ui_state "$dstate" "$(jq -cn --arg l "$dual/left" --arg r "$dual/right" '{view:"dual",dual:{paths:[$l,$r],focus:0}}')"
    launch "$dual/left"
    for _attempt in $(seq 1 100); do
        dual_json=$(ipc dualState)
        [[ "$(jq -r '[.panes[].loading] | any' <<< "$dual_json")" == false ]] && break
        sleep 0.05
    done
    ipc dualState | jq -e '.active and .focused == 0' >/dev/null || fail "railpointer: dual did not open focused on pane 0"
    key -k Tab >/dev/null
    settle
    ipc dualState | jq -e '.focused == 1' >/dev/null || fail "railpointer: dual Tab did not switch panes"
    rect=$(ipc dragPaneGeometry 0 0 | jq -er '.folder.rect')
    read -r rx ry rw rh <<< "$rect"
    read -r wx wy ww hh < <(window_box) || fail "railpointer: native window coordinates unavailable"
    omarchy-drive click "$((wx + rx + rw / 2))" "$((wy + ry + rh / 2))" left >/dev/null
    settle
    ipc dualState | jq -e '.focused == 0' >/dev/null || fail "railpointer: a row click on the other pane left focus on pane $(ipc dualState | jq -r '.focused')"
    [[ "$(ipc focusView)" == "list" ]] || fail "railpointer: a row click on the other pane left the keyboard on $(ipc focusView)"
    printf 'RAILPOINTER dual=ok\n'
    export XDG_STATE_HOME="$suite_home"
    kill_flea
}
