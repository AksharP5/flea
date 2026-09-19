.pragma library

// What an action says while it runs and when it lands. The shelf inherits the transfer surface it
// already has rather than growing a second one: these are the same wire lines ui/TransferCard.qml
// reads, off the same backend, and the words are the Actions board's own.

function idle() {
  return { running: false, verb: "", index: 0, count: 0, name: "", bytes: 0, total: 0 }
}

// Sample input, the lines `flea shelf move|copy` prints, which are the pane's own:
// {"t":"transferstarted","id":0,"n":4,"moving":true}
// {"t":"transferprogress","id":0,"index":1,"name":"plate-2.raw","bytes":36,"total":94,"scanned":0}
// {"t":"transferdone","id":0,"ok":3,"failed":1,"skipped":0,"cancelled":false,"retryPaths":[]}
function sampled(state, line) {
  var wire
  try {
    wire = JSON.parse(line)
  } catch (e) {
    return state
  }
  if (!wire || typeof wire.t !== "string") {
    return state
  }
  if (wire.t === "transferstarted") {
    return { running: true, verb: wire.moving ? "Moving" : "Copying", index: 0, count: Number(wire.n) || 0,
             name: "", bytes: 0, total: 0 }
  }
  if (wire.t === "transferprogress") {
    return { running: true, verb: state.verb, index: Number(wire.index) || 0, count: state.count,
             name: String(wire.name || ""), bytes: Number(wire.bytes) || 0, total: Number(wire.total) || 0 }
  }
  if (wire.t === "transferdone") {
    return idle()
  }
  return state
}

// The one line the body draws above the file, with the item being worked on counted from one.
function runText(state) {
  if (!state.running || state.count === 0) {
    return ""
  }
  return state.verb + " " + Math.min(state.count, state.index + 1) + " of " + state.count
}

function runFraction(state) {
  return state.total > 0 ? Math.max(0, Math.min(1, state.bytes / state.total)) : 0
}

// Rule 5: the footer is still one slot, and while an action runs it carries the keyboard's own half.
function runFooter(state) {
  var head = runText(state)
  return head.length === 0 ? "" : head + " · esc cancels"
}

// The flyout's own title, which says what is about to happen to how many.
function flyoutTitle(pending, count) {
  var verb = pending === "send" ? "Send" : (pending === "copy" ? "Copy" : "Move")
  var n = Number(count)
  return verb + " " + n + (n === 1 ? " item" : " items") + " to"
}

// One line per row, which is how every flea shelf listing answers. Only the line ending is stripped,
// because a path may legally begin or end with a space and these lines carry paths.
function lines(text) {
  var out = []
  var split = String(text || "").split("\n")
  for (var i = 0; i < split.length; i++) {
    var line = split[i].replace(/\r$/, "")
    if (line.length > 0) {
      out.push(line)
    }
  }
  return out
}

// ---- what each action says when it lands, Actions rules 4 and 5 ----

// A move empties what it moved, so a clean one says where they went and that it can be undone.
function movedText(verb, ok, failed, total, dest, firstError) {
  if (ok === 0 && failed === 0) {
    return ""
  }
  if (failed > 0) {
    // Rule 5: a partial failure is a result and an error at once, so it is one sentence, not two.
    return verb + " " + ok + " of " + total + (firstError ? " · " + firstError : "")
  }
  var landed = verb + " " + ok + (ok === 1 ? " item" : " items") + " to " + dest
  return verb === "Moved" ? landed + " · z undoes" : landed
}

// A run that exited before reporting a single item, so the counts above have nothing to say.
function runFailedText(verb) {
  return verb === "Moved" ? "That move did not run." : "That copy did not run."
}

function zippedText(count) {
  var n = Number(count)
  if (!isFinite(n) || n <= 0) {
    return ""
  }
  return "Zipped " + n + (n === 1 ? " item" : " items") + " into one archive"
}

function copiedPathsText(count) {
  var n = Number(count)
  if (!isFinite(n) || n <= 0) {
    return ""
  }
  return "Copied " + n + (n === 1 ? " path" : " paths")
}

// A send reports only by notification, so the shelf says what it handed over and keeps the pile.
function sentText(count, peer) {
  var n = Number(count)
  if (!isFinite(n) || n <= 0) {
    return ""
  }
  return "Sent " + n + (n === 1 ? " item" : " items") + " to " + peer
}

// The destination as the card names it: the leaf, because the flyout already said the whole path.
function destName(path) {
  var text = String(path || "").replace(/\/+$/, "")
  var cut = text.lastIndexOf("/")
  return cut < 0 ? text : text.substring(cut + 1)
}
