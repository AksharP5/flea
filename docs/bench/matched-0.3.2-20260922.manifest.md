# Field bench manifest

Written by tools/flea-bench-manifest. Every line below is read off the installed artefact.

## Run

- date: 2026-09-22T03:01:07-04:00
- host: minipc, kernel 7.2.5-3-omarchy
- fixture: /home/flea-sandbox/flea-matched-btrfs
- fixture payload: 1700 visible entries, filesystem btrfs
- TUI terminal: kitty 0.48.2-1
- flea launch line: FLEA_BIN=/home/gm/Work/claude/flea-032-20260919/fw-f2/target/release/flea FLEA_UI=/home/gm/Work/claude/flea-032-20260919/fw-f2/ui XDG_STATE_HOME=/tmp/flea-bench-state.VHvz5r setsid nohup /home/gm/Work/claude/flea-032-20260919/fw-f2/target/release/flea --gui /home/flea-sandbox/flea-matched-btrfs
- load average at start: 0.47 0.56 0.45
- waited 60 seconds for the box to go idle before starting
- TUI preview target: /home/flea-sandbox/flea-matched-btrfs/photo_0.jpg
- fixture payload assertion: PASSED, 1700 visible entries against the expected 1700

## Fixture by extension

```
    600 jpg
    400 mp4
    200 webp
    200 txt
    200 png
    100 webm
      0 no extension
```

- excluded from the denominator: 200 .txt files, which no thumbnailer attempts
- thumbnailable denominator: 1500, from 1700 visible entries less the 200 above

## Package freshness

- last full system upgrade: [2026-09-15T23:38:58-0400] [PACMAN] starting full system upgrade
- age at run time: 147 hours
- WARNING: this run is more than 24 hours past the last upgrade, so the packaged entrants are not necessarily current

## Entrants

```
flea       gui  source af93be8 (clean), release binary built 2026-09-22T02:59:59-04:00, 2604736 bytes
nautilus   gui  nautilus 50.3.1-1
thunar     gui  thunar 4.20.9-1
pcmanfm    gui  pcmanfm 1.4.0-2
nemo       gui  nemo 6.6.4-1
dolphin    gui  dolphin 26.08.0-5
strata     gui  source v0.19.0 committed 2026-09-18, built locally from this checkout
yazi       tui  yazi 26.9.1-2
mc         tui  mc 4.8.33-1
broot      tui  broot 1.60.0-1
nnn        tui  nnn 5.3-1
lf         tui  lf 42-1
ranger     tui  ranger 1.9.4-5
xplr       tui  xplr 1.0.1-1
superfile  tui  superfile 1.6.0-1
```

strata is the one entrant pacman did not install. It is built here from the v0.19.0 tag in a
local checkout. **The project also publishes a prebuilt x86_64 binary for that tag and it was
not used**: this harness does not download and execute a third-party binary unattended, and
every packaged entrant is itself built from source by the distribution, so building from the
tag is more consistent with the field than fetching one binary would be. Build flags may differ
from the published release, which is equally true of every AUR entrant in the list.

## The TUI bracket's configuration, as it ran

Provenance per entrant is in `tools/flea-bench-tui/README.md`. lf's is AUTHORED HERE
because lf ships no image preview at all; every other file came from that project's own docs.

### README.md

```
# The TUI bracket's configuration, and where every line of it came from

This directory is the `XDG_CONFIG_HOME` the field bench hands to every TUI entrant. The operator's
own `~/.config` is never read by a benched entrant and never written by one, so a run is
reproducible on another box and the operator's ranger, nnn and superfile settings are left alone.

GM's ruling is **bench as-intended**: each entrant runs in the configuration its own project
documents, not in whatever stock Omarchy happens to leave it in, and not in a tuned one. The rivals
are expected to get slower, and that is the point: it is the only version of this bracket that
supports a capability claim.

The guard on that ruling, which is the load-bearing part: **do not tune.** No flag is chosen because
it helps or hurts a number. A slow documented default is a result.

## Per entrant

| entrant | image preview | where the configuration came from |
|---|---|---|
| yazi | native Kitty graphics protocol | **Nothing configured.** Stock, and it was only ever blocked by `foot`. |
| ranger | Kitty protocol | The two lines its own shipped `rc.conf` documents, at `/usr/share/doc/ranger/config/rc.conf`. Needs `python-pillow`, which is installed. |
| superfile | `chafa` | **Nothing configured.** Its own docs name `chafa` as the requirement and it detects it. |
| nnn | `preview-tui`, the plugin it ships | The plugin at `/usr/share/nnn/plugins/preview-tui`, wired the way its own header documents: `NNN_FIFO`, `NNN_PLUG`, and a kitty with `allow_remote_control` and `listen_on`. The bench symlinks the shipped plugin into `nnn/plugins/` at run time rather than committing a copy of it here. |
| lf | `kitten icat` | **AUTHORED HERE.** lf ships no image preview: its own `lfrc.example` has no preview lines. The shape is lf's documented `previewer` and `cleaner` hooks. lf's row carries this caveat in the manifest. |
| mc, broot, xplr | none | **No image preview feature exists.** That is a capability finding, not a configuration gap, and it is permanent for those three. |

## The terminal is part of the configuration

`kitty/kitty.conf` is the bench's own, for two reasons. A number that depends on whatever font size
somebody set last week is not reproducible, and `nnn`'s preview plugin needs `allow_remote_control`,
which is not a thing to switch on in an operator's real terminal.

The bracket ran in `foot` before this. Per the KB, foot is sixel only while yazi and the rest prefer
the Kitty protocol, so `thumbs_n 0` across all eight entrants was the harness's terminal choice and
not a result about the entrants.

## These results are a new baseline

The as-intended numbers are **not comparable to the as-shipped numbers already collected**. Any
document carrying both says so rather than merging the two tables.
```

### kitty/kitty.conf

```
# The bench's own terminal configuration, not the operator's. A benchmark whose numbers depend on
# whatever font size somebody set last week is not reproducible, and nnn's preview plugin needs
# remote control switched on, which is not something to turn on in an operator's real terminal.
allow_remote_control yes
listen_on unix:/tmp/flea-bench-kitty

# A fixed grid, so every entrant is handed the same viewport and the same amount of preview to draw.
font_size 12
remember_window_size no
initial_window_width 1600
initial_window_height 1000
confirm_os_window_close 0
```

### lf/cleaner.sh

```
#!/bin/sh
# Without this the previous image stays on screen over the next file's preview.
kitten icat --clear --stdin no --transfer-mode file </dev/null >/dev/tty
```

### lf/lfrc

```
# lf ships no image preview at all: its own lfrc.example at /usr/share/doc/lf/lfrc.example has no
# preview lines in it. AUTHORED HERE, so lf's row carries that caveat. The shape is lf's documented
# previewer hook, with kitty's own icat kitten as the image path.
set previewer /tmp/tmp.Qu6QeMfDKH/lf/previewer.sh
set cleaner /tmp/tmp.Qu6QeMfDKH/lf/cleaner.sh
```

### lf/previewer.sh

```
#!/bin/sh
# lf calls a previewer with the file and the preview pane geometry: $1 file, $2 width, $3 height,
# $4 x, $5 y. Exiting 1 tells lf not to cache the output, which is what an image preview needs.
case "$1" in
  *.jpg|*.jpeg|*.png|*.webp|*.heic|*.gif)
    kitten icat --stdin no --transfer-mode file --place "${2}x${3}@${4}x${5}" "$1" </dev/null >/dev/tty
    exit 1
    ;;
esac
head -100 "$1"
```

### nnn/plugins/preview-tui

23174 bytes, not reprinted: this is the file the entrant's own package ships.

### ranger/rc.conf

```
# ranger ships preview_images false and preview_images_method w3m, so out of the box it draws no
# image in any terminal. These are the two lines its own shipped rc.conf documents for a
# Kitty-protocol terminal, at /usr/share/doc/ranger/config/rc.conf, and nothing else is changed.
set preview_images true
set preview_images_method kitty
```

## Libraries the entrants render through

An absent one is a capability fact about this field, not a gap in the record.

```
qt6-base               6.11.2-3
gtk3                   1:3.24.52-1
gtk4                   1:4.22.4-1
glib2                  2.88.3-1
ffmpegthumbnailer      2.3.1-1
libheif                1.23.4-1
webp-pixbuf-loader     absent
qt6-imageformats       6.11.2-1
chafa                  1.18.2-2
ueberzugpp             2.9.10-1
```

## Run close

- ended: 2026-09-22T03:15:46-04:00
- load average at end: 2.10 2.68 2.02

## Formats produced, refused, and never attempted

The formats come from the fixture's own key map, not from any one run's output, so a format
an entrant never reached still gets a line. Produced is a thumbnail written. Refused is a
failure marker the thumbnailer left. Never attempted is neither, which on this fixture mostly
means the entrant settled before reaching those names: they sort by format, clip before image
before notes before photo. **A never-attempted count is not a capability claim.**

- flea produced mp4 35, webm 8; refused nothing; never attempted jpg 600, mp4 365, png 200, txt 200, webm 92, webp 200
- nautilus produced mp4 400, png 71, webm 100, webp 70; refused nothing; never attempted jpg 600, png 129, txt 200, webp 130
- thunar produced mp4 177, webm 44; refused nothing; never attempted jpg 600, mp4 223, png 200, txt 200, webm 56, webp 200
- pcmanfm produced mp4 400, png 200, webm 100; refused nothing; never attempted jpg 600, txt 200, webp 200
- nemo: nothing reached the thumbnail cache, so this run makes no format claim about it either way; tools/flea-bench-capability is the instrument that answers what it can draw
- dolphin produced jpg 224, mp4 360, webm 90; refused nothing; never attempted jpg 376, mp4 40, png 200, txt 200, webm 10, webp 200
- strata produced mp4 34, webm 8; refused nothing; never attempted jpg 600, mp4 366, png 200, txt 200, webm 92, webp 200
- yazi: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- mc: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- broot: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- nnn: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- lf: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- ranger: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- xplr: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- superfile: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all

## The TUI bracket's preview timing

- mc, broot, xplr: no image preview feature at all, so nothing was there to time. The -1 in
  preview_ms is that fact and not a slow preview.

## The equal-work column

`cpu_tree_s` is the column to compare work on, for every entrant and not for Flea alone: a
column carrying CPU-seconds for one entrant and wall-seconds for the rest is the incomparable
rank this harness now refuses. It is on every row above.

**It is read from a control group of the run's own.** Each entrant run is a leaf cgroup that
the launching shell joins before it forks the entrant, and `cpu_tree_s` is that leaf's
`usage_usec`, plus a declared helper living outside it (thunar's tumblerd). The older sum of
reaped ticks is kept as `cpu_reaped_s` and is blind to a decode under bwrap: measured, ten
sandboxed decodes added 0.01 s to it against 0.95 s run bare. A column from before 0.3.2 is
that blind figure and compares only against `cpu_reaped_s`. A TUI row's group holds its
terminal too, so that bracket's column includes kitty's own drawing, the same kitty for each.

**What it does not yet include.** Flea thumbnails the viewport by design and every rival
thumbnails the directory, so this column is comparable in units and not in work until Flea is
driven through the whole listing. When that lands, the residual bias belongs here too: the
driver's own cost falls in omarchy-drive's tree and is excluded, while Flea's cost of
servicing that drive is included and no rival pays it. That biases against Flea, which is the
safe direction, and it is not a reason to leave the number out.

## Rank refusals

- nemo run 1: unranked: nothing reached the thumbnail cache so its work was not measured
- yazi run 1: n/a: tui in kitty
- mc run 1: n/a: tui in kitty
- broot run 1: n/a: tui in kitty
- nnn run 1: n/a: tui in kitty
- lf run 1: n/a: tui in kitty
- ranger run 1: n/a: tui in kitty
- xplr run 1: n/a: tui in kitty
- superfile run 1: n/a: tui in kitty
- nemo run 2: unranked: nothing reached the thumbnail cache so its work was not measured
- yazi run 2: n/a: tui in kitty
- mc run 2: n/a: tui in kitty
- broot run 2: n/a: tui in kitty
- nnn run 2: n/a: tui in kitty
- lf run 2: n/a: tui in kitty
- ranger run 2: n/a: tui in kitty
- xplr run 2: n/a: tui in kitty
- superfile run 2: n/a: tui in kitty
- nemo run 3: unranked: nothing reached the thumbnail cache so its work was not measured
- yazi run 3: n/a: tui in kitty
- mc run 3: n/a: tui in kitty
- broot run 3: n/a: tui in kitty
- nnn run 3: n/a: tui in kitty
- lf run 3: n/a: tui in kitty
- ranger run 3: n/a: tui in kitty
- xplr run 3: n/a: tui in kitty
- superfile run 3: n/a: tui in kitty
- the ranked rows differ in thumbnail work by 16x, from 42 to 700, so their settle times are not ranked against each other

## Notes

PREWARM one launch through flea --gui for /home/gm/Work/claude/flea-032-20260919/fw-f2
TRANSIENT_ID=none: strata v0.19.0 writes the shared cache, so it is counted from the cache like every other entrant.
Provenance: product and harness tree af93be86, the 0.3.2 release tree, published as 97ec6b90 after the release's contributor-credit rewrite, which changed commit names and no tree. Flea's first run here mapped in 3669 ms and settled in 5346 ms, with nothing in the kernel log at that minute. A batch of three more, Flea alone after one prewarm, mapped in 267 to 329 ms and settled in 1859 to 1988 ms.
