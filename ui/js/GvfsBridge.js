.pragma library

// Phones and shares open through the GVFS FUSE bridge, and Flea starts it the way gvfsd
// does when the folder is not serving yet. The QML service owns the processes and the three
// timers; this module owns every decision, so tests/js/gvfsbridge.js pins each one with no
// process and no clock. An action is what the service executes next: check (test -d the
// folder), checkFile (test -e it), start (run gvfsd-fuse once, detached), classify (test -d
// it once it is served), ready (open the folder, or hand a file to the opener), show (the
// Starting line), fail (the board's error line) or refuse (busy).
//
// The start is detached: closing the rail or the chooser never takes gvfsd-fuse down with it,
// so no exit status ever reaches the board and the folder poll's own deadline is the failure
// signal. The check stays a helper process rather than a backend peek, an order of magnitude
// slower per check in one headless sample (sub-millisecond both) but bounded: a wedged FUSE
// path hangs a helper the deadline kills and nothing else. A served path is classified by
// the kernel too, so a file under a live bridge is ready without any start (I-3) and a
// directory costs the one check it always did.

// The Starting line stands until the service's own 250 ms timer fires, so a bridge that is
// already coming up never flashes it.
var STARTING_MS = 250
// A test costs about half a millisecond, so this bounds the open behind a starting bridge.
var POLL_MS = 150
// One deadline for the whole ensure, checking, file-checking, waiting and classifying: a hung
// helper and a bridge that never serves are the same wait to the watcher, and both end in the
// board's failure line through onTimeout, once.
var ENSURE_MS = 15000

function create() {
    return { phase: "idle", waiter: null, starts: 0 }
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

// Sample input: ("Pixel 8", "waiting for the folder timed out") answers the board's
// failure line word for word.
function failedLine(name, reason) {
    return name + " needs the GVFS bridge, and it would not start · " + reason
}

// Sample input: ("Pixel 8") answers the reason a wait that outlived ENSURE_MS carries.
function timeoutReason() {
    return "waiting for the folder timed out"
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

// Sample input: a ready waiter with isDir true opens the folder, with false hands the
// file to the opener, so a typed network URL naming a file is never listed as a folder.
function readyFor(waiter, isDir) {
    return [{ op: "ready", path: waiter.path, origin: waiter.origin, isDir: isDir !== false }]
}

function reset(st) {
    st.phase = "idle"
    st.waiter = null
}

// A local folder opens at once and starts nothing; a gvfs folder is checked first.
function ensure(st, req) {
    if (!needsBridge(req.path, req.bridgeDir))
        return readyFor({ path: req.path, origin: req.origin }, true)
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

// The check answered for a directory: a served one opens, anything else is file-checked
// before anything starts, because test -d fails for a file under a live bridge too.
function onChecked(st, dirServed) {
    if (st.phase !== "checking" || !st.waiter)
        return []
    if (dirServed) {
        var done = readyFor(st.waiter, true)
        reset(st)
        return done
    }
    st.phase = "checkingFile"
    return [{ op: "checkFile", path: st.waiter.path }]
}

// The file check answered: a served file is ready without any start, and only a path that is
// neither a directory nor anything at all starts the bridge, exactly once per wait.
function onCheckedFile(st, exists) {
    if (st.phase !== "checkingFile" || !st.waiter)
        return []
    if (exists) {
        var done = readyFor(st.waiter, false)
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

// A poll answered: the folder landing is classified before it opens, anything else waits
// on. The classify is one test -d, so a file the wait started for still lands as a file.
function onPolled(st, served) {
    if (st.phase !== "waiting" || !st.waiter)
        return []
    if (!served)
        return []
    st.phase = "classifying"
    return [{ op: "classify", path: st.waiter.path }]
}

// The classify answered for a served path: directories open, files go to the opener.
function onClassified(st, isDir) {
    if (st.phase !== "classifying" || !st.waiter)
        return []
    var done = readyFor(st.waiter, isDir)
    reset(st)
    return done
}

// The whole-ensure deadline fired: whatever leg was still running ends here, in the board's
// failure line. The service kills its helper beside this and swallows that helper's own exit,
// so the line answers once however the race landed.
function onTimeout(st) {
    if ((st.phase !== "checking" && st.phase !== "checkingFile" && st.phase !== "waiting"
            && st.phase !== "classifying") || !st.waiter)
        return []
    var failed = [{ op: "fail", text: failedLine(st.waiter.label, timeoutReason()),
        origin: st.waiter.origin }]
    reset(st)
    return failed
}

// A cancelled wait answers nothing and starts nothing; the caller clears its own line.
function cancel(st) {
    reset(st)
    return []
}
