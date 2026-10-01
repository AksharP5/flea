function focusStep(turn) {
    if (turn === 0) {
        view.height = 646
        editPane.setCursor(1201)
    }
    if (turn === 1) {
        probe.check(Theme.rowHeight === 31 && Theme.grid.captionHeight === 34 && view.cellHeight === 134,
            "bottom F2 uses normal row, caption and cell tokens")
        probe.check(view.itemAtIndex(1201) !== null, "normal End draws actual last tile before F2")
        // F2's backend entry opens this same row through Ops.startRename.
        Ops.startRename(editPane)
        var field = probe.editor()
        probe.check(field && field.inputItem.activeFocus && field.inputItem.selectedText === "f1199",
            "normal bottom F2 initially focuses and selects actual filename stem")
        probe.check(field && field.extraHeight === -1 && view.cellHeight === probe.plainHeight,
            "bottom Loader defers its initial measurement without synchronous cell reflow")
    }
    if (turn === 2) {
        var before = probe.editor()
        probe.check(before && before.extraHeight === 0 && view.cellHeight === probe.plainHeight,
            "bottom normal Loader publishes its zero expansion")
        probe.check(before && before.inputItem.activeFocus && before.inputItem.selectedText === "f1199" && probe.contained(),
            "bottom zero measurement retains focus, stem selection and containment")
        if (!before) { probe.finish(); return }
        // Drive Qt's own child-focus departure before real same-row pooling, without moving focus to another surface.
        view.currentIndex = 1201
        view.currentIndex = 0
        view.contentY = 0
        probe.check(!before.inputItem.activeFocus && view.activeFocus,
            "real Grid current-item change drops child focus while viewport still owns focus")
        editPane.setCursor(1201)
        var after = probe.editor()
        probe.check(after && after !== before && after.ownsEdit(), "real Grid recycling replaces zero-height bottom editor")
        probe.check(after && after.inputItem.activeFocus && after.current === "f1199.txt",
            "zero-height replacement keeps bottom filename and restores viewport-owned focus")
        probe.check(after && after.inputItem.selectedText === "f1199",
            "zero-height replacement preserves stem selection lost before handoff")
        before.parent.active = false
        probe.check(after && view.renameEditor === after, "destroying focus-lost predecessor preserves newer owner")
        editPane.renameError = "A refusal expands the predecessor editor across several caption lines."
    }
    if (turn === 3) {
        var before = probe.editor()
        probe.check(before && before.inputItem.activeFocus && view.cellHeight > probe.plainHeight && probe.contained(),
            "recovered bottom editor survives error expansion and containment")
        if (!before) { probe.finish(); return }
        before.inputItem.text = "b-existing.md"
        before.inputItem.select(9, 2)
        editPane.renameError = ""
        view.currentIndex = 1201
        view.currentIndex = 0
        view.contentY = 0
        probe.check(!before.inputItem.activeFocus && view.activeFocus,
            "contracting predecessor loses child focus while Grid retains focus")
        before.parent.active = false
        probe.check(view.renameEditor === null && view.renameRetirement && editPane.renamingIndex === 1201,
            "focus-lost destruction retains only copied same-row edit until deferred settle")
        editPane.setCursor(1201)
        var after = probe.editor()
        probe.check(after && after !== before && after.ownsEdit() && after.inputItem.activeFocus,
            "dead focus-lost predecessor hands viewport-owned focus to real replacement")
        probe.check(after && after.current === "b-existing.md" && after.inputItem.selectionStart === 2
            && after.inputItem.selectionEnd === 9 && after.inputItem.cursorPosition === 2,
            "dead focus-lost predecessor preserves draft and reversed selection")
    }
    if (turn === 4) {
        var field = probe.editor()
        probe.check(field && field.extraHeight === 0 && view.cellHeight === probe.plainHeight,
            "recovered normal editor releases expanded predecessor height")
        probe.check(field && field.inputItem.activeFocus && field.current === "b-existing.md" && probe.contained(),
            "bottom contraction settles with complete draft and focus")
        if (!field) { probe.finish(); return }
        probe.pendingLoader = field.parent
        probe.pendingLoader.active = false
        probe.check(view.renameEditor === null && view.renameRetirement !== null,
            "focused retirement awaits same-turn replacement before menu takes focus")
        menuFocus.forceActiveFocus()
        probe.restorePendingLoader()
        probe.check(menuFocus.activeFocus && probe.editor() && !probe.editor().inputItem.activeFocus,
            "retirement captured before menu focus cannot reclaim that focus")
    }
    if (turn === 5) {
        probe.check(editPane.renamingIndex === -1 && menuFocus.activeFocus && view.renameRetirement === null,
            "menu departure releases recovered draft without reclaiming focus")
        Ops.startRename(editPane)
    }
    if (turn === 6) {
        var field = probe.editor()
        probe.check(field && field.inputItem.activeFocus && field.current === "f1199.txt",
            "later explicit F2 starts fresh after menu cancellation")
        if (!field) { probe.finish(); return }
        probe.pendingLoader = field.parent
        probe.pendingLoader.active = false
        probe.check(view.renameEditor === null && view.renameRetirement !== null,
            "focused retirement awaits same-turn replacement before rail takes focus")
        railFocus.forceActiveFocus()
        probe.restorePendingLoader()
        probe.check(railFocus.activeFocus && probe.editor() && !probe.editor().inputItem.activeFocus,
            "retirement captured before rail focus cannot reclaim that focus")
    }
    if (turn === 7) {
        probe.check(editPane.renamingIndex === -1 && railFocus.activeFocus && view.renameRetirement === null,
            "rail departure releases recovered editor without reclaiming focus")
        probe.check(view.cellHeight === probe.plainHeight && view.renameEditor === null,
            "focus lifecycle restores ordinary Grid geometry and releases editor")
        probe.finish()
    }
}

module.exports = focusStep;
