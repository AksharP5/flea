// The DCIM walk behind a photos request: every photo and video under one DCIM folder, newest first, a slice per tick.
use crate::backend::listing::Listing;
use crate::backend::mime::Db;
use std::path::PathBuf;
use std::time::Instant;

// Entries and folder opens per tick, so neither a 5,000-photo folder nor 1,000 empty ones on MTP block photoscancel.
const ENTRIES_PER_TICK: usize = 100;

// A directory a tick stopped inside, kept open so the next tick resumes it.
struct OpenDir {
    rel: String,
    dir: PathBuf,
    rd: std::fs::ReadDir,
}

pub struct Photos {
    root: PathBuf,
    hidden: bool,
    // Directories still to read, each a path relative to root; the empty string is root itself.
    pending: Vec<String>,
    // The directory a tick stopped inside, resumed rather than re-read.
    current: Option<OpenDir>,
    // One mtime per pushed match, in push order, so the finish is a permutation of the listing's spans.
    mtimes: Vec<u64>,
    pub scanned: usize,
    pub started: Instant,
}

impl Photos {
    pub fn new(root: &str, hidden: bool) -> Photos {
        Photos {
            root: PathBuf::from(root),
            hidden,
            pending: vec![String::new()],
            current: None,
            mtimes: Vec::new(),
            scanned: 0,
            started: Instant::now(),
        }
    }

    // Returns true when the walk is finished; the caller then writes the terminal line.
    pub fn step(&mut self, listing: &mut Listing, mime: &Db) -> bool {
        let mut entries = 0;
        while entries < ENTRIES_PER_TICK {
            let mut open = match self.current.take() {
                Some(open) => open,
                None => match self.pending.pop() {
                    Some(rel) => {
                        entries += 1;
                        let dir = if rel.is_empty() { self.root.clone() } else { self.root.join(&rel) };
                        // corner: an unreadable directory is skipped in silence, as scan.rs's phase one skips an unreadable entry.
                        match std::fs::read_dir(&dir) {
                            Ok(rd) => OpenDir { rel, dir, rd },
                            Err(_) => continue,
                        }
                    }
                    None => return true,
                },
            };
            // std ends a ReadDir after its first error, so an error closes the folder the same as its end.
            if let Some(Ok(entry)) = open.rd.next() {
                self.read_entry(&open.rel, &open.dir, entry, listing, mime);
                entries += 1;
                self.current = Some(open);
            }
        }
        self.current.is_none() && self.pending.is_empty()
    }

    fn read_entry(&mut self, rel: &str, dir: &PathBuf, entry: std::fs::DirEntry, listing: &mut Listing, mime: &Db) {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        // corner: a dot-prefixed name is dropped before it is counted, matching scan.rs's own hidden rule.
        if !self.hidden && name.starts_with('.') {
            return;
        }
        self.scanned += 1;
        // d_type is free and answers is_dir with no stat, matching scan.rs's phase 1.
        let is_dir = entry.file_type().map(|f| f.is_dir()).unwrap_or(false);
        let child = if rel.is_empty() { name.to_string() } else { format!("{}/{}", rel, name) };
        // corner: a symlink reports its own type here, so a link to a directory is never descended and no loop is possible.
        if is_dir {
            self.pending.push(child);
            return;
        }
        // The shipped classifier is the only filter: a name no photo or video glob claims is not a photo.
        let media = mime.lookup(&child).is_some_and(|m| m.starts_with("image/") || m.starts_with("video/"));
        if !media {
            return;
        }
        // symlink_metadata never follows, so a dangling link cannot hang the walk on a dead mount.
        let mtime = std::fs::symlink_metadata(dir.join(name.as_ref()))
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs())
            .unwrap_or(0);
        // The row's name is its path relative to root, so base.join(name) still reaches the file.
        listing.push(&child, false);
        self.mtimes.push(mtime);
    }

    // One newest-first permutation of discovery order; a changed order invalidates held row indices.
    pub fn finish(&self, listing: &mut Listing) -> bool {
        // A listing this walk did not fill by itself is never reordered: the mtimes would name other rows.
        if self.mtimes.len() != listing.len() || listing.len() < 2 {
            return false;
        }
        // Take the buffer out so the comparator can borrow it while spans are moved, as sort.rs does.
        let names = std::mem::take(&mut listing.names);
        let spans = &listing.spans;
        let mtimes = &self.mtimes;
        let mut order: Vec<usize> = (0..spans.len()).collect();
        order.sort_by(|&a, &b| {
            mtimes[b].cmp(&mtimes[a]).then_with(|| {
                let an = &names[spans[a].off as usize..(spans[a].off + spans[a].len) as usize];
                let bn = &names[spans[b].off as usize..(spans[b].off + spans[b].len) as usize];
                an.cmp(bn)
            })
        });
        let ranked: Vec<_> = order.iter().map(|&i| spans[i]).collect();
        listing.spans = ranked;
        listing.names = names;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;

    // Sample input, the globs the walk filters on, kept off whatever update-mime-database merged here.
    const GLOB_ROWS: &str = concat!(
        "50:image/jpeg:*.jpg\n",
        "50:image/heif:*.heic\n",
        "50:video/quicktime:*.mov\n",
        "50:video/mp4:*.mp4\n",
        "50:text/plain:*.txt\n",
    );

    fn mime() -> Db {
        Db::from_str(GLOB_ROWS)
    }

    fn touch_mtime(path: &std::path::Path, date: &str) {
        // The same fixture clock src/backend/ordering.rs's tests use: touch is coreutils, not a crate.
        let status = std::process::Command::new("touch")
            .args(["-d", date, &path.to_string_lossy().into_owned()])
            .status()
            .expect("touch sets the fixture mtime");
        assert!(status.success(), "touch sets the fixture mtime");
    }

    fn walk_all(dcim: &str, hidden: bool) -> (Listing, Photos) {
        let mime = mime();
        let mut w = Photos::new(dcim, hidden);
        let mut l = Listing::new();
        while !w.step(&mut l, &mime) {}
        w.finish(&mut l);
        (l, w)
    }

    // Finished order, which is the order the client is answered in.
    fn names(l: &Listing) -> Vec<String> {
        (0..l.len()).map(|i| l.name(i).to_string()).collect()
    }

    #[test]
    fn only_photos_and_videos_walk_and_newest_sorts_first() {
        let d = TestDir::new("photos");
        d.dir("DCIM/100APPLE");
        d.file("DCIM/100APPLE/IMG_4106.HEIC", "");
        d.file("DCIM/100APPLE/IMG_4120.HEIC", "");
        d.file("DCIM/100APPLE/IMG_4121.MOV", "");
        d.file("DCIM/100APPLE/notes.txt", "");
        d.file("DCIM/100APPLE/README", "");
        d.dir("DCIM/100APPLE/sub");
        touch_mtime(&d.join("DCIM/100APPLE/IMG_4106.HEIC"), "2026-01-01 10:00:00");
        touch_mtime(&d.join("DCIM/100APPLE/IMG_4120.HEIC"), "2026-03-01 10:00:00");
        touch_mtime(&d.join("DCIM/100APPLE/IMG_4121.MOV"), "2026-03-02 10:00:00");

        let dcim = d.join("DCIM").to_str().unwrap().to_string();
        let (l, w) = walk_all(&dcim, false);
        assert_eq!(names(&l), ["100APPLE/IMG_4121.MOV", "100APPLE/IMG_4120.HEIC", "100APPLE/IMG_4106.HEIC"]);
        // The root's own directory entry scans too, beside the six names inside it.
        assert_eq!(w.scanned, 7);
        // No row is a directory and its name still reaches the file from the walk root.
        for i in 0..l.len() {
            assert!(!l.is_dir(i));
            assert!(d.join("DCIM").join(l.name(i)).is_file());
        }
    }

    #[test]
    fn an_equal_mtime_falls_back_to_name_order() {
        let d = TestDir::new("phototie");
        d.dir("DCIM");
        d.file("DCIM/b.jpg", "");
        d.file("DCIM/a.jpg", "");
        touch_mtime(&d.join("DCIM/b.jpg"), "2026-03-01 10:00:00");
        touch_mtime(&d.join("DCIM/a.jpg"), "2026-03-01 10:00:00");

        let dcim = d.join("DCIM").to_str().unwrap().to_string();
        let (l, _) = walk_all(&dcim, false);
        assert_eq!(names(&l), ["a.jpg", "b.jpg"]);
    }

    #[test]
    fn matching_ignores_case_the_way_the_mime_table_does() {
        let d = TestDir::new("photocase");
        d.dir("DCIM");
        d.file("DCIM/IMG_0001.JPG", "");

        let dcim = d.join("DCIM").to_str().unwrap().to_string();
        let (l, _) = walk_all(&dcim, false);
        assert_eq!(names(&l), ["IMG_0001.JPG"]);
    }

    #[test]
    fn hidden_is_false_by_default_and_true_descends_dot_directories() {
        let d = TestDir::new("photohidden");
        d.dir("DCIM/.trash");
        d.file("DCIM/.trash/old.jpg", "");
        d.file("DCIM/new.jpg", "");

        let dcim = d.join("DCIM").to_str().unwrap().to_string();
        let (hidden_out, _) = walk_all(&dcim, false);
        assert_eq!(names(&hidden_out), ["new.jpg"]);

        let (shown, _) = walk_all(&dcim, true);
        let mut both = names(&shown);
        both.sort();
        assert_eq!(both, [".trash/old.jpg", "new.jpg"]);
    }

    #[test]
    fn a_symlink_to_a_parent_directory_is_never_descended() {
        let d = TestDir::new("photoloop");
        d.dir("DCIM/sub");
        d.file("DCIM/sub/a.jpg", "");
        std::os::unix::fs::symlink(d.path(), d.join("DCIM/sub/up")).unwrap();

        let dcim = d.join("DCIM").to_str().unwrap().to_string();
        let (l, _) = walk_all(&dcim, false);
        assert_eq!(names(&l), ["sub/a.jpg"]);
    }

    #[test]
    fn a_missing_root_finishes_with_nothing_rather_than_failing() {
        let mime = mime();
        let mut w = Photos::new("/definitely/not/here", false);
        let mut l = Listing::new();
        assert!(w.step(&mut l, &mime));
        assert_eq!(l.len(), 0);
        assert_eq!(w.scanned, 0);
    }

    #[test]
    fn a_step_reads_a_bounded_slice_so_a_cancel_is_never_blocked() {
        let d = TestDir::new("photoslice");
        d.dir("DCIM");
        for i in 0..ENTRIES_PER_TICK + 3 {
            d.dir(&format!("DCIM/d{}", i));
        }
        let mime = mime();
        let mut w = Photos::new(&d.join("DCIM").to_str().unwrap().to_string(), false);
        let mut l = Listing::new();
        // The root alone holds more entries than one tick, so the first step leaves its ReadDir open.
        assert!(!w.step(&mut l, &mime));
    }

    #[test]
    fn a_tick_is_bounded_by_entries_so_one_huge_folder_never_blocks_a_cancel() {
        let d = TestDir::new("photosentries");
        d.dir("DCIM/Camera");
        let total = ENTRIES_PER_TICK * 2 + 10;
        for i in 0..total {
            d.file(&format!("DCIM/Camera/IMG_{i:05}.jpg"), "");
        }
        let mime = mime();
        let mut w = Photos::new(&d.join("DCIM").to_str().unwrap().to_string(), false);
        let mut l = Listing::new();
        assert!(!w.step(&mut l, &mime), "one tick stops with the huge folder still open");
        assert!(w.scanned <= ENTRIES_PER_TICK, "one tick reads at most one slice, got {}", w.scanned);
        assert!(l.len() < total, "the tick left photos unread for the next tick");
        while !w.step(&mut l, &mime) {}
        assert_eq!(l.len(), total, "the kept ReadDir resumes until every photo arrives");
    }

    #[test]
    fn a_tick_counts_folder_opens_so_empty_folders_never_block_a_cancel() {
        let d = TestDir::new("photosopens");
        let total = ENTRIES_PER_TICK + 50;
        for i in 0..total {
            d.dir(&format!("DCIM/d{i}"));
        }
        let mime = mime();
        let mut w = Photos::new(&d.join("DCIM").to_str().unwrap().to_string(), false);
        w.pending = (0..total).map(|i| format!("d{i}")).collect();
        let mut l = Listing::new();
        assert!(!w.step(&mut l, &mime), "one tick cannot open every empty folder");
        assert!(w.pending.len() >= total - ENTRIES_PER_TICK, "one tick opened {} folders", total - w.pending.len());
    }

    #[test]
    fn a_cancelled_walk_keeps_what_it_found_in_newest_first_order() {
        let d = TestDir::new("photocancel");
        d.dir("DCIM/Camera");
        d.file("DCIM/Camera/old.jpg", "");
        d.file("DCIM/Camera/new.mp4", "");
        touch_mtime(&d.join("DCIM/Camera/old.jpg"), "2026-01-01 10:00:00");
        touch_mtime(&d.join("DCIM/Camera/new.mp4"), "2026-06-01 10:00:00");
        for i in 0..ENTRIES_PER_TICK {
            d.file(&format!("DCIM/Camera/fill_{i:03}.jpg"), "");
        }
        let mime = mime();
        let dcim = d.join("DCIM").to_str().unwrap().to_string();
        let mut w = Photos::new(&dcim, false);
        let mut l = Listing::new();
        // One bounded tick, then the cancel with the folder still open: the terminal line still ranks the partial walk.
        assert!(!w.step(&mut l, &mime), "the cancel lands with pending work left");
        let arrived = l.len();
        assert!(arrived >= 2 && arrived < ENTRIES_PER_TICK + 2, "a partial walk, got {}", arrived);
        assert!(w.finish(&mut l), "the partial walk still ranks what it found");
        assert_eq!(l.len(), arrived, "finishing a cancelled walk adds no rows");
        let order: Vec<String> = names(&l);
        let mtime_of = |name: &str| {
            d.join("DCIM").join(name).symlink_metadata().unwrap().modified().unwrap()
                .duration_since(std::time::UNIX_EPOCH).unwrap().as_secs()
        };
        for pair in order.windows(2) {
            let (a, b) = (&pair[0], &pair[1]);
            assert!(mtime_of(a) > mtime_of(b) || (mtime_of(a) == mtime_of(b) && a <= b), "partial walk is newest first, {a} before {b}");
        }
    }

    #[test]
    fn a_listing_the_walk_did_not_fill_is_never_reordered() {
        let w = Photos::new("/definitely/not/here", false);
        let mut l = Listing::new();
        l.push("b.jpg", false);
        l.push("a.jpg", false);
        assert!(!w.finish(&mut l));
        assert_eq!(names(&l), ["b.jpg", "a.jpg"]);
    }
}
