use crate::backend::proto::thumbed_line;
use crate::backend::timing::since;
use crate::backend::state::{State, Tables};
use crate::backend::thumbcache::{Cache, Hit};
use crate::backend::thumbs::{trace, Done, Job, Outcome, Pool, Trace};
use std::io::Write;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

// A cancelled row is never answered, so dropping its mapping is the whole of what a later request for it needs.
pub(crate) fn forget_one(st: &mut State, path: &Path) {
    st.outstanding = st.outstanding.saturating_sub(1);
    if let Some(at) = st.asked.iter().position(|(p, _)| p == path) {
        st.asked.remove(at);
    }
}

// corner: generation happens only for the rows a client named, and nothing here walks the listing; see AGENTS.md "Thumbnail requests".
pub(crate) fn thumb_rows(
    out: &mut impl Write,
    rows: &[usize],
    st: &mut State,
    tb: &Tables,
    pool: &Pool,
    cache: &Cache,
    cache_only: bool,
) {
    for &row in rows {
        if row >= st.listing.len() {
            continue;
        }
        let t = Instant::now();
        let name = st.listing.name(row);
        let path = st.base.join(name);
        // corner: only a regular file is queued, so a fifo or a device node named like a video cannot block a worker; see AGENTS.md "Thumbnail requests".
        let meta = std::fs::metadata(&path).ok().filter(|m| m.is_file());
        let declared = meta.as_ref().and_then(|_| {
            tb.mime
                .lookup(name)
                .filter(|m| tb.thumbs.for_mime(m, &tb.aliases).is_some())
                .map(str::to_string)
        });
        let mime = match declared {
            // corner: a row no thumbnailer declares is answered at once and never queued, see AGENTS.md.
            None => {
                writeln!(out, "{}", thumbed_line(row, "", since(t))).ok();
                continue;
            }
            Some(m) => m,
        };
        let mtime = meta.map(|m| m.mtime()).unwrap_or(0);
        match cache.lookup(&path, mtime) {
            Hit::Ready(p) => {
                writeln!(out, "{}", thumbed_line(row, &p.to_string_lossy(), since(t))).ok();
            }
            Hit::Failed => {
                writeln!(out, "{}", thumbed_line(row, "", since(t))).ok();
            }
            // A class whose switch is off is cache-only: a miss answers none rather than
            // starting a decoder, so a NAS folder costs one stat per visible row and no read.
            Hit::Miss if cache_only => {
                writeln!(out, "{}", thumbed_line(row, "", since(t))).ok();
            }
            Hit::Miss => queue_row(out, st, pool, row, path, mtime, mime),
        }
    }
}

// One entry per queued or running job, so the pool's own queue bound plus the worker count bounds this map too.
fn queue_row(
    out: &mut impl Write,
    st: &mut State,
    pool: &Pool,
    row: usize,
    path: PathBuf,
    mtime: i64,
    mime: String,
) {
    // A mapped path already has a job for this listing, so a repeated row costs a worker nothing; see AGENTS.md "Thumbnail requests".
    if st.asked.iter().any(|(p, _)| *p == path) {
        return;
    }
    st.asked.push((path.clone(), row));
    st.outstanding += 1;
    // A job the pool dropped to make room will never report, so its row is unmapped and answered here rather than at shutdown.
    for job in pool.submit(Job { path, mtime, mime, trace: trace(row) }) {
        st.outstanding = st.outstanding.saturating_sub(1);
        if let Some(at) = st.asked.iter().position(|(p, _)| *p == job.path) {
            let dropped_row = st.asked.remove(at).1;
            writeln!(out, "{}", thumbed_line(dropped_row, "", 0.0)).ok();
        }
    }
}

// A job already inside a worker cannot be cancelled, so its row stays mapped until it reports.
pub(crate) fn cancel_row(st: &mut State, pool: &Pool, row: usize) {
    let at = match st.asked.iter().position(|(_, r)| *r == row) {
        Some(i) => i,
        None => return,
    };
    let dropped = pool.cancel(&st.asked[at].0);
    if dropped.is_empty() {
        return;
    }
    st.outstanding = st.outstanding.saturating_sub(dropped.len());
    st.asked.remove(at);
}

// A result whose path is no longer mapped belongs to a superseded listing and is dropped, never reported against the current one.
pub(crate) fn report_done(out: &mut impl Write, st: &mut State, done: Done) {
    st.outstanding = st.outstanding.saturating_sub(1);
    let row = match st.asked.iter().position(|(p, _)| *p == done.path) {
        Some(i) => st.asked.remove(i).1,
        None => return,
    };
    let file = match done.result {
        Outcome::Ready(p) => p.to_string_lossy().into_owned(),
        Outcome::Failed => String::new(),
    };
    writeln!(out, "{}", thumbed_line(row, &file, done.ms)).ok();
    out.flush().ok();
    if let Some(t) = &done.trace {
        trace_line(t);
    }
}

// stderr, never stdout, because stdout is the wire and a client parses every line of it; see AGENTS.md "Thumbnail trace".
fn trace_line(t: &Trace) {
    let whole = t.at.elapsed();
    // A job that failed before any child has no spawn and no exit mark, so its whole life after the pop is charged to setup.
    let spawned = if t.spawned.is_zero() { whole } else { t.spawned };
    let exited = if t.exited.is_zero() { whole } else { t.exited };
    let ms = |d: Duration| d.as_secs_f64() * 1000.0;
    eprintln!(
        "flea: trace row={} depth={} queued={:.2} setup={:.2} child={:.2} after={:.2} total={:.2}",
        t.row, t.depth, ms(t.popped), ms(spawned.saturating_sub(t.popped)),
        ms(exited.saturating_sub(spawned)), ms(whole.saturating_sub(exited)), ms(whole)
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::aliases::Aliases;
    use crate::backend::archive::Formats;
    use crate::backend::icons::Names;
    use crate::backend::kind::Kinds;
    use crate::backend::listing::Listing;
    use crate::backend::mime::Db;
    use crate::backend::testdir::TestDir;
    use crate::backend::thumbcache;
    use crate::backend::thumbspec::Thumbnailers;
    use crate::backend::thumbwrite;
    use std::cell::RefCell;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::mpsc::channel;
    use std::sync::Arc;

    // One jpeg declaration over /bin/sh, which is_runnable resolves on this box; the
    // cache-only path never runs it, and the full path only queues under it here.
    fn tables() -> Tables {
        let aliases = Arc::new(Aliases::load());
        let thumbs = Arc::new(Thumbnailers::from_entries(
            &[("t.thumbnailer".to_string(),
               "[Thumbnailer Entry]\nExec=/bin/sh -i %i -o %o -s %s\nMimeType=image/jpeg;\n".to_string())],
            &aliases,
        ));
        assert!(thumbs.for_mime("image/jpeg", &aliases).is_some(), "the fixture declares jpeg");
        Tables {
            mime: Arc::new(Db::load()),
            icons: Arc::new(Names::load()),
            aliases,
            thumbs,
            kinds: RefCell::new(Kinds::new()),
            formats: Arc::new(Formats::probe()),
        }
    }

    // Sample input: rows [0] over a listing holding photo.jpg; out collects the wire.
    fn listed(dir: &TestDir, st: &mut State) {
        st.base = dir.path().to_path_buf();
        let mut l = Listing::new();
        l.push("photo.jpg", false);
        st.listing = l;
    }

    fn harness(dir: &TestDir, tb: &Tables) -> (State, Pool, Cache) {
        let (events, _) = channel();
        let (results, _) = channel();
        let st = State::new(crate::backend::dirsizeworker::Worker::new(events));
        let pool = Pool::new(1, results, dir.join("poolcache"), Arc::clone(&tb.aliases), Arc::clone(&tb.thumbs));
        let cache = Cache::at(dir.join("cache"));
        (st, pool, cache)
    }

    #[test]
    fn a_cache_only_miss_answers_none_and_queues_no_decode() {
        let d = TestDir::new("thumbcacheonly");
        d.file("photo.jpg", "not a picture, so no decoder could read it either");
        let tb = tables();
        let (mut st, pool, cache) = harness(&d, &tb);
        listed(&d, &mut st);
        let mut out = Vec::new();
        thumb_rows(&mut out, &[0], &mut st, &tb, &pool, &cache, true);
        let line = String::from_utf8(out).unwrap();
        assert!(line.contains(r#""file":"""#), "a miss with no cache entry answers none: {}", line);
        assert_eq!(st.outstanding, 0, "no job may be in flight for a row that was answered");
        assert!(st.asked.is_empty(), "and no mapping may hold it for a later report");
        pool.cancel_all();
    }

    #[test]
    fn a_cache_only_hit_serves_a_source_that_can_no_longer_be_opened() {
        let d = TestDir::new("thumbcacheonlyhit");
        let path = d.file("photo.jpg", "bytes the open is then refused for");
        let mtime = std::fs::metadata(&path).unwrap().mtime();
        let tb = tables();
        let (mut st, pool, cache) = harness(&d, &tb);
        let uri = thumbcache::uri_for(&path);
        let large = cache.large_path(&uri);
        std::fs::create_dir_all(large.parent().unwrap()).unwrap();
        thumbwrite::write_marker(&large, &uri, mtime).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o000)).unwrap();
        listed(&d, &mut st);
        let mut out = Vec::new();
        thumb_rows(&mut out, &[0], &mut st, &tb, &pool, &cache, true);
        let line = String::from_utf8(out).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
        assert!(line.contains(&large.to_string_lossy().into_owned()),
            "the cached entry is served although the source no longer opens: {}", line);
        assert_eq!(st.outstanding, 0, "a served row queues nothing either");
        pool.cancel_all();
    }

    #[test]
    fn a_local_row_without_the_flag_takes_exactly_todays_path() {
        let d = TestDir::new("thumbfull");
        d.file("photo.jpg", "not a picture, and nothing here decodes it");
        let tb = tables();
        let (mut st, pool, cache) = harness(&d, &tb);
        listed(&d, &mut st);
        let mut out = Vec::new();
        thumb_rows(&mut out, &[0], &mut st, &tb, &pool, &cache, false);
        assert!(out.is_empty(), "a genuine miss is queued, not answered: {}",
            String::from_utf8_lossy(&out));
        assert_eq!(st.outstanding, 1, "the job is in flight as it always was");
        assert_eq!(st.asked.len(), 1, "and the mapping holds it for the report");
        pool.cancel_all();
    }
}
