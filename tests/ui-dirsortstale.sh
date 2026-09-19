# Defines the native stale-dirsize race case; tests/ui.sh supplies the guarded fixture and IPC helpers.

dirsortstale_wait_size() {
    local want="$1" state=""
    for _attempt in $(seq 1 300); do
        state=$(ipc dirSizeState 2>/dev/null || true)
        if jq -e --argjson want "$want" '.file["0"].bytes == $want' <<<"$state" >/dev/null 2>&1; then
            printf '%s' "$state"
            return 0
        fi
        sleep 0.05
    done
    printf 'dirSizeState did not reach bytes=%s; last=%s\n' "$want" "$state" >&2
    return 1
}

dirsortstale_cleanup() {
    [[ -n "${dirsortstale_test_ui:-}" ]] || return 0
    flea_ui="$dirsortstale_test_ui"
    flea_bin="$dirsortstale_candidate_bin"
    kill_flea
    flea_ui="$dirsortstale_saved_ui"
    flea_bin="$dirsortstale_saved_bin"
}

case_dirsortstale() {
    local candidate_ui="$flea_ui" candidate_bin="$flea_bin"
    local dir="$fixture_root/dirsortstale"
    local test_ui="$fixture_root/dirsortstale-ui"
    local proxy="$fixture_root/dirsortstale-flea"
    local proxy_py="$fixture_root/dirsortstale-proxy.py"
    local armed="$fixture_root/dirsortstale-armed"
    local events="$fixture_root/dirsortstale-events"
    local source="$dir/aaa" destination="$dir/zzz"
    local old_bytes new_bytes old_state new_state
    local flea_ui="$candidate_ui" flea_bin="$candidate_bin"
    dirsortstale_saved_ui="$candidate_ui"
    dirsortstale_saved_bin="$candidate_bin"
    dirsortstale_test_ui="$test_ui"
    dirsortstale_candidate_bin="$candidate_bin"
    trap dirsortstale_cleanup EXIT

    sandbox_scratch "$dir"
    mkdir -p "$source" "$destination"
    printf 's' > "$source/payload"
    head -c 257 /dev/zero > "$destination/payload"
    old_bytes=$(( $(stat -c %s "$source") + $(stat -c %s "$source/payload") ))
    new_bytes=$(( $(stat -c %s "$destination") + $(stat -c %s "$destination/payload") ))
    [[ "$old_bytes" != "$new_bytes" ]] || fail "dirsortstale: fixture sizes are indistinguishable"

    sandbox_scratch "$test_ui"
    cp -a "$candidate_ui"/. "$test_ui/"
    python3 - "$test_ui/Ipc.qml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = "        function dirSizeRequests(): int { return root.backend.dirSizeRequests }\n"
addition = needle + "        function dirSizeState(): string { return JSON.stringify(root.pane.dirSizeState) }\n"
if text.count(needle) != 1:
    raise SystemExit("dirsortstale: copied Ipc.qml getter anchor is not unique")
path.write_text(text.replace(needle, addition))
PY

    sandbox_require "$proxy_py"
    cat > "$proxy_py" <<'PY'
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys

real = os.environ["FLEA_DIRSORT_REAL_BIN"]
armed_path = Path(os.environ["FLEA_DIRSORT_ARMED"])
events_path = Path(os.environ["FLEA_DIRSORT_EVENTS"])
old_bytes = int(os.environ["FLEA_DIRSORT_OLD_BYTES"])

def log(value):
    with events_path.open("a") as stream:
        stream.write(value + "\n")

def emit(line):
    try:
        sys.stdout.buffer.write(line)
        sys.stdout.buffer.flush()
    except BrokenPipeError:
        raise OutputClosed

class OutputClosed(Exception):
    pass

def complete_lines(buffer):
    lines = []
    while True:
        end = buffer.find(b"\n")
        if end < 0:
            return lines
        lines.append(bytes(buffer[:end + 1]))
        del buffer[:end + 1]

def read_lines(key, buffer, name):
    try:
        chunk = os.read(key.fd, 65536)
    except OSError as error:
        raise RuntimeError(f"{name} read failed: {error}") from error
    if not chunk:
        if buffer:
            raise RuntimeError(f"{name} closed with an incomplete protocol line")
        return [], True
    buffer.extend(chunk)
    return complete_lines(buffer), False

child = subprocess.Popen([real, "--backend"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
selector = selectors.DefaultSelector()
selector.register(sys.stdin.buffer, selectors.EVENT_READ, "ui")
selector.register(child.stdout, selectors.EVENT_READ, "backend")
armed = False
injected = False
queued = []
ui_open = True
backend_open = True
ui_buffer = bytearray()
backend_buffer = bytearray()

def close_child_input():
    try:
        child.stdin.close()
    except (BrokenPipeError, OSError, ValueError):
        pass

try:
    while ui_open or backend_open:
        if not injected and armed_path.exists():
            armed = True
        ready = selector.select(0.1)
        for key, _ in [item for item in ready if item[0].data == "ui"]:
            lines, eof = read_lines(key, ui_buffer, "ui")
            for line in lines:
                if not injected and armed_path.exists():
                    armed = True
                request = {}
                try:
                    request = json.loads(line)
                except (TypeError, ValueError):
                    pass
                if armed and not injected and request.get("c") == "sort":
                    emit((json.dumps({"t": "dirsized", "row": 0, "bytes": old_bytes,
                                      "partial": False, "ms": 0.0}) + "\n").encode())
                    log("inject-before-sort")
                    child.stdin.write(line)
                    child.stdin.flush()
                    log("forward-sort")
                    for pending in queued:
                        emit(pending)
                    queued.clear()
                    injected = True
                    armed = False
                else:
                    child.stdin.write(line)
                    child.stdin.flush()
            if eof:
                selector.unregister(key.fileobj)
                ui_open = False
                close_child_input()
        for key, _ in [item for item in ready if item[0].data == "backend"]:
            lines, eof = read_lines(key, backend_buffer, "backend")
            for line in lines:
                if armed and not injected:
                    queued.append(line)
                else:
                    emit(line)
            if eof:
                selector.unregister(key.fileobj)
                backend_open = False
except OutputClosed:
    ui_open = False
    try:
        sys.stdout.buffer.close()
    except (BrokenPipeError, OSError, ValueError):
        pass
finally:
    close_child_input()
    if child.poll() is None:
        try:
            child.terminate()
        except ProcessLookupError:
            pass
        try:
            child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                child.kill()
            except ProcessLookupError:
                pass
            child.wait()
    selector.close()
PY

    sandbox_require "$proxy"
    cat > "$proxy" <<'SH'
#!/usr/bin/env bash
set -u
if [[ "${1:-}" == "--backend" ]]; then
    exec python3 "$FLEA_DIRSORT_PROXY_PY"
fi
exec "$FLEA_DIRSORT_REAL_BIN" "$@"
SH
    chmod +x "$proxy"

    sandbox_require "$armed"
    sandbox_require "$events"
    : > "$events"
    seed_ui_state "$fixture_root/dirsortstale-state" '{"sort":{"key":"name","reverse":false}}'
    kill_flea
    local -x FLEA_DIRSORT_REAL_BIN="$candidate_bin"
    local -x FLEA_DIRSORT_PROXY_PY="$proxy_py"
    local -x FLEA_DIRSORT_ARMED="$armed"
    local -x FLEA_DIRSORT_EVENTS="$events"
    local -x FLEA_DIRSORT_OLD_BYTES="$old_bytes"
    flea_ui="$test_ui"
    flea_bin="$proxy"
    launch "$dir"
    wait_listing 2
    old_state=$(dirsortstale_wait_size "$old_bytes") || fail "dirsortstale: initial source dirsize never arrived"
    : > "$armed"
    key S >/dev/null
    new_state=$(dirsortstale_wait_size "$new_bytes") || fail "dirsortstale: fresh destination dirsize never arrived"
    grep -Fx 'inject-before-sort' "$events" >/dev/null || fail "dirsortstale: proxy did not inject before sort"
    grep -Fx 'forward-sort' "$events" >/dev/null || fail "dirsortstale: proxy did not forward sort"
    [[ "$old_state" != "$new_state" ]] || fail "dirsortstale: source and destination states were identical"
    printf 'DIRSORTSTALE old=%s new=%s fixture_bytes=%s/%s\n' "$old_state" "$new_state" "$old_bytes" "$new_bytes"
}
