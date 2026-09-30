#!/usr/bin/env python3
"""Deterministic interrupted ui.json proof; called inside uistate.sh guarded sandbox."""
import hashlib
import os
import subprocess
import sys
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
binary = str(Path(sys.argv[2]).resolve())
assert root.name.startswith("flea-uistate-det-")
assert (root / ".flea-test-sandbox").is_file()
assert not root.is_relative_to(Path.home().resolve())
assert Path(binary).is_file()
# Sample input: 7d2f…  /tmp/…/ui.json.12345.tmp receipt line `12345 7 /…/ui.json.12345.tmp`.
library = root / "write-block.so"
subprocess.run(["cc", "-shared", "-fPIC", "-o", str(library),
                str(Path(__file__).with_name("uistate-write-block.c")), "-ldl"], check=True)

digest = hashlib.sha256(Path(binary).read_bytes()).hexdigest()
print(f"deterministic binary sha256={digest}", flush=True)

def run_flea(state, config, patch, extra_env):
    env = dict(os.environ, XDG_STATE_HOME=str(state),
               XDG_CONFIG_HOME=str(config))
    env.update(extra_env)
    return subprocess.Popen([binary, "--ui-state", patch], env=env,
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)

def wait_path(path, deadline_s, label):
    end = time.monotonic() + deadline_s
    while not path.exists():
        assert time.monotonic() < end, f"{label} missing: {path}"
        time.sleep(0.005)

def read_bytes(path):
    return Path(path).read_bytes()

# Reference run without barrier gives the exact complete expected state.
ref_state = root / "ref" / "state"
ref_config = root / "ref" / "config"
ref_state.mkdir(parents=True)
ref_config.mkdir(parents=True)
ref_ui = ref_state / "flea" / "ui.json"
p = run_flea(ref_state, ref_config, '{"view":"list"}', {})
out, err = p.communicate(timeout=10)
assert p.returncode == 0, f"reference seed failed: {p.returncode} {err}"
p = run_flea(ref_state, ref_config, '{"view":"grid"}', {})
out, err = p.communicate(timeout=10)
assert p.returncode == 0, f"reference patch failed: {p.returncode} {err}"
expected = read_bytes(ref_ui)
assert b'"view": "grid"' in expected, f"reference state incomplete: {expected[:200]!r}"

# Killed proof holds the owned tmp inside its first write, then SIGKILLs.
case = root / "killed"
state = case / "state"
config = case / "config"
(state / "flea").mkdir(parents=True)
(config).mkdir(parents=True)
p = run_flea(state, config, '{"view":"list"}', {})
out, err = p.communicate(timeout=10)
assert p.returncode == 0, f"killed seed failed: {p.returncode} {err}"
before = read_bytes(state / "flea" / "ui.json")
before_ino = (state / "flea" / "ui.json").stat().st_ino
entered = case / "entered"
release = case / "release"
if entered.exists():
    entered.unlink()
if release.exists():
    release.unlink()
child = run_flea(state, config, '{"view":"grid"}', {
    "LD_PRELOAD": str(library),
    "FLEA_TEST_UIS_ENTERED": str(entered),
    "FLEA_TEST_UIS_RELEASE": str(release),
})
try:
    wait_path(entered, 10, "barrier receipt")
    receipt = entered.read_text().strip()
    print(f"deterministic receipt {receipt}", flush=True)
    parts = receipt.split(" ", 2)
    assert len(parts) == 3, f"receipt shape: {receipt!r}"
    assert parts[0] == str(child.pid), f"receipt pid {parts[0]} != child {child.pid}"
    tmp_path = Path(parts[2])
    assert tmp_path.is_absolute() and tmp_path.is_relative_to(root), f"tmp outside root: {parts[2]}"
    allow_direct = os.environ.get("FLEA_TEST_UIS_ALLOW_DIRECT") == "1"
    if allow_direct:
        assert parts[2].endswith(f"ui.json.{child.pid}.tmp") or parts[2].endswith("/ui.json"), receipt
    else:
        assert parts[2].endswith(f"ui.json.{child.pid}.tmp"), receipt
    assert tmp_path.is_file(), f"tmp missing: {tmp_path}"
    size = tmp_path.stat().st_size
    assert size > 0, "temp is empty, so the kill proves nothing"
    assert size < len(expected), f"temp size {size} not incomplete vs {len(expected)}"
    live = read_bytes(state / "flea" / "ui.json")
    assert live == before, "ui.json moved before the kill"
    child.kill()
    try:
        child.wait(timeout=10)
    except subprocess.TimeoutExpired:
        child.kill()
        raise AssertionError("killed child did not reap")
    assert child.returncode == -9, f"killed child rc={child.returncode}"
    after_kill = read_bytes(state / "flea" / "ui.json")
    assert after_kill == before, f"interrupted publication left partial: {after_kill[:200]!r}"
    assert (state / "flea" / "ui.json").stat().st_ino == before_ino, "kill replaced inode"
    print(f"ok   deterministic interrupted publication kept {len(before)} bytes, tmp {size} bytes", flush=True)
finally:
    if child.poll() is None:
        child.kill()
        child.wait(timeout=10)
    try:
        child.stdout.close()
    except Exception:
        pass
    try:
        child.stderr.close()
    except Exception:
        pass

# Released control holds first with release absent, then releases to the exact expected state.
case2 = root / "released"
state2 = case2 / "state"
config2 = case2 / "config"
(state2 / "flea").mkdir(parents=True)
config2.mkdir(parents=True)
p = run_flea(state2, config2, '{"view":"list"}', {})
p.communicate(timeout=10)
assert p.returncode == 0
seed2 = read_bytes(state2 / "flea" / "ui.json")
seed2_ino = (state2 / "flea" / "ui.json").stat().st_ino
entered2 = case2 / "entered"
release2 = case2 / "release"
if entered2.exists():
    entered2.unlink()
if release2.exists():
    release2.unlink()
child2 = run_flea(state2, config2, '{"view":"grid"}', {
    "LD_PRELOAD": str(library),
    "FLEA_TEST_UIS_ENTERED": str(entered2),
    "FLEA_TEST_UIS_RELEASE": str(release2),
})
try:
    wait_path(entered2, 10, "released barrier receipt")
    receipt2 = entered2.read_text().strip()
    print(f"released receipt {receipt2}", flush=True)
    parts2 = receipt2.split(" ", 2)
    assert len(parts2) == 3, f"receipt shape: {receipt2!r}"
    assert parts2[0] == str(child2.pid), f"receipt pid {parts2[0]} != child {child2.pid}"
    tmp2 = Path(parts2[2])
    assert tmp2.is_absolute() and tmp2.is_relative_to(root), f"tmp outside root: {parts2[2]}"
    if os.environ.get("FLEA_TEST_UIS_ALLOW_DIRECT") == "1":
        assert parts2[2].endswith(f"ui.json.{child2.pid}.tmp") or parts2[2].endswith("/ui.json"), receipt2
    else:
        assert parts2[2].endswith(f"ui.json.{child2.pid}.tmp"), receipt2
    assert tmp2.is_file(), f"tmp missing: {tmp2}"
    size2 = tmp2.stat().st_size
    assert size2 > 0 and size2 < len(expected), f"held tmp size {size2} not a partial prefix"
    assert read_bytes(state2 / "flea" / "ui.json") == seed2, "published bytes moved during hold"
    assert (state2 / "flea" / "ui.json").stat().st_ino == seed2_ino, "hold replaced inode"
    assert child2.poll() is None, "child exited before release, so the hold proves nothing"
    release2.touch()
    out2, err2 = child2.communicate(timeout=15)
    assert child2.returncode == 0, f"released run failed: {child2.returncode} {err2}"
    assert entered2.is_file(), "released barrier never intercepted, so the control proves nothing"
    got = read_bytes(state2 / "flea" / "ui.json")
    assert got == expected, f"released state differs: {got[:200]!r} vs {expected[:200]!r}"
    assert (state2 / "flea" / "ui.json").stat().st_ino != seed2_ino, "released write did not replace inode"
    left = list((state2 / "flea").glob("ui.json.*.tmp"))
    assert left == [], f"released temp survives: {left}"
    print(f"ok   released barrier published {len(got)} bytes with new inode", flush=True)
finally:
    if child2.poll() is None:
        child2.kill()
        child2.wait(timeout=10)

print("deterministic ui-state proof: 2 checks passed", flush=True)
