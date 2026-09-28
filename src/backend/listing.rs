// One buffer plus a span each, see AGENTS.md "Why the listing is an arena".
use std::collections::HashMap;
use std::path::{Component, Path};

// One gio row's figures in 24 bytes, keyed by its span's name offset, which every sort carries along.
#[derive(Clone, Copy, Debug)]
pub struct GioMeta {
    pub name_off: u32,
    pub mode: u32,
    pub size: u64,
    pub mtime: i64,
}

// A symlink row's target keyed by the same offset; only symlink rows have one.
#[derive(Clone, Debug)]
pub struct GioTarget {
    pub name_off: u32,
    pub target: String,
}

// Enough that a normal directory never reallocates its way up from nothing.
const NAME_RESERVE_BYTES: usize = 1 << 20;
const SPAN_RESERVE: usize = 4096;
// vfat's statfs magic, see linux/magic.h MSDOS_SUPER_MAGIC.
const MSDOS_SUPER_MAGIC: i64 = 0x4D44;
// exfat's statfs magic, see linux/magic.h EXFAT_SUPER_MAGIC.
const EXFAT_SUPER_MAGIC: i64 = 0x2011BAB0;

#[derive(Clone, Copy, Debug)]
pub struct Span {
    pub off: u32,
    pub len: u32,
    pub is_dir: bool,
    pub is_symlink: bool,
}

#[derive(Debug)]
pub struct Listing {
    pub names: String,
    pub spans: Vec<Span>,
    // Empty for readdir listings; the gvfs path fills it, so local rows pay no store.
    pub gio_meta: Vec<GioMeta>,
    pub gio_targets: Vec<GioTarget>,
    // The directory's device once per listing; every cached row takes this dev.
    pub base_dev: u64,
    // One statfs f_type per listing, so every window reuses it instead of adding one.
    pub fs_magic: Option<i64>,
}

impl Listing {
    pub fn new() -> Listing {
        let mut names = String::new();
        names.reserve(NAME_RESERVE_BYTES);
        let mut spans = Vec::new();
        spans.reserve(SPAN_RESERVE);
        Listing { names, spans, gio_meta: Vec::new(), gio_targets: Vec::new(), base_dev: 0, fs_magic: None }
    }

    // corner: u32 offsets cap the arena at 4 GiB of names, see AGENTS.md.
    pub fn push(&mut self, name: &str, is_dir: bool) {
        let off = self.names.len() as u32;
        self.names.push_str(name);
        self.spans.push(Span {
            off,
            len: (self.names.len() as u32) - off,
            is_dir,
            is_symlink: false,
        });
    }

    pub fn name(&self, i: usize) -> &str {
        let s = &self.spans[i];
        &self.names[s.off as usize..(s.off + s.len) as usize]
    }

    // The seam: callers ask the listing; spans is public only because sort borrows it.
    pub fn is_dir(&self, i: usize) -> bool {
        self.spans[i].is_dir
    }

    // A cached gio row by its listing index: the span's offset binary searched in build order.
    pub fn gio_for(&self, i: usize) -> Option<&GioMeta> {
        let off = self.spans.get(i)?.off;
        self.gio_meta.binary_search_by_key(&off, |m| m.name_off).ok().map(|at| &self.gio_meta[at])
    }

    // A cached symlink's target by the same offset; empty for every other row.
    pub fn gio_target(&self, name_off: u32) -> &str {
        self.gio_targets.binary_search_by_key(&name_off, |t| t.name_off).ok().map(|at| self.gio_targets[at].target.as_str()).unwrap_or("")
    }

    pub fn len(&self) -> usize {
        self.spans.len()
    }

    // Locate only names already in this listing; no filesystem access or symlink resolution.
    pub fn index_of(&self, base: &Path, path: &Path) -> Option<usize> {
        let name = relative_name(base, path)?;
        (0..self.len()).find(|&index| self.name(index) == name)
    }

    pub fn indices_of<'a>(&self, base: &Path, paths: &'a [String]) -> Vec<(&'a str, usize)> {
        let mut wanted: HashMap<&str, &str> = paths.iter().filter_map(|path|
            relative_name(base, Path::new(path)).map(|name| (name, path.as_str()))).collect();
        let mut found = Vec::new();
        for index in 0..self.len() {
            if let Some(path) = wanted.remove(self.name(index)) { found.push((path, index)); }
            if wanted.is_empty() { break; }
        }
        found
    }
}

fn relative_name<'a>(base: &Path, path: &'a Path) -> Option<&'a str> {
    if !base.is_absolute() || !path.is_absolute() { return None; }
    let relative = path.strip_prefix(base).ok()?;
    if relative.components().any(|part| !matches!(part, Component::Normal(_))) { return None; }
    relative.to_str()
}

// Sample input: Some(0x4D44) answers false, Some(0x65735546) and None answer true.
pub fn threaded_for(magic: Option<i64>) -> bool {
    !matches!(magic, Some(m) if m == MSDOS_SUPER_MAGIC || m == EXFAT_SUPER_MAGIC)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn symlink_type_uses_the_existing_span_padding() {
        #[allow(dead_code)]
        struct OriginalSpan { off: u32, len: u32, is_dir: bool }
        assert_eq!(std::mem::size_of::<Span>(), std::mem::size_of::<OriginalSpan>());
    }

    #[test]
    fn stores_and_returns_names_in_order() {
        let mut l = Listing::new();
        l.push("alpha.txt", false);
        l.push("bin", true);
        assert_eq!(l.len(), 2);
        assert_eq!(l.name(0), "alpha.txt");
        assert_eq!(l.name(1), "bin");
        assert!(!l.is_dir(0));
        assert!(l.is_dir(1));
    }

    #[test]
    fn a_new_listing_is_empty() {
        let l = Listing::new();
        assert_eq!(l.len(), 0);
    }

    #[test]
    fn locates_existing_names_without_resolving_files() {
        let base = Path::new("/listing");
        let mut listing = Listing::new();
        listing.push("first.txt", false);
        listing.push("sub/selected.txt", false);
        assert_eq!(listing.index_of(base, Path::new("/listing/sub/selected.txt")), Some(1));
        listing.spans.reverse();
        assert_eq!(listing.index_of(base, Path::new("/listing/sub/selected.txt")), Some(0));
        for path in ["", "sub/selected.txt", "/listing", "/listing/missing", "/listing-other/first.txt", "/listing/../listing/first.txt"] {
            assert_eq!(listing.index_of(base, Path::new(path)), None, "{path}");
        }
        assert_eq!(listing.index_of(Path::new(""), Path::new("/first.txt")), None);
    }

    #[test]
    fn batched_lookup_scans_names_once_and_deduplicates_matches() {
        let mut listing = Listing::new();
        for name in ["a", "sub/b", "quote\"\n"] { listing.push(name, false); }
        let paths = ["/listing/sub/b", "/listing/missing", "/listing/a", "/listing/a",
            "/listing/../listing/a", "/listing-other/a", "a", "/listing/quote\"\n"]
            .map(String::from);
        assert_eq!(listing.indices_of(Path::new("/listing"), &paths),
            vec![("/listing/a", 0), ("/listing/sub/b", 1), ("/listing/quote\"\n", 2)]);
        assert!(listing.indices_of(Path::new("/listing"), &[]).is_empty());
        assert!(listing.indices_of(Path::new("relative"), &paths).is_empty());
    }

    #[test]
    fn handles_names_with_awkward_bytes() {
        let mut l = Listing::new();
        l.push("two\nlines", false);
        l.push("quote\"inside", false);
        l.push("café", false);
        assert_eq!(l.name(0), "two\nlines");
        assert_eq!(l.name(1), "quote\"inside");
        assert_eq!(l.name(2), "café");
    }

    #[test]
    fn one_buffer_holds_every_name() {
        let mut l = Listing::new();
        for i in 0..1000 {
            l.push(&format!("file_{}.txt", i), false);
        }
        assert_eq!(l.len(), 1000);
        assert_eq!(l.name(999), "file_999.txt");
    }

    #[test]
    fn fat_magic_stays_serial_while_fuse_cifs_and_unknown_thread() {
        assert!(!threaded_for(Some(0x4D44)), "vfat stays serial");
        assert!(!threaded_for(Some(0x2011BAB0)), "exfat stays serial");
        assert!(threaded_for(Some(0x65735546)), "fuse keeps today's threads");
        assert!(threaded_for(Some(0xFF534D42)), "cifs keeps today's threads");
        assert!(threaded_for(Some(0xFE534D42)), "smb2 keeps today's threads");
        assert!(threaded_for(Some(0x6969)), "nfs keeps today's threads");
        assert!(threaded_for(Some(0xEF53)), "ext4 keeps today's threads");
        assert!(threaded_for(None), "unknown keeps today's threads");
    }
}
