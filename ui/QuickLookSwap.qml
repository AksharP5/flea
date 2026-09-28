import QtQuick
import "." as Flea

// Quick Look's half of the preview swap, built on the first open and never at launch; see
// AGENTS.md "The preview swap". The panes stay eager in ui/Preview.qml the way 0.3.5 drew them,
// so this wrapper captures that outer container rather than children of its own.
Flea.PreviewSwap {
    // Fills the Loader ui/Preview.qml parents it to; without this the wrapper measures zero
    // and every hold answers at once, which reads as the swap silently doing nothing.
    anchors.fill: parent
    property Item panesSource: null
    captureSource: panesSource
}
