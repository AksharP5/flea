#!/usr/bin/env bash
# Pins the Jump board's flush dropdown by summing the hairline literals between the path field and the dropdown.
set -u
arg=${1:-}
if [ -n "$arg" ]; then tree=$(realpath -m -- "$arg") || exit 1; else tree=""; fi
cd "$(dirname "$0")/.." || exit 1
if [ -z "$tree" ]; then tree=$PWD; fi
python3 - "$tree" <<'PY'
# Each check reads the literal the layout reads, so a margin moved in QML moves the number here.
import re, sys

tree = sys.argv[1]

def fail(message):
    print('FAIL jump-gap ' + message)
    sys.exit(1)

def mult(expr):
    # Sample input: "Theme.spacing.hairline * 2" is 2, "Theme.spacing.hairline" is 1.
    m = re.fullmatch(r'Theme\.spacing\.hairline(?:\s*\*\s*(\d+))?', expr.strip())
    if not m:
        fail('a margin is no longer a hairline multiple: ' + expr.strip())
    return int(m.group(1)) if m.group(1) else 1

def after(lines, anchor, pattern):
    # Sample input: the "rename editor's own frame" comment, then "anchors.bottomMargin: ...".
    hits = []
    for n, line in enumerate(lines):
        if anchor in line:
            for later in lines[n:n + 12]:
                m = re.search(pattern, later)
                if m:
                    hits.append((n + 1, m.group(1)))
                    break
    return hits

def lines_of(rel):
    try:
        return open(tree + '/' + rel).read().split('\n')
    except OSError as e:
        fail('cannot read %s under %s: %s' % (rel, tree, e.strerror))

chrome = lines_of('ui/ChromeBar.qml')
jump = lines_of('ui/PathJump.qml')

slot = after(chrome, 'id: pathArea', r'anchors\.bottomMargin:\s*(.+?)\s*$')
frame_top = after(chrome, "rename editor's own frame", r'anchors\.topMargin:\s*(.+?)\s*$')
frame_bot = after(chrome, "rename editor's own frame", r'anchors\.bottomMargin:\s*(.+?)\s*$')
off = after(jump, 'y: root.parent', r'root\.parent\.height\s*\+\s*(Theme\.spacing\.hairline(?:\s*\*\s*\d+)?)')
for label, hits in (('path slot bottom', slot), ('field top', frame_top),
                    ('field bottom', frame_bot), ('dropdown offset', off)):
    if len(hits) != 1:
        fail('expected one %s margin, found %d' % (label, len(hits)))

slotBot, frameTop, frameBot, dropOff = (mult(slot[0][1]), mult(frame_top[0][1]),
                                        mult(frame_bot[0][1]), mult(off[0][1]))
gap = frameBot + dropOff
if dropOff != slotBot:
    fail('the dropdown top misses the strip edge by %d hairline(s), so it covers the rule or floats' % (dropOff - slotBot))
if gap != 2:
    fail('the field-to-dropdown gap is %d hairlines, the board draws 2' % gap)
if frameTop != slotBot + frameBot:
    fail('the field sits %d above and %d below centre, the board centres it' % (frameTop, slotBot + frameBot))
print('jump-gap: top=%d bottom=%d slot=%d off=%d gap=%d, the board draws 2' % (frameTop, frameBot, slotBot, dropOff, gap))
PY
