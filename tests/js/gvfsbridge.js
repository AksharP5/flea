.import "../../ui/js/GvfsBridge.js" as GvfsBridge

// The GVFS bridge board: phones and shares open through /run/user/$UID/gvfs, and Flea
// starts gvfsd-fuse the way gvfsd does when that folder is not serving yet. Every wait
// below is a scripted action list, so the 250 ms gate, the once-only start, the stay-put
// and the exact board sentences are all pinned with no process and no clock.
function run(check) {
    var dir = "/run/user/1000/gvfs"
    var phone = dir + "/mtp:host=Google_Pixel_8_37201FDH2001AB"
    var req = { path: phone, label: "Pixel 8", origin: "pane", bridgeDir: dir, fuseBin: "/usr/lib/gvfsd-fuse" }

    check("the bridge dir hangs off the runtime dir",
        GvfsBridge.bridgeDir("/run/user/1000"), dir)
    check("an empty runtime dir falls back to the board's own uid",
        GvfsBridge.bridgeDir(""), dir)
    check("a local folder never needs the bridge",
        GvfsBridge.needsBridge("/home/gm/Documents", dir), false)
    check("an empty path never needs it either", GvfsBridge.needsBridge("", dir), false)
    check("the bridge root itself needs it", GvfsBridge.needsBridge(dir, dir), true)
    check("a phone folder needs it", GvfsBridge.needsBridge(phone, dir), true)
    check("a share folder needs it",
        GvfsBridge.needsBridge(dir + "/smb-share:server=nas,share=data", dir), true)
    check("the portal documents next door do not",
        GvfsBridge.needsBridge("/run/user/1000/doc/1234/file.pdf", dir), false)

    check("the Starting line is the board's",
        GvfsBridge.startingLine("Pixel 8"), "Starting the GVFS bridge for Pixel 8")
    check("the failure line is the board's",
        GvfsBridge.failedLine("Pixel 8", "gvfsd-fuse exited with status 1"),
        "Pixel 8 needs the GVFS bridge, and it would not start · gvfsd-fuse exited with status 1")
    // The deadline's own wording is pinned beside its behaviour below.
    check("a Starting line reads as one", GvfsBridge.isStartingLine("Starting the GVFS bridge for Pixel 8"), true)
    check("any other sticky line does not", GvfsBridge.isStartingLine("Compressing 2 items to .zip"), false)
    check("the Starting line waits out the board's 250 ms", GvfsBridge.STARTING_MS, 250)

    // gvfsd's own spawn, measured on minipc: /usr/lib/gvfsd-fuse /run/user/1000/gvfs -f.
    check("the start argv is gvfsd's own",
        GvfsBridge.fuseArgv("/usr/lib/gvfsd-fuse", dir).join(" "),
        "/usr/lib/gvfsd-fuse " + dir + " -f")
    check("the binary defaults to the Arch path", GvfsBridge.fuseBin(""), "/usr/lib/gvfsd-fuse")
    check("a fake bridge command rides the environment",
        GvfsBridge.fuseBin("/sandbox/bin/gvfsd-fuse"), "/sandbox/bin/gvfsd-fuse")
    check("an empty label falls back to the folder's own leaf",
        GvfsBridge.displayName("", phone), "mtp:host=Google_Pixel_8_37201FDH2001AB")
    check("a label wins over the leaf", GvfsBridge.displayName("Pixel 8", phone), "Pixel 8")

    // A local folder opens at once and starts nothing.
    var local = GvfsBridge.create()
    var localActs = GvfsBridge.ensure(local, { path: "/home/gm", label: "", origin: null, bridgeDir: dir, fuseBin: "" })
    check("a local folder is ready at once", localActs.length + "|" + localActs[0].op, "1|ready")
    check("and nothing was started for it", local.starts, 0)

    // The served folder answers its check and never starts the bridge.
    var served = GvfsBridge.create()
    GvfsBridge.ensure(served, req)
    var servedActs = GvfsBridge.onChecked(served, true)
    check("a served folder is ready on its check", servedActs.length + "|" + servedActs[0].op, "1|ready")
    check("ready names the folder asked for", servedActs[0].path, phone)
    check("and the bridge was never started", served.starts, 0)

    // The unserved folder is file-checked before anything starts: a file under a
    // served bridge must never start a redundant one (I-3), so test -d failing is not
    // yet a reason to start.
    var slow = GvfsBridge.create()
    var first = GvfsBridge.ensure(slow, req)
    check("an unserved folder is checked first", first.length + "|" + first[0].op, "1|check")
    check("a timer during the check claims nothing", GvfsBridge.onElapsed(slow).length, 0)
    var fileCheck = GvfsBridge.onChecked(slow, false)
    check("a failed directory check asks for the file check, not a start",
        fileCheck.length + "|" + fileCheck[0].op, "1|checkFile")
    check("still nothing started", slow.starts, 0)
    var start = GvfsBridge.onCheckedFile(slow, false)
    check("a missing folder starts the bridge", start.length + "|" + start[0].op, "1|start")
    check("with gvfsd's own argv", start[0].argv.join(" "),
        "/usr/lib/gvfsd-fuse " + dir + " -f")
    var again = GvfsBridge.ensure(slow, req)
    check("a second open while it comes up starts nothing more", again.length, 0)
    var stranger = GvfsBridge.ensure(slow, { path: dir + "/sftp:host=nas/home/tom", label: "nas",
        origin: null, bridgeDir: dir, fuseBin: req.fuseBin })
    check("another folder meanwhile is refused rather than starting a second bridge",
        stranger.length + "|" + stranger[0].op, "1|refuse")
    check("the refusal names the wait it stands behind",
        stranger[0].text, "Another network location is still opening; give it a moment.")
    check("still exactly one start", slow.starts, 1)

    // A file under a served bridge is ready without any start.
    var filed = GvfsBridge.create()
    GvfsBridge.ensure(filed, { path: phone + "/note.txt", label: "note", origin: null,
        bridgeDir: dir, fuseBin: req.fuseBin })
    GvfsBridge.onChecked(filed, false)
    var fileReady = GvfsBridge.onCheckedFile(filed, true)
    check("a served file is ready on its file check",
        fileReady.length + "|" + fileReady[0].op + "|" + fileReady[0].isDir, "1|ready|false")
    check("and the bridge was never started for it", filed.starts, 0)

    // The window stays put: no ready and no failure until the folder is served.
    check("a fruitless poll answers nothing at all", GvfsBridge.onPolled(slow, false).length, 0)
    var show = GvfsBridge.onElapsed(slow)
    check("the 250 ms timer shows the Starting line", show.length + "|" + show[0].op, "1|show")
    check("word for word", show[0].text, "Starting the GVFS bridge for Pixel 8")
    var classifying = GvfsBridge.onPolled(slow, true)
    check("a served poll classifies before it opens",
        classifying.length + "|" + classifying[0].op, "1|classify")
    var landed = GvfsBridge.onClassified(slow, true)
    check("the folder landing opens it",
        landed.length + "|" + landed[0].op + "|" + landed[0].path + "|" + landed[0].isDir,
        "1|ready|" + phone + "|true")
    check("and the wait is over", slow.phase, "idle")

    // One deadline for the whole ensure: a hung check, a bridge that never serves and a
    // classify that never answers all end in the board's failure line, once.
    var hungCheck = GvfsBridge.create()
    GvfsBridge.ensure(hungCheck, req)
    check("the whole ensure shares one deadline", GvfsBridge.ENSURE_MS, 15000)
    check("a timeout words itself the way the board does",
        GvfsBridge.timeoutReason(), "waiting for the folder timed out")
    var hungFailed = GvfsBridge.onTimeout(hungCheck)
    check("a hung check fails at the deadline", hungFailed.length + "|" + hungFailed[0].op, "1|fail")
    check("word for word",
        hungFailed[0].text, "Pixel 8 needs the GVFS bridge, and it would not start · waiting for the folder timed out")
    check("and the wait is over", hungCheck.phase, "idle")
    var hung = GvfsBridge.create()
    GvfsBridge.ensure(hung, req)
    GvfsBridge.onChecked(hung, false)
    GvfsBridge.onCheckedFile(hung, false)
    check("a hung poll answers nothing", GvfsBridge.onPolled(hung, false).length, 0)
    check("a late exit is not a second start", hung.starts, 1)
    var hungFailed2 = GvfsBridge.onTimeout(hung)
    check("a bridge that never serves fails at the deadline",
        hungFailed2.length + "|" + hungFailed2[0].op, "1|fail")
    var sorting = GvfsBridge.create()
    GvfsBridge.ensure(sorting, req)
    GvfsBridge.onChecked(sorting, false)
    GvfsBridge.onCheckedFile(sorting, false)
    GvfsBridge.onPolled(sorting, true)
    var sortingFailed = GvfsBridge.onTimeout(sorting)
    check("a classify that never answers fails at the deadline",
        sortingFailed.length + "|" + sortingFailed[0].op, "1|fail")
    check("a timeout with nobody waiting answers nothing", GvfsBridge.onTimeout(served).length, 0)
    check("an exit after the open is nobody's failure", GvfsBridge.onTimeout(served).length, 0)
}
