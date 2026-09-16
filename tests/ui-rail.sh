#!/usr/bin/env bash
# Sourced by ui.sh; RailAdditions rule 1 and rule 2 driven against doubles on a private PATH.
# shellcheck disable=SC2154 # ui.sh supplies the fixture root, the candidate paths and the helpers.

# The box has no unmounted internal volume of its own and nothing here may create one: a loop device
# is a udisks operation behind polkit, and a polkit prompt on this display swallows the very keys the
# case is driving. So lsblk answers from a file the case owns, and gio records what it was asked to
# do and rewrites that file the way udisks would, which is the same shape tests/ui-providers.sh uses
# for Tailscale and Dropbox.
rail_listing() {
    local mountpoint="$1" point
    point=$([[ -n "$mountpoint" ]] && printf '"%s"' "$mountpoint" || printf 'null')
    cat > "$rail_box/lsblk.json" <<JSON
{"blockdevices":[
 {"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"tran":"nvme","size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,
  "children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"tran":null,"size":256060514304,"type":"part","model":null,"fstype":"btrfs","parttypename":"Linux filesystem"}]},
 {"name":"sdb","path":"/dev/sdb","label":null,"mountpoints":[null],"rm":false,"tran":"sata","size":2000398934016,"type":"disk","model":"Samsung SSD 870","fstype":null,"parttypename":null,
  "children":[{"name":"sdb1","path":"/dev/sdb1","label":"Archive","mountpoints":[$point],"rm":false,"tran":null,"size":1000398934016,"type":"part","model":null,"fstype":"ext4","parttypename":"Linux filesystem"},
   {"name":"sdb2","path":"/dev/sdb2","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":536870912,"type":"part","model":null,"fstype":"vfat","parttypename":"EFI System"},
   {"name":"sdb3","path":"/dev/sdb3","label":null,"mountpoints":["[SWAP]"],"rm":false,"tran":null,"size":8589934592,"type":"part","model":null,"fstype":"swap","parttypename":"Linux swap"}]}
]}
JSON
}

# Every command the app reaches for stays reachable; lsblk and gio are the two this case answers for.
rail_path_box() {
    local part file name
    local -a parts
    mkdir -p "$rail_box/bin" || fail 'rail: private bin failed'
    IFS=: read -r -a parts <<< "$PATH"
    for part in "${parts[@]}"; do
        [[ -d "$part" ]] || continue
        for file in "$part"/*; do
            [[ -f "$file" && -x "$file" ]] || continue
            name=${file##*/}
            case "$name" in lsblk|gio) continue ;; esac
            [[ ! -e "$rail_box/bin/$name" ]] || continue
            ln -s -- "$file" "$rail_box/bin/$name" || fail "rail: cannot retain required command $name"
        done
    done
    cat > "$rail_box/bin/lsblk" <<'SH'
#!/usr/bin/env bash
set -eu
box=${FLEA_RAIL_BOX:?}
[[ "$box" == /* && -f "$box/.flea-test-sandbox" ]] || exit 90
cat "$box/lsblk.json"
SH
    # Only the two calls this case owns are answered here; the trash count, the mount listing and the
    # trash monitor are the real gio's, because a double that refused them would be testing itself.
    local real_gio
    real_gio=$(command -v gio) || fail 'rail: the box has no gio to stand behind the double'
    cat > "$rail_box/bin/gio" <<SH
#!/usr/bin/env bash
set -eu
box=\${FLEA_RAIL_BOX:?}
[[ "\$box" == /* && -f "\$box/.flea-test-sandbox" ]] || exit 90
jq -cn --args '{args:\$ARGS.positional}' -- "\$@" >> "\$box/calls.jsonl"
case "\$*" in
    "mount -d /dev/sdb1")
        mkdir -p "\$box/mnt/Archive"
        sed -i "s|\[null\],\\"rm\\":false,\\"tran\\":null,\\"size\\":1000398934016|[\\"\$box/mnt/Archive\\"],\\"rm\\":false,\\"tran\\":null,\\"size\\":1000398934016|" "\$box/lsblk.json"
        ;;
    "mount -u \$box/mnt/Archive")
        sed -i "s|\[\\"\$box/mnt/Archive\\"\],\\"rm\\":false,\\"tran\\":null,\\"size\\":1000398934016|[null],\\"rm\\":false,\\"tran\\":null,\\"size\\":1000398934016|" "\$box/lsblk.json"
        ;;
    *) exec REAL_GIO "\$@" ;;
esac
SH
    sed -i "s|REAL_GIO|$real_gio|" "$rail_box/bin/gio" || fail 'rail: the double could not be pointed at the real gio'
    chmod 700 "$rail_box/bin/lsblk" "$rail_box/bin/gio" || fail 'rail: cannot make the doubles executable'
}

# The mounts this case asked for, in order; every other gio call belongs to the trash and the rail.
rail_calls() {
    jq -sc '[.[] | .args | join(" ")] | map(select(startswith("mount -d") or startswith("mount -u")))' "$rail_box/calls.jsonl"
}

rail_entry() {
    ipc deviceEntries | grep -c "^Archive|device|volume|$1$" || true
}

rail_wait_entry() {
    local want="$1" attempt
    for attempt in $(seq 1 200); do
        [[ "$(rail_entry "$want")" == "1" ]] && return
        sleep 0.05
    done
    fail "rail: the Archive row never read mounted=$want, the rail carries $(ipc deviceEntries)"
}

# RailAdditions rules 1 and 2: a volume nothing mounted is a rail row behind its own switch, its menu
# is Mount, and choosing it mounts through gio and opens what came up. The switch off is 0.2.1's rail.
case_unmounted() (
    local rail_box="$fixture_root/unmounted" rail_dir="$fixture_root/unmounted/home"
    local index before
    sandbox_scratch "$rail_box"
    : > "$rail_box/.flea-test-sandbox" || fail 'rail: sandbox marker write failed'
    mkdir -p "$rail_box/state" "$rail_box/config" "$rail_box/cache" "$rail_box/data" || fail 'rail: private directories failed'
    fixture_home_make "$rail_dir"
    : > "$rail_box/calls.jsonl"
    rail_listing ""
    rail_path_box
    export HOME="$rail_dir" XDG_STATE_HOME="$rail_box/state" XDG_CONFIG_HOME="$rail_box/config"
    export XDG_CACHE_HOME="$rail_box/cache" XDG_DATA_HOME="$rail_box/data"
    export PATH="$rail_box/bin" FLEA_RAIL_BOX="$rail_box"

    echo "-- with the switch off the rail is the one 0.2.1 drew --"
    "$flea_bin" --ui-state '{"view":"list","keys":"default"}' >/dev/null || fail 'rail: private settings seed failed'
    launch "$rail_dir"
    wait_rail 2
    settle
    [[ "$(ipc deviceEntries)" != *"Archive"* ]] \
        || fail "rail: the switch is off and the rail still carries $(ipc deviceEntries)"
    printf 'RAIL off=%s\n' "$(ipc deviceEntries | tr '\n' ' ')"
    kill_flea

    echo "-- switched on, the volume nothing mounted is a row of its own --"
    "$flea_bin" --ui-state '{"places":{"showUnmounted":true}}' >/dev/null || fail 'rail: switch seed failed'
    launch "$rail_dir"
    rail_wait_entry false
    printf 'RAIL on=%s\n' "$(ipc deviceEntries | tr '\n' ' ')"
    [[ "$(ipc deviceEntries)" != *"|volume|true"* ]] || fail 'rail: the fixture volume started out mounted'
    index=$(rail_row_of Archive)
    click_rail_row "$index" right
    settle
    [[ "$(ipc contextMenuVisible)" == "true" ]] || fail 'rail: the unmounted volume opened no menu'
    [[ "$(ipc contextMenuEntries)" == "Mount" ]] \
        || fail "rail: the unmounted volume offers $(ipc contextMenuEntries), not Mount alone"
    shot rail-unmounted-menu

    echo "-- Mount is the activation, and what comes up is opened --"
    before=$(rail_calls)
    key -k Return >/dev/null
    rail_wait_entry true
    wait_path "$rail_box/mnt/Archive"
    printf 'RAIL mounted calls=%s path=%s\n' "$(rail_calls)" "$(ipc path)"
    [[ "$(rail_calls)" == '["mount -d /dev/sdb1"]' ]] \
        || fail "rail: the Mount row ran $(rail_calls), not one gio mount by device (before: $before)"
    shot rail-mounted

    echo "-- and a mounted one offers the open beside its release --"
    index=$(rail_row_of Archive)
    click_rail_row "$index" right
    settle
    [[ "$(ipc contextMenuEntries)" == "Open|Unmount" ]] \
        || fail "rail: the mounted volume offers $(ipc contextMenuEntries), not Open then Unmount"
    [[ "$(ipc contextMenuGlyphs)" == "folder|eject" ]] \
        || fail "rail: the mounted volume draws $(ipc contextMenuGlyphs)"
    menu_seek Unmount
    key -k Return >/dev/null
    rail_wait_entry false
    printf 'RAIL unmounted calls=%s\n' "$(rail_calls)"
    [[ "$(rail_calls)" == '["mount -d /dev/sdb1","mount -u '"$rail_box"'/mnt/Archive"]' ]] \
        || fail "rail: Unmount ran $(rail_calls)"

    echo "-- Enter on the row mounts it the same way the menu row does --"
    # The chosen menu row handed the keyboard back to the listing, so the rail is asked for again.
    [[ "$(ipc focusView)" == "rail" ]] || { key -k Tab >/dev/null; settle; }
    [[ "$(ipc focusView)" == "rail" ]] || fail "rail: Tab did not reach the rail, focus is $(ipc focusView)"
    rail_seek Archive
    key -k Return >/dev/null
    rail_wait_entry true
    wait_path "$rail_box/mnt/Archive"
    [[ "$(rail_calls)" == *'"mount -d /dev/sdb1","mount -u '"$rail_box"'/mnt/Archive","mount -d /dev/sdb1"]' ]] \
        || fail "rail: Enter ran $(rail_calls)"
    printf 'RAIL enter calls=%s\n' "$(rail_calls)"

    # The board's second theme is not this harness's to shoot: launch() refuses a window painting
    # anything but the live theme, which is the guard that keeps a colour claim honest. The rail's
    # own squares are Theme.color.executable and muted, which tests/themes.sh sweeps on all 22.
    kill_flea
)

# The window this case owns, floated so its width is this case's to set and nobody else's.
sidebar_resize() {
    local width="$1" height="${2:-800}"
    hyprctl dispatch "hl.dsp.window.resize({ x = $width, y = $height })" >/dev/null \
        || fail "sidebar: the window would not resize to $width"
    settle
    settle
}

sidebar_state() {
    ipc railState | jq -er "$1"
}

# The state file is written asynchronously, so the choice is waited for rather than read at once.
sidebar_stored() {
    local want="$1" file="$2" attempt
    for attempt in $(seq 1 60); do
        [[ "$(jq -r '.places.rail // "shown"' "$file")" == "$want" ]] && return
        sleep 0.1
    done
    fail "sidebar: the state file never held rail=$want, it holds $(jq -c .places "$file")"
}

sidebar_edge() {
    local wx wy _ww wh
    read -r wx wy _ww wh < <(window_box) || fail "sidebar: native window coordinates unavailable"
    omarchy-drive move "$((wx + 1))" "$((wy + wh / 2))" >/dev/null
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x 1 -y 0 >/dev/null 2>&1
    settle
}
sidebar_away() {
    local wx wy ww wh
    read -r wx wy ww wh < <(window_box) || fail "sidebar: native window coordinates unavailable"
    omarchy-drive move "$((wx + ww / 2))" "$((wy + wh / 2))" >/dev/null
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x 1 -y 0 >/dev/null 2>&1
    settle
}
sidebar_wait() {
    local want="$1" attempt
    for attempt in $(seq 1 60); do
        [[ "$(sidebar_state .hidden)" == "$want" ]] && return
        sleep 0.1
    done
    fail "sidebar: the rail never read hidden=$want, its state is $(ipc railState)"
}

# RailAdditions rule 4 (issue 112, muellan): ctrl-b hides the rail and brings it back, the choice
# outlives the window, and a window narrower than Theme.space(640) hides it on its own without
# touching what was remembered.
case_sidebar() (
    local dir="$fixture_root/sidebar" state="$fixture_root/sidebar-state" stored width
    sandbox_scratch "$dir"
    : > "$dir/a.txt"
    : > "$dir/b.txt"
    seed_ui_state "$state" '{"view":"list"}'
    stored="$state/flea/ui.json"

    launch "$dir"
    wait_listing 2
    hyprctl dispatch "hl.dsp.window.float()" >/dev/null || fail 'sidebar: the window would not float'
    settle
    sidebar_resize 1200
    [[ "$(sidebar_state .hidden)" == "false" ]] || fail "sidebar: a fresh home opened with the rail hidden, $(ipc railState)"
    width=$(sidebar_state .width)
    (( width > 0 )) || fail "sidebar: the rail is shown and has no width, $(ipc railState)"
    printf 'SIDEBAR shown=%s\n' "$(ipc railState)"

    echo "-- ctrl-b hides it, and the pane takes its width --"
    key -M ctrl -k b -m ctrl >/dev/null
    sidebar_wait true
    [[ "$(sidebar_state .width)" == "0" ]] || fail "sidebar: the hidden rail still takes $(sidebar_state .width) px"
    [[ "$(ipc railCount)" == "0" ]] || fail "sidebar: the hidden rail still has rows"
    shot sidebar-hidden
    sidebar_stored hidden "$stored"

    echo "-- and it is remembered, because a state is not a setting --"
    kill_flea
    launch "$dir"
    wait_listing 2
    sidebar_wait true
    key -M ctrl -k b -m ctrl >/dev/null
    sidebar_wait false
    sidebar_stored shown "$stored"

    echo "-- directive 74: with auto-hide off a narrow window keeps the rail --"
    hyprctl dispatch "hl.dsp.window.float()" >/dev/null || fail 'sidebar: the window would not float'
    settle
    sidebar_resize 1200
    sidebar_wait false
    sidebar_resize 520
    settle
    [[ "$(sidebar_state .hidden)" == "false" ]] \
        || fail "sidebar: the rail hid itself with auto-hide off, $(ipc railState)"
    sidebar_resize 1200

    echo "-- and the two Places rows are the other handle on the same state --"
    settings_open_key; settle
    settings_section places
    settings_focus_row places.rail
    key -k Space >/dev/null; settle
    sidebar_wait true
    sidebar_stored hidden "$stored"
    key -k Space >/dev/null; settle
    sidebar_wait false
    settings_focus_row places.autoHide
    key -k Space >/dev/null; settle
    settings_wait_value '.places.autoHide == true'
    shot sidebar-settings
    key -k Escape >/dev/null; settle

    echo "-- directive 77: switched on, the rail withdraws and the pane keeps the width --"
    sidebar_wait true
    [[ "$(sidebar_state .inset)" == "0" ]] || fail "sidebar: the withdrawn rail still holds $(ipc railState)"
    [[ "$(jq -r '.places.rail' "$stored")" == "shown" ]] \
        || fail "sidebar: withdrawing wrote the remembered choice, the file holds $(jq -c .places "$stored")"
    sidebar_resize 520
    sidebar_wait true
    sidebar_resize 1200
    sidebar_wait true

    echo "-- and the pointer at the window's own left edge reveals it, over the pane and not beside it --"
    sidebar_edge
    sidebar_wait false
    [[ "$(sidebar_state .inset)" == "0" ]] \
        || fail "sidebar: the revealed rail reflowed the pane, $(ipc railState)"
    [[ "$(sidebar_state '.width > 0')" == "true" ]] || fail "sidebar: the revealed rail has no width, $(ipc railState)"
    shot sidebar-overlay

    echo "-- it withdraws a moment after the pointer leaves --"
    sidebar_away
    sidebar_wait true

    echo "-- Tab reveals it the same way, and the keyboard leaving withdraws it --"
    key -k Tab >/dev/null; settle
    [[ "$(ipc focusView)" == "rail" ]] || fail "sidebar: Tab did not reach the withdrawn rail, it is on $(ipc focusView)"
    sidebar_wait false
    key -k Tab >/dev/null; settle
    sidebar_wait true

    echo "-- and the switch goes off again from its own row --"
    settings_open_key; settle
    settings_section places
    shot sidebar-greyed
    settings_focus_row places.autoHide
    key -k Space >/dev/null; settle
    settings_wait_value '.places.autoHide == false'
    key -k Escape >/dev/null; settle

    echo "-- switched off, Show sidebar and ctrl-b govern again --"
    sidebar_wait false
    [[ "$(sidebar_state '.inset > 0')" == "true" ]] || fail "sidebar: the rail came back as an overlay, $(ipc railState)"
    key -M ctrl -k b -m ctrl >/dev/null
    sidebar_wait true
    key -M ctrl -k b -m ctrl >/dev/null
    sidebar_wait false
    printf 'SIDEBAR autohide=ok remembered=%s\n' "$(jq -r '.places.rail' "$stored")"
    kill_flea
)
