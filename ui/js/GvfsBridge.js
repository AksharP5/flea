.pragma library

// Phones and shares open through the GVFS FUSE bridge, and Flea starts it the way gvfsd
// does when the folder is not serving yet. The QML service owns the processes and the two
// timers; this module owns every decision, so tests/js/gvfsbridge.js pins each one with no
// process and no clock. An action is what the service executes next: check (test -d the
// folder), start (run gvfsd-fuse once), verify (one last check after an exit), ready (open
// the folder), show (the Starting line), fail (the board's error line) or refuse (busy).

// The Starting line stands until the service's own 250 ms timer fires, so a bridge that is
// already coming up never flashes it.
var STARTING_MS = 250
// A test -d costs about a millisecond, so this bounds the open behind a starting bridge.
var POLL_MS = 150

function create() {
    return { phase: "idle", waiter: null, starts: 0, exitCode: 0 }
}

// Sample input: "/run/user/1000" answers "/run/user/1000/gvfs", and "" answers the board's
// own "/run/user/1000/gvfs", because XDG_RUNTIME_DIR is always set in a systemd session.
function bridgeDir(runtimeDir) {
    var dir = String(runtimeDir || "")
    return dir.length > 0 ? dir + "/gvfs" : "/run/user/1000/gvfs"
}

// Sample input: "/run/user/1000/gvfs/mtp:host=X" needs it, "/home/gm" and the portal's
// "/run/user/1000/doc/1/file.pdf" do not. The bridge root itself counts, because with the
// bridge down even it is unserved.
function needsBridge(path, dir) {
    var text = String(path || "")
    var root = String(dir || "")
    return root.length > 0 && (text === root || text.indexOf(root + "/") === 0)
}

// Sample input: "Pixel 8" answers "Starting the GVFS bridge for Pixel 8".
function startingLine(name) {
    return "Starting the GVFS bridge for " + name
}

// Sample input: ("Pixel 8", "gvfsd-fuse exited with status 1") answers the board's failure
// line word for word.
function failedLine(name, reason) {
    return name + " needs the GVFS bridge, and it would not start · " + reason
}

// Sample input: 1 answers "gvfsd-fuse exited with status 1".
function exitReason(code) {
    return "gvfsd-fuse exited with status " + code
}

function startFailedReason() {
    return "gvfsd-fuse could not start"
}

// The openShare guard's own refusal, reused so two waiters never start two bridges.
function busyReason() {
    return "Another network location is still opening; give it a moment."
}

// The status strip lights its busy mark exactly while a Starting line stands.
function isStartingLine(text) {
    return String(text || "").indexOf("Starting the GVFS bridge for ") === 0
}

// Sample input: "" with "/run/user/1000/gvfs/mtp:host=X" answers that leaf.
function displayName(label, path) {
    var name = String(label || "")
    if (name.length > 0)
        return name
    var text = String(path || "")
    var cut = text.lastIndexOf("/")
    return cut < 0 ? text : text.substring(cut + 1)
}

// Sample input: "" answers "/usr/lib/gvfsd-fuse", the binary gvfsd spawns on Arch.
function fuseBin(env) {
    var bin = String(env || "")
    return bin.length > 0 ? bin : "/usr/lib/gvfsd-fuse"
}

// Sample input: ("/usr/lib/gvfsd-fuse", "/run/user/1000/gvfs") answers gvfsd's own spawn,
// "/usr/lib/gvfsd-fuse /run/user/1000/gvfs -f", measured on minipc.
function fuseArgv(bin, dir) {
    return [bin, dir, "-f"]
}

function readyFor(waiter) {
    return [{ op: "ready", path: waiter.path, origin: waiter.origin }]
}

function reset(st) {
    st.phase = "idle"
    st.waiter = null
}

// A local folder opens at once and starts nothing; a gvfs folder is checked first.
function ensure(st, req) {
    if (!needsBridge(req.path, req.bridgeDir))
        return [{ op: "ready", path: req.path, origin: req.origin }]
    if (st.phase !== "idle") {
        if (st.waiter && st.waiter.path === req.path)
            return []
        return [{ op: "refuse", text: busyReason(), origin: req.origin }]
    }
    st.phase = "checking"
    st.waiter = { path: req.path, label: displayName(req.label, req.path), origin: req.origin,
        bridgeDir: req.bridgeDir, fuseBin: fuseBin(req.fuseBin), shown: false }
    return [{ op: "check", path: req.path }]
}

// The check answered: a served folder opens, an unserved one starts the bridge once.
function onChecked(st, served) {
    if (st.phase !== "checking" || !st.waiter)
        return []
    if (served) {
        var done = readyFor(st.waiter)
        reset(st)
        return done
    }
    st.phase = "waiting"
    st.starts += 1
    return [{ op: "start", argv: fuseArgv(st.waiter.fuseBin, st.waiter.bridgeDir) }]
}

// The 250 ms timer fired: the Starting line appears only now, and only while waiting.
function onElapsed(st) {
    if (st.phase !== "waiting" || !st.waiter || st.waiter.shown)
        return []
    st.waiter.shown = true
    return [{ op: "show", text: startingLine(st.waiter.label), origin: st.waiter.origin }]
}

// A poll answered: the folder landing opens it, anything else waits on.
function onPolled(st, served) {
    if (st.phase !== "waiting" || !st.waiter)
        return []
    if (!served)
        return []
    var done = readyFor(st.waiter)
    reset(st)
    return done
}

// The bridge exited while waited on: one last check first, because a bridge started beside
// this one may have served the folder anyway, and only then the board's failure line.
function onExited(st, code) {
    if (st.phase !== "waiting" || !st.waiter)
        return []
    st.phase = "verifying"
    st.exitCode = code
    return [{ op: "verify", path: st.waiter.path }]
}

function onVerified(st, served) {
    if (st.phase !== "verifying" || !st.waiter)
        return []
    if (served) {
        var done = readyFor(st.waiter)
        reset(st)
        return done
    }
    var failed = [{ op: "fail", text: failedLine(st.waiter.label, exitReason(st.exitCode)),
        origin: st.waiter.origin }]
    reset(st)
    return failed
}

// The bridge process never started at all: fail loudly rather than poll forever.
function onStartFailed(st) {
    if ((st.phase !== "waiting" && st.phase !== "verifying") || !st.waiter)
        return []
    var failed = [{ op: "fail", text: failedLine(st.waiter.label, startFailedReason()),
        origin: st.waiter.origin }]
    reset(st)
    return failed
}
