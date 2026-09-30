pragma Singleton
import QtQuick

// Test-only ViewState for the headercost fixture, staged as ViewState.qml before construction
// so actual Header.qml binds to it with no production seam and no runtime patching. Records
// columnWidths commits in memory and never touches disk: Header call grouping only, while real
// disk persistence stays with the separate UI/autofit suite. Mirrors the shipped hidden default.
QtObject {
    id: root
    property var state: ({})
    property var hiddenCols: ["mode", "kind"]
    property var commits: []

    function changeMapEntries(key, entries, full) {
        var next = {}
        var s = root.state || {}
        for (var k in s) next[k] = s[k]
        next[key] = full
        root.state = next
        root.commits.push({ key: key, entries: entries, full: full })
    }

    function seed(map) {
        var s = root.state || {}
        var next = {}
        for (var k in s) next[k] = s[k]
        next.columnWidths = map
        root.state = next
    }

    function reset() { root.commits = [] }
}
