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
OPEN = re.compile(r'\bConnections\s*\{(.*)$')
METHOD = re.compile(r'function\s+(on[A-Z]\w*)\s*\(')
BINDING = re.compile(r'(?:^|[;{}])\s*(on[A-Z]\w*)\s*:')

def fail(message):
    print('FAIL connections-style ' + message)
    sys.exit(1)

def blocks(path):
    # Sample input: "    Connections {" at indent 4, "        function onReady() {" at 8, "    }" closing at 4.
    lines = open(path).read().split('\n')
    found, broken = [], []
    for n, line in enumerate(lines):
        code = line.lstrip()
        m = OPEN.search(code)
        if not m or code.startswith(('//', '/*', '*')):
            continue
        indent, rest = line[:len(line) - len(code)], m.group(1).strip()
        following = [later for later in lines[n + 1:] if later.strip()]
        if rest.endswith('}') and not (following and following[0].startswith(indent + MEMBER_INDENT)):
            found.append((n + 1, [rest]))
            continue
        members = [rest]
        for later in lines[n + 1:]:
            if later.startswith(indent + '}'):
                found.append((n + 1, members))
                break
            if later.strip() and not later.startswith(indent + MEMBER_INDENT):
                broken.append('%s:%d has a member off its indent' % (path, n + 1))
                break
            if not later.startswith(indent + MEMBER_INDENT + ' ') and not later.strip().startswith(('//', '/*', '*')):
                members.append(later)
        else:
            broken.append('%s:%d never closes at its own indent' % (path, n + 1))
    return found, broken

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
    found, broken = blocks(f)
    bad += ['connections-style ' + b for b in broken]
    for line, members in found:
        total += 1
        hit = mixed(members)
        if hit:
            bad.append('%s:%d mixes function-style %s with binding-style %s' % (os.path.relpath(f, tree), line, hit[0], hit[1]))
for b in bad:
    print('FAIL ' + b)
if total == 0:
    fail('found zero Connections blocks in %d files' % len(files))
reds = sorted(glob.glob(os.path.join(reds_dir, '*.qml')))
cleans = sorted(glob.glob(os.path.join(reds_dir, 'clean', '*.qml')))
brokens = sorted(glob.glob(os.path.join(reds_dir, 'broken', '*.qml')))
if not reds or not cleans or not brokens:
    fail('needs red, clean and broken fixtures under ' + reds_dir)
for f in reds:
    if not any(mixed(members) for _, members in blocks(f)[0]):
        fail('missed its red fixture ' + os.path.basename(f))
for f in cleans:
    found, broken = blocks(f)
    if broken or any(mixed(members) for _, members in found):
        fail('misread its clean fixture ' + os.path.basename(f))
for f in brokens:
    if not blocks(f)[1]:
        fail('missed its broken fixture ' + os.path.basename(f))
print('connections-style: %d file(s), %d block(s), %d problem(s), %d fixture(s) held' % (len(files), total, len(bad), len(reds) + len(cleans) + len(brokens)))
sys.exit(1 if bad else 0)
PY
