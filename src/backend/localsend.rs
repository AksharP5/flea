// LocalSend ships a CLI, and it is a full-screen program: it draws what it discovered in a panel and
// takes arrow keys and Enter. Directive 71 is that Flea drives that CLI rather than opening the app,
// so this opens a pty of its own and drives it there. No shell is involved at any point, which is
// what keeps a file name with a quote or a space in it an argument rather than somebody else's word.
use super::localsendtext::{parse_peers, refusal, strip_ansi, Peer};
use std::io::{Read, Write};
use std::os::fd::{FromRawFd, OwnedFd};
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

// The CLI the package installs. The bare "localsend" beside it is the GTK app and is never run here.
const COMMAND: &str = "localsend-cli";
// The panel is drawn to fit its terminal, so the pty is opened at a size that holds the device list
// rather than the zero-by-zero a pty starts at, which makes the CLI draw nothing at all.
const ROWS: u16 = 40;
const COLS: u16 = 120;
// Keys the panel answers to: its own footer says up and down navigate, Enter sends, and D is the
// global hotkey that opens the panel on a run that carries no files.
const KEY_SHOW_DEVICES: &[u8] = b"D";
const KEY_DOWN: &[u8] = b"\x1b[B";
const KEY_ENTER: &[u8] = b"\r";
// A device answers a discovery announcement in well under a second on this LAN; measured at 1.2 s
// from process start to the first row, most of which is the CLI's own start.
const POLL: Duration = Duration::from_millis(100);

// Linux ioctl numbers. TIOCSWINSZ gives the pty its size, TIOCSCTTY makes it the child's terminal.
const TIOCSWINSZ: usize = 0x5414;
const TIOCSCTTY: usize = 0x540E;

#[repr(C)]
struct WinSize {
    rows: u16,
    cols: u16,
    x_pixels: u16,
    y_pixels: u16,
}

// std already links the system libc, so these are declared the way src/backend/child.rs declares its own.
extern "C" {
    fn posix_openpt(flags: i32) -> i32;
    fn grantpt(fd: i32) -> i32;
    fn unlockpt(fd: i32) -> i32;
    fn ptsname_r(fd: i32, buf: *mut u8, len: usize) -> i32;
    fn ioctl(fd: i32, request: usize, ...) -> i32;
    fn setsid() -> i32;
}

fn open_pty() -> Result<(OwnedFd, std::fs::File), String> {
    // O_RDWR | O_NOCTTY: this side is Flea's, and the terminal belongs to the child.
    const O_RDWR_NOCTTY: i32 = 0o2 | 0o400;
    let raw = unsafe { posix_openpt(O_RDWR_NOCTTY) };
    if raw < 0 { return Err("LocalSend could not open a terminal for its own CLI.".into()) }
    let master = unsafe { OwnedFd::from_raw_fd(raw) };
    if unsafe { grantpt(raw) } < 0 || unsafe { unlockpt(raw) } < 0 {
        return Err("LocalSend could not prepare a terminal for its own CLI.".into())
    }
    let mut name = [0u8; 256];
    if unsafe { ptsname_r(raw, name.as_mut_ptr(), name.len()) } != 0 {
        return Err("LocalSend could not name the terminal it opened.".into())
    }
    let end = name.iter().position(|b| *b == 0).unwrap_or(0);
    let path = String::from_utf8_lossy(&name[..end]).into_owned();
    let size = WinSize { rows: ROWS, cols: COLS, x_pixels: 0, y_pixels: 0 };
    if unsafe { ioctl(raw, TIOCSWINSZ, &size as *const WinSize) } < 0 {
        return Err("LocalSend could not size the terminal for its own CLI.".into())
    }
    let slave = std::fs::OpenOptions::new().read(true).write(true).open(&path)
        .map_err(|e| format!("LocalSend could not open {}: {}.", path, crate::error::io_message(&e)))?;
    Ok((master, slave))
}

// No --port: measured on the box, a run on any other port hears nothing at all, because LocalSend
// announces to the multicast group on 53317 and a CLI bound elsewhere never receives those
// announcements. A box already running its own LocalSend is told so instead, by refusal() below.
fn spawn(args: &[String], slave: &std::fs::File) -> Result<Child, String> {
    let stdin = slave.try_clone().map_err(|e| format!("LocalSend terminal setup failed: {}.", crate::error::io_message(&e)))?;
    let stdout = slave.try_clone().map_err(|e| format!("LocalSend terminal setup failed: {}.", crate::error::io_message(&e)))?;
    let stderr = slave.try_clone().map_err(|e| format!("LocalSend terminal setup failed: {}.", crate::error::io_message(&e)))?;
    let mut command = Command::new(COMMAND);
    // A pty is not a terminal until something says which one: the backend inherits no TERM, and
    // without one the CLI draws its frame and never refreshes the device list inside it.
    command.args(args).env("TERM", "xterm-256color")
        .stdin(Stdio::from(stdin)).stdout(Stdio::from(stdout)).stderr(Stdio::from(stderr));
    unsafe {
        // A session of its own, then this pty as its controlling terminal: without one the CLI reads
        // no keys at all, and with Flea's own session it would take Flea's.
        command.pre_exec(|| {
            if setsid() < 0 { return Err(std::io::Error::last_os_error()) }
            if ioctl(0, TIOCSCTTY, 0) < 0 { return Err(std::io::Error::last_os_error()) }
            Ok(())
        });
    }
    command.spawn().map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => format!("{} is not installed.", COMMAND),
        _ => format!("{} could not start: {}.", COMMAND, crate::error::io_message(&e)),
    })
}

// The reader owns the master for the length of the run: the CLI repaints constantly, so its output is
// drained on a thread of its own and the panel is read from what has arrived so far.
fn read_into(master: OwnedFd) -> Arc<Mutex<String>> {
    let seen = Arc::new(Mutex::new(String::new()));
    let sink = Arc::clone(&seen);
    std::thread::spawn(move || {
        let mut file = std::fs::File::from(master);
        let mut buf = [0u8; 4096];
        while let Ok(n) = file.read(&mut buf) {
            if n == 0 { break }
            if let Ok(mut held) = sink.lock() {
                held.push_str(&String::from_utf8_lossy(&buf[..n]));
            }
        }
    });
    seen
}

fn text_of(seen: &Arc<Mutex<String>>) -> String {
    match seen.lock() {
        Ok(held) => strip_ansi(&held),
        Err(_) => String::new(),
    }
}

// Keys go to the master, which is the terminal's input side. Writing them to the slave instead is a
// key the app never reads: it is the app's own output, so the write lands on its screen and nowhere
// else, which is why every press before this was silently lost.
fn press(master: &OwnedFd, keys: &[u8]) -> Result<(), String> {
    let mut writer = std::fs::File::from(master.try_clone().map_err(|e| format!("LocalSend could not reach its CLI: {}.", crate::error::io_message(&e)))?);
    writer.write_all(keys).map_err(|e| format!("LocalSend could not reach its CLI: {}.", crate::error::io_message(&e)))?;
    writer.flush().map_err(|e| format!("LocalSend could not reach its CLI: {}.", crate::error::io_message(&e)))
}

// Sample event lines, exactly as the CLI prints them under its panel:
// "S Clean Lemon: Sent 1 file (61 B, took 0s)" and "D [1] Clean Lemon (192.168.21.23)".
// The prefix is the whole test, never a substring: a device named "Sent Phone" would otherwise be
// read as a completed transfer the moment it was discovered, and "Failed Phone" as a refusal.
pub fn sent(text: &str, name: &str) -> Option<Result<(), String>> {
    let head = format!("S {}: ", name);
    let line = text.lines().map(str::trim).rev().find(|l| l.starts_with(&head))?;
    let said = line[head.len()..].trim();
    if said.starts_with("Sent ") { return Some(Ok(())) }
    if said.starts_with("Failed") {
        return Some(Err(format!("LocalSend could not send to {}: {}.", name, said.trim_end_matches('.'))))
    }
    None
}

fn stop(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}

// The devices this box can see right now. A run that carries no files starts in receive mode, so the
// panel is asked for by its own D and the run ends as soon as the answer is in.
pub fn peers(limit: Duration) -> Result<Vec<Peer>, String> {
    let (master, slave) = open_pty()?;
    let mut child = spawn(&[], &slave)?;
    let keys = master.try_clone()
        .map_err(|e| format!("LocalSend could not hold its own terminal: {}.", crate::error::io_message(&e)))?;
    let seen = read_into(master);
    let deadline = Instant::now() + limit;
    // The CLI has to be up before it has a key reader, so the panel is asked for after one poll.
    std::thread::sleep(POLL * 3);
    let _ = press(&keys, KEY_SHOW_DEVICES);
    loop {
        let found = parse_peers(&text_of(&seen));
        if !found.is_empty() {
            stop(&mut child);
            return Ok(found)
        }
        if let Some(refusal) = refusal(&text_of(&seen)) {
            stop(&mut child);
            return Err(refusal)
        }
        if Instant::now() >= deadline {
            stop(&mut child);
            return Ok(Vec::new())
        }
        std::thread::sleep(POLL);
    }
}

// One send, to the device the front end named, driven on the CLI's own terminal. Two things were
// measured here the hard way, both by driving it: keys go to the MASTER side of the pty, because the
// slave is the app's own output and a key written there is never read, and the device the CLI found
// arrives as an incremental screen update, so the stream is read whole rather than frame by frame.
// The row is reached with the arrows the CLI's own footer names, Enter sends, and the CLI says so.
pub fn send(name: &str, paths: &[String], limit: Duration) -> Result<(), String> {
    if paths.is_empty() { return Err("LocalSend was given nothing to send.".into()) }
    let mut args: Vec<String> = Vec::new();
    for path in paths {
        args.push("-f".into());
        args.push(path.clone());
    }
    let (master, slave) = open_pty()?;
    let mut child = spawn(&args, &slave)?;
    let keys = master.try_clone()
        .map_err(|e| format!("LocalSend could not hold its own terminal: {}.", crate::error::io_message(&e)))?;
    let seen = read_into(master);
    let deadline = Instant::now() + limit;
    let mut index = None;
    while Instant::now() < deadline {
        let text = text_of(&seen);
        if let Some(refusal) = refusal(&text) {
            stop(&mut child);
            return Err(refusal)
        }
        if let Some(peer) = parse_peers(&text).into_iter().find(|p| p.name == name) {
            index = Some(peer.index);
            break
        }
        std::thread::sleep(POLL);
    }
    let index = match index {
        Some(index) => index,
        None => {
            stop(&mut child);
            return Err(format!("{} is not answering on this network any more.", name))
        }
    };
    // The list opens on its first device, so the row wanted is that many presses further down.
    for _ in 1..index {
        press(&keys, KEY_DOWN)?;
        std::thread::sleep(POLL);
    }
    press(&keys, KEY_ENTER)?;
    // The CLI reports the transfer on its own event line, "S <device>: Sent 1 file (61 B, took 0s)",
    // and that line is the only success this side can honestly report.
    while Instant::now() < deadline {
        let text = text_of(&seen);
        if let Some(verdict) = sent(&text, name) {
            stop(&mut child);
            return verdict
        }
        // The CLI ending is not a transfer. Only its own Sent line is one, so a run that ended
        // without printing one sent nothing, whatever its exit code was.
        if let Ok(Some(_)) = child.try_wait() {
            return match sent(&text_of(&seen), name) {
                Some(verdict) => verdict,
                None => Err(format!("LocalSend's own CLI ended without sending to {}.", name)),
            }
        }
        std::thread::sleep(POLL);
    }
    stop(&mut child);
    Err(format!("{} did not accept the transfer.", name))
}

// How long each leg may take. Discovery is a CLI start plus one announcement round trip, measured at
// 1.2 s on this box; a send waits for the other machine's own accept, which is a person.
const PEERS_LIMIT: Duration = Duration::from_secs(4);
const SEND_LIMIT: Duration = Duration::from_secs(45);

// The one line the client hears, for either leg. Sample: {"t":"localsendpeers","id":3,"peers":[
// {"name":"Clean Lemon","address":"192.168.21.23"}],"reason":""}
pub fn request(op: String, peer: String, paths: Vec<String>, id: usize, replies: std::sync::mpsc::Sender<crate::backend::opsreq::OpMsg>) {
    std::thread::spawn(move || {
        let line = answer(&op, &peer, &paths, id);
        let _ = replies.send(crate::backend::opsreq::OpMsg::Meta { line });
    });
}

pub fn answer(op: &str, peer: &str, paths: &[String], id: usize) -> String {
    if op == "send" {
        return match send(peer, paths, SEND_LIMIT) {
            Ok(()) => format!(r#"{{"t":"localsendsent","id":{},"ok":true,"reason":""}}"#, id),
            Err(reason) => format!(r#"{{"t":"localsendsent","id":{},"ok":false,"reason":"{}"}}"#, id, crate::json::escape(&reason)),
        }
    }
    match peers(PEERS_LIMIT) {
        Ok(found) => {
            let rows: Vec<String> = found.iter()
                .map(|p| format!(r#"{{"name":"{}","address":"{}"}}"#, crate::json::escape(&p.name), crate::json::escape(&p.address)))
                .collect();
            let reason = if rows.is_empty() { "no devices are answering on this network" } else { "" };
            format!(r#"{{"t":"localsendpeers","id":{},"peers":[{}],"reason":"{}"}}"#, id, rows.join(","), reason)
        }
        Err(reason) => format!(r#"{{"t":"localsendpeers","id":{},"peers":[],"reason":"{}"}}"#, id, crate::json::escape(&reason)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Codex's finding on the first drive that worked: a substring test reads a device named after
    // the event as the event itself, and a CLI that ended is not a CLI that sent.
    #[test]
    fn only_the_transfer_s_own_event_line_is_a_transfer() {
        let discovered = "D [1] Sent Phone (10.0.0.4)\nD [2] Failed Phone (10.0.0.5)";
        assert!(sent(discovered, "Sent Phone").is_none());
        assert!(sent(discovered, "Failed Phone").is_none());
        assert!(sent("S Sent Phone: Sent 1 file (61 B, took 0s)", "Sent Phone").expect("a verdict").is_ok());
        let refused = sent("S Clean Lemon: Failed to send: connection refused", "Clean Lemon").expect("a verdict");
        assert!(refused.unwrap_err().contains("connection refused"));
        // The peer's own name is what anchors it, so another device's line is not this one's.
        assert!(sent("S Other Box: Sent 1 file (61 B, took 0s)", "Clean Lemon").is_none());
    }

    #[test]
    fn nothing_to_send_is_refused_before_a_terminal_is_opened() {
        assert!(send("Clean Lemon", &[], Duration::from_millis(1)).is_err());
    }
}
