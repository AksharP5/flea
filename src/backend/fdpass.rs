// Descriptors over a local socket, which is how the thumbnail worker is handed one job's two files
// without being able to see a single path; see AGENTS.md "Thumbnail worker".
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::os::raw::{c_int, c_void};

// socket(2) and cmsg(3) constants, x86_64 Linux: AF_UNIX, SOCK_SEQPACKET so a message keeps its
// bounds, SOCK_CLOEXEC so no exec'd child inherits either end, and SCM_RIGHTS on SOL_SOCKET.
const AF_UNIX: c_int = 1;
const SOCK_SEQPACKET: c_int = 5;
const SOCK_CLOEXEC: c_int = 0o2000000;
const SOL_SOCKET: c_int = 1;
const SCM_RIGHTS: c_int = 1;
// recvmsg(2): received descriptors arrive close-on-exec, and a peer gone is EPIPE and not SIGPIPE.
const MSG_CMSG_CLOEXEC: c_int = 0x4000_0000;
const MSG_NOSIGNAL: c_int = 0x4000;
// recvmsg(2) sets this when the control buffer was too small and descriptors were dropped.
const MSG_CTRUNC: c_int = 0x8;
// A job carries exactly three: the input, the output and the reply socket.
pub const MAX_FDS: usize = 3;
// cmsghdr is 16 bytes on x86_64 and its payload is padded to 8, so three ints take CMSG_SPACE(12) = 32.
const CMSG_HEADER: usize = 16;
const CMSG_SPACE: usize = 32;
// The largest request payload either side ever sends.
pub const MAX_PAYLOAD: usize = 16;

#[repr(C)]
struct IoVec {
    base: *mut c_void,
    len: usize,
}

// struct msghdr as glibc lays it out on x86_64; repr(C) supplies the padding after msg_namelen.
#[repr(C)]
struct MsgHdr {
    name: *mut c_void,
    namelen: u32,
    iov: *mut IoVec,
    iovlen: usize,
    control: *mut c_void,
    controllen: usize,
    flags: c_int,
}

// The control buffer has to sit on cmsghdr's own 8-byte alignment.
#[repr(C, align(8))]
struct Control([u8; CMSG_SPACE]);

// std already links the system libc, so the three symbols are declared here rather than taking a crate.
extern "C" {
    fn socketpair(domain: c_int, kind: c_int, protocol: c_int, sv: *mut [c_int; 2]) -> c_int;
    fn sendmsg(fd: c_int, msg: *const MsgHdr, flags: c_int) -> isize;
    fn recvmsg(fd: c_int, msg: *mut MsgHdr, flags: c_int) -> isize;
}

// Both ends close on exec, so the only process that ever holds the far end is the one it is handed to.
pub fn pair() -> std::io::Result<(OwnedFd, OwnedFd)> {
    let mut fds: [c_int; 2] = [-1, -1];
    if unsafe { socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, &mut fds) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(unsafe { (OwnedFd::from_raw_fd(fds[0]), OwnedFd::from_raw_fd(fds[1])) })
}

// One message: the payload bytes and up to MAX_FDS descriptors, which the kernel duplicates into the receiver.
pub fn send(sock: RawFd, payload: &[u8], fds: &[RawFd]) -> std::io::Result<()> {
    assert!(fds.len() <= MAX_FDS && !payload.is_empty() && payload.len() <= MAX_PAYLOAD);
    let mut iov = IoVec { base: payload.as_ptr() as *mut c_void, len: payload.len() };
    let mut control = Control([0; CMSG_SPACE]);
    let data_len = std::mem::size_of_val(fds);
    let mut msg = MsgHdr {
        name: std::ptr::null_mut(),
        namelen: 0,
        iov: &mut iov,
        iovlen: 1,
        control: std::ptr::null_mut(),
        controllen: 0,
        flags: 0,
    };
    if !fds.is_empty() {
        // cmsghdr: cmsg_len (size_t), cmsg_level (int), cmsg_type (int), then the ints themselves.
        let buf = &mut control.0;
        buf[0..8].copy_from_slice(&((CMSG_HEADER + data_len) as u64).to_ne_bytes());
        buf[8..12].copy_from_slice(&SOL_SOCKET.to_ne_bytes());
        buf[12..16].copy_from_slice(&SCM_RIGHTS.to_ne_bytes());
        for (i, fd) in fds.iter().enumerate() {
            let at = CMSG_HEADER + i * 4;
            buf[at..at + 4].copy_from_slice(&fd.to_ne_bytes());
        }
        msg.control = control.0.as_mut_ptr() as *mut c_void;
        msg.controllen = CMSG_SPACE;
    }
    let sent = unsafe { sendmsg(sock, &msg, MSG_NOSIGNAL) };
    if sent < 0 {
        return Err(std::io::Error::last_os_error());
    }
    if sent as usize != payload.len() {
        return Err(std::io::Error::new(std::io::ErrorKind::WriteZero, "a short send on a packet socket"));
    }
    Ok(())
}

// What one recvmsg returned: the payload and the descriptors, each already owned so none can leak.
pub struct Received {
    pub payload: Vec<u8>,
    pub fds: Vec<OwnedFd>,
}

// Ok(None) is an orderly end: the peer closed its side.
pub fn recv(sock: RawFd) -> std::io::Result<Option<Received>> {
    let mut bytes = [0u8; MAX_PAYLOAD];
    let mut iov = IoVec { base: bytes.as_mut_ptr() as *mut c_void, len: bytes.len() };
    let mut control = Control([0; CMSG_SPACE]);
    let mut msg = MsgHdr {
        name: std::ptr::null_mut(),
        namelen: 0,
        iov: &mut iov,
        iovlen: 1,
        control: control.0.as_mut_ptr() as *mut c_void,
        controllen: CMSG_SPACE,
        flags: 0,
    };
    let got = unsafe { recvmsg(sock, &mut msg, MSG_CMSG_CLOEXEC) };
    if got < 0 {
        return Err(std::io::Error::last_os_error());
    }
    if got == 0 {
        return Ok(None);
    }
    let fds = descriptors(&control.0, msg.controllen);
    // Descriptors that did not fit were closed by the kernel, so the message is not the one that was sent.
    if msg.flags & MSG_CTRUNC != 0 {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "the descriptors did not fit"));
    }
    Ok(Some(Received { payload: bytes[..got as usize].to_vec(), fds }))
}

// Sample input, three descriptors: cmsg_len 28, SOL_SOCKET, SCM_RIGHTS, then the ints 7, 8 and 9.
fn descriptors(buf: &[u8; CMSG_SPACE], filled: usize) -> Vec<OwnedFd> {
    let mut out = Vec::new();
    if filled < CMSG_HEADER {
        return out;
    }
    let len = u64::from_ne_bytes(buf[0..8].try_into().unwrap()) as usize;
    let level = c_int::from_ne_bytes(buf[8..12].try_into().unwrap());
    let kind = c_int::from_ne_bytes(buf[12..16].try_into().unwrap());
    if level != SOL_SOCKET || kind != SCM_RIGHTS || len < CMSG_HEADER || len > filled {
        return out;
    }
    let count = ((len - CMSG_HEADER) / 4).min(MAX_FDS);
    for i in 0..count {
        let at = CMSG_HEADER + i * 4;
        let fd = c_int::from_ne_bytes(buf[at..at + 4].try_into().unwrap());
        if fd >= 0 {
            out.push(unsafe { OwnedFd::from_raw_fd(fd) });
        }
    }
    out
}

// The one-byte answers both sides trade, written as plain packets with no descriptors.
pub fn send_byte(sock: &OwnedFd, byte: u8) -> std::io::Result<()> {
    send(sock.as_raw_fd(), &[byte], &[])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;
    use std::os::unix::fs::MetadataExt;

    fn inode(fd: &OwnedFd) -> (u64, u64) {
        let file = std::fs::File::from(fd.try_clone().unwrap());
        let m = file.metadata().unwrap();
        (m.dev(), m.ino())
    }

    #[test]
    fn three_descriptors_arrive_as_the_same_files() {
        let dir = TestDir::new("fdpass-three");
        let names = ["a", "b", "c"];
        let files: Vec<OwnedFd> = names
            .iter()
            .map(|n| {
                std::fs::write(dir.join(n), n.as_bytes()).unwrap();
                OwnedFd::from(std::fs::File::open(dir.join(n)).unwrap())
            })
            .collect();
        let (left, right) = pair().unwrap();
        let raw: Vec<RawFd> = files.iter().map(|f| f.as_raw_fd()).collect();
        send(left.as_raw_fd(), &[1, 2, 3], &raw).unwrap();
        let got = recv(right.as_raw_fd()).unwrap().expect("a message");
        assert_eq!(got.payload, vec![1, 2, 3]);
        assert_eq!(got.fds.len(), 3);
        for (sent, arrived) in files.iter().zip(got.fds.iter()) {
            assert_eq!(inode(sent), inode(arrived), "a descriptor arrived pointing at another file");
            assert_ne!(sent.as_raw_fd(), arrived.as_raw_fd(), "the kernel hands back new numbers");
        }
    }

    #[test]
    fn a_closed_peer_reads_as_an_orderly_end() {
        let (left, right) = pair().unwrap();
        drop(left);
        assert!(recv(right.as_raw_fd()).unwrap().is_none());
    }

    #[test]
    fn a_plain_byte_carries_no_descriptors() {
        let (left, right) = pair().unwrap();
        send_byte(&left, b'S').unwrap();
        let got = recv(right.as_raw_fd()).unwrap().unwrap();
        assert_eq!(got.payload, b"S");
        assert!(got.fds.is_empty());
    }
}
