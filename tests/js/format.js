.import "../../ui/js/Format.js" as Format

function run(check) {
    // The home prefix reads as the user writes it; the window chrome and the search strip share this.
    check("a path under home comes back with a tilde",
          Format.tilde("/home/gm/Documents/claude", "/home/gm"), "~/Documents/claude")
    check("home itself is just the tilde",
          Format.tilde("/home/gm", "/home/gm"), "~")
    check("a path outside home is left alone",
          Format.tilde("/usr/share/omarchy", "/home/gm"), "/usr/share/omarchy")
    check("an unknown home leaves every path alone",
          Format.tilde("/home/gm/x", ""), "/home/gm/x")

    // ui/js/Tabs.js "label" names a tab after the directory it stands in, which is this and nothing else.
    check("the leaf is the directory's own name",
          Format.leafPart("~/Documents/claude"), "claude")
    check("a bare name is all leaf", Format.leafPart("claude"), "claude")
    check("the root is its own label", Format.leafPart("/"), "/")
    check("a tilde alone is its own leaf", Format.leafPart("~"), "~")

    check("zero bytes", Format.size(0), "0 B")
    check("just under a kilobyte", Format.size(999), "999 B")
    check("exactly a kilobyte", Format.size(1000), "1.0 kB")
    check("the old kibibyte boundary is not special", Format.size(1024), "1.0 kB")
    check("a megabyte and a half", Format.size(1500000), "1.5 MB")
    // Finder renders this exact number as 26.95 GB; real GLib on this box prints 26.9 GB, see AGENTS.md.
    check("Finder's own example, at GLib's precision", Format.size(26950000000), "26.9 GB")
    check("a terabyte", Format.size(1000000000000), "1.0 TB")

    // Local constructors keep these wall-clock expectations valid in every non-UTC test zone.
    check("the stamp is the local wall clock",
          Format.date(new Date(2026, 0, 1, 0, 10).getTime() / 1000), "2026-01-01 00:10")
    check("the minute before local midnight keeps its own day",
          Format.date(new Date(2025, 11, 31, 23, 55).getTime() / 1000), "2025-12-31 23:55")
    check("an older instant is the same form, never a shorter one",
          Format.date(new Date(2025, 11, 30, 22, 0).getTime() / 1000), "2025-12-30 22:00")
    check("this year is the same form too",
          Format.date(new Date(2026, 6, 28, 0, 27).getTime() / 1000), "2026-07-28 00:27")
    // Single-digit months and days pad, which is what makes the column sortable as text.
    check("a single-digit month and day both pad",
          Format.date(new Date(2026, 8, 5, 9, 4).getTime() / 1000), "2026-09-05 09:04")
    // ui/Theme.qml sizes column.date at dateChars, so no instant may be wider than that.
    check("the stamp is always the sixteen characters the column is cut for",
          Format.date(new Date(2026, 8, 5, 9, 4).getTime() / 1000).length, 16)

    // The send picker's own column: SendPicker.html draws 11:32, 10:18, 21 Aug and 15 Aug, and the
    // window's Format.date above is untouched. Fixed instants throughout, never Date.now().
    check("today is the clock alone",
          Format.compactDate(new Date(2026, 7, 21, 11, 32).getTime() / 1000,
                             new Date(2026, 7, 21, 14, 0).getTime()), "11:32")
    check("an earlier day this year is the bare stamp",
          Format.compactDate(new Date(2026, 7, 21, 21, 5).getTime() / 1000,
                             new Date(2026, 7, 27, 12, 0).getTime()), "21 Aug")

    // The local-day rollover: one minute either side of local midnight, which is where this breaks.
    var justAfterMidnight = new Date(2026, 7, 22, 0, 1).getTime()
    check("23:59 last night is no longer the clock",
          Format.compactDate(new Date(2026, 7, 21, 23, 59).getTime() / 1000, justAfterMidnight), "21 Aug")
    check("00:01 this morning is already the clock",
          Format.compactDate(new Date(2026, 7, 22, 0, 1).getTime() / 1000, justAfterMidnight), "00:01")
    check("23:59 tonight is still the clock at 23:59",
          Format.compactDate(new Date(2026, 7, 21, 23, 59).getTime() / 1000,
                             new Date(2026, 7, 21, 23, 59).getTime()), "23:59")

    // The year boundary, which is the rollover and the disambiguation at once.
    var justAfterNewYear = new Date(2026, 0, 1, 0, 1).getTime()
    check("23:59 on new year's eve carries the year it belongs to",
          Format.compactDate(new Date(2025, 11, 31, 23, 59).getTime() / 1000, justAfterNewYear), "31 Dec '25")
    check("00:01 on new year's day is the clock",
          Format.compactDate(new Date(2026, 0, 1, 0, 1).getTime() / 1000, justAfterNewYear), "00:01")
    check("January this year drops the year again",
          Format.compactDate(new Date(2026, 0, 1, 9, 0).getTime() / 1000,
                             new Date(2026, 2, 1, 9, 0).getTime()), "1 Jan")

    // Two Augusts must not read as one string, which is the whole reason the year survives the trim.
    var fromTwentySix = new Date(2026, 7, 27, 12, 0).getTime()
    check("last August carries its year",
          Format.compactDate(new Date(2025, 7, 21, 10, 0).getTime() / 1000, fromTwentySix), "21 Aug '25")
    check("the August before it carries a different one",
          Format.compactDate(new Date(2024, 7, 21, 10, 0).getTime() / 1000, fromTwentySix), "21 Aug '24")
    check("a single-digit year keeps both of its digits",
          Format.compactDate(new Date(2005, 7, 21, 10, 0).getTime() / 1000, fromTwentySix), "21 Aug '05")
    // ui/Theme.qml sizes column.pickerDate at ten characters of this face, so nothing here may elide.
    check("the widest compact form is the ten characters the column is cut for",
          Format.compactDate(new Date(2025, 7, 21, 10, 0).getTime() / 1000, fromTwentySix).length, 10)

    // The window keeps its own form for the same instant; the picker column is the narrower one.
    check("the window's stamp is not the picker's compact form",
          Format.date(new Date(2025, 7, 21, 10, 0).getTime() / 1000), "2025-08-21 10:00")

    check("a regular file 644", Format.permissions(33188), "rw-r--r--")
    check("a directory 755", Format.permissions(16877), "rwxr-xr-x")
    check("a symlink 777", Format.permissions(41471), "rwxrwxrwx")
    check("no permissions at all", Format.permissions(32768), "---------")

    check("a symlink is a symlink", Format.isSymlink(41471), true)
    check("a file is not a symlink", Format.isSymlink(33188), false)
    check("mode 755 is executable", Format.isExecutable(33261), true)
    check("mode 644 is not executable", Format.isExecutable(33188), false)
    check("a vanished row is not executable", Format.isExecutable(0), false)
}
