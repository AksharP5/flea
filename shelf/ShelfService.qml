import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The only thing here that touches the outside world: the pile's own state file, which the
// `flea shelf` backend writes and this reads. The widget never learns how a file got into the pile.
Item {
  id: root
  visible: false

  property var settings: ({})

  readonly property string home: Quickshell.env("HOME") || ""
  // XDG_STATE_HOME is what the driven tests point at a sandbox, the way every other plugin reads it.
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/omarchy/flea-shelf"
  readonly property string statePath: root.stateDir + "/shelf.json"

  property var pile: Model.empty()
  readonly property int count: root.pile.count
  readonly property bool holding: root.pile.count > 0
  // Nothing is known before the first read answers, so the mark must not assert empty on a shell start.
  property bool read: false

  // Re-clamped on read, so a hand-edited shell.json cannot poison the timer.
  function intSetting(name, fallback, minValue, maxValue) {
    var raw = root.settings ? root.settings[name] : undefined
    var n = parseInt(raw, 10)
    if (!isFinite(n)) n = fallback
    return Math.max(minValue, Math.min(maxValue, n))
  }

  readonly property int refreshIntervalSec: root.intSetting("refreshIntervalSec", 5, 1, 120)
  // ShelfEmpty rule 7: the tray's count is a clamped setting, and zero removes the tray.
  readonly property int recentCaptures: root.intSetting("recentCaptures", 3, 0, 6)
  // EdgeRail rules 3 and 5: the dwell is clamped on every read, and the edge is one of four words.
  readonly property int railDwellMs: root.intSetting("railDwell", 120, 60, 600)
  property string barPosition: "top"
  readonly property string railEdge: {
    var raw = root.settings ? root.settings["railEdge"] : undefined
    var name = String(raw === undefined || raw === null ? "" : raw).trim().toLowerCase()
    if (name === "off" || name === "left" || name === "right" || name === "bottom") {
      return name
    }
    // The edge opposite the bar, and the right edge when that would be the bar's own.
    return root.barPosition === "left" ? "right" : (root.barPosition === "right" ? "left" : "bottom")
  }
  // The command that owns the pile. It is "flea" on an installed box and a path on a development
  // tree, and it is a setting because the plugin ships as its own repository beside the app.
  readonly property string fleaCommand: {
    var raw = root.settings ? root.settings["fleaCommand"] : undefined
    var name = String(raw === undefined || raw === null ? "" : raw).trim()
    return name.length > 0 ? name : "flea"
  }
  readonly property int millisecondsPerSecond: 1000

  // BarMark's Land: the pile grew, by any route, which is one of the few things this widget itself
  // can see. Nothing is emitted for the first read, which is a shelf that was already holding.
  signal grew()

  function load(text) {
    var next = Model.parse(text)
    if (root.read && next.count > root.pile.count) {
      root.grew()
    }
    root.pile = next
    root.read = true
  }

  FileView {
    id: file
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.load(file.text())
    // A pile nobody has started yet has no file at all, which is the empty shelf and not an error.
    onLoadFailed: root.load("")
  }

  // DragOut rule 1: the token is minted before the platform loop starts, and the backend binds it to
  // these entries and this intent. The shelf is another process, so this is a command and not a wire
  // line; flea answers with the token on stdout and nothing else.
  signal minted(string token, bool moving)
  signal failed(string why)

  property bool moving: true

  function mintDrag(wantsMove) {
    if (mint.running || root.pile.count === 0) {
      return
    }
    root.moving = wantsMove
    var argv = [root.fleaCommand, "shelf", "drag-begin", wantsMove ? "move" : "copy"]
    for (var i = 0; i < root.pile.items.length; i++) {
      argv.push(root.pile.items[i].path)
    }
    mint.command = argv
    mint.running = true
  }

  // Main rule 6: the reference leaves the pile and the file it names is not touched.
  function forget(path) {
    drop.command = [root.fleaCommand, "shelf", "forget", path]
    drop.running = true
  }

  Process {
    id: drop
    running: false
    onExited: function (code) { if (code !== 0) root.failed("The shelf kept that row.") }
  }

  Process {
    id: mint
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var token = String(text).trim()
        if (token.length > 0) root.minted(token, root.moving)
        else root.failed("The shelf could not start that drag.")
      }
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  // Main rule 4's budget: a size is asked for only while the card is drawing the row, one path per
  // request, and never twice for the same path. DirSizes.js is the model for the gating and not a
  // call this can make: its queue indexes the active listing, which the shelf is not.
  property bool drawing: false
  property var sizes: ({})
  property string asking: ""

  onDrawingChanged: {
    root.askSize()
    root.askCaptures()
  }
  onPileChanged: {
    root.sizes = Model.keep(root.sizes, root.pile)
    root.askSize()
  }

  function askSize() {
    if (measure.running || !root.drawing) {
      return
    }
    var path = Model.nextSize(root.pile, root.sizes)
    if (path.length === 0) {
      return
    }
    root.asking = path
    measure.command = [root.fleaCommand, "shelf", "size", path]
    measure.running = true
  }

  // Sample input: `4096 1`, the bytes then whether the walk was cut short. A path that could not be
  // read answers -1, which the card draws as the same dot a pending row draws, and is not re-asked.
  function answered(text) {
    var fields = String(text).trim().split(" ")
    var bytes = Number(fields[0])
    var next = {}
    for (var path in root.sizes) {
      next[path] = root.sizes[path]
    }
    next[root.asking] = isFinite(bytes) && fields.length === 2
      ? { bytes: bytes, partial: fields[1] === "1" }
      : { bytes: -1, partial: false }
    root.sizes = next
    root.asking = ""
    root.askSize()
  }

  // ShelfEmpty rule 4: the two capture directories are resolved by the backend, exactly the way
  // Omarchy's own capture scripts resolve them, so the widget stays a display.
  property var captures: []

  function askCaptures() {
    if (list.running || !root.drawing || root.recentCaptures === 0) {
      return
    }
    list.command = [root.fleaCommand, "shelf", "captures", String(root.recentCaptures)]
    list.running = true
  }

  Process {
    id: list
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.captures = Model.parseCaptures(text)
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  // ShelfEmpty rule 5: a click on a capture adds it to the pile, the same call a drop makes, and a
  // drop on the rail is that same call with everything it was carrying.
  function add(path) {
    root.addAll([path])
  }

  function addAll(paths) {
    if (addOne.running || paths.length === 0) {
      return
    }
    addOne.command = [root.fleaCommand, "shelf", "add"].concat(paths)
    addOne.running = true
  }

  Process {
    id: addOne
    running: false
    onExited: function (code) { if (code !== 0) root.failed("The shelf could not take that one.") }
  }

  Process {
    id: measure
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.answered(text)
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  // Summon: the keybind, the CLI and the card all reach each other through the state directory, so
  // none of them needs an IPC contract. The file carries a count rather than a state: every write is
  // one ring of the bell, which the card answers by toggling, so the two can never disagree.
  signal summoned()
  signal cleared(int count)
  property int rings: -1

  function rang(text) {
    var now = Model.ringsOf(text)
    if (root.rings >= 0 && now !== root.rings) {
      root.summoned()
    }
    root.rings = now
  }

  FileView {
    id: bell
    path: root.stateDir + "/summon.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.rang(bell.text())
    onLoadFailed: root.rang("")
  }

  // The verbs that change the pile and answer with one number: how many the shelf cleared or put back.
  property string pending: ""

  function clear() {
    root.runVerb("clear", ["shelf", "clear"])
  }

  function restore(index) {
    root.runVerb("restore", ["shelf", "restore", String(index + 1)])
  }

  function runVerb(name, argv) {
    if (verb.running) {
      return
    }
    root.pending = name
    verb.command = [root.fleaCommand].concat(argv)
    verb.running = true
  }

  Process {
    id: verb
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var count = parseInt(String(text).trim(), 10)
        if (root.pending === "clear" && isFinite(count)) {
          root.cleared(count)
        }
        root.pending = ""
        file.reload()
        root.askPiles()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text).trim().length > 0) root.failed("The shelf could not do that.")
    }
  }

  // Summon rule 4: one shelf, plus the last five piles, which the card's own menu lists.
  property var piles: []

  function askPiles() {
    if (pileList.running) {
      return
    }
    pileList.command = [root.fleaCommand, "shelf", "piles"]
    pileList.running = true
  }

  Process {
    id: pileList
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.piles = Model.parsePiles(text)
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  // The empty card names the bind only once it is installed, and the user's own config owns that line.
  property string summonBind: ""

  Process {
    id: bindName
    command: [root.fleaCommand, "shelf", "bind"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.summonBind = String(text).trim()
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  // A watch cannot fire for a file that does not exist yet, so the first drop is found by this.
  Timer {
    interval: root.refreshIntervalSec * root.millisecondsPerSecond
    running: true
    repeat: true
    onTriggered: {
      file.reload()
      bell.reload()
      // ShelfEmpty rule 4: the tray is listed on open and on each re-read while the card is up, so a
      // capture taken with the card open appears within one poll. A re-read of an unchanged pile
      // raises nothing, which is why this hangs off the poll itself rather than off the pile.
      root.askCaptures()
    }
  }
}
