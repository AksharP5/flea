#!/usr/bin/env node
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const repo = path.resolve(process.argv[2] || path.join(__dirname, ".."));
const source = name => fs.readFileSync(path.join(repo, "ui", name), "utf8");

function body(name, pattern) {
    const match = source(name).match(pattern);
    assert.ok(match, `${name}: expected QML handler is missing`);
    return match[1];
}

// QML libraries are evaluated unchanged after their namespace imports are resolved.
function library(file) {
    // Enum values only initialize transitively imported Keymap; rename checks never dispatch keys.
    const context = vm.createContext({Qt: {}});
    const text = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/gm, "")
        .replace(/^\.import "([^"]+)" as (\w+)\s*$/gm, (_, imported, name) => {
            context[name] = library(path.resolve(path.dirname(file), imported));
            return "";
        });
    vm.runInContext(text, context, {filename: file});
    return context;
}
const Ops = library(path.join(repo, "ui/js/Ops.js"));
const Errors = library(path.join(repo, "ui/js/Errors.js"));
const Nav = library(path.join(repo, "ui/js/Nav.js"));
const Swap = library(path.join(repo, "ui/js/Swap.js"));
const clearEditor = new Function("root",
    body("Pane.qml", /    onRenamingIndexChanged: ([\s\S]*?)\n    \}/) + "\n}");
const failed = new Function("pane", "root", "Errors", "Ops", "Nav", "Swap", "where", "input", "message", "mode",
    body("PaneWire.qml", /        function onFailed\(where, input, message, mode\) \{([\s\S]*?)\n        \}/));
const renamed = new Function("pane", "root", "Nav", "ok", "path",
    body("PaneWire.qml", /        function onRenamed\(ok, path\) \{([\s\S]*?)\n        \}/));
const refresh = new Function("pane", "root", "watchSettle", "request", "selected",
    body("PaneWire.qml", /    function refreshRename\(request, selected\) \{([\s\S]*?)\n    \}/));
let checked = 0;
function equal(actual, expected) { assert.deepEqual(actual, expected); checked++; }

function editing() {
    const p = {path: "/fixture/list", cursorIndex: 7, shown: null, renameRequest: null, renameSource: "", renameError: "",
        renameMenuId: 42, renameKeepsPointerRow: false, listInFlight: false, searchMode: "", listingState: "ready",
        sent: [], messages: [], refreshed: [], setCursor(index) { this.cursorIndex = index; },
        rowFor() { return {n: "before.txt"}; }, join(base, name) { return `${base}/${name}`; },
        swap: {drop() {}}, message(text, error) { this.messages.push([text, error]); }, sticky() {},
        refresh(selected) { this.refreshed.push(selected); }};
    let index = -1;
    Object.defineProperty(p, "renamingIndex", {get: () => index, set(value) { index = value; clearEditor(p); }});
    Object.defineProperty(p, "renamePending", {get: () => p.renameRequest !== null});
    p.backend = {rename(...args) { p.sent.push(args); }};
    const root = {stale: false, refreshRename(request, selected) { refresh(p, root, {stop() {}}, request, selected); }};
    p.fail = (where, input, message) => failed(p, root, Errors, Ops, Nav, Swap, where, input, message, 0);
    p.done = name => renamed(p, root, Nav, true, name);
    p.wire = root;
    Ops.startRename(p, 42);
    Ops.commitRename(p, "after.txt");
    return p;
}

let p = editing();
equal(p.sent, [["/fixture/list/before.txt", "after.txt", 42]]);
p.fail("journal", "/fixture/list/before.txt", "file or folder not found");
equal([p.renamePending, p.renamingIndex, p.renameError, p.refreshed.length],
    [false, 7, "File or folder not found.", 0]);
Ops.commitRename(p, "retry.txt");
equal([p.renamePending, p.sent.length, p.renameRequest.destination], [true, 2, "/fixture/list/retry.txt"]);

p = editing();
p.fail("journal", "/fixture/list/after.txt", "permission denied");
equal([p.renamePending, p.renamingIndex, p.refreshed], [false, -1, ["/fixture/list/after.txt"]]);
equal(p.messages, [["Renamed, but Undo was not recorded: permission denied.", true]]);

p = editing();
p.fail("rename-kept", "/fixture/list/before.txt", "permission denied");
equal([p.renamePending, p.renamingIndex, p.refreshed], [false, -1, [""]]);
equal(p.messages, [[Errors.sentence("rename-kept", "permission denied"), true]]);

for (const input of ["", "/fixture/list/after.txt", "/fixture/list/after.txt/child"]) {
    p = editing();
    p.fail("rename", input, "permission denied");
    equal([p.renamePending, p.renamingIndex, p.renameError], [false, 7, "Permission denied."]);
}

for (const where of ["rename", "journal", "rename-kept"]) {
    p = editing();
    p.fail(where, "/fixture/unrelated", "permission denied");
    equal([p.renamePending, p.renamingIndex, p.renameError], [true, 7, ""]);
}

p = editing();
p.done("/fixture/unrelated");
equal([p.renamePending, p.renamingIndex, p.refreshed.length], [true, 7, 0]);
p.done("/fixture/list/after.txt");
equal([p.renamePending, p.renamingIndex, p.refreshed], [false, -1, ["/fixture/list/after.txt"]]);

p = editing();
p.path = "/fixture/another-directory";
p.renamingIndex = -1;
equal([p.renamePending, p.renameSource, p.renameError], [true, "", ""]);
Ops.startRename(p, 99);
equal([p.renamingIndex, p.sent.length], [-1, 1]);
p.done("/fixture/list/after.txt");
equal([p.renamePending, p.renamingIndex, p.refreshed.length], [false, -1, 0]);

for (const where of ["backend", "read"]) {
    p = editing();
    p.fail(where, "", "the backend stopped");
    equal([p.renamePending, p.renamingIndex, p.listingState, p.total], [false, -1, "error", 0]);
    equal(p.messages, [["Backend stopped; rename outcome unknown.", true]]);
}

p = editing();
p.searchMode = "results";
p.done("/fixture/list/after.txt");
equal([p.renamePending, p.refreshed.length, p.wire.stale], [false, 0, true]);
console.log(`rename-lifecycle: ${checked} checks, 0 failed`);

// Optional real Qt scroll proof, using the product's unchanged Loader bodies and RenameField. qml6 needs no Quickshell, display server, driver, backend or filesystem rename operation here.
if (process.argv.includes("--qt-scroll")) {
    const {spawnSync, spawn} = require("node:child_process");
    const made = spawnSync("mktemp", ["-d", path.join(repo, ".rename-scroll.XXXXXXXX")], {encoding: "utf8"});
    assert.equal(made.status, 0, made.stderr);
    const testRoot = made.stdout.trim(), marker = path.join(testRoot, ".flea-test-sandbox");
    fs.writeFileSync(marker, "rename scroll Qt regression\n");
    const write = (name, text) => {
        const file = path.join(testRoot, name);
        fs.mkdirSync(path.dirname(file), {recursive: true});
        fs.writeFileSync(file, text);
    };
    // Sample input: "    Loader {\n        id: renameLoader\n        sourceComponent: Flea.RenameField {}\n    }".
    function loader(file, marker = "    Loader {\n        id: renameLoader") {
        const text = source(file), start = text.indexOf(marker);
        assert.ok(start >= 0, `${file}: QML block ${marker} missing`);
        let depth = 1, end = text.indexOf("{", start) + 1;
        while (depth && end < text.length) {
            if (text[end] === "{") depth++;
            if (text[end] === "}") depth--;
            end++;
        }
        assert.equal(depth, 0);
        return text.slice(start, end);
    }
    write("flea/qmldir", "singleton Theme 1.0 Theme.qml\nRenameField 1.0 RenameField.qml\n");
    write("flea/RenameField.qml", source("RenameField.qml"));
    write("flea/js/Buttons.js", source("js/Buttons.js"));
    write("imports/qs/Commons/qmldir", "module qs.Commons\nsingleton Dummy 1.0 Dummy.qml\n");
    write("imports/qs/Commons/Dummy.qml", "pragma Singleton\nimport QtQuick\nQtObject {}\n");
    write("flea/Theme.qml", `pragma Singleton
import QtQuick
QtObject {
    property int rowHeight: 31
    property int fileRowHeight: rowHeight
    property var spacing: ({rowPaddingY: 4, gap: 4, hairline: 1})
    property var color: ({background: "#101315", foreground: "#eeeeee", muted: "#aaaaaa", error: "#ff7777", accent: "#77aaff"})
    property var font: ({family: "monospace", body: 14, caption: 12})
}
`);
    const delegate = (grid) => `delegate: Item {
        id: root
        required property int index
        property var renamePane: editPane
        property var row: ({n: "a-original.md"})
        property string displayName: row.n
        property bool modeShown: false
        property bool renaming: index === editPane.renamingIndex
        property var editor: renameLoader.item
        width: ${grid ? "view.cellWidth" : "view.width"}
        height: ${grid ? "view.cellHeight" : "renaming && editor ? Math.max(31, editor.implicitHeight + 8) : 31"}
        signal renameCommitted(string name)
        signal renameAbandoned()
        onRenameAbandoned: editPane.renamingIndex = -1
        Item { id: icon; width: 16 }
        Item { id: mode; x: root.width }
        Item { id: nameLabel; x: 4; y: 28; width: root.width - 8 }
        ${loader(grid ? "GridTile.qml" : "Row.qml")}
    }`;
    for (const grid of [false, true]) {
        const mode = grid ? "grid" : "list";
        write(`${mode}.qml`, `import QtQuick
import "flea"
import "flea" as Flea
Window {
    id: probe
    width: 1000; height: 700; visible: true
    property int step: 0
    property int failures: 0
    property var request: ({source: "/fixture/a-original.md", destination: "/fixture/pending.md"})
    function check(ok, label) { if (!ok) { failures++; console.log("RENAME_SCROLL FAIL ${mode} " + label) } }
    function end() { view.contentY = Math.max(0, view.contentHeight - view.height) }
    QtObject {
        id: editPane
        property int renamingIndex: -1
        property string renameError: ""
        property var renameRequest: null
        readonly property bool renamePending: renameRequest !== null
        onRenamingIndexChanged: if (renamingIndex < 0) renameError = ""
        function setCursor(index) { view.positionViewAtIndex(index, ListView.Contain) }
    }
    ${grid ? "GridView" : "ListView"} {
        id: view
        width: 1000; height: 619; clip: true; focus: true
        model: (visible || editPane.renamingIndex >= 0) ? 1202 : 0
        reuseItems: true; cacheBuffer: 0
        property bool hiddenHeld: false
        property Item renameEditor: null
        ${grid ? "cellWidth: 100; cellHeight: 90 + (currentItem && currentItem.editor ? currentItem.editor.errorHeight : 0)" : ""}
        ${delegate(grid)}
    }
    Timer {
        interval: 80; running: true; repeat: true
        onTriggered: {
            var cell = view.currentItem
            if (probe.step === 0) { view.forceActiveFocus(); editPane.renamingIndex = 0 }
            if (probe.step === 1) {
                probe.check(cell && cell.editor && cell.editor.begun, "real field began")
                if (!cell || !cell.editor) { Qt.quit(); return }
                cell.editor.inputItem.text = "b-existing.md"
                editPane.renameError = "b-existing.md already exists."
            }
            if (probe.step === 2) {
                probe.check(cell.editor.errorHeight > 0 && cell.editor.inputItem.activeFocus, "expanded error retains focus")
                var hidden = Qt.createQmlObject('import QtQuick; Item { visible: false }', view)
                var ghost = Qt.createComponent("flea/RenameField.qml").createObject(hidden, {pane: editPane, viewport: view})
                probe.check(ghost && !ghost.begun && editPane.renamingIndex === 0, "unbegun hidden field cannot abandon the live editor")
                hidden.destroy()
                view.contentY = 1
            }
            if (probe.step === 3) {
                probe.check(editPane.renamingIndex === 0 && cell.editor.current === "b-existing.md", "partial editor stays editable")
                probe.end()
            }
            if (probe.step === 4) {
                probe.check(view.itemAtIndex(0) === null && cell !== null, "Qt retains currentItem outside held viewport")
                probe.check(editPane.renamingIndex === -1 && editPane.renameError === "", "released editor clears ownership and error")
                probe.check(view.activeFocus, "listing recovers focus")
                view.positionViewAtBeginning()
            }
            if (probe.step === 5) {
                probe.check(!cell.editor && ${grid ? "view.cellHeight === 90" : "cell.height === 31"}, "plain geometry recovers")
                editPane.renamingIndex = 0
            }
            if (probe.step === 6) {
                cell.editor.inputItem.text = "pending.md"
                editPane.renameRequest = probe.request
                probe.end()
            }
            if (probe.step === 7) {
                probe.check(editPane.renamingIndex === 0 && editPane.renameRequest === probe.request, "scroll preserves pending ownership")
                probe.check(cell.editor && cell.editor.current === "pending.md" && !cell.editor.commit(), "pending draft and submit guard survive scroll")
                view.visible = false
                view.contentY = 0
            }
            if (probe.step === 8) {
                probe.check(editPane.renamingIndex === 0 && editPane.renameRequest === probe.request, "hidden geometry retains pending ownership")
                editPane.renameRequest = null
                editPane.renamingIndex = -1
                view.visible = true
                view.positionViewAtBeginning()
            }
            if (probe.step === 9) { editPane.renamingIndex = 0 }
            if (probe.step === 10) { view.visible = false }
            if (probe.step === 11) {
                probe.check(editPane.renamingIndex === -1 && editPane.renameError === "", "nonpending hide still abandons")
                console.log("RENAME_SCROLL DONE ${mode} failures=" + probe.failures)
                Qt.quit()
            }
            probe.step++
        }
    }
}
`);
    }
    write("origin.qml", fs.readFileSync(path.join(repo, "tests/rename-list-origin.qml"), "utf8").replaceAll("@UI@", path.join(repo, "ui"))
        .replace("/* LIST_GEOMETRY */", ["onContentYChanged:", "function visibleRange()", "function coversCursor(", "function requestIfDrifted()", "function requestAround(", "function restartCoalesce()"].map(name => loader("List.qml", "    " + name)).join("\n")).replace("/* ROW_LOADER */", loader("Row.qml")).replace("/* PANE_SHOW_ROW */", loader("Pane.qml", "    function showRow(")));
    fs.mkdirSync(path.join(testRoot, "runtime"), {mode: 0o700});
    const env = {...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software", QML_DISABLE_DISK_CACHE: "1",
        QML_IMPORT_PATH: path.join(testRoot, "imports"), XDG_RUNTIME_DIR: path.join(testRoot, "runtime"),
        XDG_CACHE_HOME: path.join(testRoot, "cache"), XDG_CONFIG_HOME: path.join(testRoot, "config"),
        XDG_DATA_HOME: path.join(testRoot, "data"), XDG_STATE_HOME: path.join(testRoot, "state")};
    console.log(`rename-scroll evidence: ${testRoot}`);
    (async () => {
        for (const mode of ["list", "grid", "origin"]) {
            const result = await new Promise((resolve, reject) => {
                const child = spawn("timeout", ["15", process.env.QML_BIN || "qml6", "-I", env.QML_IMPORT_PATH, path.join(testRoot, `${mode}.qml`)], {env});
                let output = "";
                child.stdout.on("data", data => { output += data; });
                child.stderr.on("data", data => { output += data; });
                child.on("error", reject);
                child.on("close", (status, signal) => resolve({status, signal, output}));
            });
            fs.writeFileSync(path.join(testRoot, `${mode}.log`), result.output);
            console.log(result.output.trim());
            assert.equal(result.status, 0);
            assert.equal(result.output.split(`RENAME_SCROLL DONE ${mode} failures=0`).length - 1, 1);
            assert.doesNotMatch(result.output, /\bFAIL\b|\bWARN\b|Error|error:|Binding loop|failed to load|Unable to assign|Cannot assign/i);
        }
    })().catch(error => { console.error(error); process.exitCode = 1; });
}
