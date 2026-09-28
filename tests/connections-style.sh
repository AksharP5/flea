#!/usr/bin/env bash
# Qt wires one Connections handler style per block, so a mixed block drops the method side.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
arg=${1:-}
if [ -n "$arg" ]; then tree=$(realpath -m -- "$arg") || exit 1; else tree=""; fi
cd "$(dirname "$0")/.." || exit 1
if [ -z "$tree" ]; then tree=$PWD; fi
# Sample input: Connections holding function onReady beside onFailed colon; output: FAIL file:line naming both styles.
python3 - "$tree" <<'PY'
# A grep loop cannot track nested braces across quotes and comments, so the scan stays in python3.
import glob, os, re, sys
def blank(out, start, end):
    for k in range(start, end):
        if out[k] != '\n':
            out[k] = ' '
def masked(text):
    # Comments and string contents turn to spaces, newlines kept, so line numbers stay true.
    out, i, n, quote = list(text), 0, len(text), ''
    while i < n:
        c = text[i]
        if quote:
            step = 2 if c == '\\' and i + 1 < n else 1
            if c == quote:
                quote = ''
            blank(out, i, i + step)
            i += step
        elif text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j == -1 else j
            blank(out, i, j)
            i = j
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j == -1 else j + 2
            blank(out, i, j)
            i = j
        elif c in '"\'':
            quote = c
            blank(out, i, i + 1)
            i += 1
        else:
            i += 1
    return ''.join(out)
def blocks(clean):
    out = []
    for m in re.finditer(r'\bConnections\s*\{', clean):
        depth = 0
        i = m.end() - 1
        s = i
        line = clean.count('\n', 0, m.start()) + 1
        while i < len(clean):
            c = clean[i]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    out.append((line, clean[s:i + 1]))
                    break
            i += 1
    return out
def mixed_in(body):
    meth = re.findall(r'^\s*function\s+(on[A-Z][A-Za-z0-9_]*)\s*\(', body, flags=re.M)
    bind = re.findall(r'^\s*(on[A-Z][A-Za-z0-9_]*)\s*:', body, flags=re.M)
    if meth and bind:
        return meth[0], bind[0]
    return None
tree = sys.argv[1]
files = sorted(glob.glob(os.path.join(tree, 'ui', '*.qml')) + glob.glob(os.path.join(tree, 'ui', 'boot', '*.qml')))
if not files:
    print('FAIL connections-style swept zero files under ' + tree)
    sys.exit(1)
total = 0
bad = []
for f in files:
    text = open(f).read()
    for line, body in blocks(masked(text)):
        total += 1
        hit = mixed_in(body)
        if hit:
            bad.append('%s:%d mixes function-style %s with binding-style %s' % (os.path.relpath(f, tree), line, hit[0], hit[1]))
if total == 0:
    print('FAIL connections-style found zero Connections blocks in %d files' % len(files))
    sys.exit(1)
fixtures = sorted(glob.glob(os.path.join(tree, 'tests', 'fixtures', 'connections-style', '*.qml')))
if len(fixtures) != 2:
    print('FAIL connections-style expected 2 red fixtures, found %d' % len(fixtures))
    sys.exit(1)
for f in fixtures:
    seen = [mixed_in(body) for _, body in blocks(masked(open(f).read()))]
    if not any(seen):
        print('FAIL red fixture missed: ' + os.path.relpath(f, tree))
        sys.exit(1)
for b in bad:
    print('FAIL ' + b)
print('connections-style: %d file(s) swept, %d block(s), %d mixed block(s)' % (len(files), total, len(bad)))
sys.exit(1 if bad else 0)
PY
