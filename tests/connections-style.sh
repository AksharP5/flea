#!/usr/bin/env bash
# Qt wires one Connections handler style per block, so a mixed block drops the method side.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
arg=${1:-}
if [ -n "$arg" ]; then tree=$(realpath -m -- "$arg") || exit 1; else tree=""; fi
cd "$(dirname "$0")/.." || exit 1
if [ -z "$tree" ]; then tree=$PWD; fi
python3 - "$tree" "$PWD/tests/fixtures/connections-style" <<'PY'
# Blocks are found by indentation, never by braces, so no quote, regex or comment can hide one.
import glob, os, re, sys

MEMBER_INDENT = '    '
OPEN = re.compile(r'^(\s*)(?!//|\*)(.*\b)?Connections\s*\{(.*)$')
METHOD = re.compile(r'function\s+(on[A-Z]\w*)\s*\(')
BINDING = re.compile(r'(?:^|[;{}])\s*(on[A-Z]\w*)\s*:')

def fail(message):
    print('FAIL connections-style ' + message)
    sys.exit(1)

def blocks(path):
    # Sample input: "    Connections {" at indent 4, "        function onReady() {" at 8, "    }" closing at 4.
    lines = open(path).read().split('\n')
    found = []
    for n, line in enumerate(lines):
        m = OPEN.match(line)
        if not m:
            continue
        indent, rest = m.group(1), m.group(3)
        if rest.rstrip().endswith('}'):
            found.append((n + 1, [rest]))
            continue
        members = []
        for later in lines[n + 1:]:
            if later.startswith(indent + '}'):
                break
            if later.strip() and not later.startswith(indent + MEMBER_INDENT):
                fail('%s:%d has a member off its indent' % (path, n + 1))
            if not later.startswith(indent + MEMBER_INDENT + ' ') and not later.strip().startswith(('//', '/*', '*')):
                members.append(later)
        else:
            fail('%s:%d never closes at its own indent' % (path, n + 1))
        found.append((n + 1, members))
    return found

def mixed(members):
    meth = [x for m in members for x in METHOD.findall(m)]
    bind = [x for m in members for x in BINDING.findall(m)]
    if meth and bind:
        return meth[0], bind[0]
    return None

tree, reds_dir = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(tree, 'ui', '*.qml')) + glob.glob(os.path.join(tree, 'ui', 'boot', '*.qml')))
if not files:
    fail('swept zero files under ' + tree)
total = 0
bad = []
for f in files:
    for line, members in blocks(f):
        total += 1
        hit = mixed(members)
        if hit:
            bad.append('%s:%d mixes function-style %s with binding-style %s' % (os.path.relpath(f, tree), line, hit[0], hit[1]))
for b in bad:
    print('FAIL ' + b)
if total == 0:
    fail('found zero Connections blocks in %d files' % len(files))
reds = sorted(glob.glob(os.path.join(reds_dir, '*.qml')))
if not reds:
    fail('has no red fixtures in ' + reds_dir)
for f in reds:
    if not any(mixed(members) for _, members in blocks(f)):
        fail('missed its red fixture ' + os.path.basename(f))
print('connections-style: %d file(s), %d block(s), %d mixed, %d red fixture(s) caught' % (len(files), total, len(bad), len(reds)))
sys.exit(1 if bad else 0)
PY
