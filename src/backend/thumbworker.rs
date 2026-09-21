// `flea --thumb-worker`: libffmpegthumbnailer linked once, then one forked and confined child per video; see AGENTS.md "Thumbnail worker".
use crate::backend::fdpass;
use crate::backend::sandbox;
use crate::backend::thumbs::JOB_TIMEOUT;
use std::ffi::{c_void, CStr};
use std::io::Write;
use std::os::fd::{AsRawFd, FromRawFd, IntoRawFd, OwnedFd, RawFd};
use std::os::raw::{c_char, c_int, c_long};
use std::os::unix::process::ExitStatusExt;
use std::time::Instant;

// The worker's first byte: it can serve, or which of its two requirements is missing.
pub const READY: u8 = b'R';
pub const NO_LIBRARY: u8 = b'L';
pub const NO_LANDLOCK: u8 = b'K';
// Each job's one verdict: a thumbnail was written, the file failed, or this machine failed the job.
pub const SUCCEEDED: u8 = b'S';
pub const FAILED: u8 = b'F';
pub const NOT_STARTED: u8 = b'N';
// A request is the thumbnail size as four little-endian bytes and then the film-strip flag.
pub const REQUEST_BYTES: usize = 5;
// The ffmpegthumbnailer 2.x soname, the same library /usr/bin/ffmpegthumbnailer links.
pub const SONAME: &CStr = c"libffmpegthumbnailer.so.4";
// The child keeps the two job files here, so the path libav is handed is a constant.
const INPUT_FD: RawFd = 3;
const OUTPUT_FD: RawFd = 4;
const FIRST_UNUSED_FD: u32 = 5;
const INPUT_PATH: &CStr = c"/proc/self/fd/3";
// Descriptors are parked above this while the low numbers are rearranged, so no dup2 lands on one still needed.
const PARK_FD: c_int = 100;
// The child's exit codes: a verdict on the file, or a failure of this machine that judges nothing.
const CHILD_OK: i32 = 0;
const CHILD_REFUSED: i32 = 1;
const CHILD_MACHINE: i32 = 2;
// A larger request is not a thumbnail, and the pool only ever asks for THUMB_SIZE.
const MAX_SIZE: u32 = 1024;

// dlopen(3) RTLD_NOW, so a library missing a symbol fails at load and never inside a child.
const RTLD_NOW: c_int = 2;
// prctl(2): not dumpable, so no process of this user can ptrace the worker or read its descriptors; no new privileges, which Landlock requires.
const PR_SET_DUMPABLE: c_int = 4;
const PR_SET_NO_NEW_PRIVS: c_int = 38;
// setrlimit(2) resources, and the two values prlimit applies on the exec path.
const RLIMIT_CPU: c_int = 0;
const RLIMIT_AS: c_int = 9;
// Landlock's two syscalls on x86_64, and the flag that asks create_ruleset for the ABI version.
const SYS_LANDLOCK_CREATE_RULESET: c_long = 444;
const SYS_LANDLOCK_RESTRICT_SELF: c_long = 446;
const LANDLOCK_CREATE_RULESET_VERSION: u32 = 1;
// Every filesystem right that writes, creates, removes, renames or truncates; reads are not handled, so libraries and the input still open.
const LANDLOCK_WRITE_V1: u64 = (1 << 1) | (0x1ff << 4);
const LANDLOCK_REFER_V2: u64 = 1 << 13;
const LANDLOCK_TRUNCATE_V3: u64 = 1 << 14;
// From ABI 6 a scoped child can signal nothing outside its own domain, so not a sibling and not the worker.
const LANDLOCK_SCOPE_SIGNAL: u64 = 1 << 1;
const LANDLOCK_SCOPE_SIGNAL_ABI: i64 = 6;
// poll(2) POLLIN, and EINTR, which is a retry.
const POLLIN: i16 = 1;
const EINTR: i32 = 4;
const SIGKILL: c_int = 9;
// fcntl(2) F_DUPFD_CLOEXEC.
const F_DUPFD_CLOEXEC: c_int = 1030;

#[repr(C)]
struct PollFd {
    fd: c_int,
    events: i16,
    revents: i16,
}

#[repr(C)]
struct RLimit {
    current: u64,
    maximum: u64,
}

// struct landlock_ruleset_attr; a kernel older than a field accepts it while that field is zero.
#[repr(C)]
struct RulesetAttr {
    handled_access_fs: u64,
    handled_access_net: u64,
    scoped: u64,
}

// video_thumbnailer from ffmpegthumbnailer 2.3's videothumbnailerc.h; only overlay_film_strip is written.
#[repr(C)]
struct VideoThumbnailer {
    thumbnail_size: c_int,
    seek_percentage: c_int,
    seek_time: *mut c_char,
    overlay_film_strip: c_int,
    workaround_bugs: c_int,
    thumbnail_image_quality: c_int,
    thumbnail_image_type: c_int,
    av_format_context: *mut c_void,
    maintain_aspect_ratio: c_int,
    prefer_embedded_metadata: c_int,
    tdata: *mut c_void,
}

// image_data from the same header; the library fills it with the encoded PNG.
#[repr(C)]
struct ImageData {
    ptr: *mut u8,
    size: c_int,
    width: c_int,
    height: c_int,
    source: c_int,
    internal: *mut c_void,
}

type Create = unsafe extern "C" fn() -> *mut VideoThumbnailer;
type SetSize = unsafe extern "C" fn(*mut VideoThumbnailer, c_int, c_int) -> c_int;
type CreateImageData = unsafe extern "C" fn() -> *mut ImageData;
type ToBuffer = unsafe extern "C" fn(*mut VideoThumbnailer, *const c_char, *mut ImageData) -> c_int;

// std already links the system libc, so every symbol is declared here rather than taking a crate.
extern "C" {
    fn dlopen(file: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn prctl(option: c_int, arg2: u64, arg3: u64, arg4: u64, arg5: u64) -> c_int;
    fn setrlimit(resource: c_int, limit: *const RLimit) -> c_int;
    fn syscall(number: c_long, ...) -> c_long;
    fn fork() -> c_int;
    fn _exit(code: c_int) -> !;
    fn kill(pid: c_int, sig: c_int) -> c_int;
    fn waitpid(pid: c_int, status: *mut c_int, options: c_int) -> c_int;
    fn pidfd_open(pid: c_int, flags: u32) -> c_int;
    fn poll(fds: *mut PollFd, nfds: usize, timeout: c_int) -> c_int;
    fn fcntl(fd: c_int, cmd: c_int, arg: c_int) -> c_int;
    fn dup2(old: c_int, new: c_int) -> c_int;
    fn close_range(first: u32, last: u32, flags: c_int) -> c_int;
}

struct Decoder {
    create: Create,
    set_size: SetSize,
    create_image_data: CreateImageData,
    to_buffer: ToBuffer,
}

impl Decoder {
    // corner: the handle is never dlclose()d, because every child borrows it until this process exits.
    fn load(soname: &CStr) -> Option<Decoder> {
        unsafe {
            let library = dlopen(soname.as_ptr(), RTLD_NOW);
            if library.is_null() {
                return None;
            }
            let entry = |symbol: &CStr| {
                let found = dlsym(library, symbol.as_ptr());
                (!found.is_null()).then_some(found)
            };
            Some(Decoder {
                create: std::mem::transmute::<*mut c_void, Create>(entry(c"video_thumbnailer_create")?),
                set_size: std::mem::transmute::<*mut c_void, SetSize>(entry(c"video_thumbnailer_set_size")?),
                create_image_data: std::mem::transmute::<*mut c_void, CreateImageData>(entry(
                    c"video_thumbnailer_create_image_data",
                )?),
                to_buffer: std::mem::transmute::<*mut c_void, ToBuffer>(entry(
                    c"video_thumbnailer_generate_thumbnail_to_buffer",
                )?),
            })
        }
    }

    // `-s N` is set_size(N, N), measured against the CLI on portrait clips where (N, 0) differs, and `-f` is overlay_film_strip.
    fn generate(&self, size: c_int, film_strip: bool) -> i32 {
        unsafe {
            let thumbnailer = (self.create)();
            let image = (self.create_image_data)();
            if thumbnailer.is_null() || image.is_null() {
                return CHILD_MACHINE;
            }
            (self.set_size)(thumbnailer, size, size);
            (*thumbnailer).overlay_film_strip = c_int::from(film_strip);
            if (self.to_buffer)(thumbnailer, INPUT_PATH.as_ptr(), image) != 0 || (*image).ptr.is_null() || (*image).size <= 0 {
                return CHILD_REFUSED;
            }
            let png = std::slice::from_raw_parts((*image).ptr, (*image).size as usize);
            let mut out = std::fs::File::from_raw_fd(OUTPUT_FD);
            if out.write_all(png).is_err() {
                return CHILD_MACHINE;
            }
            CHILD_OK
        }
    }
}

// The Landlock ABI version, or None on a kernel without Landlock, which gets no worker.
fn landlock_abi() -> Option<i64> {
    let abi = unsafe {
        syscall(SYS_LANDLOCK_CREATE_RULESET, std::ptr::null::<RulesetAttr>(), 0usize, LANDLOCK_CREATE_RULESET_VERSION)
    };
    (abi >= 1).then_some(abi)
}

// The write rights this ABI knows, so an older kernel is not handed a bit it would refuse.
fn write_rights(abi: i64) -> u64 {
    let mut rights = LANDLOCK_WRITE_V1;
    if abi >= 2 {
        rights |= LANDLOCK_REFER_V2;
    }
    if abi >= 3 {
        rights |= LANDLOCK_TRUNCATE_V3;
    }
    rights
}

// After this the child can open nothing for writing, create or remove nothing, and signal nothing outside itself.
fn lock_down(abi: i64) -> Option<()> {
    // corner: before ABI 6 there is no signal scope, so a child there could still signal its siblings.
    let scoped = if abi >= LANDLOCK_SCOPE_SIGNAL_ABI { LANDLOCK_SCOPE_SIGNAL } else { 0 };
    let attr = RulesetAttr { handled_access_fs: write_rights(abi), handled_access_net: 0, scoped };
    unsafe {
        if prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0 {
            return None;
        }
        let ruleset = syscall(SYS_LANDLOCK_CREATE_RULESET, &attr as *const RulesetAttr, std::mem::size_of::<RulesetAttr>(), 0u32);
        if ruleset < 0 {
            return None;
        }
        let ruleset = OwnedFd::from_raw_fd(ruleset as RawFd);
        (syscall(SYS_LANDLOCK_RESTRICT_SELF, ruleset.as_raw_fd(), 0u32) == 0).then_some(())
    }
}

// The child's whole descriptor table becomes /dev/null on 0 to 2, the input on 3 and the output on 4.
fn keep_only_the_job(input: RawFd, output: RawFd) -> Option<()> {
    let null = std::fs::OpenOptions::new().read(true).write(true).open("/dev/null").ok()?.into_raw_fd();
    unsafe {
        let parked = [fcntl(null, F_DUPFD_CLOEXEC, PARK_FD), fcntl(input, F_DUPFD_CLOEXEC, PARK_FD), fcntl(output, F_DUPFD_CLOEXEC, PARK_FD)];
        if parked.iter().any(|fd| *fd < 0) {
            return None;
        }
        let [null, input, output] = parked;
        for (from, to) in [(null, 0), (null, 1), (null, 2), (input, INPUT_FD), (output, OUTPUT_FD)] {
            if dup2(from, to) != to {
                return None;
            }
        }
        (close_range(FIRST_UNUSED_FD, u32::MAX, 0) == 0).then_some(())
    }
}

fn set_limit(resource: c_int, value: u64) -> Option<()> {
    let limit = RLimit { current: value, maximum: value };
    (unsafe { setrlimit(resource, &limit) } == 0).then_some(())
}

// Everything that has to hold before a byte of the file is decoded; any failure judges no file.
fn confine(input: RawFd, output: RawFd, abi: i64) -> Option<()> {
    keep_only_the_job(input, output)?;
    set_limit(RLIMIT_CPU, u64::from(sandbox::CPU_SECONDS))?;
    set_limit(RLIMIT_AS, sandbox::ADDRESS_SPACE_BYTES)?;
    lock_down(abi)
}

// Runs in the forked child and never returns: the exit code is the verdict, and a panic is caught so it never unwinds into the worker's loop.
fn child(input: RawFd, output: RawFd, size: c_int, film_strip: bool, decoder: &Decoder, abi: i64) -> ! {
    let verdict = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| match confine(input, output, abi) {
        None => CHILD_MACHINE,
        Some(()) => decoder.generate(size, film_strip),
    }));
    unsafe { _exit(verdict.unwrap_or(CHILD_MACHINE)) }
}

struct Running {
    pid: c_int,
    pidfd: OwnedFd,
    reply: OwnedFd,
    deadline: Instant,
}

// Reaps one child and answers its job; a child killed by a signal, the deadline's included, ran on the file and failed.
fn finish(job: Running, past_deadline: bool) {
    if past_deadline {
        unsafe { kill(job.pid, SIGKILL) };
    }
    let mut status: c_int = 0;
    let verdict = if unsafe { waitpid(job.pid, &mut status, 0) } != job.pid {
        NOT_STARTED
    } else {
        match std::process::ExitStatus::from_raw(status).code() {
            Some(CHILD_OK) if !past_deadline => SUCCEEDED,
            Some(CHILD_MACHINE) => NOT_STARTED,
            _ => FAILED,
        }
    };
    // corner: a backend that gave up on this job has closed its end, and there is no one left to tell.
    let _ = fdpass::send_byte(&job.reply, verdict);
}

// Sample request: payload [0, 1, 0, 0, 1] (size 256, film strip on), descriptors [input, output, reply].
fn start(message: fdpass::Received, decoder: &Decoder, abi: i64, running: &mut Vec<Running>) {
    let mut fds = message.fds.into_iter();
    let (Some(input), Some(output), Some(reply), None) = (fds.next(), fds.next(), fds.next(), fds.next()) else {
        return;
    };
    let payload = message.payload;
    let size = if payload.len() == REQUEST_BYTES { u32::from_le_bytes([payload[0], payload[1], payload[2], payload[3]]) } else { 0 };
    if size == 0 || size > MAX_SIZE {
        let _ = fdpass::send_byte(&reply, NOT_STARTED);
        return;
    }
    let film_strip = payload[4] != 0;
    let pid = unsafe { fork() };
    if pid == 0 {
        child(input.as_raw_fd(), output.as_raw_fd(), size as c_int, film_strip, decoder, abi);
    }
    if pid < 0 {
        let _ = fdpass::send_byte(&reply, NOT_STARTED);
        return;
    }
    drop(input);
    drop(output);
    let raw = unsafe { pidfd_open(pid, 0) };
    if raw < 0 {
        // corner: with no descriptor there is no deadline to enforce, so the child is ended now and judges nothing.
        unsafe { kill(pid, SIGKILL) };
        let mut status: c_int = 0;
        unsafe { waitpid(pid, &mut status, 0) };
        let _ = fdpass::send_byte(&reply, NOT_STARTED);
        return;
    }
    let pidfd = unsafe { OwnedFd::from_raw_fd(raw) };
    running.push(Running { pid, pidfd, reply, deadline: Instant::now() + JOB_TIMEOUT });
}

// Milliseconds to the nearest deadline, rounded up, or -1 to wait for a request with no child running.
fn poll_timeout(running: &[Running]) -> c_int {
    match running.iter().map(|r| r.deadline).min() {
        None => -1,
        Some(at) => at.saturating_duration_since(Instant::now()).as_millis().saturating_add(1).min(c_int::MAX as u128) as c_int,
    }
}

fn serve(requests: &OwnedFd, decoder: &Decoder, abi: i64) -> i32 {
    let mut running: Vec<Running> = Vec::new();
    loop {
        let mut fds: Vec<PollFd> = Vec::with_capacity(running.len() + 1);
        fds.push(PollFd { fd: requests.as_raw_fd(), events: POLLIN, revents: 0 });
        for job in &running {
            fds.push(PollFd { fd: job.pidfd.as_raw_fd(), events: POLLIN, revents: 0 });
        }
        let ready = unsafe { poll(fds.as_mut_ptr(), fds.len(), poll_timeout(&running)) };
        if ready < 0 {
            if std::io::Error::last_os_error().raw_os_error() == Some(EINTR) {
                continue;
            }
            return 1;
        }
        // Children first, so a verdict is never held behind a request.
        let now = Instant::now();
        let mut still = Vec::with_capacity(running.len());
        for (job, polled) in running.into_iter().zip(fds.iter().skip(1)) {
            if polled.revents != 0 {
                finish(job, false);
            } else if now >= job.deadline {
                finish(job, true);
            } else {
                still.push(job);
            }
        }
        running = still;
        if fds[0].revents != 0 {
            match fdpass::recv(requests.as_raw_fd()) {
                Ok(Some(message)) => start(message, decoder, abi, &mut running),
                // The backend closed its end, so there will be no more work; bwrap's own init ends any child still running.
                Ok(None) => return 0,
                Err(e) if e.raw_os_error() == Some(EINTR) => {}
                // A malformed packet is dropped with its descriptors; anything else is a socket that no longer works.
                Err(e) if e.kind() == std::io::ErrorKind::InvalidData => {}
                Err(_) => return 1,
            }
        }
    }
}

// The whole process: stdin is the request socket, and the first byte says whether this worker can serve.
pub fn run() -> i32 {
    let requests = unsafe { OwnedFd::from_raw_fd(0) };
    unsafe { prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) };
    let Some(decoder) = Decoder::load(SONAME) else {
        let _ = fdpass::send_byte(&requests, NO_LIBRARY);
        return 1;
    };
    let Some(abi) = landlock_abi() else {
        let _ = fdpass::send_byte(&requests, NO_LANDLOCK);
        return 1;
    };
    if fdpass::send_byte(&requests, READY).is_err() {
        return 1;
    }
    serve(&requests, &decoder, abi)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;
    use std::process::Command;

    // The probe confines a second copy of this test binary, so nothing it locks down can reach the harness running every other test.
    const CONFINE_PROBE: &str = "FLEA_CONFINE_PROBE";
    const THIS_TEST: &str = "backend::thumbworker::tests::a_confined_child_holds_only_its_job_and_can_write_or_signal_nothing";
    // Every descriptor below this is looked at, which covers PARK_FD and anything a leak could leave.
    const FD_CEILING: c_int = 1024;
    // fcntl(2) F_GETFD, which fails only on a descriptor that is not open.
    const F_GETFD: c_int = 1;

    extern "C" {
        fn getppid() -> c_int;
        fn getrlimit(resource: c_int, limit: *mut RLimit) -> c_int;
    }

    fn soft_limit(resource: c_int) -> u64 {
        let mut limit = RLimit { current: 0, maximum: 0 };
        unsafe { getrlimit(resource, &mut limit) };
        limit.current
    }

    // What descriptor 0, 1 or 2 points at, such as "/dev/null" or "socket:[123]".
    fn target(fd: c_int) -> String {
        std::fs::read_link(format!("/proc/self/fd/{}", fd)).map(|p| p.to_string_lossy().into_owned()).unwrap_or_default()
    }

    // Holds the input read-only, the report write-only and a socket on 0, the way a job arrives in the worker, runs confine() and writes what it can still do to the report.
    fn probe(dir: &str) -> ! {
        let victim = format!("{}/victim.mp4", dir);
        let reader = std::fs::File::open(&victim).expect("the probe could not open its input");
        let report = std::fs::OpenOptions::new().write(true).open(format!("{}/report", dir)).expect("the probe could not open its report");
        let (_peer, planted) = fdpass::pair().expect("the probe could not make its socket");
        if unsafe { dup2(planted.as_raw_fd(), 0) } != 0 {
            unsafe { _exit(CHILD_MACHINE) };
        }
        let socket_before = target(0).starts_with("socket:");
        let Some(abi) = landlock_abi() else {
            println!("probe=no-landlock");
            std::process::exit(0);
        };
        let writable = |path: &str| std::fs::OpenOptions::new().write(true).open(path).is_ok();
        let wrote_before = writable(&format!("/proc/self/fd/{}", reader.as_raw_fd()));
        let signalled_before = unsafe { kill(getppid(), 0) } == 0;
        if confine(reader.as_raw_fd(), report.as_raw_fd(), abi).is_none() {
            unsafe { _exit(CHILD_MACHINE) };
        }
        let open: Vec<c_int> = (0..FD_CEILING).filter(|fd| unsafe { fcntl(*fd, F_GETFD, 0) } >= 0).collect();
        let nulls = (0..3).all(|fd| target(fd) == "/dev/null");
        let facts = format!(
            "socket_before={} nulls={} before={} reopened={} direct={} readable={} signalled_before={} signalled={} fds={:?} cpu={} as={}",
            socket_before,
            nulls,
            wrote_before,
            writable("/proc/self/fd/3"),
            writable(&victim),
            std::fs::File::open("/proc/self/fd/3").is_ok(),
            signalled_before,
            unsafe { kill(getppid(), 0) } == 0,
            open,
            soft_limit(RLIMIT_CPU),
            soft_limit(RLIMIT_AS)
        );
        let mut out = unsafe { std::fs::File::from_raw_fd(OUTPUT_FD) };
        let _ = out.write_all(facts.as_bytes());
        unsafe { _exit(CHILD_OK) }
    }

    #[test]
    fn a_confined_child_holds_only_its_job_and_can_write_or_signal_nothing() {
        if let Ok(dir) = std::env::var(CONFINE_PROBE) {
            probe(&dir);
        }
        let dir = TestDir::new("worker-confine");
        let victim = dir.file("victim.mp4", "original");
        let report = dir.file("report", "");
        let out = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", THIS_TEST, "--test-threads=1", "--nocapture"])
            .env(CONFINE_PROBE, dir.path())
            .output()
            .unwrap();
        if String::from_utf8_lossy(&out.stdout).contains("probe=no-landlock") {
            std::io::stderr().write_all(format!("SKIP {}: this kernel has no Landlock\n", THIS_TEST).as_bytes()).ok();
            return;
        }
        let scoped = landlock_abi().is_some_and(|abi| abi >= LANDLOCK_SCOPE_SIGNAL_ABI);
        // socket_before, before and signalled_before are the negative controls: unconfined, the same process holds a socket on 0, writes and signals.
        let expected = format!(
            "socket_before=true nulls=true before=true reopened=false direct=false readable=true signalled_before=true signalled={} fds=[0, 1, 2, 3, 4] cpu={} as={}",
            !scoped,
            sandbox::CPU_SECONDS,
            sandbox::ADDRESS_SPACE_BYTES
        );
        assert_eq!(std::fs::read_to_string(&report).unwrap(), expected, "the probe exited {:?}", out.status);
        assert_eq!(std::fs::read(&victim).unwrap(), b"original");
    }

    #[test]
    fn a_library_that_is_not_there_is_refused() {
        assert!(Decoder::load(c"libflea-definitely-not-here.so.9").is_none());
    }

    #[test]
    fn an_older_abi_is_never_handed_a_right_it_does_not_know() {
        assert_eq!(write_rights(1) & (LANDLOCK_REFER_V2 | LANDLOCK_TRUNCATE_V3), 0);
        assert_eq!(write_rights(2) & LANDLOCK_TRUNCATE_V3, 0);
        assert_ne!(write_rights(3) & LANDLOCK_TRUNCATE_V3, 0);
        // Execute, read file and read dir are bits 0, 2 and 3, and none of them may ever be denied.
        let reads = (1 << 0) | (1 << 2) | (1 << 3);
        for abi in 1..=10 {
            assert_eq!(write_rights(abi) & reads, 0, "abi {} would deny a read", abi);
        }
    }
}
