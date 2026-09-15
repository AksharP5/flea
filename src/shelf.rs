// The drop shelf's own state, and the single-use token a drag out of it carries. The bar widget
// reads shelf.json and never writes it; every write is here, under the same lock discipline ui.json
// takes. DragOut rule 1: no row index crosses the process boundary, only a token bound to entries.
use crate::jsondoc::{self, Json};
use crate::uistore;
use std::fs;
use std::io::Read;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const DIR: &str = "omarchy/flea-shelf";
const PILE: &str = "shelf.json";
const DRAGS: &str = "drags.json";
const DRAGS_LOCK: &str = "drags.json.lock";
const PILE_LOCK: &str = "shelf.json.lock";

// A drag is a gesture, not a session: a token older than this is refused however it was stored.
const TOKEN_LIFE_MS: u64 = 120_000;
// Sixteen bytes of urandom, hex encoded: the token is the only thing standing between a foreign
// process and a move, so it is not a counter and not the clock.
const TOKEN_BYTES: usize = 16;

pub struct Shelf {
    pile: PathBuf,
    pile_lock: PathBuf,
    drags: PathBuf,
    lock: PathBuf,
}

// What a redeemed token asks for: the entries as they were at the lift, and the intent fixed there.
pub struct Redeemed {
    pub moving: bool,
    pub paths: Vec<String>,
}

impl Shelf {
    pub fn user() -> Result<Shelf, String> {
        Ok(Shelf::at(&uistore::state_home()?))
    }

    pub fn at(state_dir: &Path) -> Shelf {
        let dir = state_dir.join(DIR);
        Shelf {
            pile: dir.join(PILE),
            pile_lock: dir.join(PILE_LOCK),
            drags: dir.join(DRAGS),
            lock: dir.join(DRAGS_LOCK),
        }
    }

    pub fn pile_file(&self) -> &Path {
        &self.pile
    }

    // Never fails: the bar draws an empty shelf for a file that is missing or unreadable, and so does this.
    pub fn pile(&self) -> Vec<String> {
        let text = match fs::read_to_string(&self.pile) {
            Ok(text) => text,
            Err(_) => return Vec::new(),
        };
        let doc = match jsondoc::parse(&text) {
            Ok(doc) => doc,
            Err(_) => return Vec::new(),
        };
        let items = match doc.get("items").and_then(Json::as_array) {
            Some(items) => items,
            None => return Vec::new(),
        };
        items.iter().filter_map(|item| item.get("path").and_then(Json::as_str)).map(String::from).collect()
    }

    // Rule 1: the token is bound to the entries and to the intent, both fixed before the platform
    // loop starts, so nothing the drag passes through can change what is being asked for.
    pub fn drag_begin(&self, moving: bool, paths: &[String], now_ms: u64) -> Result<String, String> {
        if paths.is_empty() {
            return Err("a drag carries at least one entry".to_string());
        }
        let token = mint()?;
        let mut entries = Vec::new();
        for path in paths {
            entries.push(entry_of(path)?);
        }
        let record = Json::Obj(vec![
            ("token".to_string(), Json::Str(token.clone())),
            ("intent".to_string(), Json::Str(if moving { "move" } else { "copy" }.to_string())),
            ("created".to_string(), Json::Num(now_ms.to_string())),
            ("entries".to_string(), Json::Arr(entries)),
        ]);
        self.write_drags(|drags| {
            let mut kept = live_drags(drags, now_ms);
            kept.push(record.clone());
            Ok(Json::Obj(vec![("drags".to_string(), Json::Arr(kept))]))
        })?;
        Ok(token)
    }

    // Single use: the record is taken out of the file under the lock, so a replayed token finds
    // nothing. Rule 4: a token that is unknown, expired or already spent is refused outright.
    pub fn redeem(&self, token: &str, now_ms: u64) -> Result<Redeemed, String> {
        let mut found: Option<Json> = None;
        self.write_drags(|drags| {
            let mut kept = Vec::new();
            for drag in live_drags(drags, now_ms) {
                if drag.get("token").and_then(Json::as_str) == Some(token) && found.is_none() {
                    found = Some(drag);
                } else {
                    kept.push(drag);
                }
            }
            Ok(Json::Obj(vec![("drags".to_string(), Json::Arr(kept))]))
        })?;
        let record = found.ok_or_else(|| "that drag is not one this shelf started".to_string())?;
        let moving = record.get("intent").and_then(Json::as_str) == Some("move");
        let entries: Vec<Json> = record.get("entries").and_then(Json::as_array).map(<[Json]>::to_vec).unwrap_or_default();
        let mut paths = Vec::new();
        for entry in &entries {
            paths.push(unchanged(entry)?);
        }
        Ok(Redeemed { moving, paths })
    }

    // Rule 3: the shelf changes only after completion. A copy leaves every reference, a move removes
    // the ones the transfer engine reported moved, and a failure or a cancel leaves the rest. Rule
    // 10: a pinned row is never consumed, so its entry is re-pointed by `repoint` instead.
    pub fn settle(&self, moved: &[String]) -> Result<(), String> {
        if moved.is_empty() {
            return Ok(());
        }
        self.write_pile(|items| {
            items
                .into_iter()
                .filter(|item| match item.get("path").and_then(Json::as_str) {
                    Some(path) => !moved.iter().any(|gone| gone == path) || is_pinned(item),
                    None => false,
                })
                .collect()
        })
    }

    // Which of the paths the shelf holds are pinned, which is what a move has to re-point.
    pub fn pinned_among(&self, paths: &[String]) -> Vec<String> {
        let text = fs::read_to_string(&self.pile).unwrap_or_default();
        let doc = jsondoc::parse(&text).unwrap_or(Json::Obj(Vec::new()));
        let items: Vec<Json> = doc.get("items").and_then(Json::as_array).map(<[Json]>::to_vec).unwrap_or_default();
        items
            .iter()
            .filter(|item| is_pinned(item))
            .filter_map(|item| item.get("path").and_then(Json::as_str))
            .filter(|path| paths.iter().any(|asked| asked == path))
            .map(String::from)
            .collect()
    }

    // Main rule 10: a pinned row is always there. The flag rides the pile's own entry, so the bar's
    // reader needs no second file, and pinning a path the shelf is not holding puts it on first.
    pub fn pin(&self, paths: &[String], pinned: bool) -> Result<(), String> {
        let mut entries = Vec::new();
        for path in paths {
            entries.push(item_of(path)?);
        }
        self.write_pile(move |mut items| {
            for entry in entries {
                let path = entry.get("path").and_then(Json::as_str).map(String::from);
                let mut held = false;
                for item in items.iter_mut() {
                    if item.get("path").and_then(Json::as_str).map(String::from) != path {
                        continue;
                    }
                    held = true;
                    *item = with_pinned(item, pinned);
                }
                if !held && pinned {
                    items.push(with_pinned(&entry, true));
                }
            }
            items
        })
    }

    // Rule 10 again: Move on a pinned row moves the file and the pin follows it to the new path.
    pub fn repoint(&self, moved: &[(String, String)]) -> Result<(), String> {
        if moved.is_empty() {
            return Ok(());
        }
        self.write_pile(|items| {
            items
                .into_iter()
                .map(|item| {
                    let path = item.get("path").and_then(Json::as_str).unwrap_or_default().to_string();
                    match moved.iter().find(|(from, _)| *from == path) {
                        Some((_, to)) => with_path(&item, to),
                        None => item,
                    }
                })
                .collect()
        })
    }

    // Actions rule 6: Add to shelf is the same call a drop makes, and a path the shelf already holds
    // is not added twice, because what the shelf holds is a reference and not a copy.
    pub fn add(&self, paths: &[String]) -> Result<(), String> {
        let mut entries = Vec::new();
        for path in paths {
            entries.push(item_of(path)?);
        }
        self.write_pile(move |mut items| {
            for entry in entries {
                let path = entry.get("path").and_then(Json::as_str).map(String::from);
                let held = items
                    .iter()
                    .any(|item| item.get("path").and_then(Json::as_str).map(String::from) == path);
                if !held {
                    items.push(entry);
                }
            }
            items
        })
    }

    // Summon: clearing takes the whole pile out and hands it back, so the caller can keep it as the
    // last pile. Read and write are one locked step, or a drop landing meanwhile would be lost.
    pub fn clear(&self) -> Result<Vec<Json>, String> {
        let mut taken = Vec::new();
        self.write_pile(|items| {
            taken = items;
            Vec::new()
        })?;
        Ok(taken)
    }

    // And putting one back: what the pile was comes back, so a pile that was not empty becomes the
    // last pile in its turn rather than disappearing under the one being restored.
    pub fn put(&self, pile: Vec<Json>) -> Result<Vec<Json>, String> {
        let mut was = Vec::new();
        self.write_pile(|items| {
            was = items;
            pile
        })?;
        Ok(was)
    }

    // Every write of the pile goes through one lock, so a click that adds and a move that settles
    // cannot land on top of each other.
    fn write_pile(&self, change: impl FnOnce(Vec<Json>) -> Vec<Json>) -> Result<(), String> {
        let dir = self.pile.parent().ok_or("the shelf has no directory to write in")?;
        uistore::make_dir(dir)?;
        let lock = uistore::take_lock(&self.pile_lock)?;
        let text = fs::read_to_string(&self.pile).unwrap_or_default();
        let doc = jsondoc::parse(&text).unwrap_or(Json::Obj(Vec::new()));
        let items: Vec<Json> = doc.get("items").and_then(Json::as_array).map(<[Json]>::to_vec).unwrap_or_default();
        let next = Json::Obj(vec![("items".to_string(), Json::Arr(change(items)))]);
        let written = uistore::replace(&self.pile, &jsondoc::render(&next));
        lock.unlock().map_err(|e| format!("{} could not be unlocked ({:?})", self.pile_lock.display(), e.kind()))?;
        written
    }

    fn write_drags(&self, change: impl FnOnce(&Json) -> Result<Json, String>) -> Result<(), String> {
        let dir = self.drags.parent().ok_or("the shelf has no directory to write in")?;
        uistore::make_dir(dir)?;
        let lock = uistore::take_lock(&self.lock)?;
        let current = fs::read_to_string(&self.drags)
            .ok()
            .and_then(|text| jsondoc::parse(&text).ok())
            .unwrap_or(Json::Obj(Vec::new()));
        let next = change(&current)?;
        let written = uistore::replace(&self.drags, &jsondoc::render(&next));
        lock.unlock().map_err(|e| format!("{} could not be unlocked ({:?})", self.lock.display(), e.kind()))?;
        written
    }
}

// Every drag still inside its own lifetime, so an abandoned gesture cannot be redeemed later.
fn live_drags(drags: &Json, now_ms: u64) -> Vec<Json> {
    drags
        .get("drags")
        .and_then(Json::as_array)
        .map(|list| {
            list.iter()
                .filter(|drag| match drag.get("created").and_then(Json::as_f64) {
                    Some(created) => now_ms.saturating_sub(created as u64) < TOKEN_LIFE_MS,
                    None => false,
                })
                .cloned()
                .collect()
        })
        .unwrap_or_default()
}

pub fn is_pinned(item: &Json) -> bool {
    item.get("pinned").and_then(Json::as_bool) == Some(true)
}

// An entry with one field changed, because a pile entry is rewritten rather than edited in place.
fn with_pinned(item: &Json, pinned: bool) -> Json {
    rebuilt(item, |name| name != "pinned", vec![("pinned".to_string(), Json::Bool(pinned))])
}

fn with_path(item: &Json, path: &str) -> Json {
    rebuilt(item, |name| name != "path", vec![("path".to_string(), Json::Str(path.to_string()))])
}

fn rebuilt(item: &Json, keep: impl Fn(&str) -> bool, mut added: Vec<(String, Json)>) -> Json {
    let mut fields: Vec<(String, Json)> = match item {
        Json::Obj(fields) => fields.iter().filter(|(name, _)| keep(name)).cloned().collect(),
        _ => Vec::new(),
    };
    fields.append(&mut added);
    Json::Obj(fields)
}

// A pile entry: the path the shelf holds and whether the card draws it as a folder. The size is not
// recorded, because the card asks for it per drawn row and a folder's answer goes stale on its own.
fn item_of(path: &str) -> Result<Json, String> {
    let full = std::path::absolute(path).map_err(|e| format!("{} could not be read ({:?})", path, e.kind()))?;
    let meta = fs::symlink_metadata(&full).map_err(|e| format!("{} could not be read ({:?})", path, e.kind()))?;
    Ok(Json::Obj(vec![
        ("path".to_string(), Json::Str(full.to_string_lossy().to_string())),
        ("folder".to_string(), Json::Bool(meta.is_dir())),
    ]))
}

// The source identity the lift recorded, which is what makes a token name a file rather than a name.
fn entry_of(path: &str) -> Result<Json, String> {
    let meta = fs::symlink_metadata(path).map_err(|e| format!("{} could not be read ({:?})", path, e.kind()))?;
    Ok(Json::Obj(vec![
        ("path".to_string(), Json::Str(path.to_string())),
        ("dev".to_string(), Json::Num(meta.dev().to_string())),
        ("ino".to_string(), Json::Num(meta.ino().to_string())),
        ("bytes".to_string(), Json::Num(meta.len().to_string())),
    ]))
}

// The same file, or the drag is refused: a path that now names another inode is not what was lifted.
fn unchanged(entry: &Json) -> Result<String, String> {
    let path = entry.get("path").and_then(Json::as_str).ok_or("a drag entry with no path")?;
    let meta = fs::symlink_metadata(path).map_err(|_| format!("{} is no longer there", path))?;
    let same = entry.get("dev").and_then(Json::as_f64) == Some(meta.dev() as f64)
        && entry.get("ino").and_then(Json::as_f64) == Some(meta.ino() as f64);
    if !same {
        return Err(format!("{} is not the file the shelf was holding", path));
    }
    Ok(path.to_string())
}

fn mint() -> Result<String, String> {
    let mut bytes = [0u8; TOKEN_BYTES];
    let mut source = fs::File::open("/dev/urandom").map_err(|e| format!("no randomness for a drag token ({:?})", e.kind()))?;
    source.read_exact(&mut bytes).map_err(|e| format!("short read of randomness ({:?})", e.kind()))?;
    Ok(bytes.iter().map(|b| format!("{:02x}", b)).collect())
}

pub fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

// Main rule 4's budget: the card asks about one path it is drawing, so this answers one path. A
// directory takes the listing's own bounded walk, which is why a floor comes back marked partial and
// the card draws it with the same > prefix a list row does.
pub fn size_of(path: &str) -> Result<(u64, bool), String> {
    let meta = fs::symlink_metadata(path).map_err(|e| format!("{} could not be read ({:?})", path, e.kind()))?;
    if meta.is_dir() {
        let walked = crate::backend::dirsize::walk(Path::new(path));
        return Ok((walked.bytes, walked.partial));
    }
    Ok((meta.len(), false))
}

#[cfg(test)]
#[path = "shelf_tests.rs"]
mod tests;
