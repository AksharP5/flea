import Quickshell
import Quickshell.Io
import QtQuick
import QtQml.XmlListModel
import "js/Format.js" as Format
import "js/Recent.js" as Recent

// The desktop's own recent history, read and never written. Qt's XML reader does the parsing, so
// this file has no parser of its own: XmlListModel is QXmlStreamReader behind a query, and a
// history Flea hand-parsed would be a second XBEL implementation on a file it does not own.
// The read is lazy, so a picker whose user never asks for Recent never opens the file at all.
QtObject {
    id: root

    // The validated absolute paths, newest first; empty until refresh() has been asked for.
    property var paths: []
    signal refreshed()

    readonly property string file: Recent.historyPath(Quickshell.env("XDG_DATA_HOME"), Quickshell.env("HOME"))

    // Asked for when the Recent location is opened, so the file is re-read rather than remembered:
    // every other application on the box appends to it while this window is up.
    function refresh() {
        if (historyFile.path === root.file) historyFile.reload()
        else historyFile.path = root.file
    }

    // Read first so only an absent file is quiet: XmlListModel warns on one, and a fresh account has none.
    property FileView historyFile: FileView {
        printErrors: false
        onLoaded: root.parse()
        onLoadFailed: function (error) {
            if (error !== FileViewError.FileNotFound)
                console.warn("PickerRecent: could not read " + root.file + ": " + error)
            root.paths = []
            root.refreshed()
        }
    }

    // The model re-reads what the check just read, so a present history is a second read from the page cache.
    function parse() {
        var url = Format.fileUri(root.file)
        if (history.source.toString() === url) history.reload()
        else history.source = url
    }

    property XmlListModel historyModel: XmlListModel {
        id: history
        query: "/xbel/bookmark"
        // Never on the construction-time Null: that answered refreshed with no rows, and the path jump takes the first answer.
        onStatusChanged: if (status === XmlListModel.Ready || status === XmlListModel.Error) root.rebuild()
        XmlListModelRole { name: "href"; attributeName: "href" }
        XmlListModelRole { name: "visited"; attributeName: "visited" }
        XmlListModelRole { name: "modified"; attributeName: "modified" }
        XmlListModelRole { name: "added"; attributeName: "added" }
    }

    // Qt 6 gives XmlListModel no get(), so the rows are read off the model itself: data() is
    // invokable and the roles are numbered from Qt.UserRole in the order declared above.
    readonly property int hrefRole: Qt.UserRole
    readonly property int visitedRole: Qt.UserRole + 1
    readonly property int modifiedRole: Qt.UserRole + 2
    readonly property int addedRole: Qt.UserRole + 3

    // Every bookmark is read, because ui/js/Recent.js LIMIT bounds the rail and not the read: XBEL
    // promises no order, so a bound in file order hands the sort an arbitrary slice and lists the
    // newest of that. Measured on oldest-first fixtures, six batches whole against two capped: a
    // rebuild costs about 3 ms at 500 bookmarks whichever way, tens of ms against 3 at 5,000, and
    // hundreds of ms against 4 at 50,000, over an XmlListModel parse both pay that is itself a
    // sixth of a second there. The Instantiator this replaced cost seconds at 50,000.
    function rebuild() {
        var found = []
        var wanted = history.count
        for (var i = 0; i < wanted; i++) {
            var at = history.index(i, 0)
            // visited is when the file itself was last opened, which is what Recent means; the
            // other two stamp the bookmark and stand in for a writer that left visited out.
            var visited = String(history.data(at, root.visitedRole) || "")
            var modified = String(history.data(at, root.modifiedRole) || "")
            var added = String(history.data(at, root.addedRole) || "")
            found.push({ href: String(history.data(at, root.hrefRole) || ""),
                         stamp: visited.length > 0 ? visited : (modified.length > 0 ? modified : added) })
        }
        root.paths = Recent.paths(found)
        root.refreshed()
    }
}
