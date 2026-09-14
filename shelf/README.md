# Flea shelf

A drop shelf for the [Omarchy](https://omarchy.org) bar. Files gathered from anywhere are held in
one pile and taken out together, so a copy that spans five folders is one drag rather than five.

The shelf is a bar widget: the mark sits beside its neighbours at all times, dim while the pile is
empty and at full strength while it is holding something. The count is never drawn in the bar
itself; it is in the hover tooltip, in the card and on the screen edge, where nothing competes
with it.

## What ships today

The bar presence, the card the mark opens, the sizes the card asks for row by row, the row's own
remove, and the tray of recent captures. The keys, the screen-edge rail and the five actions land in
the units that follow.

| Piece | What it is |
|---|---|
| `manifest.json` | the plugin the shell loads, one bar widget and its settings |
| `Panel.qml` | the bar presence and the card's own layer surface |
| `ShelfService.qml` | the only thing that touches the outside world: the pile's file and `flea shelf` |
| `Model.js` | pure functions, no QML imports: what the file's bytes mean |
| `ShelfCard.qml` | the pile itself, a Flea listing's own row and strip heights |
| `ShelfTray.qml` | the newest captures Omarchy has taken, on the card at all times |
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

The pile's file is watched, so a change is drawn as it happens; the interval is what finds the
first item, because a watch cannot fire for a file that does not exist yet.

The tray holds the newest screenshots and screen recordings Omarchy has taken, from the directories
its own capture commands write to (`OMARCHY_SCREENSHOT_DIR`, else `XDG_PICTURES_DIR`, else
`~/Pictures`; `OMARCHY_SCREENRECORD_DIR`, else `XDG_VIDEOS_DIR`, else `~/Videos`). They are listed
when the card opens and on each re-read while it is up, never while it is closed. Click one to add it
to the pile, drag it to take it straight out; either way the capture stays where Omarchy put it.

## State

`$XDG_STATE_HOME/omarchy/flea-shelf/shelf.json`, or `~/.local/state/omarchy/flea-shelf/shelf.json`
when that is unset. The shelf never writes it: `flea shelf` does.

## Keyboard

| Key | What it does |
|---|---|
| `esc` | closes the card |

The card's action strip draws its own keys beside every action; they run the actions with them.

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
