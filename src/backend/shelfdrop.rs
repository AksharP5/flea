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
    let shelf = match Shelf::user() {
        Ok(shelf) => shelf,
        Err(e) => return refuse(out, &e),
    };
    let redeemed = match shelf.redeem(token, now_ms()) {
        Ok(redeemed) => redeemed,
        Err(e) => return refuse(out, &e),
    };
    let dest = match usable_dest(dest) {
        Ok(dest) => dest,
        Err(e) => {
            writeln!(out, "{}", error_line(&e)).ok();
            out.flush().ok();
            return;
        }
    };
    if ops.live.running().is_some() {
        return refuse(out, "another operation is running");
    }
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
        let mut moved = Vec::new();
        for msg in watch {
            if let OpMsg::Item { index, ok, .. } = &msg {
                if *ok && moving {
                    if let Some(path) = watched.get(*index) {
                        moved.push(path.clone());
                    }
                }
            }
            let _ = tx.send(msg);
        }
        if let Err(e) = shelf.settle(&moved) {
            eprintln!("flea: the shelf kept its references ({})", e);
        }
    });
    run_transfer_checked(id, moving, paths, dest, cancel, mine, None, None);
    let _ = forward.join();
}

fn refuse(out: &mut impl Write, why: &str) {
    writeln!(out, "{}", error_line(&op_err("transfer", "", why))).ok();
    out.flush().ok();
}
