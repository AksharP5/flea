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
  // EdgeRail rule 3: how long a drag rests on the rail before the card opens. A constant now, since
  // the manifest keeps only the two technical values and Settings offers no row for a dwell.
  readonly property int railDwellMs: 120
  property string barPosition: "top"
  // SettingsRest rule 2: the edge is Flea's own setting, and the master takes the rail away with it.
  readonly property string railEdge: root.shelfSettings.enabled ? root.shelfSettings.rail : "off"
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

  // An action changed the pile under us, so the file is read again rather than waited for.
  function reread() {
    file.reload()
  }

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

  // The card says what is being carried, because a pinned row and a capture row are draggable and
  // are not pile entries. Answers whether the drag started, which is the card's carrying state.
  function mintDrag(wantsMove, paths) {
    if (mint.running || !paths || paths.length === 0) {
      return false
    }
    root.moving = wantsMove
    var argv = [root.fleaCommand, "shelf", "drag-begin", wantsMove ? "move" : "copy"]
    for (var i = 0; i < paths.length; i++) {
      argv.push(paths[i])
    }
    mint.command = argv
    mint.running = true
    return true
  }

  // Main rule 10: `p` on a row, whichever section it is in.
  function pin(path, pinned) {
    pinner.command = [root.fleaCommand, "shelf", pinned ? "pin" : "unpin", path]
    pinner.running = true
  }

  Process {
    id: pinner
    running: false
    onExited: function (code) {
      if (code !== 0) {
        root.failed("The shelf could not pin that one.")
        return
      }
      root.reread()
    }
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

  // Rule 11 and directive 59: the key hints toggle and the Shelf section are Flea's own settings,
  // read from the file Flea writes rather than duplicated in this plugin's manifest.
  readonly property string fleaStatePath: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/flea/ui.json"
  property bool keyHints: false
  property var shelfSettings: Model.shelfDefaults()

  FileView {
    id: fleaState
    path: root.fleaStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readSettings(fleaState.text())
    // No Flea has ever run here, so every setting is its own default.
    onLoadFailed: root.readSettings("")
  }

  function readSettings(text) {
    root.keyHints = Model.keyHintsOf(text)
    root.shelfSettings = Model.shelfOf(text)
  }

  // Main rule 4's budget: a size is asked for only while the card is drawing the row, one path per
  // request, and never twice for the same path. DirSizes.js is the model for the gating and not a
  // call this can make: its queue indexes the active listing, which the shelf is not.
  property bool drawing: false
  property var sizes: ({})
  property string asking: ""

  // Main rule 9: the captures are listed before the card's first frame, so the ask rides the open.
  onDrawingChanged: {
    if (root.drawing) {
      root.thumbs = Model.thumbsFound(root.thumbs)
    }
    root.askCaptures()
    root.askSize()
    root.askThumbs()
    fast.running = root.drawing
  }
  onPileChanged: {
    root.sizes = Model.keep(root.sizes, root.drawnRows)
    root.thumbs = Model.keep(root.thumbs, root.drawnRows)
    root.askSize()
  }

  // What the card is drawing, which is what a size and a thumbnail are asked for and what a capture
  // joins.
  readonly property var drawnRows: Model.rows(root.pile, root.captures)
  onDrawnRowsChanged: {
    root.askSize()
    root.askThumbs()
  }

  // Main rule 4: one path-addressed request for the rows the card is drawing, on open and on each
  // re-read while it is up, and nothing at all while it is closed.
  property var thumbs: ({})

  function askThumbs() {
    if (thumber.running || !root.drawing) {
      return
    }
    var wanted = Model.thumbWanted(root.drawnRows, root.thumbs)
    if (wanted.length === 0) {
      return
    }
    thumber.command = [root.fleaCommand, "shelf", "thumb"].concat(wanted)
    thumber.running = true
  }

  Process {
    id: thumber
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.thumbs = Model.thumbsFrom(text, root.thumbs)
        root.askThumbs()
      }
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  function askSize() {
    if (measure.running || !root.drawing) {
      return
    }
    var path = Model.nextSize(root.drawnRows, root.sizes)
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
    if (list.running || !root.drawing || root.shelfSettings.recent === 0) {
      return
    }
    list.command = [root.fleaCommand, "shelf", "captures",
                    String(root.shelfSettings.recent), Model.kindsArg(root.shelfSettings)]
    list.running = true
  }

  // Rule 9 and directive 58: while the card is up a new capture is there within a second, and this
  // runs only then. The pile keeps its own five second re-read.
  Timer {
    id: fast
    interval: root.millisecondsPerSecond
    running: false
    repeat: true
    onTriggered: root.askCaptures()
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

  // Keys: enter opens the file with its own handler, or reveals a folder in Flea. Actions rule 1: it
  // is a flea shelf call like every other, because the plugin draws and nothing else.
  function open(path) {
    opener.command = [root.fleaCommand, "shelf", "open", path]
    opener.running = true
  }

  Process {
    id: opener
    running: false
    onExited: function (code) { if (code !== 0) root.failed("That one could not be opened.") }
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
