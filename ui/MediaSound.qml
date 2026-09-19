pragma Singleton
import QtQuick

// MediaMute rule 3: mute is one session flag both media surfaces read, the preview column's strip
// and Quick Look's, kept across previews and never written to ui.json.
QtObject {
    id: root

    property bool muted: false

    function toggle() { root.muted = !root.muted }
}
