//@ pragma ShellId flea-settings-columns-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Settings.js" as Settings
import "flea/js/TextSize.js" as TextSize

// Every row each settings section builds, drawn by the real ui/SettingsRow.qml at the pane's width:
// a hint and the Display ruler start on their control's label column, HANDOFF rules 3 and 8, and
// only the pane's footer line starts at the row's own edge. tests/settings-columns.sh drives it.
ShellRoot {
    id: root

    // A state every section's rows() accepts; no value in it moves a column, only which rows exist.
    readonly property var probeState: ({ data: {}, home: "/probe", favouriteStatuses: {}, pins: [], selectedFavourite: "",
        about: {}, saveStatus: "", textSize: TextSize.follow(), hidden: [], keyHints: false, preset: "default",
        baseSize: 14, monitorScale: 1, cornerRadius: 8, presetKeys: {} })

    Item {
        id: holder
        width: Flea.Theme.settings.paneWidth
    }

    Component {
        id: rowComponent
        Flea.SettingsRow {}
    }

    // The x a row's text starts at: its label, a hint's own line, or the ruler; null when nothing drawn matches.
    function textX(item, row) {
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i]
            if (!child.visible)
                continue
            if (row.kind === "ruler" ? child.stops !== undefined : child.text === row.label)
                return child.x
        }
        return null
    }

    function measure() {
        var out = { label: [], hint: [], ruler: [], footer: [], failures: [] }
        var sections = Settings.SECTIONS.map(function (section) { return section.id }).concat(["columns"])
        for (var s = 0; s < sections.length; s++) {
            var rows = []
            try {
                rows = Settings.rows(sections[s], root.probeState)
            } catch (error) {
                out.failures.push(sections[s] + " built no rows: " + error)
            }
            for (var r = 0; r < rows.length; r++) {
                var row = rows[r]
                var item = rowComponent.createObject(holder, { row: row, width: holder.width })
                var kind = row.kind === "hint" ? (row.footer === true ? "footer" : "hint")
                         : row.kind === "ruler" ? "ruler" : item.isGroup || item.isHero || item.isFavourite || item.isKeyPreview ? "" : "label"
                if (kind !== "")
                    out[kind].push({ at: sections[s] + ": " + (row.label || row.id), x: root.textX(item, row) })
                item.destroy()
            }
        }
        return out
    }

    Component.onCompleted: {
        var found = root.measure()
        var labelX = found.label.length > 0 ? found.label[0].x : null
        var failures = found.failures
        function expect(list, x, what) {
            for (var i = 0; i < list.length; i++) {
                if (list[i].x === null || list[i].x !== x)
                    failures.push(list[i].at + " starts at " + list[i].x + ", " + what + " is " + x)
            }
        }
        expect(found.label, labelX, "the label column")
        expect(found.hint, labelX, "the label column")
        expect(found.ruler, labelX, "the label column")
        // The control that proves the reader tells two columns apart: the footer sits at the row's edge.
        expect(found.footer, Flea.Theme.spacing.rowPaddingX, "the row edge")
        if (labelX === null || labelX === Flea.Theme.spacing.rowPaddingX || found.hint.length === 0
                || found.ruler.length === 0 || found.footer.length === 0)
            failures.push("nothing to compare: label " + labelX + ", " + found.hint.length + " hints, "
                          + found.ruler.length + " rulers, " + found.footer.length + " footers")
        for (var f = 0; f < failures.length; f++)
            console.log("SETTINGS_COLUMNS FAIL " + failures[f])
        if (failures.length === 0)
            console.log("SETTINGS_COLUMNS PASS label=" + labelX + " labels=" + found.label.length + " hints=" + found.hint.length
                        + " rulers=" + found.ruler.length + " footer=" + found.footer[0].x)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
