// A slow mount's statfs is a network round trip (about 800 ms on the NAS), so it runs on a worker, never the loop.
use super::events::Event;
use super::extclass::{classify_entry_with_magic, fstype_is_network, gvfs_class, gvfs_root, resolved};
use super::fsinfo::Info;
use super::mountinfo::mount_entry_in;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{mpsc::Sender, Arc};
use std::time::{Duration, Instant};

// A statfs outstanding this long is presumed hung, so the next ask for its mount starts another.
pub const FSINFO_DEADLINE: Duration = Duration::from_secs(10);
// corner: past this many folders the remembered figures are dropped whole; the next visit reads them again.
const KNOWN_MAX: usize = 64;

// Sample input: root "/run/user/1000/gvfs/smb-share:server=n,share=x", dir root + "/photos", info Some(fuse, 7).
pub struct Done {
    pub root: PathBuf,
    pub dir: PathBuf,
    // Which statfs this is, so a hung one landing late is told apart from its replacement.
    pub seq: u64,
    pub info: Option<Info>,
}

// The test seam: production reads statfs once for figures and magic, a test sleeps or counts instead.
type Reader = Arc<dyn Fn(PathBuf) -> (Option<Info>, Option<i64>) + Send + Sync>;

pub struct FsInfo {
    events: Sender<Event>,
    reader: Reader,
    // Figures per folder, because an sftp host or a phone's storages answer differently below one mount root.
    known: HashMap<PathBuf, Option<Info>>,
    // One statfs per mount root at a time, with its start and number, so fast navigation never piles round trips on the daemon.
    inflight: HashMap<PathBuf, (Instant, u64)>,
    // Mount roots asked for again while their statfs was busy; the folder on screen is read when it lands.
    waiting: HashSet<PathBuf>,
    // The number of the last statfs started; the next one takes one more.
    seq: u64,
    // Set by the first fsinfo ask; the TUI never asks, so its listings start no statfs, as in 0.3.5.
    asked: bool,
}

impl FsInfo {
    pub fn new(events: Sender<Event>) -> Self {
        Self::with_reader(events, Arc::new(|path: PathBuf| super::fsinfo::read_with_magic(&path)))
    }

    pub fn with_reader(events: Sender<Event>, reader: Reader) -> Self {
        FsInfo { events, reader, known: HashMap::new(), inflight: HashMap::new(), waiting: HashSet::new(), seq: 0, asked: false }
    }

    // After a share's rows are out, so the statfs never competes with its gio listing; a kernel mount waits for fsinfo.
    pub fn list_arrived(&mut self, path: &Path) {
        if !self.asked {
            return;
        }
        if let Some(root) = gvfs_root(path) {
            self.refresh(root, path.to_path_buf());
        }
    }

    // The fsinfo answer, never blocked on a slow mount: its class and last known figures now, fresh figures as a later line.
    pub fn answer(&mut self, path: &Path) -> (Option<Info>, &'static str) {
        let body = if gvfs_root(path).is_some() { String::new() } else { std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default() };
        self.answer_in(path, &body)
    }

    // The test seam: body is one /proc/self/mountinfo read, ignored for a gvfs path.
    fn answer_in(&mut self, path: &Path, body: &str) -> (Option<Info>, &'static str) {
        self.asked = true;
        if let Some(root) = gvfs_root(path) {
            return self.slow_answer(root, path, slow_class(path));
        }
        // The raw path's own mount first, so a kernel share whose server died is decided with no syscall on the loop.
        if let Some(entry) = mount_entry_in(path, body).filter(|e| fstype_is_network(&e.fstype)) {
            return self.slow_answer(entry.mount, path, "network");
        }
        let owned = resolved(path);
        if let Some(root) = gvfs_root(&owned) {
            return self.slow_answer(root, path, slow_class(&owned));
        }
        match mount_entry_in(&owned, body) {
            Some(entry) if fstype_is_network(&entry.fstype) => self.slow_answer(entry.mount, path, "network"),
            entry => {
                let (info, magic) = (self.reader)(path.to_path_buf());
                (info, classify_entry_with_magic(&owned, entry.as_ref(), magic))
            }
        }
    }

    fn slow_answer(&mut self, root: PathBuf, path: &Path, class: &'static str) -> (Option<Info>, &'static str) {
        let figures = self.known.get(path).cloned().flatten();
        self.refresh(root, path.to_path_buf());
        (figures, class)
    }

    fn refresh(&mut self, root: PathBuf, dir: PathBuf) {
        if self.inflight.get(&root).is_some_and(|(started, _)| started.elapsed() < FSINFO_DEADLINE) {
            self.waiting.insert(root);
            return;
        }
        self.seq += 1;
        let (events, reader, key, seq) = (self.events.clone(), Arc::clone(&self.reader), root.clone(), self.seq);
        let worker = std::thread::Builder::new().name("flea-fsinfo".into()).spawn(move || {
            let (info, _) = reader(dir.clone());
            let _ = events.send(Event::FsInfo(Done { root: key, dir, seq, info }));
        });
        // corner: a spawn that fails records nothing, so the next ask tries again and answers unknown meanwhile.
        if worker.is_ok() {
            self.inflight.insert(root, (Instant::now(), seq));
        }
    }

    // The figures to print, only for the folder on screen and only when they moved since its last answer.
    pub fn finish(&mut self, done: Done, base: &Path) -> Option<Option<Info>> {
        // A hung statfs landing late never clears the newer one that replaced it.
        if self.inflight.get(&done.root).is_some_and(|(_, seq)| *seq == done.seq) {
            self.inflight.remove(&done.root);
        }
        if self.waiting.remove(&done.root) && base != done.dir && base.starts_with(&done.root) {
            self.refresh(done.root.clone(), base.to_path_buf());
        }
        let moved = self.known.get(&done.dir) != Some(&done.info);
        if self.known.len() >= KNOWN_MAX && !self.known.contains_key(&done.dir) {
            self.known.clear();
        }
        self.known.insert(done.dir.clone(), done.info.clone());
        if moved && done.dir == base {
            return Some(done.info);
        }
        None
    }
}

// A slow mount is a gvfs share or phone by its path, else a kernel network mount; answer passes a resolved path.
pub fn slow_class(path: &Path) -> &'static str {
    gvfs_class(path).unwrap_or("network")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::mpsc::Receiver;

    const SHARE: &str = "/run/user/1000/gvfs/smb-share:server=fake,share=media";

    fn share_dir(name: &str) -> PathBuf {
        Path::new(SHARE).join(name)
    }

    fn figures(free: u64) -> Option<Info> {
        Some(Info { name: "fuse".to_string(), free })
    }

    // The GUI, which asks for figures on every listing, so its listings start the share's statfs.
    fn gui(mut fs: FsInfo) -> FsInfo {
        fs.asked = true;
        fs
    }

    // A fake statfs that takes delay_ms and counts its calls.
    fn counted(delay_ms: u64, free: u64) -> (FsInfo, Receiver<Event>, Arc<AtomicUsize>) {
        let (events, rx) = std::sync::mpsc::channel();
        let calls = Arc::new(AtomicUsize::new(0));
        let seen = Arc::clone(&calls);
        let reader: Reader = Arc::new(move |_: PathBuf| {
            seen.fetch_add(1, Ordering::SeqCst);
            std::thread::sleep(Duration::from_millis(delay_ms));
            (figures(free), Some(0x65735546))
        });
        (gui(FsInfo::with_reader(events, reader)), rx, calls)
    }

    fn next_done(rx: &Receiver<Event>) -> Done {
        match rx.recv_timeout(Duration::from_secs(5)).expect("the worker reports its figures") {
            Event::FsInfo(done) => done,
            _ => panic!("the worker reports its figures as an fsinfo event"),
        }
    }

    #[test]
    fn a_client_that_never_asks_for_figures_starts_no_statfs() {
        let (events, _rx) = std::sync::mpsc::channel();
        let mut fs = FsInfo::with_reader(events, Arc::new(|_: PathBuf| (figures(7), None)));
        fs.list_arrived(&share_dir("a"));
        assert!(fs.inflight.is_empty(), "the TUI lists a share and never asks for its figures, so no statfs starts");
        let _ = fs.answer(&share_dir("a"));
        assert_eq!(fs.inflight.len(), 1, "the first ask starts the share's statfs");
        fs.list_arrived(&share_dir("b"));
        assert!(fs.waiting.contains(&gvfs_root(&share_dir("b")).unwrap()), "once asked, a listing asks for its share again");
    }

    #[test]
    fn a_slow_fsinfo_answers_its_class_at_once_and_its_figures_later() {
        let (mut fs, rx, _) = counted(500, 7);
        let dir = share_dir("photos");
        fs.list_arrived(&dir);
        let t = Instant::now();
        let (info, class) = fs.answer(&dir);
        let ms = t.elapsed().as_secs_f64() * 1000.0;
        assert!(info.is_none(), "figures the worker has not returned are unknown, never a block");
        assert_eq!(class, "network");
        assert!(ms < 250.0, "answered in {:.1} ms against a 500 ms statfs, over a 250 ms budget", ms);
        let done = next_done(&rx);
        assert_eq!((done.root.as_path(), done.dir.as_path()), (Path::new(SHARE), dir.as_path()), "keyed by the share, read at the folder");
        assert_eq!(fs.finish(done, &dir).flatten().map(|i| i.free), Some(7), "the current folder's figures print");
        let (info, _) = fs.answer(&dir);
        assert_eq!(info.map(|i| i.free), Some(7), "the folder answers its known figures at once next time");
        let (info, _) = fs.answer(&share_dir("other"));
        assert!(info.is_none(), "another folder never borrows figures it was not read for");
    }

    #[test]
    fn one_statfs_per_share_at_a_time_and_the_folder_on_screen_goes_next() {
        let (mut fs, rx, calls) = counted(200, 7);
        fs.list_arrived(&share_dir("a"));
        fs.list_arrived(&share_dir("b"));
        fs.list_arrived(&share_dir("c"));
        let done = next_done(&rx);
        assert_eq!(calls.load(Ordering::SeqCst), 1, "three folders of one share ran {} statfs calls at once", calls.load(Ordering::SeqCst));
        assert!(fs.finish(done, &share_dir("c")).is_none(), "a's figures never print over c");
        let second = next_done(&rx);
        assert_eq!(second.dir, share_dir("c"), "the skipped middle folder is never read, the one on screen is");
        assert_eq!(fs.finish(second, &share_dir("c")).flatten().map(|i| i.free), Some(7));
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn unchanged_figures_print_nothing_and_moved_ones_print() {
        let (mut fs, _rx, _) = counted(0, 7);
        let dir = share_dir("a");
        let done = |free| Done { root: PathBuf::from(SHARE), dir: share_dir("a"), seq: 0, info: figures(free) };
        assert!(fs.finish(done(7), &dir).is_some(), "the first figures print");
        assert!(fs.finish(done(7), &dir).is_none(), "the answer already carried these");
        assert!(fs.finish(done(5), &dir).is_some(), "a copy to the share moved them");
    }

    #[test]
    fn a_folder_the_client_has_left_prints_nothing() {
        let (mut fs, _rx, _) = counted(0, 7);
        let done = Done { root: PathBuf::from(SHARE), dir: share_dir("back"), seq: 0, info: figures(7) };
        assert!(fs.finish(done, Path::new("/home/gm")).is_none(), "a left folder's figures name the wrong place");
        let (info, _) = fs.answer_in(&share_dir("back"), "");
        assert_eq!(info.map(|i| i.free), Some(7), "but coming back answers them at once");
    }

    // A fake statfs that records every path it was asked for and fails for one named "gone".
    fn recording() -> (FsInfo, Receiver<Event>, Arc<std::sync::Mutex<Vec<PathBuf>>>) {
        let (events, rx) = std::sync::mpsc::channel();
        let asked = Arc::new(std::sync::Mutex::new(Vec::new()));
        let seen = Arc::clone(&asked);
        let reader: Reader = Arc::new(move |path: PathBuf| {
            seen.lock().unwrap().push(path.clone());
            if path.ends_with("gone") { (None, None) } else { (figures(7), Some(0x65735546)) }
        });
        (gui(FsInfo::with_reader(events, reader)), rx, asked)
    }

    #[test]
    fn a_list_of_a_missing_folder_never_blanks_the_folder_on_screen() {
        let (mut fs, rx, _) = recording();
        let photos = share_dir("photos");
        fs.list_arrived(&photos);
        let _ = fs.finish(next_done(&rx), &photos);
        fs.list_arrived(&share_dir("gone"));
        assert!(fs.finish(next_done(&rx), &photos).is_none(), "a failed statfs of another folder prints nothing for photos");
        assert_eq!(fs.answer(&photos).0.map(|i| i.free), Some(7), "and photos keeps its figures");
    }

    #[test]
    fn a_failed_list_during_a_busy_statfs_still_reads_the_folder_on_screen() {
        let (mut fs, rx, _) = counted(200, 7);
        let photos = share_dir("photos");
        fs.list_arrived(&share_dir("w"));
        fs.list_arrived(&photos);
        fs.list_arrived(&share_dir("gone"));
        assert!(fs.finish(next_done(&rx), &photos).is_none(), "w's figures never print over photos");
        let second = next_done(&rx);
        assert_eq!(second.dir, photos, "the folder on screen is read, not the failed list's folder");
    }

    #[test]
    fn a_folder_left_behind_a_hung_statfs_is_never_read() {
        let (mut fs, rx, calls) = counted(0, 7);
        let root = PathBuf::from(SHARE);
        fs.inflight.insert(root.clone(), (Instant::now(), 90));
        fs.list_arrived(&share_dir("b"));
        fs.inflight.insert(root.clone(), (Instant::now().checked_sub(FSINFO_DEADLINE + Duration::from_secs(1)).unwrap(), 90));
        fs.list_arrived(&share_dir("c"));
        let done = next_done(&rx);
        assert_eq!(done.dir, share_dir("c"));
        let _ = fs.finish(done, &share_dir("c"));
        let _ = fs.finish(Done { root: root.clone(), dir: share_dir("a"), seq: 90, info: figures(7) }, &share_dir("c"));
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(calls.load(Ordering::SeqCst), 1, "b, left behind the hung statfs, was read anyway");
    }

    #[test]
    fn a_hung_statfs_landing_late_never_frees_its_replacement_slot() {
        let (mut fs, rx, calls) = counted(300, 7);
        let root = PathBuf::from(SHARE);
        fs.inflight.insert(root.clone(), (Instant::now().checked_sub(FSINFO_DEADLINE + Duration::from_secs(1)).unwrap(), 90));
        fs.list_arrived(&share_dir("a"));
        let _ = fs.finish(Done { root: root.clone(), dir: share_dir("a"), seq: 90, info: figures(7) }, &share_dir("a"));
        fs.list_arrived(&share_dir("b"));
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(calls.load(Ordering::SeqCst), 1, "the hung statfs's late landing let a second one start beside its replacement");
        let _ = next_done(&rx);
    }

    #[test]
    fn a_phone_storage_is_read_where_it_is_listed_not_at_the_device() {
        let (mut fs, rx, asked) = recording();
        let storage = PathBuf::from("/run/user/1000/gvfs/mtp:host=Phone/Internal shared storage/DCIM");
        fs.list_arrived(&storage);
        let done = next_done(&rx);
        assert_eq!(done.root, Path::new("/run/user/1000/gvfs/mtp:host=Phone"), "keyed by the device");
        assert_eq!(*asked.lock().unwrap(), vec![storage], "read at the storage folder, whose figures the device root does not carry");
    }

    #[test]
    fn a_hung_statfs_past_the_deadline_lets_the_next_ask_try_again() {
        let (mut fs, _rx, calls) = counted(0, 7);
        fs.inflight.insert(PathBuf::from(SHARE), (Instant::now().checked_sub(FSINFO_DEADLINE + Duration::from_secs(1)).unwrap(), 90));
        fs.list_arrived(&share_dir("a"));
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(calls.load(Ordering::SeqCst), 1, "a presumed hung statfs does not hold the share's figures forever");
    }

    #[test]
    fn a_kernel_network_mount_is_answered_off_the_loop() {
        let (mut fs, rx, _) = counted(300, 9);
        // Sample body: mount point, then "-" and the fstype, the fields answer_in reads.
        let cifs = "31 23 0:27 / /media/nas rw - cifs //nas/media rw\n";
        let t = Instant::now();
        let (info, class) = fs.answer_in(Path::new("/media/nas/photos"), cifs);
        assert!(info.is_none() && t.elapsed() < Duration::from_millis(250), "cifs pays its round trip on the worker");
        assert_eq!(class, "network");
        let done = next_done(&rx);
        assert_eq!((done.root.as_path(), done.dir.as_path()), (Path::new("/media/nas"), Path::new("/media/nas/photos")), "keyed by the mount point, read at the folder");
    }

    #[test]
    fn a_local_directory_still_answers_synchronously() {
        let (events, _rx) = std::sync::mpsc::channel();
        let mut fs = FsInfo::new(events);
        let sandbox = super::super::testdir::TestDir::new("fsinfoearly-local");
        let (info, class) = fs.answer(sandbox.path());
        assert!(info.is_some_and(|i| i.free > 0), "a local statfs answers its figures at once");
        assert_eq!(class, super::super::extclass::classify(sandbox.path()), "and its class is the full one");
        assert!(fs.inflight.is_empty(), "no worker for a local directory");
    }

    #[test]
    fn a_symlink_into_a_network_mount_answers_off_the_loop() {
        let sandbox = super::super::testdir::TestDir::new("fsinfolink");
        let target = sandbox.path().join("real");
        std::fs::create_dir(&target).unwrap();
        let link = sandbox.path().join("link");
        std::os::unix::fs::symlink(&target, &link).unwrap();
        let body = format!("1 0 0:30 / / rw - ext4 /dev/a rw\n30 1 0:9 / {} rw - cifs //nas/media rw\n", target.display());
        // A statfs that takes half a second, so an answer inside a quarter of one proves it ran on the worker.
        let (mut fs, rx, _) = counted(500, 7);
        let t = Instant::now();
        let (info, class) = fs.answer_in(&link, &body);
        assert!(t.elapsed() < Duration::from_millis(250), "no statfs ran on the loop, took {:?}", t.elapsed());
        assert_eq!(class, "network", "a symlink into a cifs mount is network, not local");
        assert!(info.is_none(), "its figures arrive on the worker, never blocked");
        assert_eq!(next_done(&rx).info.map(|i| i.free), Some(7), "and the worker does report them");
    }

    #[test]
    fn a_raw_kernel_share_is_decided_before_any_resolve() {
        let sandbox = super::super::testdir::TestDir::new("fsinforawfirst");
        let share = sandbox.path().join("share");
        let real = sandbox.path().join("real");
        std::fs::create_dir(&share).unwrap();
        std::fs::create_dir(&real).unwrap();
        let link = share.join("link");
        std::os::unix::fs::symlink(&real, &link).unwrap();
        let body = format!("1 0 0:30 / / rw - ext4 /dev/a rw\n30 1 0:9 / {} rw - cifs //nas/media rw\n", share.display());
        let (mut fs, _rx, _) = counted(0, 7);
        let (_, class) = fs.answer_in(&link, &body);
        assert_eq!(class, "network", "a path under a cifs mount is network by its own mount, before its link is followed");
    }

    #[test]
    fn a_decided_path_takes_no_statfs_and_a_local_one_takes_exactly_one() {
        use super::super::fsinfo::{statfs_calls, test_reset_statfs};
        let cifs = "31 23 0:27 / /media/nas rw - cifs //nas/media rw\n";
        let (mut fs, _rx, _) = counted(0, 7);
        test_reset_statfs();
        let (_, class) = fs.answer_in(Path::new("/media/nas/photos"), cifs);
        assert_eq!(class, "network");
        assert_eq!(statfs_calls(), 0, "fstype already decided; a dead server gets no statfs for nothing");
        let sandbox = super::super::testdir::TestDir::new("fsinfoonestatfs");
        let local = "1 0 0:30 / / rw - ext4 /dev/a rw\n";
        let (events, _rx) = std::sync::mpsc::channel();
        let mut real = FsInfo::new(events);
        test_reset_statfs();
        let (info, class) = real.answer_in(sandbox.path(), local);
        assert!(info.is_some_and(|i| i.free > 0), "a local statfs answers its figures at once");
        assert_eq!(class, "");
        assert_eq!(statfs_calls(), 1, "figures and magic share one statfs, not two");
    }
}
