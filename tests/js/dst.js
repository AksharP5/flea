.import "../../ui/js/Format.js" as Format

function run(check, suite) {
    if (suite === "edmonton") {
        runEdmonton(check)
        return
    }
    // America/New_York skips from 01:59 EST to 03:00 EDT on 8 March 2026.
    check("the hour before spring forward keeps its own wall clock",
          Format.date(1772951400), "2026-03-08 01:30")
    check("the first hour after the spring gap keeps its own wall clock",
          Format.date(1772955000), "2026-03-08 03:30")
    check("the evening before spring forward keeps the earlier day",
          Format.date(1772944200), "2026-03-07 23:30")

    // America/New_York repeats 01:00 through 01:59 on 1 November 2026.
    check("the hour before fall back keeps its own wall clock",
          Format.date(1793507400), "2026-11-01 00:30")
    check("the first pass through the repeated hour reads 01:30",
          Format.date(1793511000), "2026-11-01 01:30")
    // Two instants an hour apart share one wall clock, which is why every sort is on mtime.
    check("the second pass through the repeated hour reads 01:30 as well",
          Format.date(1793514600), "2026-11-01 01:30")
    check("the evening before fall back keeps the earlier day",
          Format.date(1793503800), "2026-10-31 23:30")

    // The picker's compact form is the one surface that still asks which local day it is.
    var fallNow = 1793552400
    check("the compact form keeps the repeated hour on today",
          Format.compactDate(1793514600, fallNow * 1000), "01:30")
    check("the compact form puts the evening before on yesterday's stamp",
          Format.compactDate(1793503800, fallNow * 1000), "31 Oct")
}

function runEdmonton(check) {
    // Issue #40 was observed at 23:21 MDT on 3 September 2026: a late-evening file must not advance
    // into the next day, which is what reading the instant in UTC would have done.
    check("the reporter's first late-evening file stays on its own day",
          Format.date(1788499140), "2026-09-03 23:19")
    check("the reporter's second late-evening file stays on its own day",
          Format.date(1788498720), "2026-09-03 23:12")
    check("the reporter's August date does not advance into September",
          Format.date(1788237660), "2026-08-31 22:41")
    check("the reporter's older date keeps its local day",
          Format.date(1787631840), "2026-08-24 22:24")
}
