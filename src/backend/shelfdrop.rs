// A drop out of the shelf, redeemed. DragOut rule 1: the token names the entries and the intent, and
// the transfer engine the rest of the app uses runs it; rule 3: the pile changes only on completion.
use crate::backend::opsdispatch::Ops;
use crate::backend::opsreq::{op_err, run_transfer_checked, transferstarted_line, usable_dest, OpMsg};
use crate::backend::proto::error_line;
use crate::shelf::{now_ms, Shelf};
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::sync::mpsc::{channel, Sender};
use std::sync::Arc;
use std::thread;

// Rule 4: a token that is unknown, expired, already spent or no longer names the files it was minted
// for is refused with a sentence. Flea never falls back to a URI copy after promising a move.
pub(crate) fn start(out: &mut impl Write, ops: &mut Ops, token: &str, dest: &str) {
    // Redeeming spends the token whatever happens next, so every refusal this drop can earn is
    // earned before it: a burned token leaves the operator with a drag they cannot repeat.
    if ops.live.running().is_some() {
        return refuse(out, dest, "another operation is running");
    }
    let landing = match usable_dest(dest) {
        Ok(landing) => landing,
        Err(e) => {
            writeln!(out, "{}", error_line(&e)).ok();
            out.flush().ok();
            return;
        }
    };
    let shelf = match Shelf::user() {
        Ok(shelf) => shelf,
        Err(e) => return refuse(out, dest, &e),
    };
    let redeemed = match shelf.redeem(token, now_ms()) {
        Ok(redeemed) => redeemed,
        Err(e) => return refuse(out, dest, &e),
    };
    let dest = landing;
    let (id, cancel) = ops.claim_transfer();
    writeln!(out, "{}", transferstarted_line(id, redeemed.paths.len(), redeemed.moving)).ok();
    out.flush().ok();
    let tx = ops.tx.clone();
    thread::spawn(move || run_and_settle(id, redeemed.moving, redeemed.paths, dest, cancel, tx, shelf));
}

// The pile is updated from what the engine reported, not from what the drag asked for: an item that
// failed or was skipped stays on the shelf, and a copy leaves every reference where it was.
fn run_and_settle(
    id: usize,
    moving: bool,
    paths: Vec<String>,
    dest: PathBuf,
    cancel: Arc<AtomicBool>,
    tx: Sender<OpMsg>,
    shelf: Shelf,
) {
    // The engine's own channel, watched on the way past: the client still sees every line unchanged.
    let (mine, watch) = channel::<OpMsg>();
    let watched = paths.clone();
    let forward = thread::spawn(move || {
        let mut reported = Vec::new();
        let mut done = None;
        for msg in watch {
            if let OpMsg::Item { index, ok, .. } = &msg {
                reported.push((*index, *ok));
            }
            // Held back until the pile has been settled: a client told the transfer finished must
            // never read a pile that still lists what the move took away.
            if matches!(msg, OpMsg::TransferDone { .. }) {
                done = Some(msg);
                continue;
            }
            let _ = tx.send(msg);
        }
        if let Err(e) = shelf.settle(&moved_paths(&reported, &watched, moving)) {
            eprintln!("flea: the shelf kept its references ({})", e);
        }
        if let Some(done) = done {
            let _ = tx.send(done);
        }
    });
    run_transfer_checked(id, moving, paths, dest, cancel, mine, None, None);
    if forward.join().is_err() {
        eprintln!("flea: the shelf's own bookkeeping stopped before it finished");
    }
}

// What leaves the pile: the entries the engine reported moved, so a copy settles nothing and an
// entry that failed or was skipped stays on the shelf.
fn moved_paths(reported: &[(usize, bool)], paths: &[String], moving: bool) -> Vec<String> {
    if !moving {
        return Vec::new();
    }
    let mut moved = Vec::new();
    for (index, ok) in reported {
        if *ok {
            if let Some(path) = paths.get(*index) {
                moved.push(path.clone());
            }
        }
    }
    moved
}

fn refuse(out: &mut impl Write, dest: &str, why: &str) {
    writeln!(out, "{}", error_line(&op_err("transfer", dest, why))).ok();
    out.flush().ok();
}

#[cfg(test)]
mod tests {
    use super::moved_paths;

    #[test]
    fn only_what_the_engine_moved_leaves_the_pile() {
        let paths = vec!["/p/one".to_string(), "/p/two".to_string(), "/p/three".to_string()];
        let reported = vec![(0, true), (1, false), (2, true)];
        assert_eq!(moved_paths(&reported, &paths, true), vec!["/p/one", "/p/three"],
                   "the one that failed stays on the shelf");
        assert!(moved_paths(&reported, &paths, false).is_empty(),
                "a copy leaves every reference where it was");
        assert!(moved_paths(&[], &paths, true).is_empty(),
                "an engine that reported nothing settles nothing");
        assert!(moved_paths(&[(9, true)], &paths, true).is_empty(),
                "and an index past the end names no entry");
    }
}
