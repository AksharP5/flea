#!/usr/bin/env bash
# Neighbour-column backgrounds (e41): a peek column's empty space navigates to its drawn directory and opens its background menu once the rows land.
# shellcheck disable=SC2034,SC2154 # ui.sh supplies the launch, ipc and click helpers.

# Click empty space in a neighbour column: x off a real row centre in that column, y at the window middle, well below the few rows the fixture draws.
columnsbg_click_column() {
    local centre="$1" cx cy
    [[ -n "$centre" ]] || fail "columnsbackground: the neighbour column has no row centre"
    read -r cx cy <<< "$centre"
    columnsbg_click_x "$cx"
}

# Click empty space at a relative x and the window middle: the empty child's own helper, which has no row centre to read.
columnsbg_click_x() {
    local cx="$1" wx wy ww wh
    read -r wx wy ww wh < <(window_box) || fail "native window coordinates unavailable"
    omarchy-drive click "$((wx + cx))" "$((wy + wh / 2))" right >/dev/null
}

# The deferred menu already stands open: click its New Folder row by centre, never menu_click, which would reopen the middle column's own background instead.
columnsbg_choose_new_folder() {
    local index cx cy wx wy
    index=$(menu_row_index "New Folder") || fail "columnsbackground: the menu has no New Folder row in $(ipc contextMenuEntries)"
    read -r cx cy <<< "$(ipc contextMenuRowCentre "$index")"
    [[ -n "$cy" ]] || fail "columnsbackground: New Folder has no on-screen centre"
    read -r wx wy _ww _wh < <(window_box) || fail "native window coordinates unavailable"
    omarchy-drive click "$((wx + cx))" "$((wy + cy))" left >/dev/null
}

columnsbg_wait_menu_on() {
    local want_path="$1" path=unavailable opened=unavailable
    for _attempt in $(seq 1 300); do
        path=$(ipc path 2>/dev/null || printf unavailable)
        opened=$(ipc contextMenuVisible 2>/dev/null || printf unavailable)
        if [[ "$path" == "$want_path" && "$opened" == "true" ]]; then return 0; fi
        sleep 0.05
    done
    fail "columnsbackground: no background menu on $want_path (path=$path opened=$opened entries=$(ipc contextMenuEntries))"
}

columnsbg_fixture() {
    local root="$1"
    sandbox_scratch "$root"
    mkdir -p "$root/P/A/B" "$root/P/A/E"
    printf 'sibling\n' > "$root/P/sibling.txt"
    printf 'file\n' > "$root/P/A/fileA.txt"
    printf 'deep\n' > "$root/P/A/B/deep.txt"
}

columnsbg_to_columns() {
    click_chrome columns
    settle
    [[ "$(ipc viewMode)" == "columns" ]] || fail "columnsbackground: the columns view did not come up"
    [[ "$(ipc columnCount)" -ge 3 ]] || fail "columnsbackground: needs 3 columns, has $(ipc columnCount)"
}

case_columnsbackground() {
    local root="$fixture_root/columnsbackground" state="$fixture_root/columnsbackground-state"
    columnsbg_fixture "$root"
    seed_ui_state "$state" "{\"menu\":{\"hidden\":$menu_shipped}}"

    # Parent: empty space in P's column navigates to P, then New Folder lands in P alone.
    launch "$root/P/A"
    wait_listing 3
    columnsbg_to_columns
    seek_row_named "B"
    settle
    columnsbg_click_column "$(ipc columnParentRowCentre 0)"
    columnsbg_wait_menu_on "$root/P"
    [[ "$(ipc contextMenuEntries)" == *"New Folder"* ]] || fail "columnsbackground: parent menu lacks New Folder in $(ipc contextMenuEntries)"
    columnsbg_choose_new_folder
    settle
    [[ -d "$root/P/New Folder" ]] || fail "columnsbackground: parent New Folder created nothing in $root/P"
    [[ ! -e "$root/P/A/New Folder" ]] || fail "columnsbackground: parent menu wrote into the active directory"
    [[ ! -e "$root/P/A/B/New Folder" ]] || fail "columnsbackground: parent menu wrote into the child directory"
    printf 'COLUMNSBACKGROUND parent=%s\n' "$(ls -A "$root/P" | tr '\n' '|')"
    key -k Escape >/dev/null
    settle
    kill_flea

    # Current: the middle column's own background still creates in A alone.
    columnsbg_fixture "$root"
    launch "$root/P/A"
    wait_listing 3
    columnsbg_to_columns
    click_background
    settle
    columnsbg_wait_menu_on "$root/P/A"
    columnsbg_choose_new_folder
    settle
    [[ -d "$root/P/A/New Folder" ]] || fail "columnsbackground: active New Folder created nothing in $root/P/A"
    [[ ! -e "$root/P/New Folder" ]] || fail "columnsbackground: active menu wrote into the parent directory"
    [[ ! -e "$root/P/A/B/New Folder" ]] || fail "columnsbackground: active menu wrote into the child directory"
    printf 'COLUMNSBACKGROUND active=%s\n' "$(ls -A "$root/P/A" | tr '\n' '|')"
    key -k Escape >/dev/null
    settle
    kill_flea

    # Child: empty space in B's column navigates to B, then New Folder lands in B alone.
    columnsbg_fixture "$root"
    launch "$root/P/A"
    wait_listing 3
    columnsbg_to_columns
    seek_row_named "B"
    settle
    columnsbg_click_column "$(ipc columnChildRowCentre 0)"
    columnsbg_wait_menu_on "$root/P/A/B"
    [[ "$(ipc contextMenuEntries)" == *"New Folder"* ]] || fail "columnsbackground: child menu lacks New Folder in $(ipc contextMenuEntries)"
    columnsbg_choose_new_folder
    settle
    [[ -d "$root/P/A/B/New Folder" ]] || fail "columnsbackground: child New Folder created nothing in $root/P/A/B"
    [[ ! -e "$root/P/New Folder" ]] || fail "columnsbackground: child menu wrote into the parent directory"
    [[ ! -e "$root/P/A/New Folder" ]] || fail "columnsbackground: child menu wrote into the active directory"
    printf 'COLUMNSBACKGROUND child=%s\n' "$(ls -A "$root/P/A/B" | tr '\n' '|')"
    key -k Escape >/dev/null
    settle
    kill_flea

    # Empty active: the middle column's own background still creates in an empty E alone.
    columnsbg_fixture "$root"
    launch "$root/P/A/E"
    wait_listing 0
    columnsbg_to_columns
    click_background
    settle
    columnsbg_wait_menu_on "$root/P/A/E"
    columnsbg_choose_new_folder
    settle
    [[ -d "$root/P/A/E/New Folder" ]] || fail "columnsbackground: empty active New Folder created nothing in $root/P/A/E"
    [[ ! -e "$root/P/New Folder" ]] || fail "columnsbackground: empty active menu wrote into the parent directory"
    [[ ! -e "$root/P/A/New Folder" ]] || fail "columnsbackground: empty active menu wrote beside the empty directory"
    printf 'COLUMNSBACKGROUND empty-active=%s\n' "$(ls -A "$root/P/A/E" | tr '\n' '|')"
    key -k Escape >/dev/null
    settle
    kill_flea

    # Empty child: E draws no row, so its x comes from the column pitch (active minus parent); New Folder still lands in E alone.
    columnsbg_fixture "$root"
    launch "$root/P/A"
    wait_listing 3
    columnsbg_to_columns
    seek_row_named "E"
    settle
    [[ -z "$(ipc columnChildRowCentre 0 2>/dev/null)" ]] || fail "columnsbackground: the empty child drew a row centre"
    parent_cx=$(ipc columnParentRowCentre 0 | cut -d' ' -f1)
    active_cx=$(ipc rowCentre "$(ipc cursor)" | cut -d' ' -f1)
    [[ -n "$parent_cx" && -n "$active_cx" ]] || fail "columnsbackground: no column pitch to aim the empty child with"
    columnsbg_click_x "$((active_cx + active_cx - parent_cx))"
    columnsbg_wait_menu_on "$root/P/A/E"
    [[ "$(ipc contextMenuEntries)" == *"New Folder"* ]] || fail "columnsbackground: empty child menu lacks New Folder in $(ipc contextMenuEntries)"
    columnsbg_choose_new_folder
    settle
    [[ -d "$root/P/A/E/New Folder" ]] || fail "columnsbackground: empty child New Folder created nothing in $root/P/A/E"
    [[ ! -e "$root/P/New Folder" ]] || fail "columnsbackground: empty child menu wrote into the parent directory"
    [[ ! -e "$root/P/A/New Folder" ]] || fail "columnsbackground: empty child menu wrote into the active directory"
    printf 'COLUMNSBACKGROUND empty-child=%s\n' "$(ls -A "$root/P/A/E" | tr '\n' '|')"
    key -k Escape >/dev/null
    settle
    kill_flea

    printf 'COLUMNSBACKGROUND parent+active+child+empty-active+empty-child=ok\n'
}
