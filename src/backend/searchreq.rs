// The wire side of a search: the loop hands it a slice of walking and it decides what to say, the way thumbreq answers thumb.
use crate::backend::proto::{searched_line, searching_line};
use crate::backend::timing::since;
use crate::backend::state::State;
use std::io::{self, BufWriter, Write};
use std::time::{Duration, Instant};

// A streaming search announces its growing count no more often than this, so a fast walk cannot flood the client's parser.
const SEARCH_REPORT: Duration = Duration::from_millis(100);

// One bounded slice per call, so an opcancel or a keystroke is never behind a whole subtree. Answers
// whether the walk ended in a new row order, which is what the caller forgets its row indices on.
pub fn step_search(out: &mut BufWriter<io::Stdout>, st: &mut State) -> bool {
    let done = match st.search.as_mut() {
        Some(s) => s.step(&mut st.listing),
        None => return false,
    };
    if done {
        return finish_search(out, st, false);
    }
    if st.search_reported.elapsed() >= SEARCH_REPORT {
        st.search_reported = Instant::now();
        let (scanned, ms) = match st.search.as_ref() {
            Some(s) => (s.scanned, since(s.started)),
            None => return false,
        };
        writeln!(out, "{}", searching_line(st.listing.len(), scanned, ms)).ok();
        out.flush().ok();
    }
    false
}

// searched carries the final count itself, so no trailing listed line is needed and a replaced listing never announces a total it no longer has.
// The rows are ranked before the line goes out, so every row index the client is still holding
// names a different file the moment this arrives and the client owes itself a fresh window before
// it resolves one; see docs/protocol.md "searched", and ui/js/Search.js ranked() for the client half.
pub fn finish_search(out: &mut BufWriter<io::Stdout>, st: &mut State, cancelled: bool) -> bool {
    let s = match st.search.take() {
        Some(s) => s,
        None => return false,
    };
    let reordered = s.rank(&mut st.listing);
    let ms = since(s.started);
    writeln!(out, "{}", searched_line(st.listing.len(), s.scanned, ms, cancelled)).ok();
    out.flush().ok();
    reordered
}
