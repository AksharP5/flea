#!/usr/bin/env node
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {spawnSync} = require("node:child_process");
const repo = path.resolve(process.argv[2] || path.join(__dirname, ".."));
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
    write(`flea/${name}.qml`, fs.readFileSync(path.join(repo, "ui", `${name}.qml`), "utf8"));
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
write("probe.qml", fs.readFileSync(path.join(repo, "tests/rename-grid-bottom.qml"), "utf8"));
fs.mkdirSync(path.join(testRoot, "runtime"), {mode: 0o700});
const env = {...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software", QML_DISABLE_DISK_CACHE: "1",
    QML_IMPORT_PATH: path.join(testRoot, "imports"), XDG_RUNTIME_DIR: path.join(testRoot, "runtime"),
    XDG_CACHE_HOME: path.join(testRoot, "cache"), XDG_CONFIG_HOME: path.join(testRoot, "config"),
    XDG_DATA_HOME: path.join(testRoot, "data"), XDG_STATE_HOME: path.join(testRoot, "state")};
const result = spawnSync("timeout", ["15", process.env.QML_BIN || "qml6", "-I", env.QML_IMPORT_PATH, path.join(testRoot, "probe.qml")], {env, encoding: "utf8"});
const output = result.stdout + result.stderr;
fs.writeFileSync(path.join(testRoot, "probe.log"), output);
console.log(`rename-grid-bottom evidence: ${testRoot}`);
console.log(output.trim());
assert.equal(result.status, 0);
assert.equal(output.split("RENAME_GRID_BOTTOM CHECKS=42").length - 1, 1);
assert.equal(output.split("RENAME_GRID_BOTTOM DONE failures=0").length - 1, 1);
assert.doesNotMatch(output, /\bFAIL\b|\bWARN(?:ING)?\b|Error|error:|Binding loop|failed to load|Unable to assign|Cannot assign/i);
