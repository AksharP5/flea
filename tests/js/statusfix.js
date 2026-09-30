.import "../../ui/js/Status.js" as Status

// Status bar, Quick Look ground and PreviewSwap fixes for the 0.3.6 QML review.
// Each check reads the shipped QML source, so a live window is not needed.
function sourceText(url) {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl(url), false)
    request.send()
    return String(request.responseText || "")
}

function run(check) {
    var bar = sourceText("../../ui/StatusBar.qml")
    var swap = sourceText("../../ui/PreviewSwap.qml")
    var look = sourceText("../../ui/Preview.qml")
    var image = sourceText("../../ui/PreviewImage.qml")
    check("Spinner builds only while busy", bar.indexOf("active: root.busy") >= 0, true)
    check("undo texts stay empty unless split", bar.indexOf('root.undoSplit ? "z undoes" : ""') >= 0, true)
    check("hint reserves by advance", bar.indexOf("hintWidth: hintMetrics.advanceWidth") >= 0, true)
    check("esc keeps its order ahead of z", bar.indexOf("id: secondary") < bar.indexOf("id: undoDot"), true)
    check("click refuses through the shared gate", bar.indexOf("Focus.canUndo(root.pane") >= 0, true)
    check("whose selection-band gate lives in Focus.js", sourceText("../../ui/js/Focus.js").indexOf("selectionBand") >= 0, true)
    check("with the rename and search-typing gates beside it",
          sourceText("../../ui/js/Focus.js").indexOf("renameEditor()") >= 0
          && sourceText("../../ui/js/Focus.js").indexOf("Search.TYPING") >= 0, true)
    check("busy mark sizes from the chrome token", bar.indexOf("Theme.chromeMarkSize") >= 0, true)
    check("Quick Look ground takes the wheel", look.indexOf("onWheel") >= 0, true)
    check("afterAnimating stays live until ready lands after a release", swap.indexOf("(root.capturing || root.holding || root.dropping || !root.ready) ? root.Window.window : null") >= 0, true)
    check("hold sink keeps Back for the window", swap.indexOf("Qt.AllButtons") < 0, true)
    check("Quick Look asks no meta for a photo", look.indexOf("askImage") < 0, true)
    check("Quick Look keeps no EXIF turn", look.indexOf("imageTurn") < 0 && image.indexOf("property int turn") < 0, true)
    check("photo draws on one decode", image.indexOf("retainWhileLoading") < 0 && image.indexOf("showing") < 0, true)
    check("undo split keeps esc ahead of z", Status.withoutUndoKey("esc dismisses · z undoes"), "esc dismisses")
}
