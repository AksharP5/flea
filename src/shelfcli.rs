// The shelf's verbs as a command, because the plugin is another process: `flea shelf <verb>` is the
// only way in, and every mutation of the pile is on this side of it.
use crate::captures;
use crate::shelf::{now_ms, size_of, Shelf};
use crate::summon;

pub fn command(args: &[String]) -> i32 {
    match args.get(2).map(String::as_str) {
        Some("drag-begin") => drag_begin(&args[3..]),
        Some("size") => size(&args[3..]),
        Some("forget") => forget(&args[3..]),
        Some("add") => add(&args[3..]),
        Some("captures") => captures::command(&args[3..]),
        Some("clear") => summon::clear(),
        Some("restore") => summon::restore(&args[3..]),
        Some("piles") => summon::piles(),
        Some("toggle") => summon::toggle(),
        Some("bind") => summon::bind(),
        _ => {
            eprintln!("flea: shelf takes drag-begin, size, add, forget, captures, clear, restore, piles, toggle or bind");
            2
        }
    }
}

fn size(rest: &[String]) -> i32 {
    let path = match rest.first() {
        Some(path) => path,
        None => {
            eprintln!("flea: shelf size takes one path");
            return 2;
        }
    };
    match size_of(path) {
        Ok((bytes, partial)) => {
            println!("{} {}", bytes, u8::from(partial));
            0
        }
        Err(e) => {
            eprintln!("flea: {}", e);
            2
        }
    }
}

fn add(rest: &[String]) -> i32 {
    if rest.is_empty() {
        eprintln!("flea: shelf add takes at least one path");
        return 2;
    }
    let shelf = match Shelf::user() {
        Ok(shelf) => shelf,
        Err(e) => {
            eprintln!("flea: {}", e);
            return 2;
        }
    };
    match shelf.add(rest) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("flea: {}", e);
            2
        }
    }
}

fn forget(rest: &[String]) -> i32 {
    if rest.is_empty() {
        eprintln!("flea: shelf forget takes at least one path");
        return 2;
    }
    let shelf = match Shelf::user() {
        Ok(shelf) => shelf,
        Err(e) => {
            eprintln!("flea: {}", e);
            return 2;
        }
    };
    // Main rule 6: the row's own x is the same edit a completed move makes, and it never touches the file.
    match shelf.settle(rest) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("flea: {}", e);
            2
        }
    }
}

fn drag_begin(rest: &[String]) -> i32 {
    let moving = match rest.first().map(String::as_str) {
        Some("move") => true,
        Some("copy") => false,
        _ => {
            eprintln!("flea: shelf drag-begin takes move or copy, then the entries");
            return 2;
        }
    };
    let paths: Vec<String> = rest[1..].to_vec();
    let shelf = match Shelf::user() {
        Ok(shelf) => shelf,
        Err(e) => {
            eprintln!("flea: {}", e);
            return 2;
        }
    };
    match shelf.drag_begin(moving, &paths, now_ms()) {
        Ok(token) => {
            println!("{}", token);
            0
        }
        Err(e) => {
            eprintln!("flea: {}", e);
            2
        }
    }
}

