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

function paintStep(turn) {
    if (turn === 9) {
        editPane.renameRequest = null
        view.currentIndex = Qt.binding(function() {
            return Filter.viewOf(editPane.shown, editPane.renamingIndex >= 0 ? editPane.renamingIndex : editPane.cursorIndex)
        })
        var loader = probe.liveLoader
        loader.active = Qt.binding(function() { return loader.parent.renaming })
        editPane.setCursor(1201)
        Ops.startRename(editPane)
    }
    if (turn === 10) {
        probe.currentField = view.renameEditor
        probe.currentTile = probe.currentField ? probe.currentField.editorHost : null
        probe.check(probe.currentField && probe.currentField.ownsEdit() && probe.currentTile === view.currentItem,
            "paint control begins on actual current Grid host")
        if (!probe.currentField) { probe.finish(); return }
        probe.currentField.inputItem.text = "b-existing.md"
        probe.currentField.inputItem.select(9, 2)
        editPane.renameError = "b-existing.md already exists."
    }
    if (turn === 11) {
        probe.currentField = view.renameEditor
        probe.currentTile = probe.currentField.editorHost
        probe.check(probe.retainedLoader.parent !== probe.currentTile
            && probe.retainedLoader.parent.listingIndex === probe.currentTile.listingIndex,
            "paint control retains distinct real same-row Loader outside Grid layout")
        probe.check(view.itemAt(probe.currentTile.x + probe.currentTile.width / 2,
            probe.currentTile.y + probe.currentTile.height / 2) === probe.currentTile,
            "paint control identifies actual Grid-managed layout host")
        // Recreate the editor in the retained host. Old code registers it and hides the painted tile.
        probe.retainedLoader.active = true
    }
    if (turn === 12) {
        var field = view.renameEditor
        var host = field ? field.editorHost : null
        var top = field ? field.mapToItem(view, 0, 0).y : -1
        probe.check(field && host === probe.currentTile && host === view.currentItem
            && field.visible && host.visible && field.inputItem.activeFocus,
            "post-layout recovery registers effectively visible actual current host")
        probe.check(host && view.itemAt(host.x + host.width / 2, host.y + host.height / 2) === host
            && editPane.renameEditor() === host && top >= 0 && top + field.height <= view.height,
            "registered editor is contained in actual painted Grid slot")
        probe.check(field && field.current === "b-existing.md" && field.inputItem.selectionStart === 2
            && field.inputItem.selectionEnd === 9 && field.inputItem.cursorPosition === 2,
            "post-layout recovery preserves draft and reversed selection")
        probe.check(probe.retainedLoader.item && probe.retainedLoader.item !== field
            && !probe.retainedLoader.item.ownsEdit() && !probe.retainedLoader.parent.visible,
            "recreated retained Loader stays live but cannot cover recovered editor")
        if (!field) { probe.finish(); return }
        field.inputItem.select(2, 2)
        var point = field.inputItem.mapToItem(view, 0, 0)
        console.log("PAINT_META " + JSON.stringify({x: Math.round(point.x), y: Math.round(point.y),
            stem: Math.floor(field.inputItem.positionToRectangle(field.stemEnd).x)}))
        view.grabToImage(function(result) {
            probe.check(result.saveToFile(Qt.resolvedUrl("paint-grid.png").toString().replace("file://", "")),
                "actual Grid capture saves for pixel assertions")
        })
        field.inputItem.grabToImage(function(result) {
            probe.check(result.saveToFile(Qt.resolvedUrl("paint-input.png").toString().replace("file://", "")),
                "current TextInput capture saves for glyph assertions")
        })
    }
    if (turn === 13) {
        // A pending edit must retain the same request while a stale Loader recovers after rail focus.
        editPane.renameRequest = probe.pendingRequest
        railFocus.forceActiveFocus()
        probe.retainedLoader.active = false
        probe.retainedLoader.active = true
        probe.check(railFocus.activeFocus, "retained Loader begin cannot take rail focus")
    }
    if (turn === 14) {
        probe.check(view.renameEditor === probe.currentField && editPane.renameRequest === probe.pendingRequest
            && editPane.renamingIndex === 1201 && view.renameEditor.current === "b-existing.md",
            "pending post-layout recovery preserves exact request and draft")
        probe.check(railFocus.activeFocus && !view.renameEditor.inputItem.activeFocus,
            "post-layout recovery cannot reclaim rail focus")
        editPane.renameRequest = null
        editPane.renamingIndex = -1
        probe.finish()
    }
}

function registerPaintProof(repo) {
    const assert = require("node:assert/strict");
    const fs = require("node:fs");
    const path = require("node:path");
    const {spawnSync} = require("node:child_process");
    process.once("exit", () => {
        const root = fs.readdirSync(repo).filter(name => name.startsWith(".rename-grid-bottom."))
            .map(name => path.join(repo, name)).sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
        const log = fs.readFileSync(path.join(root, "probe.log"), "utf8");
        const metadata = log.match(/PAINT_META (\{[^\n]+\})/);
        assert.ok(metadata, "painted editor metadata must be recorded");
        const point = JSON.parse(metadata[1]);
        function image(name) {
            const file = path.join(root, name);
            const header = fs.readFileSync(file);
            const decoded = spawnSync("ffmpeg", ["-v", "error", "-threads", "1", "-i", file,
                "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"], {maxBuffer: 8 * 1024 * 1024});
            assert.equal(decoded.status, 0, decoded.stderr.toString());
            return {width: header.readUInt32BE(16), height: header.readUInt32BE(20), pixels: decoded.stdout};
        }
        const grid = image("paint-grid.png"), input = image("paint-input.png");
        let ink = 0, painted = 0;
        for (let y = 0; y < input.height; y++) {
            for (let x = 0; x < Math.min(input.width, point.stem); x++) {
                const at = (y * input.width + x) * 4;
                if (input.pixels[at + 3] < 250 || input.pixels[at] < 230) continue;
                ink++;
                const target = ((point.y + y) * grid.width + point.x + x) * 4;
                if ([0, 1, 2].every(channel => Math.abs(grid.pixels[target + channel] - input.pixels[at + channel]) <= 5)) painted++;
            }
        }
        console.log(`rename-grid-paint pixels: ${painted}/${ink}`);
        assert.ok(ink >= 30, "current draft must rasterize actual stem glyphs");
        assert.ok(painted / ink >= 0.95, `current draft glyphs must paint in Grid capture: ${painted}/${ink}`);
        console.log(`rename-grid-paint: ${painted}/${ink} current stem pixels painted, 2 checks, 0 failed`);
    });
}

focusStep.paintStep = paintStep;
focusStep.registerPaintProof = registerPaintProof;
module.exports = focusStep;
