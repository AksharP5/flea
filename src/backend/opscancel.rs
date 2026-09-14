// Issue 144: a transfercancel reached the running operation through the event loop, and a listing of
// an MTP directory held that loop inside read_dir while the copy went on, so the cancel was read only
// after the copy had finished by itself. The reader thread sets the flag here instead, so a cancel
// never queues behind whatever the loop is doing.
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

// The operation on the thread and the flag it polls, or None while nothing is running.
pub(crate) struct Live(Mutex<Option<(usize, Arc<AtomicBool>)>>);

impl Live {
    pub fn new() -> Live {
        Live(Mutex::new(None))
    }

    pub fn claim(&self, id: usize, cancel: &Arc<AtomicBool>) {
        if let Ok(mut held) = self.0.lock() {
            *held = Some((id, Arc::clone(cancel)));
        }
    }

    pub fn finished(&self) {
        if let Ok(mut held) = self.0.lock() {
            *held = None;
        }
    }

    pub fn running(&self) -> Option<usize> {
        self.0.lock().ok().and_then(|held| held.as_ref().map(|(id, _)| *id))
    }

    // The id is what keeps a cancel off the operation after the one it was aimed at, and the lock is
    // what keeps it off one claimed between the read and the store.
    pub fn cancel(&self, id: usize) {
        if let Ok(held) = self.0.lock() {
            if let Some((running, flag)) = held.as_ref() {
                if *running == id {
                    flag.store(true, Ordering::Relaxed);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_cancel_reaches_the_running_operation_and_nothing_else() {
        let live = Live::new();
        let flag = Arc::new(AtomicBool::new(false));
        live.claim(7, &flag);
        // The reader thread's own call, made while the loop is inside a read_dir on a FUSE mount.
        live.cancel(7);
        assert!(flag.load(Ordering::Relaxed), "the operation on the thread is the one a cancel reaches");
        assert_eq!(live.running(), Some(7));
    }

    #[test]
    fn a_cancel_for_an_operation_that_has_ended_never_reaches_the_next_one() {
        let live = Live::new();
        let first = Arc::new(AtomicBool::new(false));
        live.claim(7, &first);
        live.finished();
        let second = Arc::new(AtomicBool::new(false));
        live.claim(8, &second);
        live.cancel(7);
        assert!(!second.load(Ordering::Relaxed), "an id that is not running cancels nothing");
        assert!(!first.load(Ordering::Relaxed), "and the flag it was aimed at is not set either");
        live.cancel(8);
        assert!(second.load(Ordering::Relaxed), "the one that is running still takes its own cancel");
    }

    #[test]
    fn nothing_running_takes_no_cancel_at_all() {
        let live = Live::new();
        let flag = Arc::new(AtomicBool::new(false));
        live.claim(1, &flag);
        live.finished();
        live.cancel(1);
        assert_eq!(live.running(), None);
        assert!(!flag.load(Ordering::Relaxed), "a cancel with nothing running reaches the flag Live held");
        live.claim(1, &flag);
        assert!(!flag.load(Ordering::Relaxed), "and it does not carry over to the next claim of that id");
    }
}
