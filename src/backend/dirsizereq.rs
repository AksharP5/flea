// The dirsize queue and its one-at-a-time walker, kept beside the loop rather than inside it.
use crate::backend::dirsize;
use crate::backend::proto::dirsized_line;
use crate::backend::timing::since;
use crate::backend::state::State;
use std::io::{self, BufWriter, Write};
use std::time::Instant;

// Answered rows are re-answered at once, matching thumb's own cache-hit shape; only a directory can be asked for.
pub fn queue_dirsizes(out: &mut BufWriter<io::Stdout>, st: &mut State, rows: &[usize]) {
    for &row in rows {
        if row >= st.listing.len() || !st.listing.is_dir(row) {
            continue;
        }
        if let Some(&(bytes, partial)) = st.dirsizes.get(&row) {
            writeln!(out, "{}", dirsized_line(row, bytes, partial, 0.0)).ok();
            continue;
        }
        if st.dirsize_queue.contains(&row) {
            continue;
        }
        st.dirsize_queue.push(row);
    }
    out.flush().ok();
}

// One directory per call: no thread pool, so this is the whole of "one at a time" from AGENTS.md.
pub fn walk_one_dirsize(out: &mut BufWriter<io::Stdout>, st: &mut State) {
    let row = st.dirsize_queue.remove(0);
    if row >= st.listing.len() {
        return;
    }
    let path = st.base.join(st.listing.name(row));
    let t = Instant::now();
    let result = dirsize::walk(&path);
    let ms = since(t);
    st.dirsizes.insert(row, (result.bytes, result.partial));
    writeln!(out, "{}", dirsized_line(row, result.bytes, result.partial, ms)).ok();
    out.flush().ok();
}

