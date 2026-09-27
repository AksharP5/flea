.import "../../ui/js/PreviewSwap.js" as PreviewSwap
.import "../../ui/js/Facts.js" as Facts
.import "../../ui/js/Swap.js" as Swap

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
}
