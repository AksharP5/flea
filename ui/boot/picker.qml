// Its own app id, so one Hyprland rule can give the chooser the floating treatment Omarchy already
// gives xdg-desktop-portal-gtk without touching the window; flea --picker writes that rule.
//@ pragma AppId com.thisisgm.flea.picker
//@ pragma ShellId fleapicker
//@ pragma NativeTextRendering
//@ pragma CacheDir $BASE/flea

import Quickshell

// A file: URL away for the reason ui/boot/shell.qml gives, but its window stays whole: the chooser
// is not on the measured path and its size comes from the Theme. See AGENTS.md "The first window".
ShellRoot {
    LazyLoader {
        id: chooser
        active: true
        // This directory cannot import ui/js/Format.js through qs:, so the one call is written out.
        source: "file://" + encodeURI(Quickshell.shellDir + "/../PickerWindow.qml").replace(/#/g, "%23").replace(/\?/g, "%3F")
    }

    // LazyLoader has no status and this load is synchronous, so a null item here is a load that
    // failed: silence would leave tools/flea-portal's caller waiting out its whole 600 s.
    Component.onCompleted: {
        if (!chooser.item) {
            console.warn("flea: the chooser window did not load, so there is nothing to show")
            Quickshell.execDetached(["kill", String(Quickshell.processId)])
        }
    }
}
