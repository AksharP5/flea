// One persistent worker: slow filesystems can delay sizes, never navigation.
use super::{dirsize, events::Event};
use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::{Arc, atomic::{AtomicU64, Ordering}, mpsc::{channel, Sender}};
use std::time::{Duration, Instant};

pub struct Done {
    pub generation: u64,
    pub row: usize,
    pub result: dirsize::DirSize,
    pub ms: f64,
}

struct Job {
    generation: u64,
    rows: Vec<(usize, PathBuf)>,
}

struct Active {
    generation: u64,
    pending: HashSet<usize>,
}

pub struct Worker {
    jobs: Sender<Job>,
    generation: Arc<AtomicU64>,
    active: Option<Active>,
}

impl Worker {
    pub fn new(events: Sender<Event>) -> Self {
        Self::with_walk(events, |path, cancelled| {
            dirsize::walk_cancellable(path, Instant::now() + Duration::from_millis(dirsize::DEADLINE_MS), &cancelled)
        })
    }

    fn with_walk<F>(events: Sender<Event>, walk: F) -> Self
    where F: Fn(&std::path::Path, &dyn Fn() -> bool) -> dirsize::DirSize + Send + 'static {
        let (jobs, rx) = channel::<Job>();
        let generation = Arc::new(AtomicU64::new(0));
        let current = generation.clone();
        // The recursive walker previously used the main thread; retain stack headroom for deep trees.
        std::thread::Builder::new().name("flea-dirsize".into()).stack_size(16 * 1024 * 1024).spawn(move || {
            for job in rx {
                for (row, path) in job.rows {
                    // Account for queued rows after cancellation without entering their paths.
                    let (result, ms) = if current.load(Ordering::Relaxed) != job.generation {
                        (dirsize::DirSize { bytes: 0, partial: true }, 0.0)
                    } else {
                        let t = Instant::now();
                        let result = walk(&path, &|| current.load(Ordering::Relaxed) != job.generation);
                        (result, t.elapsed().as_secs_f64() * 1000.0)
                    };
                    let done = Done { generation: job.generation, row, result, ms };
                    if events.send(Event::DirSize(done)).is_err() { return; }
                }
            }
        }).expect("could not start directory size worker");
        Self { jobs, generation, active: None }
    }

    pub fn busy(&self) -> bool { self.active.is_some() }
    pub fn contains(&self, row: usize) -> bool {
        let generation = self.generation.load(Ordering::Relaxed);
        self.active.as_ref().is_some_and(|active| {
            active.generation == generation && active.pending.contains(&row)
        })
    }
    pub fn start(&mut self, rows: Vec<(usize, PathBuf)>) {
        assert!(!self.busy());
        let mut pending = HashSet::with_capacity(rows.len());
        let rows: Vec<_> = rows.into_iter().filter(|(row, _)| pending.insert(*row)).collect();
        if rows.is_empty() { return; }
        let generation = self.generation.fetch_add(1, Ordering::Relaxed).wrapping_add(1);
        if self.jobs.send(Job { generation, rows }).is_ok() {
            self.active = Some(Active {
                generation,
                pending,
            });
        }
    }
    pub fn cancel(&mut self) {
        self.generation.fetch_add(1, Ordering::Relaxed);
    }
    // Even a cancelled completion releases the single slot, but cannot publish a stale row.
    pub fn accept(&mut self, done: &Done) -> bool {
        let (current, finished) = {
            let Some(active) = self.active.as_mut() else { return false; };
            if active.generation != done.generation || !active.pending.remove(&done.row) {
                return false;
            }
            let current = self.generation.load(Ordering::Relaxed) == done.generation;
            (current, active.pending.is_empty())
        };
        if finished {
            self.active = None;
        }
        current
    }
}

impl Drop for Worker {
    fn drop(&mut self) { self.cancel(); }
}

#[cfg(test)]
mod tests {
    use super::*;
    // Depth 1900 exceeds the default 1024 open-file limit for any traversal
    // holding a descriptor per level, which is what std's remove_dir_all does,
    // so the cleanup below runs on every path out of a deep test, panic
    // included, and holds none. The walk itself holds one listing at a time,
    // pinned beside this in dirsize.rs; the depth here is stack headroom.
    const DEEP_DEPTH: usize = 1900;

    struct DeepTree {
        sandbox: super::super::testdir::TestDir,
        leaf: PathBuf,
    }

    impl DeepTree {
        // Depth stays what the stack proof was taken at: under PATH_MAX as paths, over any real tree.
        fn build(tag: &str) -> Self {
            let sandbox = super::super::testdir::TestDir::new(tag);
            let mut leaf = sandbox.path().to_path_buf();
            for _ in 0..DEEP_DEPTH {
                leaf.push("d");
                sandbox.assert_contains(&leaf);
                std::fs::create_dir(&leaf).unwrap();
            }
            Self { sandbox, leaf }
        }
        fn root(&self) -> &std::path::Path {
            self.sandbox.path()
        }
    }

    impl Drop for DeepTree {
        fn drop(&mut self) {
            // Bottom up, one rmdir at a time; best effort, so whatever this
            // cannot take falls through to the sandbox drop as before.
            while self.leaf != self.sandbox.path() {
                if std::fs::remove_dir(&self.leaf).is_err() {
                    break;
                }
                self.leaf.pop();
            }
        }
    }

    // A test that dies before its manual cleanup leaves its whole tree to the
    // sandbox drop, whose remove_dir_all holds a descriptor per level.
    #[test]
    fn a_deep_tree_is_removed_even_when_its_test_fails_before_cleanup() {
        let slot: std::sync::Mutex<Option<PathBuf>> = std::sync::Mutex::new(None);
        // No invariant crosses the panic: the slot write completes before it.
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let tree = DeepTree::build("size-deep-unwind");
            *slot.lock().unwrap() = Some(tree.root().to_path_buf());
            panic!("simulated failure before cleanup");
        }));
        assert!(result.is_err(), "the simulated failure did not panic");
        let kept = slot.lock().unwrap().take().unwrap();
        assert!(!kept.exists(), "a failed deep test left its tree behind: {}", kept.display());
    }

    #[test]
    fn deep_directory_tree_fits_the_worker_stack() {
        let tree = DeepTree::build("size-deep");
        let (events, rx) = channel();
        let mut worker = Worker::new(events);
        worker.start(vec![(0, tree.root().to_path_buf())]);
        let Event::DirSize(done) = rx.recv_timeout(Duration::from_secs(10)).unwrap() else { panic!() };
        assert!(worker.accept(&done));
        assert!(done.result.bytes > 0);
        assert!(!done.result.partial, "the walk reached the bottom of the tree rather than stopping short of it");
    }

    #[test]
    fn cancelled_running_job_cannot_publish_to_reused_row() {
        let (events, rx) = channel();
        let (entered, entry) = channel();
        let (release, released) = channel();
        let mut worker = Worker::with_walk(events, move |_, cancelled| {
            entered.send(()).unwrap();
            released.recv().unwrap();
            dirsize::DirSize { bytes: 42, partial: cancelled() }
        });
        worker.start(vec![(0, PathBuf::new())]);
        entry.recv_timeout(Duration::from_secs(2)).unwrap();
        worker.cancel();
        assert!(worker.busy());
        assert!(!worker.contains(0));
        release.send(()).unwrap();
        let Event::DirSize(old) = rx.recv_timeout(Duration::from_secs(2)).unwrap() else { panic!() };
        assert!(old.result.partial);
        assert!(!worker.accept(&old));
        assert!(!worker.busy());
        worker.start(vec![(0, PathBuf::new())]);
        entry.recv_timeout(Duration::from_secs(2)).unwrap();
        assert!(!worker.accept(&old));
        assert!(worker.busy());
        release.send(()).unwrap();
        let Event::DirSize(new) = rx.recv_timeout(Duration::from_secs(2)).unwrap() else { panic!() };
        assert!(!new.result.partial);
        assert!(worker.accept(&new));
        assert!(!worker.busy());
    }

    #[test]
    fn a_completed_row_does_not_release_later_rows_in_same_batch() {
        let (events, rx) = channel();
        let (release, released) = channel();
        let calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let seen = Arc::clone(&calls);
        let mut worker = Worker::with_walk(events, move |_, _| {
            if seen.fetch_add(1, Ordering::Relaxed) == 1 {
                released.recv().unwrap();
            }
            dirsize::DirSize { bytes: 7, partial: false }
        });
        worker.start(vec![(0, PathBuf::from("first")), (1, PathBuf::from("second"))]);
        let Event::DirSize(first) = rx.recv_timeout(Duration::from_secs(2)).unwrap() else { panic!() };
        assert!(worker.accept(&first));
        assert!(worker.busy());
        release.send(()).unwrap();
        let Event::DirSize(second) = rx.recv_timeout(Duration::from_secs(2)).unwrap() else { panic!() };
        assert!(worker.accept(&second));
        assert!(!worker.busy());
    }

    #[test]
    fn cancellation_skips_queued_paths_and_fresh_batch_progresses() {
        let (events, rx) = channel();
        let (entered, entry) = channel();
        let (release, released) = channel();
        let calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let seen = Arc::clone(&calls);
        let mut worker = Worker::with_walk(events, move |_, cancelled| {
            let call = seen.fetch_add(1, Ordering::Relaxed);
            if call == 0 {
                entered.send(()).unwrap();
                released.recv().unwrap();
            }
            dirsize::DirSize { bytes: 9, partial: cancelled() }
        });
        worker.start(vec![(0, PathBuf::from("running")), (1, PathBuf::from("skipped"))]);
        entry.recv_timeout(Duration::from_secs(2)).unwrap();
        worker.cancel();
        release.send(()).unwrap();
        for _ in 0..2 {
            let Event::DirSize(done) = rx.recv_timeout(Duration::from_secs(2)).unwrap() else { panic!() };
            assert!(!worker.accept(&done));
        }
        assert!(!worker.busy());
        assert_eq!(calls.load(Ordering::Relaxed), 1);

        worker.start(vec![(2, PathBuf::from("fresh"))]);
        let Event::DirSize(done) = rx.recv_timeout(Duration::from_secs(2)).unwrap() else { panic!() };
        assert!(worker.accept(&done));
        assert!(!worker.busy());
    }

    #[test]
    fn duplicate_done_cannot_release_or_reuse_a_batch_slot() {
        let (events, rx) = channel();
        let (entered, entry) = channel();
        let (release, released) = channel();
        let calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let seen = Arc::clone(&calls);
        let mut worker = Worker::with_walk(events, move |_, _| {
            if seen.fetch_add(1, Ordering::Relaxed) == 1 {
                entered.send(()).unwrap();
                released.recv().unwrap();
            }
            dirsize::DirSize { bytes: 11, partial: false }
        });
        worker.start(vec![(0, PathBuf::from("old"))]);
        let Event::DirSize(old) = rx.recv_timeout(Duration::from_secs(2)).unwrap() else { panic!() };
        assert!(worker.accept(&old));
        worker.start(vec![(0, PathBuf::from("new"))]);
        entry.recv_timeout(Duration::from_secs(2)).unwrap();
        assert!(!worker.accept(&old));
        assert!(worker.busy());
        release.send(()).unwrap();
        let Event::DirSize(new) = rx.recv_timeout(Duration::from_secs(2)).unwrap() else { panic!() };
        assert!(worker.accept(&new));
        assert!(!worker.busy());
    }

    #[test]
    fn duplicate_rows_are_walked_once_and_all_unique_rows_release_batch() {
        let (events, rx) = channel();
        let calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let seen = Arc::clone(&calls);
        let mut worker = Worker::with_walk(events, move |_, _| {
            seen.fetch_add(1, Ordering::Relaxed);
            dirsize::DirSize { bytes: 13, partial: false }
        });
        worker.start(vec![
            (0, PathBuf::from("first")),
            (0, PathBuf::from("duplicate")),
            (1, PathBuf::from("second")),
            (1, PathBuf::from("duplicate")),
        ]);
        for _ in 0..2 {
            let Event::DirSize(done) = rx.recv_timeout(Duration::from_secs(2)).unwrap() else { panic!() };
            assert!(worker.accept(&done));
        }
        assert!(rx.try_recv().is_err());
        assert_eq!(calls.load(Ordering::Relaxed), 2);
        assert!(!worker.busy());
    }
}
