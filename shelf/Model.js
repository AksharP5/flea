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
          folder: folder, partial: item.partial === true })
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
function nextSize(pile, sizes) {
  for (var i = 0; i < pile.items.length; i++) {
    var item = pile.items[i]
    if (item.bytes < 0 && sizes[item.path] === undefined) {
      return item.path
    }
  }
  return ""
}

// A size the card is no longer drawing is not kept: the map holds answers for the pile in front of
// the pointer and nothing else, so a path that leaves and comes back is measured again.
function keep(sizes, pile) {
  var kept = {}
  for (var i = 0; i < pile.items.length; i++) {
    var path = pile.items[i].path
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
// never two of them at once; the order is the one the card was drawn with.
function footerText(hoveredPath, result, error) {
  if (error) {
    return String(error)
  }
  if (hoveredPath) {
    return String(hoveredPath)
  }
  return String(result || "")
}

// Rule 2's header, which is also the pile's own count: the bar never draws one.
function headerText(state) {
  if (!state || state.count === 0) {
    return "Shelf"
  }
  return "Shelf  " + state.count + (state.count === 1 ? " item" : " items")
}
