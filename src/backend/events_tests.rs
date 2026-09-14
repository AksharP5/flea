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
    let line = "{\"c\":\"transfercancel\",\"id\":4}";
    let event = read_line(line.into(), &live);
    assert!(flag.load(Ordering::Relaxed), "the reader thread sets the flag itself");
    match event {
        Event::Request(l) => assert_eq!(l, line, "and the line still reaches the loop, unchanged"),
        _ => panic!("a request line is forwarded as a request"),
    }
}

// The whole loop, not just the one line, because acting on the cancel is what issue 144 changed here.
#[test]
fn the_reader_loop_cancels_on_its_own_thread_and_forwards_every_line() {
    let (live, flag) = claimed(4);
    let (tx, rx) = std::sync::mpsc::channel();
    let lines = "{\"c\":\"list\",\"path\":\"/tmp\"}\n{\"c\":\"transfercancel\",\"id\":4}\n";
    read_lines(std::io::Cursor::new(lines), &tx, &live);
    assert!(flag.load(Ordering::Relaxed), "the loop acted on the cancel rather than only forwarding it");
    // The sender outlives the loop here, so the receiver is read to the end rather than waited on.
    drop(tx);
    let seen: Vec<Event> = rx.iter().collect();
    assert_eq!(seen.len(), 3, "both lines and the close reach the event loop");
    assert!(matches!(seen[2], Event::Closed), "and the reader reports the stream ending");
}

#[test]
fn a_cancel_names_the_operation_it_stops_and_leaves_the_other_running() {
    let (live, flag) = claimed(4);
    read_line("{\"c\":\"transfercancel\",\"id\":5}".into(), &live);
    assert!(!flag.load(Ordering::Relaxed), "a cancel aimed at another operation reaches nothing");
    assert_eq!(live.running(), Some(4), "and the one that is running is still running");
}

// The token can arrive as data rather than as the command, which is the one thing the substring
// pre-filter in cancel_in can get wrong: it passes the line on, and the parse is what decides.
#[test]
fn a_path_that_carries_the_token_is_not_a_cancel() {
    let (live, flag) = claimed(4);
    read_line("{\"c\":\"list\",\"path\":\"/tmp/transfercancel\",\"id\":4}".into(), &live);
    assert!(!flag.load(Ordering::Relaxed), "the command decides, not the spelling anywhere on the line");
    assert_eq!(live.running(), Some(4));
}

// The framing cannot be trusted past a decode failure, so the loop stops there and src/backend/run.rs
// reports the error and breaks; a reader that read on would hand it lines cut out of the middle.
#[test]
fn a_line_that_does_not_decode_stops_the_reader_where_it_failed() {
    let (live, _flag) = claimed(4);
    let (tx, rx) = std::sync::mpsc::channel();
    let lines: &[u8] = b"{\"c\":\"list\"}\n\xff\n{\"c\":\"transfercancel\",\"id\":4}\n";
    read_lines(std::io::Cursor::new(lines), &tx, &live);
    drop(tx);
    let seen: Vec<Event> = rx.iter().collect();
    assert_eq!(seen.len(), 2, "the good line and the failure, and nothing read past it");
    assert!(matches!(seen[1], Event::ReadError(_)), "the decode failure is what the loop is handed");
}

#[test]
fn an_ordinary_request_cancels_nothing_on_its_way_through() {
    let (live, flag) = claimed(4);
    let event = read_line("{\"c\":\"list\",\"path\":\"/tmp\"}".into(), &live);
    assert!(!flag.load(Ordering::Relaxed), "only the one request this thread acts on is acted on");
    assert!(matches!(event, Event::Request(_)));
}
