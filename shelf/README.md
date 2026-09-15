# Flea shelf

A drop shelf for the [Omarchy](https://omarchy.org) bar. Files gathered from anywhere are held in
one pile and taken out together, so a copy that spans five folders is one drag rather than five.

The shelf is a bar widget: the mark sits beside its neighbours at all times, dim while the pile is
empty and at full strength while it is holding something. The count is never drawn in the bar
itself; it is in the hover tooltip, in the card and on the screen edge, where nothing competes
with it.

## What ships today

The bar presence, the card the mark opens, the sizes the card asks for row by row, the row's own
remove, the tray of recent captures, the ways back in (the keybind, a cleared pile and the last five
piles), and the screen-edge rail you throw a drag at. The subset gesture and the five actions land in
the units that follow.

| Piece | What it is |
|---|---|
| `manifest.json` | the plugin the shell loads, one bar widget and its settings |
| `Panel.qml` | the bar presence and the card's own layer surface |
| `ShelfService.qml` | the only thing that touches the outside world: the pile's file and `flea shelf` |
| `Model.js` | pure functions, no QML imports: what the file's bytes mean |
| `ShelfCard.qml` | the pile itself, a Flea listing's own row and strip heights |
| `ShelfTray.qml` | the newest captures Omarchy has taken, on the card at all times |
| `ShelfMenu.qml` | the card's own menu: the last five piles, and the way back to one |
| `ShelfRail.qml` | the screen edge you throw a drag at, and the notch that says what is held |
| `ShelfGlyph.qml` | one mark on the Omarchy cut, the way Flea draws its own |
| `FleaShelfMark.qml` | Flea's own mark, reproduced rather than recut |

## Requirements

- Omarchy with `omarchy-shell` (the plugin runs inside the shell, not as its own process).
- [Flea](https://github.com/thisisgm/flea) 0.3.0 or newer, which writes the pile.

## Settings

| Key | What it does | Default |
|---|---|---|
| `refreshIntervalSec` | how often the pile is re-read when no change has been signalled | 5 |
| `fleaCommand` | the flea that owns the pile, a name on PATH or a path of its own | `flea` |
| `recentCaptures` | how many recent captures the card's tray holds, none to six | 3 |
| `railEdge` | the drop rail's edge: `off`, `left`, `right`, `bottom`, or empty for the edge opposite the bar | empty |
| `railDwell` | how long a drag rests on the rail before the card opens, in milliseconds, 60 to 600 | 120 |

The pile's file is watched, so a change is drawn as it happens; the interval is what finds the
first item, because a watch cannot fire for a file that does not exist yet.

The rail is four pixels of the middle 60 percent of its edge, drawn only while something is held (a
notch stepped by the pile) and while a drag is over it (the whole region in the accent). It gives up
no space: no window ever shrinks for it. A drop on it is taken the moment it lands; the dwell only
decides whether the card has opened on the way.

The tray holds the newest screenshots and screen recordings Omarchy has taken, from the directories
its own capture commands write to (`OMARCHY_SCREENSHOT_DIR`, else `XDG_PICTURES_DIR`, else
`~/Pictures`; `OMARCHY_SCREENRECORD_DIR`, else `XDG_VIDEOS_DIR`, else `~/Videos`). They are listed
when the card opens and on each re-read while it is up, never while it is closed. Click one to add it
to the pile, drag it to take it straight out; either way the capture stays where Omarchy put it.

## State

`$XDG_STATE_HOME/omarchy/flea-shelf/`, or `~/.local/state/omarchy/flea-shelf/` when that is unset:
`shelf.json` is the pile, `piles.json` the last five it has held, `drags.json` the tokens a drag out
carries, and `summon.json` the count the keybind writes. The plugin never writes any of them:
`flea shelf` does, and the plugin watches.

## Keyboard

| Key | What it does |
|---|---|
| `super + d` | opens the shelf, or closes it, once you have installed the bind below |
| `esc` | closes the card, and steps out of its menu |
| `shift + x` | clears the shelf, and it becomes the last pile |
| `z` | brings the last pile back |
| `1` to `5` | in the menu, takes that pile back |
| right click | on the bar mark: brings back the last pile you cleared; on the card: its menu |

The card's action strip draws its own keys beside every action; they run the actions with them.

The bind is a line in your own Hyprland config, not one this plugin writes. Add it to
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + D", "Drop shelf", "flea shelf toggle")
```

The empty card names that chord once the line is there, and says nothing about it while it is not.

## Install

```bash
omarchy plugin add https://github.com/thisisgm/flea-shelf.git --enable --yes
```

## Uninstall

```bash
omarchy plugin remove io.github.thisisgm.flea-shelf
rm -rf ~/.local/state/omarchy/flea-shelf
```

That directory is the pile itself and the drag tokens Flea mints for it, so removing it empties the
shelf. Flea and the files the shelf was holding are untouched.

## Support

If this saved you an afternoon, you can
[sponsor me on GitHub](https://github.com/sponsors/thisisgm) or
[buy me a coffee](https://buymeacoffee.com/thisisgm).

## Licence

MIT.
