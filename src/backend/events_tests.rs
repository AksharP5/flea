use super::*;
use crate::backend::opscancel::Live;
use std::sync::atomic::{AtomicBool, Ordering};

fn claimed(id: usize) -> (Live, Arc<AtomicBool>) {
    let live = Live::new();
    let flag = Arc::new(AtomicBool::new(false));
    live.claim(id, &flag);
    (live, flag)
}

// Issue 144: the flag is set on this thread, so a loop parked inside a read_dir on a FUSE mount is
// not what the cancel waits for. A reader that only forwarded the line would leave the flag clear.
#[test]
fn a_cancel_line_reaches_the_operation_before_the_loop_reads_it() {
    let (live, flag) = claimed(4);
    let event = read_line("{\"c\":\"transfercancel\",\"id\":4}".into(), &live);
    assert!(flag.load(Ordering::Relaxed), "the reader thread sets the flag itself");
    assert!(matches!(event, Event::Request(_)), "and the line still reaches the loop");
}

#[test]
fn a_cancel_names_the_operation_it_stops_and_leaves_another_running() {
    let (live, flag) = claimed(4);
    read_line("{\"c\":\"transfercancel\",\"id\":5}".into(), &live);
    assert!(!flag.load(Ordering::Relaxed), "a cancel aimed at another operation reaches nothing");
}

#[test]
fn an_ordinary_request_cancels_nothing_on_its_way_through() {
    let (live, flag) = claimed(4);
    let event = read_line("{\"c\":\"list\",\"path\":\"/tmp\"}".into(), &live);
    assert!(!flag.load(Ordering::Relaxed), "only the one request this thread acts on is acted on");
    assert!(matches!(event, Event::Request(_)));
}
