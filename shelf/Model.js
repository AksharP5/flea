.pragma library

// The pile as the bar reads it. Every function here is pure: the Service owns the file and this
// owns what its bytes mean, so a shape nobody has drawn yet can be tested without a shell at all.

// The shape the widget draws when nothing has been read, so no caller ever meets an undefined pile.
function empty() {
  return { items: [], count: 0, ok: false }
}

// Sample input: {"items":[{"path":"/home/gm/Work/a.txt","name":"a.txt","bytes":1024}]}
// A file that is missing, half written or not JSON at all answers the empty shape rather than
// throwing: the pile is written by another process and the bar has to survive reading it mid-write.
function parse(text) {
  var raw = String(text || "")
  if (raw.length === 0) {
    return empty()
  }
  var parsed
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    return empty()
  }
  if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.items)) {
    return empty()
  }
  var items = []
  for (var i = 0; i < parsed.items.length; i++) {
    var item = parsed.items[i]
    if (!item || typeof item.path !== "string" || item.path.length === 0) {
      continue
    }
    var folder = item.folder === true
    // A folder wears its own separator, the way every Flea listing draws one: rule 3's "reads as Flea".
    items.push({ path: item.path, name: leaf(item.path) + (folder ? "/" : ""), bytes: bytesOf(item),
          folder: folder, partial: item.partial === true, pinned: item.pinned === true })
  }
  return { items: items, count: items.length, ok: true }
}

// The row's own name, which is the path's last segment; a trailing slash names the folder before it.
function leaf(path) {
  var text = String(path)
  if (text.length > 1 && text.charAt(text.length - 1) === "/") {
    text = text.substring(0, text.length - 1)
  }
  var cut = text.lastIndexOf("/")
  return cut < 0 ? text : text.substring(cut + 1)
}

// A size the writer did not answer is not a zero, so it is carried as -1 and drawn as nothing.
function bytesOf(item) {
  var n = Number(item.bytes)
  return isFinite(n) && n >= 0 ? n : -1
}

// BarMark rule 3: the count is never in the bar itself, so this is what the hover tooltip says.
function tooltip(state) {
  if (!state || state.count === 0) {
    return "Flea shelf is empty"
  }
  return state.count === 1 ? "Flea shelf is holding 1 item" : "Flea shelf is holding " + state.count + " items"
}

// ---- what the card draws, Main board rules 4, 5 and 7 ----

// The two marks a row can take, on the Omarchy cut, the same paths ui/js/Icons.js draws them from.
// Flea's own mark, which is what an empty shelf draws rather than a stand-in for one.
var SHELF_GLYPH = "M21 21H3V3h18v14H7V7h10v6h-6"
// Rule 14: the actions are icon buttons, and the ink is Flea's own recut set, copied here because a
// plugin cannot import the app's Icons.js: folder-plus, copy, archive, network, clipboard, star, x.
var ACTION_GLYPHS = {
  move: "M2 20V3h6l2 3h12v14H2z M12 10v6 M9 13h6",
  copy: "M9 8h12v13H9z M4 16V3h13",
  zip: "M2 3h20v5H2z M4 8v13h16V8 M10 12h4",
  send: "M9 2h6v6H9z M2 16h6v6H2z M16 16h6v6h-6z M12 8v4 M5 16v-4h14v4",
  paths: "M9 2h6v4H9z M6 4H3v18h18V4h-3 M8 12h8 M8 16h5",
  pin: "M12 2l2.9 6.6 7.1.6-5.4 4.7 1.6 7L12 17.3l-6.2 3.6 1.6-7L2 9.2l7.1-.6z",
  remove: "M6 6l12 12 M18 6 6 18"
}
var FOLDER_GLYPH = "M2 20V3h6l2 3h12v14H2z"
var FILE_GLYPH = "M4 22V2h10l6 6v14H4z M14 2v6h6"

// Rule 4: a folder shows bytes, never an item count, because that is what the backend answers. A
// size nobody has answered yet is one dot, and a walk that was cut short keeps its own > prefix.
function sizeText(item) {
  if (!item || item.bytes === undefined || item.bytes === null || item.bytes < 0) {
    return "\u00b7"
  }
  return (item.partial === true ? ">" : "") + size(item.bytes)
}

function glyphFor(item) {
  return item && item.folder === true ? FOLDER_GLYPH : FILE_GLYPH
}

// A size in the same words Flea's own list uses, so the shelf reads as Flea and not as a second app.
function size(bytes) {
  var n = Number(bytes)
  if (!isFinite(n) || n < 0) {
    return ""
  }
  var units = ["B", "kB", "MB", "GB", "TB"]
  var at = 0
  while (n >= 1000 && at < units.length - 1) {
    n = n / 1000
    at += 1
  }
  return (at === 0 ? String(Math.round(n)) : n.toFixed(1)) + " " + units[at]
}

// Rule 4's budget: the next path the card is drawing that nobody has answered for, one at a time.
// A path already answered is never asked again, so nothing here polls, and a path the card is not
// drawing is never in this list at all.
function nextSize(list, sizes) {
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (item.bytes < 0 && sizes[item.path] === undefined) {
      return item.path
    }
  }
  return ""
}

// A size the card is no longer drawing is not kept: the map holds answers for the pile in front of
// the pointer and nothing else, so a path that leaves and comes back is measured again.
function keep(sizes, list) {
  var kept = {}
  for (var i = 0; i < list.length; i++) {
    var path = list[i].path
    if (sizes[path] !== undefined) {
      kept[path] = sizes[path]
    }
  }
  return kept
}

// The pile the card draws: the writer's own bytes where it had them, the answered size where it did
// not. An answer of -1 is a path that could not be read, which draws as the same dot as a pending one.
function sized(pile, sizes) {
  var items = []
  for (var i = 0; i < pile.items.length; i++) {
    var item = pile.items[i]
    var answer = item.bytes < 0 ? sizes[item.path] : undefined
    items.push(answer === undefined ? item
               : { path: item.path, name: item.name, bytes: answer.bytes,
                   folder: item.folder, partial: answer.partial })
  }
  return { items: items, count: pile.count, ok: pile.ok }
}

// Rule 5: one slot with one voice. The hovered row's path, or the last result, or the one error, and
// never two of them at once; the order is the one the card was drawn with. The hint is last, because
// an empty shelf has no row to hover and nothing has happened on it yet.
function footerText(hoveredPath, result, error, hint, chosen) {
  if (error) {
    return String(error)
  }
  if (hoveredPath) {
    return String(hoveredPath)
  }
  if (result) {
    return String(result)
  }
  if (chosen) {
    return String(chosen)
  }
  return String(hint || "")
}

// ---- the recent captures tray, ShelfEmpty rules 2, 4, 5 and 7 ----

// A recording is drawn by its mark and never decoded, so it needs one: the Omarchy cut's play square.
var RECORDING_GLYPH = "M4 3h16v18H4z M10 9l6 3l-6 3z"

// Sample input, one line per capture, newest first, the mtime in milliseconds then the path:
// 1757890932000 /home/gm/Pictures/screenshot-2026-09-14_19-02-11.png
function parseCaptures(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var cut = line.indexOf(" ")
    if (cut < 1) {
      continue
    }
    var at = Number(line.substring(0, cut))
    var path = line.substring(cut + 1)
    if (!isFinite(at) || path.length === 0) {
      continue
    }
    out.push({ path: path, at: at, recording: isRecording(path) })
  }
  return out
}

function isRecording(path) {
  return String(path).slice(-4).toLowerCase() === ".mp4"
}

// The one clock this project draws, cut to the part a tray of three needs.
function captureTime(at) {
  var when = new Date(Number(at))
  if (!isFinite(when.getTime())) {
    return ""
  }
  return pad2(when.getHours()) + ":" + pad2(when.getMinutes())
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

// The empty card names only the routes that are on, so it never advertises a gesture that will not
// work. The edge and the bind arrive with the units that build them; the mark is drawn today.
function routesHint(routes) {
  var parts = []
  if (routes && routes.edge) {
    parts.push("throw at the " + routes.edge + " edge")
  }
  if (routes && routes.mark) {
    parts.push("the bar mark opens")
  }
  if (routes && routes.bind) {
    parts.push(routes.bind + " opens")
  }
  return parts.join(" \u00b7 ")
}

// What the one footer slot says on a card with nothing on it: how to use the tray when there is one,
// and how to fill the shelf when there is not.
function emptyHint(pile, captures, routes) {
  if (pile && pile.count > 0) {
    return ""
  }
  if (captures && captures.length > 0) {
    return "click to add \u00b7 drag to take it straight out"
  }
  return routesHint(routes)
}

// ---- EdgeRail: what a drag dropped on the wall is offering ----

// Sample input, one URI per line as every toolkit writes a text/uri-list, comments and all:
// file:///home/gm/Pictures/one.png\r\n
function pathsFromUris(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace("\r", "").trim()
    if (line.length === 0 || line.charAt(0) === "#" || line.indexOf("file://") !== 0) {
      continue
    }
    out.push(decodeURIComponent(line.substring("file://".length)))
  }
  return out
}

// ---- Summon: the bell, the cleared transient and the Recent piles rows ----

// The bind writes a count, not a state: every write is one more ring, and the card answers each one.
function ringsOf(text) {
  var doc
  try {
    doc = JSON.parse(String(text || ""))
  } catch (e) {
    return 0
  }
  var n = doc ? Number(doc.summon) : 0
  return isFinite(n) && n >= 0 ? n : 0
}

// Summon: clearing is reversible, and the transient says so for the four seconds it lives.
function clearedText(count) {
  var n = Number(count)
  if (!isFinite(n) || n <= 0) {
    return ""
  }
  return "Cleared " + n + (n === 1 ? " item" : " items") + " \u00b7 z restores"
}

// Sample input, one line per kept pile, newest first: the time it was cleared, then how many it held.
// 1789426925000 4
function parsePiles(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split(" ")
    if (parts.length !== 2) {
      continue
    }
    var at = Number(parts[0])
    var count = Number(parts[1])
    if (!isFinite(at) || !isFinite(count)) {
      continue
    }
    out.push({ at: at, count: count })
  }
  return out
}

// The one date format this project draws, which is Flea's own: 2026-09-12 19:04.
function pileText(pile) {
  var n = Number(pile.count)
  return n + (n === 1 ? " item" : " items") + " \u00b7 " + stamp(pile.at)
}

// The archive's own date, which is the stamp cut at its day: 2026-09-12.
function today() {
  return stamp(Date.now()).substring(0, DATE_CHARS)
}

var DATE_CHARS = 10

function stamp(at) {
  var when = new Date(Number(at))
  if (!isFinite(when.getTime())) {
    return ""
  }
  return when.getFullYear() + "-" + pad2(when.getMonth() + 1) + "-" + pad2(when.getDate())
         + " " + pad2(when.getHours()) + ":" + pad2(when.getMinutes())
}

// ---- Flea's own settings, which this plugin reads and never writes ----

// Sample input, the part of ~/.local/state/flea/ui.json this reads:
// {"keyHints":false,"shelf":{"screenshots":true,"recordings":true,"recent":3}}
function keyHintsOf(text) {
  var doc = parsedOr(text)
  return doc.keyHints === true
}

function shelfDefaults() {
  return { enabled: true, bar: true, rail: "off", screenshots: true, recordings: true, recent: 3 }
}

var EDGES = ["off", "left", "right", "bottom"]

// SettingsRest rules 1 to 3: Flea's Settings owns the shelf's switches and this plugin only reads
// them. A value this build cannot honour falls back to the same default a fresh ui.json holds.
function shelfOf(text) {
  var doc = parsedOr(text)
  var shelf = doc.shelf && typeof doc.shelf === "object" ? doc.shelf : {}
  var recent = Number(shelf.recent)
  return {
    enabled: shelf.enabled !== false,
    bar: shelf.bar !== false,
    rail: EDGES.indexOf(String(shelf.rail)) >= 0 ? String(shelf.rail) : "off",
    screenshots: shelf.screenshots !== false,
    recordings: shelf.recordings !== false,
    recent: isFinite(recent) && recent >= 0 ? recent : 3
  }
}

function parsedOr(text) {
  try {
    var doc = JSON.parse(String(text || ""))
    return doc && typeof doc === "object" ? doc : {}
  } catch (e) {
    return {}
  }
}

// Which kinds the captures listing is asked for, which is one word on the command line.
function kindsArg(settings) {
  if (settings.screenshots && settings.recordings) {
    return "both"
  }
  return settings.screenshots ? "screenshots" : "recordings"
}

// ---- Main rules 9 and 10: the card is one list of three sections ----

var PILE = "pile"
var PINNED = "pinned"
var CAPTURE = "capture"
var CAPTURES_CAPTION = "Screenshots & recordings"

// Every row the card draws, in drawn order, each carrying the section it belongs to: the pile, the
// pins that are always there, and the newest captures. A caption is drawn where the section changes.
function rows(pile, captures, sizes) {
  var out = []
  var items = (pile && pile.items) || []
  for (var i = 0; i < items.length; i++) {
    if (!items[i].pinned) {
      out.push(sectioned(items[i], PILE))
    }
  }
  for (var j = 0; j < items.length; j++) {
    if (items[j].pinned) {
      out.push(sectioned(items[j], PINNED))
    }
  }
  for (var k = 0; k < (captures || []).length; k++) {
    var capture = captures[k]
    out.push(sectioned({ path: capture.path, name: leaf(capture.path), bytes: -1, folder: false,
                         partial: false, pinned: false, recording: capture.recording === true,
                         at: capture.at }, CAPTURE))
  }
  return sizes === undefined ? out : sizedRows(out, sizes)
}

function sectioned(item, section) {
  return { path: item.path, name: item.name, bytes: item.bytes, folder: item.folder,
           partial: item.partial, pinned: item.pinned, recording: item.recording === true,
           at: item.at, section: section }
}

// The same answers the pile's rows take, applied to every drawn row: a capture has no size of its
// own until the card asks for one.
function sizedRows(list, sizes) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    var row = list[i]
    var answer = row.bytes < 0 ? sizes[row.path] : undefined
    if (answer === undefined) {
      out.push(row)
      continue
    }
    var filled = sectioned(row, row.section)
    filled.bytes = answer.bytes
    filled.partial = answer.partial
    out.push(filled)
  }
  return out
}

// A caption is drawn above the first row of a section, and never above the pile's own.
function captionFor(list, index, kinds) {
  var row = list[index]
  if (!row || row.section === PILE) {
    return ""
  }
  if (index > 0 && list[index - 1].section === row.section) {
    return ""
  }
  return row.section === PINNED ? "Pinned" : capturesCaption(kinds)
}

// Rule 4: the rows the card is drawing that have no answer yet, so a path is asked for once and a
// closed card asks for nothing.
function thumbWanted(list, thumbs) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    var path = list[i].path
    if (thumbs[path] === undefined && out.indexOf(path) < 0) {
      out.push(path)
    }
  }
  return out
}

// Sample input, one line per path asked for, the cache file or `none`, a tab, then the path:
// /home/gm/.cache/thumbnails/large/714c8a7d754b5cbc79c30b7ad0646785.png\t/home/gm/Pictures/shot.png
function thumbsFrom(text, current) {
  var next = {}
  for (var path in current) {
    next[path] = current[path]
  }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var at = lines[i].indexOf("\t")
    if (at <= 0) {
      continue
    }
    var file = lines[i].substring(0, at)
    next[lines[i].substring(at + 1)] = file === "none" ? "" : file
  }
  return next
}

// A path that answered with nothing is asked once more on the next open: the cache records its own
// failures, so a second ask is a lookup, and a thumbnail produced meanwhile is then drawn.
function thumbsFound(thumbs) {
  var kept = {}
  for (var path in thumbs) {
    if (thumbs[path]) {
      kept[path] = thumbs[path]
    }
  }
  return kept
}

// A thumbnail path is not a thumbnail: the cache file can be evicted between the answer and the
// decode, and Row.qml marks such a row by its kind instead. This says which file to try.
function thumbFor(thumbs, item) {
  var file = item && thumbs ? thumbs[item.path] : ""
  return file === undefined || file === null ? "" : file
}

// Rule 9: the caption names the kinds that are checked, which is Settings' own answer.
function capturesCaption(kinds) {
  if (!kinds || (kinds.screenshots && kinds.recordings)) {
    return CAPTURES_CAPTION
  }
  return kinds.screenshots ? "Screenshots" : "Recordings"
}

function sectionCount(list, section) {
  var n = 0
  for (var i = 0; i < list.length; i++) {
    if (list[i].section === section) {
      n += 1
    }
  }
  return n
}

// ---- Keys: the subset gesture, which every file action reads ----

// Chosen by path rather than by row, so a pile that changes underneath cannot leave a row chosen by
// position alone. The map is rebuilt on every change, so a binding that reads it re-evaluates.
function toggleChosen(chosen, path) {
  var next = {}
  for (var held in chosen) {
    next[held] = chosen[held]
  }
  if (next[path]) {
    delete next[path]
  } else {
    next[path] = true
  }
  return next
}

// shift-j and shift-k extend a range, which is the rows between where the cursor was and where it is.
function chooseRange(chosen, items, from, to) {
  var next = {}
  for (var held in chosen) {
    next[held] = chosen[held]
  }
  var first = Math.min(from, to)
  var last = Math.max(from, to)
  for (var i = first; i <= last; i++) {
    if (items[i]) {
      next[items[i].path] = true
    }
  }
  return next
}

// ctrl-a takes all, and a second ctrl-a clears: the same key both ways, as it is in the pane.
function chooseAll(chosen, items) {
  if (chosenCount(chosen, items) === items.length && items.length > 0) {
    return {}
  }
  var next = {}
  for (var i = 0; i < items.length; i++) {
    next[items[i].path] = true
  }
  return next
}

// Only the rows the pile still holds count: a chosen row that has left the shelf is not chosen.
function chosenCount(chosen, items) {
  var n = 0
  for (var i = 0; i < items.length; i++) {
    if (chosen[items[i].path]) {
      n += 1
    }
  }
  return n
}

// Every file action is chosen-or-whole, with no exceptions: the chosen rows, or the whole pile when
// nothing is chosen. Order is the pile's own, never the order they were chosen in. Rule 9: a capture
// row is reached by choosing it, and is never part of "the whole pile", which is what Keys says the
// five actions take when nothing is chosen.
function actionPaths(chosen, items) {
  var picked = []
  for (var i = 0; i < items.length; i++) {
    if (chosen[items[i].path]) {
      picked.push(items[i].path)
    }
  }
  if (picked.length > 0) {
    return picked
  }
  var all = []
  for (var j = 0; j < items.length; j++) {
    if (items[j].section !== CAPTURE) {
      all.push(items[j].path)
    }
  }
  return all
}

// Rule 11: a drag carries the chosen rows, or the one row it was started from when none are chosen.
// A keyboard action still takes the whole pile, because an action names no row and a grab does.
function carryPaths(chosen, items, index) {
  var picked = []
  for (var i = 0; i < items.length; i++) {
    if (chosen[items[i].path]) {
      picked.push(items[i].path)
    }
  }
  if (picked.length > 0) {
    return picked
  }
  return items[index] ? [items[index].path] : []
}

// How many rows "none chosen" would take, which is the pile and its pinned rows and no capture.
function wholeCount(items) {
  var n = 0
  for (var i = 0; i < items.length; i++) {
    if (items[i].section !== CAPTURE) {
      n += 1
    }
  }
  return n
}

// Rules 9 and 10: a capture row and a pinned row leave as a copy, so a drag carrying either one is
// a copy however it was started, and only a set of plain pile rows can be a move.
function dragMoves(paths, items, wantsMove) {
  if (!wantsMove) {
    return false
  }
  for (var i = 0; i < items.length; i++) {
    if (items[i].section !== PILE && paths.indexOf(items[i].path) >= 0) {
      return false
    }
  }
  return true
}

// The footer while a subset is being chosen: what the five actions will take, and what none means.
function chosenSentence(count, total) {
  var n = Number(count)
  if (!isFinite(n) || n <= 0) {
    return ""
  }
  return "5 actions take " + n + " chosen \u00b7 none chosen: all " + total
}

// EdgeRail: while a drag hovers the rail the header says what letting go would do, and the way out
// is not what the eye needs at that moment.
function headerRight(incoming, chosen, total) {
  var n = Number(incoming)
  if (isFinite(n) && n > 0) {
    return "drop to add " + n
  }
  var picked = Number(chosen)
  if (isFinite(picked) && picked > 0) {
    return picked + " of " + total + " chosen"
  }
  return "esc"
}

// Rule 2's header, which is also the pile's own count: the bar never draws one. An empty shelf says
// so in the same slot, the way the ShelfEmpty board draws it.
function headerText(state) {
  var n = state ? loose(state.items).length : 0
  if (n === 0) {
    return "Shelf  empty"
  }
  return "Shelf  " + n + (n === 1 ? " item" : " items")
}

// Main rule 12: the header counts the pile alone, because pinned rows and captures are not items
// anybody sent to the shelf.
function loose(items) {
  var out = []
  for (var i = 0; i < (items || []).length; i++) {
    if (!items[i].pinned) {
      out.push(items[i])
    }
  }
  return out
}
