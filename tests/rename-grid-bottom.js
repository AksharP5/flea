#!/usr/bin/env node
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {spawnSync} = require("node:child_process");
const focusStep = require("./rename-grid-focus.js");
const owner = require("./rename-grid-owner.js");
const repo = path.resolve(process.argv.slice(2).find(arg => !arg.startsWith("--")) || path.join(__dirname, ".."));
const option = name => process.argv.find(arg => arg.startsWith(`--${name}=`))?.slice(name.length + 3);
const testCase = option("case") || "all";
assert.ok(["all", "legacy", "measurement", "pending", "focus", "owner"].includes(testCase));
const productRoot = path.resolve(option("product-root") || repo);
// Isolate the new normal-token cases from the existing oversized-token lifetime fixture.
if (testCase === "all") {
    for (const selected of ["legacy", "measurement", "pending", "focus", "owner"]) {
        const result = spawnSync(process.execPath, [__filename, repo, `--case=${selected}`, `--product-root=${productRoot}`], {stdio: "inherit"});
        assert.equal(result.status, 0, `${selected} case failed`);
    }
    fs.writeSync(1, `rename-grid-bottom: 126 prior + ${owner.checks} owner checks, 0 failed\n`);
    process.exit(0);
}
// These functions run in the generated Qt fixture, with its real GridView and Loader.
function measurementStep(turn) {
    if (turn === 0) {
        Theme.rowHeight = 31
        view.visible = true
        editPane.setCursor(0)
        editPane.renamingIndex = 0
    }
    if (turn === 1) {
        var first = probe.editor()
        probe.check(Theme.rowHeight === 31 && Theme.grid.captionHeight === 34,
            "measurement uses normal row and caption tokens")
        probe.check(first && first.extraHeight === 0, "normal initial Loader measures zero editor expansion")
        if (!first) { probe.finish(); return }
        first.inputItem.text = "previous-draft.md"
        editPane.renameError = "A refusal expands the predecessor editor across several caption lines."
    }
    if (turn === 2) {
        probe.check(view.cellHeight > probe.plainHeight, "normal predecessor error expands global cells")
        probe.check(view.itemAtIndex(1) !== null, "next rename uses another resident Grid tile")
        var expandedHeight = view.cellHeight
        probe.replacementChanges = probe.heightChanges
        editPane.renameError = ""
        editPane.renamingIndex = 1
        probe.check(view.cellHeight === expandedHeight,
            "normal replacement defers global height mutation until after Loader creation")
    }
    if (turn === 3) {
        var next = probe.editor()
        probe.check(next && next.extraHeight === 0, "normal replacement Loader publishes its initial zero measurement")
        probe.check(view.cellHeight === probe.plainHeight && probe.heightChanges === probe.replacementChanges + 1,
            "normal replacement releases predecessor expansion with one deferred reflow")
        probe.check(next && next.ownsEdit() && next.inputItem.activeFocus && next.current === editPane.rowFor(1).n,
            "normal replacement retains new row identity and focus without inheriting draft")
        probe.check(probe.contained(), "normal replacement contains complete editor after contraction")
    }
    if (turn === 4) {
        probe.check(view.cellHeight === probe.plainHeight && probe.contained(),
            "normal replacement remains measured and contained on a later turn")
        editPane.renamingIndex = -1
        probe.finish()
    }
}
function restorePendingLoader() {
    var loader = probe.pendingLoader
    loader.active = Qt.binding(function() { return loader.parent.renaming })
}
function retirePendingField(field, draft, checkCaret) {
    field.inputItem.text = draft
    editPane.renameRequest = probe.pendingRequest
    field.inputItem.select(4, 4)
    if (checkCaret) probe.check(field.inputItem.cursorPosition === 4 && field.inputItem.selectionStart === 4
        && field.inputItem.selectionEnd === 4, "pending destroyed editor starts with caret four")
    probe.pendingLoader = field.parent
    probe.pendingLoader.active = false
}
function pendingRetirementStep(turn) {
    if (turn === 0) {
        Theme.rowHeight = 31
        view.visible = true
        editPane.setCursor(1201)
        editPane.renamingIndex = 1201
    }
    if (turn === 1) {
        var field = probe.editor()
        probe.check(field && field.ownsEdit() && field.inputItem.activeFocus,
            "delayed pending retirement starts from actual owned Grid Loader")
        if (!field) { probe.finish(); return }
        probe.retirePendingField(field, "pending.md", true)
        probe.check(view.renameEditor === null && probe.editor() === null,
            "pending Loader destruction removes every live editor before queued settle")
    }
    if (turn === 2) {
        probe.check(editPane.renamingIndex === 1201 && editPane.renameRequest === probe.pendingRequest
            && view.renameEditor === null && probe.editor() === null,
            "queued settle preserves pending identity while no editor lives")
        probe.check(view.renameRetirement && view.renameRetirement.text === "pending.md"
            && view.renameRetirement.cursor === 4 && view.renameRetirement.anchor === 4,
            "queued settle retains pending draft and caret values for delayed same-row replacement")
        probe.restorePendingLoader()
        var reborn = probe.editor()
        probe.check(reborn && reborn.ownsEdit() && view.renameEditor === reborn,
            "delayed real Loader recreation takes current pending ownership")
        probe.check(reborn && reborn.current === "pending.md", "delayed pending replacement preserves submitted draft")
        probe.check(reborn && reborn.inputItem.cursorPosition === 4
            && reborn.inputItem.selectionStart === 4 && reborn.inputItem.selectionEnd === 4,
            "delayed pending replacement preserves collapsed caret")
        probe.check(reborn && reborn.inputItem.readOnly && !reborn.commit()
            && editPane.renameRequest === probe.pendingRequest,
            "delayed pending replacement still guards submitted backend write")
        probe.check(view.renameRetirement === null, "delayed matching editor consumes copied retirement")
    }
    if (turn === 3) {
        probe.check(probe.contained() && probe.editor() && probe.editor().inputItem.activeFocus,
            "delayed pending replacement remains focused and contained")
        editPane.renameRequest = null
        editPane.renameError = "pending.md already exists."
    }
    if (turn === 4) {
        var failed = probe.editor()
        probe.check(failed && failed.current === "pending.md" && !failed.inputItem.readOnly
            && editPane.renamingIndex === 1201 && editPane.renameError.length > 0,
            "backend error leaves replacement draft editable under same rename owner")
        probe.check(probe.contained(), "backend error contains delayed replacement")
        if (!failed) { probe.finish(); return }
        probe.pendingLoader = failed.parent
        probe.pendingLoader.active = false
    }
    if (turn === 5) {
        probe.check(editPane.renamingIndex === -1 && view.renameRetirement === null,
            "nonpending error editor retirement releases ownership and copied values")
        probe.restorePendingLoader()
        editPane.setCursor(1201)
        editPane.renamingIndex = 1201
    }
    if (turn === 6) {
        var again = probe.editor()
        probe.check(again && again.current === editPane.rowFor(1201).n,
            "cancelled error draft cannot reappear in later same-row edit")
        if (!again) { probe.finish(); return }
        probe.retirePendingField(again, "pending.md", false)
    }
    if (turn === 7) {
        editPane.renameRequest = null
        editPane.renamingIndex = -1
    }
    if (turn === 8) {
        probe.check(view.renameRetirement === null && view.renameEditor === null && editPane.renamingIndex === -1,
            "backend completion releases editorless pending retirement")
        probe.restorePendingLoader()
        editPane.renamingIndex = 1201
    }
    if (turn === 9) {
        var completed = probe.editor()
        probe.check(completed && completed.current === editPane.rowFor(1201).n,
            "completed backend request cannot resurrect retired pending draft")
        if (!completed) { probe.finish(); return }
        probe.retirePendingField(completed, "pending.md", false)
    }
    if (turn === 10) {
        editPane.renameRequest = null
        editPane.renameError = "Permission denied."
    }
    if (turn === 11) {
        probe.check(view.renameRetirement === null && editPane.renamingIndex === -1,
            "backend error without live editor releases unclaimed retirement")
        editPane.renamingIndex = -1
        probe.restorePendingLoader()
        editPane.renamingIndex = 1201
    }
    if (turn === 12) {
        var cancelled = probe.editor()
        probe.check(cancelled && cancelled.current === editPane.rowFor(1201).n,
            "editorless backend error cannot leak retired draft into retry")
        if (!cancelled) { probe.finish(); return }
        probe.retirePendingField(cancelled, "pending.md", false)
    }
    if (turn === 13) {
        editPane.renamingIndex = -1
    }
    if (turn === 14) {
        probe.check(view.renameRetirement === null && editPane.renameRequest === probe.pendingRequest,
            "cancel invalidates copied draft without releasing pending backend request")
        probe.restorePendingLoader()
        editPane.renamingIndex = 1201
    }
    if (turn === 15) {
        var fresh = probe.editor()
        probe.check(fresh && fresh.current === editPane.rowFor(1201).n && fresh.inputItem.readOnly,
            "cancelled pending edit cannot hand draft to new same-row owner")
        if (!fresh) { probe.finish(); return }
        probe.retirePendingField(fresh, "other-request.md", false)
    }
    if (turn === 16) {
        probe.check(view.renameRetirement && view.renameRetirement.text === "other-request.md",
            "second editorless pending retirement holds only current draft values")
        editPane.renameRequest = {source: probe.pendingRequest.source, destination: probe.pendingRequest.destination}
        probe.restorePendingLoader()
        var otherRequest = probe.editor()
        probe.check(otherRequest && otherRequest.current === editPane.rowFor(1201).n && otherRequest.inputItem.readOnly,
            "same-row Loader rejects retirement from a different pending backend request before settle")
    }
    if (turn === 17) {
        probe.check(view.renameRetirement === null && editPane.renamePending
            && editPane.renameRequest !== probe.pendingRequest,
            "replacement request retains its own guard after stale retirement is consumed")
        editPane.renameRequest = null
        editPane.renamingIndex = -1
        probe.pendingLoader = null
        probe.finish()
    }
}
const made = spawnSync("mktemp", ["-d", path.join(repo, ".rename-grid-bottom.XXXXXXXX")], {encoding: "utf8"});
assert.equal(made.status, 0, made.stderr);
const testRoot = made.stdout.trim();
fs.writeFileSync(path.join(testRoot, ".flea-test-sandbox"), "real Qt bottom Grid rename regression\n");
function write(name, text) {
    const file = path.join(testRoot, name);
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, text);
}
// Use the complete product view, tile and editor. Only unrelated chrome and services are stubbed.
for (const name of ["GridArea", "GridTile", "RenameField", "FastScrollHandler"])
    write(`flea/${name}.qml`, fs.readFileSync(path.join(name === "FastScrollHandler" ? repo : productRoot, "ui", `${name}.qml`), "utf8"));
fs.cpSync(path.join(repo, "ui/js"), path.join(testRoot, "flea/js"), {recursive: true});
write("flea/qmldir", ["Theme", "ViewState", "Style", "Util"].map(name => `singleton ${name} 1.0 ${name}.qml`).join("\n") + "\n");
write("imports/qs/Commons/qmldir", "module qs.Commons\nsingleton Dummy 1.0 Dummy.qml\n");
write("imports/qs/Commons/Dummy.qml", "pragma Singleton\nimport QtQuick\nQtObject {}\n");
write("flea/Theme.qml", `pragma Singleton
import QtQuick
QtObject {
    property int rowHeight: 31
    property int chromeHeight: 23
    property real bodySmallAdvance: 8
    property real disabledOpacity: 0.5
    property var spacing: ({rowPaddingY: 4, rowPaddingX: 14, gap: 8, hairline: 1})
    property var grid: ({captionHeight: 34, captionLineHeight: 17, minCellWidth: 146})
    property var color: ({background: "#101315", surface: "#181825", foreground: "#eeeeee", muted: "#aaaaaa", error: "#ff7777", accent: "#77aaff"})
    property var font: ({family: "monospace", body: 14, bodySmall: 14, caption: 12})
    property var scroll: ({notchPx: 24, multiplier: 4})
}
`);
write("flea/ViewState.qml", `pragma Singleton
import QtQuick
QtObject {
    property string density: "compact"
    property int thumbnailPixels: 64
    property string thumbnailMode: "off"
    property bool ctrlZoom: false
    property var hiddenCols: []
    property var preview: ({})
}
`);
write("flea/Style.qml", `pragma Singleton
import QtQuick
QtObject {
    property color selectedAccentFill: "#224466"
    property color selectionFill: "#223344"
    property color hoverFill: "#334455"
    property real hoverFillAlpha: 0.2
}
`);
write("flea/Util.qml", "pragma Singleton\nimport QtQuick\nQtObject { function alpha(color, value) { return color } }\n");
write("flea/Glyph.qml", "import QtQuick\nItem { property int maxSize: 128; property string name; property color color }\n");
write("flea/ViewportScrollBar.qml", "import QtQuick\nItem { property var flickable; property var ctrlWheelAction }\n");
write("flea/SelectionBand.qml", "import QtQuick\nItem { property var pane; property var flickable; property int columns; property real cellWidth; property real cellHeight }\n");
write("flea/FileDrag.qml", "import QtQuick\nItem { property var pane; property int dropIndex: -1; property bool dragCopy: false }\n");
write("flea/RowDrag.qml", "import QtQuick\nItem { property var session; property int listingIndex; property var row }\n");
let fixture = fs.readFileSync(path.join(repo, "tests/rename-grid-bottom.qml"), "utf8");
if (testCase !== "legacy") {
    const timer = fixture.indexOf("    Timer {\n        interval: 80"), finish = fixture.indexOf("    function finish()", timer);
    assert.ok(timer >= 0 && finish > timer);
    const functions = [measurementStep, focusStep, restorePendingLoader, retirePendingField, pendingRetirementStep, owner.ownerStep].map(fn => fn.toString()).join("\n");
    fixture = fixture.slice(0, timer) + functions + `
    Timer {
        interval: 80; running: true; repeat: true
        onTriggered: {
            if (probe.step === 0) probe.plainHeight = view.cellHeight
            probe.${({measurement: "measurementStep", pending: "pendingRetirementStep", focus: "focusStep", owner: "ownerStep"})[testCase]}(probe.step++)
        }
    }
` + fixture.slice(finish);
    fixture = fixture.replace("    property int step: 0", `    property string testCase: "${testCase}"\n    property var pendingLoader: null\n    property int step: 0`);
}
if (testCase === "owner") fixture = owner.injectPane(fixture, fs.readFileSync(path.join(productRoot, "ui/Pane.qml"), "utf8"));
write("probe.qml", fixture);
fs.mkdirSync(path.join(testRoot, "runtime"), {mode: 0o700});
const env = {...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software", QML_DISABLE_DISK_CACHE: "1",
    QML_IMPORT_PATH: path.join(testRoot, "imports"), XDG_RUNTIME_DIR: path.join(testRoot, "runtime"),
    XDG_CACHE_HOME: path.join(testRoot, "cache"), XDG_CONFIG_HOME: path.join(testRoot, "config"),
    XDG_DATA_HOME: path.join(testRoot, "data"), XDG_STATE_HOME: path.join(testRoot, "state")};
const result = spawnSync("timeout", ["15", process.env.QML_BIN || "qml6", "-I", env.QML_IMPORT_PATH, path.join(testRoot, "probe.qml")], {env, encoding: "utf8"});
const output = result.stdout + result.stderr;
fs.writeFileSync(path.join(testRoot, "probe.log"), output);
fs.writeSync(1, `rename-grid-bottom evidence: ${testRoot}\n${output.trim()}\n`);
assert.equal(result.status, 0);
assert.equal(output.split(`RENAME_GRID_BOTTOM CHECKS=${({legacy: 66, measurement: 10, pending: 24, focus: 26, owner: owner.checks})[testCase]}`).length - 1, 1);
assert.equal(output.split("RENAME_GRID_BOTTOM DONE failures=0").length - 1, 1);
assert.doesNotMatch(output, /\bFAIL\b|\bWARN(?:ING)?\b|Error|error:|Binding loop|failed to load|Unable to assign|Cannot assign/i);
