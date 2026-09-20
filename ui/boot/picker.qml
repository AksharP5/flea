// Its own app id, so one Hyprland rule can give the chooser the floating treatment Omarchy already
// gives xdg-desktop-portal-gtk without touching the window; flea --picker writes that rule.
//@ pragma AppId com.thisisgm.flea.picker
//@ pragma ShellId fleapicker
//@ pragma NativeTextRendering
//@ pragma CacheDir $BASE/flea

import Quickshell

// The chooser's window is a file: URL away for the reason ui/boot/shell.qml gives: a Quickshell
// config is served through qs: URLs, which Qt's QML disk cache refuses. The chooser is not on the
// measured path, so it keeps its window whole rather than splitting a body off the first frame:
// its title and size are read from Picker.js and the Theme, and a portal dialog that resized
// itself once the body landed would be a visible defect for no gain. See AGENTS.md "The first window".
ShellRoot {
    LazyLoader {
        active: true
        // This directory cannot import ui/js/Format.js through qs:, so the one call is written out.
        source: "file://" + encodeURI(Quickshell.shellDir + "/../PickerWindow.qml").replace(/#/g, "%23").replace(/\?/g, "%3F")
    }
}
