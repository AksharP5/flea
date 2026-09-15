// LocalSend ships a CLI, and it is a full-screen program: it draws what it discovered in a panel and
// takes arrow keys and Enter. Directive 71 is that Flea drives that CLI rather than opening the app,
// so this opens a pty of its own and drives it there. No shell is involved at any point, which is
// what keeps a file name with a quote or a space in it an argument rather than somebody else's word.
use super::localsendtext::{panel, parse_peers, refusal, strip_ansi, Peer};
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

// LocalSend's own port is where a device receives, and the operator's own LocalSend may already hold
// it. Flea only ever sends, so each run takes a free port of its own and announces itself on that;
// without this a run alongside the app dies with "Address already in use" and sends nothing.
fn free_port() -> u16 {
    match std::net::TcpListener::bind(("127.0.0.1", 0)) {
        Ok(listener) => listener.local_addr().map(|a| a.port()).unwrap_or(0),
        Err(_) => 0,
    }
}

fn spawn(args: &[String], slave: &std::fs::File) -> Result<Child, String> {
    let stdin = slave.try_clone().map_err(|e| format!("LocalSend terminal setup failed: {}.", crate::error::io_message(&e)))?;
    let stdout = slave.try_clone().map_err(|e| format!("LocalSend terminal setup failed: {}.", crate::error::io_message(&e)))?;
    let stderr = slave.try_clone().map_err(|e| format!("LocalSend terminal setup failed: {}.", crate::error::io_message(&e)))?;
    let mut command = Command::new(COMMAND);
    command.args(args).stdin(Stdio::from(stdin)).stdout(Stdio::from(stdout)).stderr(Stdio::from(stderr));
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

fn press(slave: &std::fs::File, keys: &[u8]) -> Result<(), String> {
    let mut writer = slave.try_clone().map_err(|e| format!("LocalSend could not reach its CLI: {}.", crate::error::io_message(&e)))?;
    writer.write_all(keys).map_err(|e| format!("LocalSend could not reach its CLI: {}.", crate::error::io_message(&e)))?;
    writer.flush().map_err(|e| format!("LocalSend could not reach its CLI: {}.", crate::error::io_message(&e)))
}

fn stop(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}

// Every run carries its own port, so two of them and the operator's own app can be up at once.
fn port_args(rest: &[String]) -> Vec<String> {
    let mut args: Vec<String> = Vec::new();
    let port = free_port();
    if port > 0 {
        args.push("--port".into());
        args.push(port.to_string());
    }
    args.extend_from_slice(rest);
    args
}

// The devices this box can see right now. A run that carries no files starts in receive mode, so the
// panel is asked for by its own D and the run ends as soon as the answer is in.
pub fn peers(limit: Duration) -> Result<Vec<Peer>, String> {
    let (master, slave) = open_pty()?;
    let mut child = spawn(&port_args(&[]), &slave)?;
    let seen = read_into(master);
    let deadline = Instant::now() + limit;
    // The CLI has to be up before it has a key reader, so the panel is asked for after one poll.
    std::thread::sleep(POLL * 3);
    let _ = press(&slave, KEY_SHOW_DEVICES);
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

// One send, to the device the front end named. The panel numbers what it found, so the row is reached
// by pressing down from the first one, and Enter is what starts the transfer; the CLI ends the run
// itself when the transfer is over, which is the only success this side can honestly report.
pub fn send(name: &str, paths: &[String], limit: Duration) -> Result<(), String> {
    if paths.is_empty() { return Err("LocalSend was given nothing to send.".into()) }
    let mut args: Vec<String> = Vec::new();
    for path in paths {
        args.push("-f".into());
        args.push(path.clone());
    }
    let (master, slave) = open_pty()?;
    let mut child = spawn(&port_args(&args), &slave)?;
    let seen = read_into(master);
    let deadline = Instant::now() + limit;
    let mut index = None;
    while Instant::now() < deadline {
        let text = text_of(&seen);
        if let Some(refusal) = refusal(&text) {
            stop(&mut child);
            return Err(refusal)
        }
        // The panel's own rows, because Enter acts on those and not on what the log has printed.
        if let Some(peer) = parse_peers(panel(&text)).into_iter().find(|p| p.name == name) {
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
    // The panel opens on its first device, so the row wanted is that many presses further down.
    for _ in 1..index {
        press(&slave, KEY_DOWN)?;
        std::thread::sleep(POLL);
    }
    press(&slave, KEY_ENTER)?;
    // The CLI exits when the transfer ends. A run still going at the deadline is a transfer nobody
    // accepted, which is a refusal on the other machine rather than a failure here.
    while Instant::now() < deadline {
        match child.try_wait() {
            Ok(Some(status)) if status.success() => return Ok(()),
            Ok(Some(_)) => return Err(format!("LocalSend could not send to {}.", name)),
            Ok(None) => std::thread::sleep(POLL),
            Err(e) => return Err(format!("LocalSend lost its own CLI: {}.", crate::error::io_message(&e))),
        }
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

    #[test]
    fn nothing_to_send_is_refused_before_a_terminal_is_opened() {
        assert!(send("Clean Lemon", &[], Duration::from_millis(1)).is_err());
    }
}
