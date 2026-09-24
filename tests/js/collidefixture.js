// The real ui/CollideHost.qml, ui/FileDrag.qml and ui/RowDrag.qml over a stub pane and backend, for tests/js/collide.js.

// A file of this tree, read the way tests/js/settingsabout.js reads its sources.
function source(path) {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../../" + path), false)
    request.send()
    return String(request.responseText || "")
}

// ui/<file> built from its own text beside ui/js, because ui/qmldir's singletons need Quickshell, which qml6 lacks.
// Sample input: 'import QtQuick\nimport "js/Drag.js" as DragOps\n\n// Delegate input ...\nItem {\n    id: root\n'
function built(file, parent, properties) {
    var text = source("ui/" + file)
    var body = text.search(/^[A-Z]\w* \{/m)
    var imports = text.substring(0, body).replace(/import "js\//g, "import \"")
    var wrapper = Qt.createQmlObject(imports + "QtObject { property Component made: Component { " + text.substring(body) + " } }",
                                     parent, Qt.resolvedUrl("../../ui/js/" + file))
    return wrapper.made.createObject(parent, properties)
}

// ui/Backend.qml as the card and the drag reach it: the two replies CollideHost hears, and send() naming rows as it does.
// The failed signal carries production's four arguments (ui/Backend.qml), because CollideHost reads
// the second: the error line's path, "collisions" for a refused question.
var BACKEND = "import QtQuick\nimport \"../../ui/js/Swap.js\" as Swap\nQtObject {\n"
    + "    signal collisions(int id, int total, var names)\n    signal failed(string where, string input, string message, int mode)\n"
    + "    property real heldListing: 0\n    property var sent: []\n"
    + "    function send(object) { sent.push(Swap.named(object, heldListing)) }\n}\n"

// The commands written so far, in order.
function verbs(backend) {
    return backend.sent.map(function (line) { return line.c }).join(",")
}

// A pane at rest over a folder row in listing held, its card the real one, its drag session and the folder row's drop target.
function scene(held) {
    var parent = Qt.createComponent("QtQuick", "Item").createObject(null)
    var backend = Qt.createQmlObject(BACKEND, parent, Qt.resolvedUrl("backend.qml"))
    backend.heldListing = held
    var folder = [{ n: "a.txt", d: false }, { n: "b.txt", d: false }, { n: "omarchy", d: true }]
    var p = { path: "/d", backend: backend, statusBar: null, clipboard: { paths: ["/s/a.txt"], moving: true },
              listInFlight: false, renamePending: false, renamingIndex: -1, menuVisible: false, menuActions: { opened: false },
              filterTyping: false, searchMode: "", selectionBand: null }
    p.rowFor = function (index) { return folder[index] || null }
    p.selectedIndices = function () { return [] }
    p.selectionCount = function () { return 0 }
    p.join = function (base, name) { return base + "/" + name }
    p.message = function () {}
    p.collide = built("CollideHost.qml", parent, { pane: p })
    var session = built("FileDrag.qml", parent, { pane: p })
    var target = built("RowDrag.qml", parent, { session: session, listingIndex: 2, row: folder[2] })
    return { parent: parent, backend: backend, pane: p, session: session, target: target }
}
