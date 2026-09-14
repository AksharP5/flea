# Flea shelf

A drop shelf for the [Omarchy](https://omarchy.org) bar. Files gathered from anywhere are held in
one pile and taken out together, so a copy that spans five folders is one drag rather than five.

The shelf is a bar widget: the mark sits beside its neighbours at all times, dim while the pile is
empty and at full strength while it is holding something. The count is never drawn in the bar
itself; it is in the hover tooltip, in the card and on the screen edge, where nothing competes
with it.

## What ships today

This is the scaffold. It reads the pile's own state file and reports the pile's presence in the
bar. Adding, holding, dragging out and the card itself land in the units that follow.

| Piece | What it is |
|---|---|
| `manifest.json` | the plugin the shell loads, one bar widget, one setting |
| `Panel.qml` | the bar presence: the mark, its two rungs and the tooltip |
| `ShelfService.qml` | the only thing that touches the outside world, the pile's state file |
| `Model.js` | pure functions, no QML imports: what the file's bytes mean |
| `FleaShelfMark.qml` | Flea's own mark, reproduced rather than recut |

## Requirements

- Omarchy with `omarchy-shell` (the plugin runs inside the shell, not as its own process).
- [Flea](https://github.com/thisisgm/flea) 0.3.0 or newer, which writes the pile.

## Settings

| Key | What it does | Default |
|---|---|---|
| `refreshIntervalSec` | how often the pile is re-read when no change has been signalled | 5 |

The pile's file is watched, so a change is drawn as it happens; the interval is what finds the
first item, because a watch cannot fire for a file that does not exist yet.

## State

`$XDG_STATE_HOME/omarchy/flea-shelf/shelf.json`, or `~/.local/state/omarchy/flea-shelf/shelf.json`
when that is unset. The shelf never writes it: `flea shelf` does.

## Keyboard

Nothing yet. The card's own keys arrive with the card.

## Install

```bash
omarchy plugin add https://github.com/thisisgm/flea-shelf.git --enable --yes
```

## Support

If this saved you an afternoon, you can
[sponsor me on GitHub](https://github.com/sponsors/thisisgm) or
[buy me a coffee](https://buymeacoffee.com/thisisgm).

## Licence

MIT.
