// The wire side of a photos walk, the way searchreq answers search, with its own searching and searched lines.
use crate::backend::proto::{searched_line, searching_line};
use crate::backend::timing::since;
use crate::backend::state::State;
use std::io::{self, BufWriter, Write};
use std::time::{Duration, Instant};

// A streaming walk announces its growing count no more often than this, so a fast walk cannot flood the client's parser.
const PHOTOS_REPORT: Duration = Duration::from_millis(100);

// One bounded slice per call; answers whether the walk ended in a new row order.
pub fn step_photos(out: &mut BufWriter<io::Stdout>, st: &mut State, mime: &crate::backend::mime::Db) -> bool {
    let done = match st.photos.as_mut() {
        Some(w) => w.step(&mut st.listing, mime),
        None => return false,
    };
    if done {
        return finish_photos(out, st, false);
    }
    if st.photos_reported.elapsed() >= PHOTOS_REPORT {
        st.photos_reported = Instant::now();
        let (scanned, ms) = match st.photos.as_ref() {
            Some(w) => (w.scanned, since(w.started)),
            None => return false,
        };
        writeln!(out, "{}", searching_line(st.listing.len(), scanned, ms)).ok();
        out.flush().ok();
    }
    false
}

// searched carries the final count and follows the newest-first rank; see docs/protocol.md "searched".
pub fn finish_photos(out: &mut BufWriter<io::Stdout>, st: &mut State, cancelled: bool) -> bool {
    let w = match st.photos.take() {
        Some(w) => w,
        None => return false,
    };
    let reordered = w.finish(&mut st.listing);
    let ms = since(w.started);
    writeln!(out, "{}", searched_line(st.listing.len(), w.scanned, ms, cancelled)).ok();
    out.flush().ok();
    reordered
}
