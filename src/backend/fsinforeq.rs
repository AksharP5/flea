// A slow mount's statfs is a network round trip (about 800 ms on the NAS), so it runs on a worker, never the loop.
use super::events::Event;
use super::extclass::{classify_entry, fstype_is_network, gvfs_class, gvfs_root};
use super::fsinfo::Info;
use super::mountinfo::mount_entry_in;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{mpsc::Sender, Arc};
use std::time::{Duration, Instant};

// A statfs outstanding this long is presumed hung, so the next ask for its mount starts another.
pub const FSINFO_DEADLINE: Duration = Duration::from_secs(10);

// Sample input: root "/run/user/1000/gvfs/smb-share:server=n,share=x", info Some(fuse, 7).
pub struct Done {
    pub root: PathBuf,
    pub info: Option<Info>,
}

// The test seam: production reads statfs, a test sleeps or counts instead.
type Reader = Arc<dyn Fn(PathBuf) -> Option<Info> + Send + Sync>;

pub struct FsInfo {
    events: Sender<Event>,
    reader: Reader,
    // The last figures per slow mount root, one entry per mounted share, since a share's statfs answers every folder in it.
    known: HashMap<PathBuf, Option<Info>>,
    // The start of each root's outstanding statfs, so a share never runs two at once.
    inflight: HashMap<PathBuf, Instant>,
}

impl FsInfo {
    pub fn new(events: Sender<Event>) -> Self {
        Self::with_reader(events, Arc::new(|path: PathBuf| super::fsinfo::read(&path)))
    }

    pub fn with_reader(events: Sender<Event>, reader: Reader) -> Self {
        FsInfo { events, reader, known: HashMap::new(), inflight: HashMap::new() }
    }

    // Before the scan, so a share's statfs runs beside its gio listing; a kernel mount waits for fsinfo, keeping local lists free of a mountinfo read.
    pub fn list_arrived(&mut self, path: &Path) {
        if let Some(root) = gvfs_root(path) {
            self.refresh(root);
        }
    }

    // The fsinfo answer, never blocked on a slow mount: its class and last known figures now, fresh figures as a later line.
    pub fn answer(&mut self, path: &Path) -> (Option<Info>, &'static str) {
        let body = if gvfs_root(path).is_some() { String::new() } else { std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default() };
        self.answer_in(path, &body)
    }

    // The test seam: body is one /proc/self/mountinfo read, ignored for a gvfs path.
    fn answer_in(&mut self, path: &Path, body: &str) -> (Option<Info>, &'static str) {
        if let Some(root) = gvfs_root(path) {
            return self.slow_answer(root, slow_class(path));
        }
        match mount_entry_in(path, body) {
            Some(entry) if fstype_is_network(&entry.fstype) => self.slow_answer(entry.mount, "network"),
            entry => ((self.reader)(path.to_path_buf()), classify_entry(path, entry.as_ref())),
        }
    }

    fn slow_answer(&mut self, root: PathBuf, class: &'static str) -> (Option<Info>, &'static str) {
        let figures = self.known.get(&root).cloned().flatten();
        self.refresh(root);
        (figures, class)
    }

    // The statfs reads the mount root, which answers for every folder in it and cannot vanish the way a mistyped folder can.
    fn refresh(&mut self, root: PathBuf) {
        if self.inflight.get(&root).is_some_and(|started| started.elapsed() < FSINFO_DEADLINE) {
            return;
        }
        let (events, reader, key) = (self.events.clone(), Arc::clone(&self.reader), root.clone());
        let worker = std::thread::Builder::new().name("flea-fsinfo".into()).spawn(move || {
            let info = reader(key.clone());
            let _ = events.send(Event::FsInfo(Done { root: key, info }));
        });
        // corner: a spawn that fails records nothing, so the next ask tries again and answers unknown meanwhile.
        if worker.is_ok() {
            self.inflight.insert(root, Instant::now());
        }
    }

    // The figures to print for base, only when base sits in that mount and they moved since the last answer.
    pub fn finish(&mut self, done: Done, base: &Path) -> Option<Option<Info>> {
        self.inflight.remove(&done.root);
        let moved = self.known.get(&done.root) != Some(&done.info);
        self.known.insert(done.root.clone(), done.info.clone());
        if moved && base.starts_with(&done.root) {
            return Some(done.info);
        }
        None
    }
}

// A slow mount is a gvfs share or phone by its path, else a kernel network mount.
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

    // A fake statfs that takes delay_ms and counts its calls.
    fn counted(delay_ms: u64, free: u64) -> (FsInfo, Receiver<Event>, Arc<AtomicUsize>) {
        let (events, rx) = std::sync::mpsc::channel();
        let calls = Arc::new(AtomicUsize::new(0));
        let seen = Arc::clone(&calls);
        let reader: Reader = Arc::new(move |_: PathBuf| {
            seen.fetch_add(1, Ordering::SeqCst);
            std::thread::sleep(Duration::from_millis(delay_ms));
            figures(free)
        });
        (FsInfo::with_reader(events, reader), rx, calls)
    }

    fn next_done(rx: &Receiver<Event>) -> Done {
        match rx.recv_timeout(Duration::from_secs(5)).expect("the worker reports its figures") {
            Event::FsInfo(done) => done,
            _ => panic!("the worker reports its figures as an fsinfo event"),
        }
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
        assert_eq!(done.root, Path::new(SHARE), "the figures belong to the share, not the folder");
        assert_eq!(fs.finish(done, &dir).flatten().map(|i| i.free), Some(7), "the current folder's figures print");
        let (info, _) = fs.answer(&share_dir("other"));
        assert_eq!(info.map(|i| i.free), Some(7), "another folder in the share answers the known figures at once");
    }

    #[test]
    fn one_statfs_per_share_at_a_time() {
        let (mut fs, rx, calls) = counted(200, 7);
        fs.list_arrived(&share_dir("a"));
        fs.list_arrived(&share_dir("b"));
        let _ = fs.answer(&share_dir("b"));
        let done = next_done(&rx);
        assert_eq!(calls.load(Ordering::SeqCst), 1, "two folders of one share ran {} statfs calls", calls.load(Ordering::SeqCst));
        let _ = fs.finish(done, &share_dir("b"));
        fs.list_arrived(&share_dir("c"));
        let _ = next_done(&rx);
        assert_eq!(calls.load(Ordering::SeqCst), 2, "a finished statfs lets the next list refresh the figures");
    }

    #[test]
    fn unchanged_figures_print_nothing_and_moved_ones_print() {
        let (mut fs, _rx, _) = counted(0, 7);
        let dir = share_dir("a");
        assert!(fs.finish(Done { root: PathBuf::from(SHARE), info: figures(7) }, &dir).is_some(), "the first figures print");
        assert!(fs.finish(Done { root: PathBuf::from(SHARE), info: figures(7) }, &dir).is_none(), "the answer already carried these");
        assert!(fs.finish(Done { root: PathBuf::from(SHARE), info: figures(5) }, &dir).is_some(), "a copy to the share moved them");
    }

    #[test]
    fn a_share_the_client_has_left_prints_nothing() {
        let (mut fs, _rx, _) = counted(0, 7);
        let done = Done { root: PathBuf::from(SHARE), info: figures(7) };
        assert!(fs.finish(done, Path::new("/home/gm")).is_none(), "a left share's figures name the wrong place");
        let (info, _) = fs.answer_in(&share_dir("back"), "");
        assert_eq!(info.map(|i| i.free), Some(7), "but coming back answers them at once");
    }

    #[test]
    fn a_list_of_a_missing_folder_never_blanks_the_share() {
        let (events, rx) = std::sync::mpsc::channel();
        let asked = Arc::new(std::sync::Mutex::new(Vec::new()));
        let seen = Arc::clone(&asked);
        let reader: Reader = Arc::new(move |path: PathBuf| {
            seen.lock().unwrap().push(path);
            figures(7)
        });
        let mut fs = FsInfo::with_reader(events, reader);
        fs.list_arrived(&share_dir("gone"));
        let _ = next_done(&rx);
        assert_eq!(*asked.lock().unwrap(), vec![PathBuf::from(SHARE)], "the statfs reads the share root, not the folder the list named");
    }

    #[test]
    fn a_hung_statfs_past_the_deadline_lets_the_next_ask_try_again() {
        let (mut fs, _rx, calls) = counted(0, 7);
        fs.inflight.insert(PathBuf::from(SHARE), Instant::now().checked_sub(FSINFO_DEADLINE + Duration::from_secs(1)).unwrap());
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
        assert_eq!(next_done(&rx).root, Path::new("/media/nas"), "keyed by the mount point");
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
}
