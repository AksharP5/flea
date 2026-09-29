.import "../../ui/js/PreviewSwap.js" as PreviewSwap
.import "../../ui/js/Facts.js" as Facts
.import "../../ui/js/Swap.js" as Swap
.import "../../ui/js/Columns.js" as Columns
.import "sourcefixture.js" as Source

// The preview swap, AGENTS.md "The preview swap": its moves, its cap, its frame kinds and what each surface waits for.

// Qt's Image.Status values, which the column hands over as plain numbers.
var NULL_STATUS = 0
var READY = 1
var LOADING = 2
var ERROR = 3

function column(state, extra) {
    var p = { state: state, thumb: false, frame: NULL_STATUS, noThumbComing: false, pdfDrawn: false,
              pdfFailed: false, linesLoading: false, meta: false }
    for (var k in extra)
        p[k] = extra[k]
    return PreviewSwap.columnReady(p)
}

function run(check) {
    check("a preview gets the listing swap's cap once its own work starts", PreviewSwap.capMs(false), Swap.HOLD_MS)
    check("a PDF's cap starts after the document settle ui/PreviewPdf.qml waits",
          PreviewSwap.capMs(true), Swap.HOLD_MS + PreviewSwap.DOCUMENT_SETTLE_MS)
    check("a capture gives up before the preview column's own 120 ms settle would load under it",
          PreviewSwap.CAPTURE_MS < 120, true)

    var idle = { capturing: false, holding: false, key: undefined }
    var held = { capturing: false, holding: true, key: "/d\n3" }
    check("a move with nothing held starts a hold", PreviewSwap.onMove(idle, "/d\n3", true), PreviewSwap.HOLD)
    check("the second caller for the same row joins it",
          PreviewSwap.onMove(held, "/d\n3", true), PreviewSwap.JOIN)
    check("a move to another row during a column hold is held j, which gives the stale picture up",
          PreviewSwap.onMove(held, "/d\n4", true), PreviewSwap.BURST)
    check("Quick Look keeps its picture through held j, as it kept the live preview before",
          PreviewSwap.onMove(held, "/d/b.jpg", false), PreviewSwap.JOIN)
    check("a capture still in flight counts as a hold",
          PreviewSwap.onMove({ capturing: true, holding: false, key: "/d\n3" }, "/d\n4", true), PreviewSwap.BURST)

    check("a frame under the picture is held whatever builds beneath it", PreviewSwap.frameKind(true, false, false), "held")
    check("a whole preview drawn live is no kind of frame at all", PreviewSwap.frameKind(false, true, false), "")
    check("a half-built preview drawn live is the defect", PreviewSwap.frameKind(false, false, false), "mid")
    check("after a fallback the same frame is the loading state, which is allowed",
          PreviewSwap.frameKind(false, false, true), "loading")

    check("the column's loading state is never ready", column(Facts.LOADING, {}), false)
    check("an image waits for its cache file to decode", column(Facts.IMAGE, { thumb: true, frame: LOADING }), false)
    check("and lands when it has", column(Facts.IMAGE, { thumb: true, frame: READY }), true)
    check("or when it failed, since the mark stands in then", column(Facts.IMAGE, { thumb: true, frame: ERROR }), true)
    check("an image with no cache file yet but one coming waits for it", column(Facts.IMAGE, {}), false)
    check("an image with none coming waits for the original the frame decodes itself",
          column(Facts.IMAGE, { noThumbComing: true, frame: LOADING }) + "|"
          + column(Facts.IMAGE, { noThumbComing: true, frame: READY }), "false|true")
    check("a video with no poster coming lands on its mark", column(Facts.VIDEO, { noThumbComing: true }), true)
    check("a video with a poster waits for it", column(Facts.VIDEO, { thumb: true, frame: LOADING }), false)
    check("a PDF waits for its first page", column(Facts.PDF, {}) + "|" + column(Facts.PDF, { pdfDrawn: true }), "false|true")
    check("an unreadable PDF lands on its error", column(Facts.PDF, { pdfFailed: true }), true)
    check("text and code wait for their lines",
          column(Facts.TEXT, { linesLoading: true }) + "|" + column(Facts.CODE, { linesLoading: false }), "false|true")
    check("an archive waits for its index", column(Facts.ARCHIVE, {}) + "|" + column(Facts.ARCHIVE, { meta: true }), "false|true")
    check("a kind drawn only as its mark lands with its facts",
          column(Facts.UNSUPPORTED, {}) + "|" + column(Facts.AUDIO, {}) + "|" + column(Facts.SYMLINK, {}) + "|"
          + column(Facts.MULTI, {}), "true|true|true|true")

    check("Quick Look waits while any pane says loading", PreviewSwap.lookReady("loading", false, false, false), false)
    check("a PDF viewer is ready once a page is on screen",
          PreviewSwap.lookReady("pdf", true, false, false) + "|" + PreviewSwap.lookReady("pdf", true, true, false), "false|true")
    check("or once the document is refused", PreviewSwap.lookReady("This file could not be read.", true, false, true), true)
    check("anything else not loading is whole", PreviewSwap.lookReady("image", false, false, false), true)
    runFolderDataHold(check)
    runPictureHoldLeak(check)
}

// The body of one QML function by brace count, so each check reads the arm it names and not a copy elsewhere.
// Sample input: bodyOf("f() { return 1 }", "f") is "{ return 1 }".
function bodyOf(src, name) {
    var text = String(src)
    var at = text.indexOf(name + "(")
    if (at < 0)
        return ""
    var open = text.indexOf("{", at)
    if (open < 0)
        return ""
    var depth = 0
    for (var i = open; i < text.length; i++) {
        var c = text.charAt(i)
        if (c === "{")
            depth += 1
        else if (c === "}") {
            depth -= 1
            if (depth === 0)
                return text.substring(open, i + 1)
        }
    }
    return ""
}

// Sample input: squashed("a  b\n c") is "a b c".
function squashed(s) {
    return String(s).replace(/\s+/g, " ")
}

// A folder peek in Columns holds by data: an unanswered folder keeps the old column, and the landed peek shows it with its rows in one pass.
function runFolderDataHold(check) {
    check("an unanswered folder defers by data", Columns.folderDataHold(true, false), true)
    check("an answered folder lands at once", Columns.folderDataHold(true, true), false)
    check("a file never defers by data", Columns.folderDataHold(false, false)
        + "|" + Columns.folderDataHold(false, true), "false|false")
    check("a landed peek shows the folder it waited for", Columns.showFolderOnPeek("/a", "/b", true), true)
    check("an already shown folder shows nothing new", Columns.showFolderOnPeek("/a", "/a", true), false)
    check("a still outstanding peek leaves the old column up", Columns.showFolderOnPeek("/a", "/b", false), false)
    check("no cursor folder shows nothing", Columns.showFolderOnPeek("", "/b", true), false)
    check("a data-held empty folder lands settled", Columns.shouldSettleHero(true, "/a", "/a", false, 0), true)
    check("a non-empty folder never settles a hero", Columns.shouldSettleHero(true, "/a", "/a", false, 3), false)
    check("a locked folder never settles a hero", Columns.shouldSettleHero(true, "/a", "/a", true, 0), false)
    check("a file never settles a hero", Columns.shouldSettleHero(false, "/a", "/a", false, 0), false)
    check("a stale peek never settles a hero", Columns.shouldSettleHero(true, "/a", "/b", false, 0), false)
    var area = Source.source("ui/ColumnsArea.qml")
    var move = squashed(bodyOf(area, "moveThird"))
    check("a move onto an unanswered folder takes the data hold", move.indexOf("Columns.folderDataHold(") >= 0, true)
    var arm = move.substring(move.indexOf("Columns.folderDataHold("), move.indexOf("folderFallback.restart()"))
    check("a live hold is handed to the data hold's wait, never cancelled into it",
        arm.indexOf("thirdSwap.cancel()") < 0, true)
    check("the waiting folder is never shown before its peek lands", arm.indexOf("showCursorRow") < 0, true)
    check("the data hold takes no picture",
        arm.indexOf("thirdSwap.hold(") < 0 && arm.indexOf("thirdSwap.start(") < 0, true)
    check("while every other move stops it", move.indexOf("folderFallback.stop()") >= 0, true)
    var peeked = squashed(bodyOf(area, "onPeeked"))
    check("a landed peek shows the folder it waited for", peeked.indexOf("Columns.showFolderOnPeek(") >= 0
        && peeked.indexOf("root.showCursorRow()") > peeked.indexOf("Columns.showFolderOnPeek("), true)
    check("the fallback is a single shot at the listing swap cap", area.indexOf("interval: Swap.HOLD_MS") >= 0, true)
    check("and shows the pending column when the peek is late", area.indexOf("onTriggered: if (root.cursorIsDir && !root.answered(root.childPath)) { thirdSwap.cancel(); root.showCursorRow(true) }") >= 0, true)
    var show = squashed(bodyOf(area, "showCursorRow"))
    check("a stale queued show never draws an unanswered folder",
        show.indexOf("Columns.folderDataHold(") >= 0 && show.indexOf("force") >= 0, true)
    check("a data-held empty hero skips its entrance", Source.source("ui/EmptyState.qml").indexOf("animateEntrance") >= 0, true)
    check("its mark can settle at once", Source.source("ui/FleaMark.qml").indexOf("function settle()") >= 0, true)
    check("a landed empty peek settles its hero whole", peeked.indexOf("Columns.shouldSettleHero(") >= 0
        && peeked.indexOf("markItem.settle()") > peeked.indexOf("Columns.shouldSettleHero("), true)
}

// A launch or folder move must never leave the third-column picture up: only a real file row takes one.
function fileRowSafe(row) {
    return typeof Columns.isFileRow === "function" ? Columns.isFileRow(row) : "missing"
}

function runPictureHoldLeak(check) {
    check("the file-row rule exists", typeof Columns.isFileRow === "function", true)
    check("a null row never takes a file load", fileRowSafe(null), false)
    check("an undefined row never takes a file load", fileRowSafe(undefined), false)
    check("a folder never takes a file load", fileRowSafe({d: true}), false)
    check("a file takes a file load", fileRowSafe({d: false}), true)
    var area = Source.source("ui/ColumnsArea.qml")
    var move = squashed(bodyOf(area, "moveThird"))
    check("a move takes a file hold only for a real file row",
        move.indexOf("Columns.isFileRow(root.cursorRow)") >= 0, true)
    var peeked = squashed(bodyOf(area, "onPeeked"))
    var landAt = peeked.indexOf("showFolderOnPeek(")
    var shownAt = peeked.indexOf("root.showCursorRow()", landAt)
    var cancelAt = peeked.indexOf("thirdSwap.cancel()", landAt)
    check("a landed peek ends a live picture before showing",
        landAt >= 0 && shownAt > landAt && cancelAt >= 0 && cancelAt < shownAt, true)
    var fallbackAt = area.indexOf("id: folderFallback")
    var triggerAt = area.indexOf("onTriggered:", fallbackAt)
    var trigger = area.substring(triggerAt, area.indexOf("\n", triggerAt))
    check("the fallback ends a live picture before showing",
        trigger.indexOf("thirdSwap.cancel()") >= 0 && trigger.indexOf("root.showCursorRow(true)") >= 0, true)
    var preview = Source.source("ui/SelectionPreview.qml")
    check("the preview imports the file-row rule",
        preview.indexOf('import "js/Columns.js" as Columns') >= 0, true)
    check("the preview never holds a picture for a folder cursor",
        preview.indexOf("Columns.isFileRow") >= 0, true)
    var replaceArm = squashed(bodyOf(preview, "replace"))
    var replaceGuard = replaceArm.indexOf("Columns.isFileRow(")
    var replaceReturn = replaceArm.indexOf("return", replaceGuard)
    var replaceSlice = replaceGuard >= 0 ? replaceArm.substring(replaceGuard, replaceReturn) : ""
    check("a folder move keeps the old preview instead of clearing it",
        replaceGuard >= 0 && replaceSlice.indexOf("settle.stop()") >= 0 && replaceSlice.indexOf("root.clear()") < 0, true)
    var followArm = squashed(bodyOf(preview, "followSelection"))
    var followGuard = followArm.indexOf("Columns.isFileRow(candidate)")
    var followReturn = followArm.indexOf("return", followGuard)
    var followSlice = followGuard >= 0 ? followArm.substring(followGuard, followReturn) : ""
    check("a folder selection keeps the old preview instead of clearing it",
        followGuard >= 0 && followSlice.indexOf("settle.stop()") >= 0 && followSlice.indexOf("root.clear()") < 0, true)
    var selAt = preview.indexOf("function loadSelection()")
    var loadAt = preview.indexOf("function load()", selAt)
    var selBody = squashed(preview.substring(selAt, loadAt))
    var selGuard = selBody.indexOf("Columns.isFileRow(")
    check("a folder cursor takes no load hold and keeps the old preview",
        selGuard >= 0 && selBody.indexOf("settle.stop()") > selGuard
        && selBody.indexOf("settle.stop()") < selBody.indexOf("root.swap.hold("), true)
    var loadBody = squashed(preview.substring(loadAt, preview.indexOf("function startSwap", loadAt)))
    var loadGuard = loadBody.indexOf("Columns.isFileRow(current)")
    check("a folder load keeps the old preview instead of clearing it",
        loadGuard >= 0 && loadBody.indexOf("root.clear()") > loadGuard, true)
}
