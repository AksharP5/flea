#!/usr/bin/env bash
# Counts group in thousands everywhere: no count of rows, items, files or matches may be
# built into a string by hand. Format.count (GUI), Model.grouped (shelf) and render::grouped
# (TUI) are the only groupers. Each forbid below names the raw shape it refuses; a hit prints
# the file and line that still builds a count by hand.
set -u
cd "$(dirname "$0")/.." || exit 1
failed=0
checks=0

# forbid <file> <ere> : fails when the pattern still matches, i.e. a raw count survives.
forbid() {
    checks=$((checks + 1))
    hits=$(grep -nE "$2" "$1" || true)
    if [ -n "$hits" ]; then
        printf 'counts: FAIL %s still builds a count by hand:\n%s\n' "$1" "$hits"
        failed=$((failed + 1))
    fi
}

# forbid_fixed <file> <literal> : same, for strings grep -E cannot spell plainly.
forbid_fixed() {
    checks=$((checks + 1))
    hits=$(grep -nF "$2" "$1" || true)
    if [ -n "$hits" ]; then
        printf 'counts: FAIL %s still builds a count by hand:\n%s\n' "$1" "$hits"
        failed=$((failed + 1))
    fi
}

# The four the unit names.
forbid ui/StatusBar.qml 'root\.total \+'
forbid ui/StatusBar.qml 'selectionCount \+ " of "'
forbid ui/StatusBar.qml '" of " \+ root\.total'
forbid ui/js/Filter.js 'list\.length \+ " of "'
forbid ui/js/Filter.js '" of " \+ loaded'
forbid ui/PreviewArchive.qml '\+ Facts\.archiveMore'

# Every other GUI count the grep found.
forbid ui/js/Ops.js 'return n \+ \(n === 1'
forbid ui/js/Ops.js 'ok \+ " of " \+ t\.n'
forbid ui/js/Ops.js 'failed \+ " failed"'
forbid ui/js/Ops.js 'skipped \+ " skipped"'
forbid ui/js/Ops.js 'message\.deleted \+ " of "'
forbid ui/js/Ops.js 'message\.failed \+ " failed"'
forbid ui/js/Transfer.js '[^t]\(t\.index \+ 1\) \+ " of "'
forbid ui/js/Transfer.js '" of " \+ t\.n'
forbid ui/js/Collide.js 'total \+ " items already exist in "'
forbid ui/js/Collide.js '[^t]\(total - shown\) \+ " more"'
forbid ui/js/Picker.js 'base \+ " " \+ count'
forbid ui/js/Picker.js 'count \+ " selected'
forbid ui/js/Facts.js 'g\.count \+ " "'
forbid ui/js/Facts.js 'String\(meta\.entries\)'
forbid ui/js/Facts.js '\+ meta\.lines'
forbid ui/js/Search.js 'total \+ " found'
forbid ui/js/LocalSend.js 'paths\.length \+ " items'
forbid ui/js/PathBar.js 'after\.matches \+ " names'
forbid ui/TrashView.qml 'root\.total \+'
forbid ui/TrashView.qml 'message\.done \+ " of "'
forbid ui/TrashView.qml '" of " \+ \(message\.done \+ failed\)'
forbid ui/TrashView.qml 'failed \+ " failed"'
forbid ui/TrashConfirm.qml 'snapshot\.count \+'
forbid ui/PaneMenuActions.qml 'message\.deleted \+ " of "'
forbid ui/PaneMenuActions.qml '" of " \+ message\.count'
forbid ui/PaneMenuActions.qml 'message\.failed \+ " failed"'

# The shelf plugin groups through its own helper: it moves with shelf/ into its own
# repository, so nothing there may import up to ui/js/Format.js.
forbid shelf/Model.js '\+ n \+ \(n === 1'
forbid shelf/Model.js 'return n \+ \(n === 1'
forbid shelf/Model.js 'holding " \+ n \+ " items"'
forbid shelf/Run.js 'state\.index \+ 1\) \+ " of "'
forbid shelf/Run.js '" of " \+ state\.count'
forbid shelf/Run.js 'ok \+ " of " \+ total'
forbid shelf/Run.js '\+ n \+ \(n === 1'

# The TUI groups through render::grouped. Each literal below is the exact pre-fix shape.
forbid_fixed src/tui/model.rs 'format!("Renaming {} of {}", batch.completed + 1, batch.total)'
forbid_fixed src/tui/model.rs '}, batch.completed) });'
forbid_fixed src/tui/model.rs 'count(&value, "entries").to_string()'
forbid src/tui/model.rs '^\s*self\.total,$'
forbid src/tui/model.rs '^\s*count\(&value, "scanned"\)$'
forbid src/tui/model.rs '^\s*count\(&value, "ok"\),$'
forbid_fixed src/tui/model.rs 'format!(" · {} skipped", count(&value, "skipped"))'
forbid_fixed src/tui/model.rs 'format!("{} failed", count(&value, "failed"))'
forbid_fixed src/tui/model.rs '"Deleted {} of {}{}", count(&value, "deleted"), self.menu_count'
forbid_fixed src/tui/model.rs '"{} failed · {}", count(&value, "failed")'
forbid_fixed src/tui/render.rs '"{} rows hidden by the filter", m.rows.len() - count'
forbid_fixed src/tui/render.rs '"{} {}, {}", deletion.count, if deletion.count'
forbid_fixed src/tui/render.rs 'format!(" V {} ", m.selected.len())'
forbid_fixed src/tui/render.rs 'format!("{} items", m.total)'
forbid_fixed src/tui/render.rs '"Filter {} · {} matches in {} loaded rows", m.filter, m.shown().len(), m.rows.len()'
forbid_fixed src/tui/render.rs 'format!("{} items selected", m.selected.len())'

if [ "$failed" -eq 0 ]; then
    printf 'counts: %d checks, every count groups\n' "$checks"
else
    printf 'counts: %d of %d checks failed\n' "$failed" "$checks"
fi
exit "$failed"
