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
        [[ "$(ipc focusView)" == "rail" ]] || fail "railpointer: $mode: the second Tab did not reach the rail (focusView=$(ipc focusView))"
        click_row 8 right
        settle
        [[ "$(ipc focusView)" == "list" ]] || fail "railpointer: $mode: a right click left the keyboard on $(ipc focusView) instead of returning it to the list"
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
    # A press on the revealed auto-hide rail is a rail press, so it takes the rail keyboard even from the list.
    seed_ui_state "$fixture_root/railpointer-hide" '{"view":"list","places":{"autoHide":true}}'
    launch "$dir"
    wait_listing 12
    key -k Tab >/dev/null
    settle
    [[ "$(ipc focusView)" == "rail" ]] || fail "railpointer: auto-hide Tab did not reach the rail"
    wait_rail 1
    local rail_total
    rail_total=$(ipc railCount)
    [[ "$rail_total" =~ ^[0-9]+$ ]] || fail "railpointer: the revealed rail has no numeric count (railCount=$rail_total railState=$(ipc railState))"
    (( rail_total >= 2 )) || fail "railpointer: the revealed rail has $rail_total rows, need two for the landed-press proof (railState=$(ipc railState))"
    # Rail j still steps before the pointer path.
    if [[ "$(ipc railCursor)" == "0" ]]; then
        key j >/dev/null
        settle
        [[ "$(ipc railCursor)" != "0" ]] || fail "railpointer: j never left rail row 0 (railCount=$rail_total)"
    fi
    # Return focus to the list; the hide unloads the rail Loader and resets its cursor.
    key -k Tab >/dev/null
    settle
    [[ "$(ipc focusView)" == "list" ]] || fail "railpointer: Tab back to the list left the keyboard on $(ipc focusView) instead of the list"
    local hid=false hid_json
    for _attempt in $(seq 1 60); do
        hid_json=$(ipc railState)
        [[ "$(jq -r '.hidden' 2>/dev/null <<< "$hid_json")" == "true" ]] && { hid=true; break; }
        sleep 0.05
    done
    [[ "$hid" == true ]] || fail "railpointer: the rail never hid before the reveal (railState=$hid_json)"
    # Without these the reveal gesture below is silent, and the rail assertions after it are vacuous.
    command -v ydotool >/dev/null || fail "railpointer: no ydotool on PATH, so the auto-hide rail cannot be revealed"
    [[ -S "${XDG_RUNTIME_DIR:-}/.ydotool_socket" ]] || fail "railpointer: no ydotool socket at ${XDG_RUNTIME_DIR:-}/.ydotool_socket, so the auto-hide rail cannot be revealed"
    local wx wy wh
    read -r wx wy _ww wh < <(window_box) || fail "railpointer: native window coordinates unavailable"
    omarchy-drive move "$((wx + 1))" "$((wy + wh / 2))" >/dev/null || fail "railpointer: the pointer move to the left edge failed, so the rail never revealed"
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x 1 -y 0 >/dev/null || fail "railpointer: ydotool mousemove failed, so the rail never revealed"
    settle
    # The rail Loader unloads while hidden, so a polled hidden=false proves the reveal happened.
    local revealed=false rail_json
    for _attempt in $(seq 1 60); do
        rail_json=$(ipc railState)
        [[ "$(jq -r '.hidden' 2>/dev/null <<< "$rail_json")" == "false" ]] && { revealed=true; break; }
        sleep 0.05
    done
    [[ "$revealed" == true ]] || fail "railpointer: the auto-hide rail never revealed (railState=$rail_json)"
    # Real mouse path: the pointer reveals while the keyboard stays in the list.
    [[ "$(ipc focusView)" == "list" ]] || fail "railpointer: the pointer reveal left the keyboard on $(ipc focusView) instead of the list"
    [[ "$(jq -r '.hidden' 2>/dev/null <<< "$(ipc railState)")" == "false" ]] || fail "railpointer: the rail is not shown before the press (railState=$(ipc railState))"
    # A hide unloads the rail Loader and resets its cursor to 0, so press the row it does not hold.
    local rail_before rail_target
    rail_before=$(ipc railCursor)
    [[ "$rail_before" =~ ^[0-9]+$ ]] || fail "railpointer: the revealed rail has no numeric cursor (railCursor=$rail_before)"
    if [[ "$rail_before" == "0" ]]; then rail_target=1; else rail_target=0; fi
    [[ -n "$(ipc railRowCentre "$rail_target")" ]] || fail "railpointer: rail row $rail_target has no on-screen centre while revealed, so the press has no target"
    click_rail_row "$rail_target" left
    settle
    [[ "$(ipc railCursor)" == "$rail_target" ]] || fail "railpointer: a press on revealed rail row $rail_target left the rail cursor on $(ipc railCursor) (was $rail_before)"
    [[ "$(ipc focusView)" == "rail" ]] || fail "railpointer: a press on the revealed rail left the keyboard on $(ipc focusView)"
    printf 'RAILPOINTER autohide=ok\n'
    # In dual view Tab still switches panes, and a row click focuses that pane with the list keyboard.
    local dual="$fixture_root/railpointer-dual" dstate="$fixture_root/railpointer-dual-state" rect rx ry rw rh cx cy ww hh dual_json
    sandbox_scratch "$dual"
    mkdir -p "$dual/left" "$dual/right"
    for i in $(seq -w 1 6); do : > "$dual/left/l$i.txt"; : > "$dual/right/r$i.txt"; done
    seed_ui_state "$dstate" "$(jq -cn --arg l "$dual/left" --arg r "$dual/right" '{view:"dual",dual:{paths:[$l,$r],focus:0}}')"
    launch "$dual/left"
    # An empty panes array reads as not-loading, so the wait requires a pane to exist first.
    local dual_ready=false
    for _attempt in $(seq 1 100); do
        dual_json=$(ipc dualState)
        [[ "$(jq -r '(.panes | length > 0) and ([.panes[].loading] | any | not)' 2>/dev/null <<< "$dual_json")" == "true" ]] && { dual_ready=true; break; }
        sleep 0.05
    done
    [[ "$dual_ready" == true ]] || fail "railpointer: dual panes still loading after 5 s (dualState=$dual_json)"
    ipc dualState | jq -e '.active and .focused == 0' >/dev/null || fail "railpointer: dual did not open focused on pane 0"
    key -k Tab >/dev/null
    settle
    ipc dualState | jq -e '.focused == 1' >/dev/null || fail "railpointer: dual Tab did not switch panes"
    # .folder is pane 0 row 0 (l01.txt), so its rect centre is a pinned row and never pane chrome.
    local geo
    geo=$(ipc dragPaneGeometry 0 0) || fail "railpointer: dual geometry read failed for pane 0 row 0"
    rect=$(jq -er '.folder.rect' <<< "$geo") || fail "railpointer: pane 0 row 0 has no rect (geometry=$geo)"
    [[ -n "$rect" ]] || fail "railpointer: pane 0 row 0 read an empty rect (geometry=$geo)"
    read -r rx ry rw rh <<< "$rect"
    [[ "$rx" =~ ^-?[0-9]+$ && "$ry" =~ ^-?[0-9]+$ && "$rw" =~ ^-?[0-9]+$ && "$rh" =~ ^-?[0-9]+$ ]] || fail "railpointer: pane 0 row 0 read no four numbers (rect=$rect)"
    (( rw > 0 && rh > 0 )) || fail "railpointer: pane 0 row 0 read an empty rect (rect=$rect)"
    [[ "$(jq -er '.folder.name' <<< "$geo")" == "l01.txt" ]] || fail "railpointer: pane 0 row 0 names $(jq -r '.folder.name' <<< "$geo"), want l01.txt, so the click is not pinned to a row (geometry=$geo)"
    read -r wx wy ww hh < <(window_box) || fail "railpointer: native window coordinates unavailable"
    omarchy-drive click "$((wx + rx + rw / 2))" "$((wy + ry + rh / 2))" left >/dev/null || fail "railpointer: the click on pane 0 row 0 failed"
    settle
    ipc dualState | jq -e '.focused == 0' >/dev/null || fail "railpointer: a row click on the other pane left focus on pane $(ipc dualState | jq -r '.focused')"
    [[ "$(ipc focusView)" == "list" ]] || fail "railpointer: a row click on the other pane left the keyboard on $(ipc focusView)"
    printf 'RAILPOINTER dual=ok\n'
    export XDG_STATE_HOME="$suite_home"
    kill_flea
}
