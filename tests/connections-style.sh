#!/usr/bin/env bash
# The Connections-style sweep: Qt connects only one handler style per Connections
# object, so a block mixing `function onFoo()` with `onFoo: ...` leaves the method
# side silently unwired (f036net: NetworkMounts.qml's bridge onReady never fired).
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
tree=${1:-$PWD}
python3 - "$tree" <<'PY'
# Sample input: a Connections block holding "function onReady(path) {...}" beside
# "onStarting: function (text) {...}"; sample output: the FAIL line below naming
# the file and the block's opening line.
import glob, os, re, sys

def blocks(text):
    out = []
    for m in re.finditer(r'\bConnections\s*\{', text):
        depth, i, line = 0, m.end() - 1, text.count('\n', 0, m.start()) + 1
        s, in_str, esc = i, False, False
        while i < len(text):
            c = text[i]
            if in_str:
                if esc:
                    esc = False
                elif c == '\\':
                    esc = True
                elif c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
            elif c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    out.append((line, text[s:i + 1]))
                    break
            i += 1
    return out

def clean(body):
    body = re.sub(r'/\*.*?\*/', '', body, flags=re.S)
    return '\n'.join(l.split('//')[0] for l in body.split('\n'))

bad = []
files = sorted(glob.glob(os.path.join(sys.argv[1], 'ui', '*.qml'))
    + glob.glob(os.path.join(sys.argv[1], 'ui', 'boot', '*.qml')))
for f in files:
    text = open(f).read()
    for line, body in blocks(text):
        c = clean(body)
        meth = re.findall(r'^\s*function\s+(on[A-Z][A-Za-z0-9_]*)\s*\(', c, flags=re.M)
        bind = re.findall(r'^\s*(on[A-Z][A-Za-z0-9_]*)\s*:', c, flags=re.M)
        if meth and bind:
            bad.append('%s:%d mixes function-style %s with binding-style %s'
                % (os.path.relpath(f, sys.argv[1]), line, meth[0], bind[0]))
for b in bad:
    print('FAIL ' + b)
print('connections-style: %d file(s) swept, %d mixed block(s)' % (len(files), len(bad)))
sys.exit(1 if bad else 0)
PY
