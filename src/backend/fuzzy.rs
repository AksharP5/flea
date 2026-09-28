// The scoring half of docs/protocol.md "search": a home-directory subsequence match needs ranking by run, boundary and basename to stay usable.
use crate::backend::sort::name_order;
use std::cmp::Ordering;

// A character matching right after the previous one, which is what makes a contiguous run win.
const BONUS_CONSECUTIVE: i32 = 8;
// The first character of the candidate, of a path segment, of a word, or of a camelCase hump.
const BONUS_BOUNDARY: i32 = 6;
// The match is in the file's own name rather than in a parent directory the query merely passed through.
const BONUS_BASENAME: i32 = 4;
// Charged per candidate character skipped between two matches, so a scattered match sinks.
const PENALTY_GAP: i32 = 1;
// Past this many first-character occurrences only the first ones score: an unseen alignment is not worth an unbounded scan.
const MAX_STARTS: usize = 16;

// The characters a word or a path segment starts after.
fn is_separator(c: char) -> bool {
    c == '/' || c == '-' || c == '_' || c == '.' || c == ' '
}

// One candidate character folded once per candidate for index comparison; a multi-char lowercase (Turkish dotted capital I) keeps only its first, matching ui/js/Match.js.
#[derive(Clone, Copy)]
struct Folded {
    lower: char,
    upper: bool,
}

fn fold(c: char) -> Folded {
    let lower = c.to_lowercase().next().unwrap_or(c);
    Folded { lower, upper: lower != c }
}

// Where the candidate's own name begins: the character after its last path separator.
fn base_start(hay: &[Folded]) -> usize {
    let mut start = 0;
    for (i, c) in hay.iter().enumerate() {
        if c.lower == '/' {
            start = i + 1;
        }
    }
    start
}

// The folded query plus one reusable candidate buffer, so a subtree walk allocates twice rather than once per entry.
pub struct Fuzzy {
    needle: Vec<char>,
    hay: Vec<Folded>,
}

impl Fuzzy {
    pub fn new(query: &str) -> Fuzzy {
        Fuzzy {
            needle: query.to_lowercase().chars().collect(),
            hay: Vec::new(),
        }
    }

    // None means the query is no subsequence of the candidate; Some carries the best alignment's score, higher winning.
    pub fn score(&mut self, candidate: &str) -> Option<i32> {
        // An empty query matches everything, which is what an empty search line shows.
        if self.needle.is_empty() {
            return Some(0);
        }
        self.hay.clear();
        self.hay.extend(candidate.chars().map(fold));
        let base = base_start(&self.hay);
        let first = self.needle[0];
        let mut best: Option<i32> = None;
        let mut starts = 0;
        for i in 0..self.hay.len() {
            if self.hay[i].lower != first {
                continue;
            }
            match self.score_from(i, base) {
                Some(s) => best = Some(best.map_or(s, |b| if s > b { s } else { b })),
                // A greedy scan takes the earliest position per character, so a start that cannot finish means no later start can.
                None => return best,
            }
            starts += 1;
            if starts == MAX_STARTS {
                break;
            }
        }
        best
    }

    // Greedy alignment from one start: each needle character takes its next match, the hand-traced alignment.
    fn score_from(&self, start: usize, base: usize) -> Option<i32> {
        let mut total = 0;
        let mut at = start;
        let mut previous: Option<usize> = None;
        for k in 0..self.needle.len() {
            if k > 0 {
                at += 1;
                while at < self.hay.len() && self.hay[at].lower != self.needle[k] {
                    at += 1;
                }
                if at == self.hay.len() {
                    return None;
                }
            }
            total += self.character_score(at, base, previous);
            previous = Some(at);
        }
        Some(total)
    }

    // One matched character's worth: run, boundary and basename bonuses minus the gap charge.
    fn character_score(&self, at: usize, base: usize, previous: Option<usize>) -> i32 {
        let mut score = 0;
        match previous {
            Some(p) if at == p + 1 => score += BONUS_CONSECUTIVE,
            Some(p) => score -= PENALTY_GAP * ((at - p - 1) as i32),
            None => {}
        }
        if self.starts_a_word(at) {
            score += BONUS_BOUNDARY;
        }
        if at >= base {
            score += BONUS_BASENAME;
        }
        score
    }

    fn starts_a_word(&self, at: usize) -> bool {
        if at == 0 {
            return true;
        }
        let before = self.hay[at - 1];
        is_separator(before.lower) || (self.hay[at].upper && !before.upper)
    }
}

// Result order: better score, then shorter path, then name order, so one walk answers in exactly one order.
pub fn rank_order(a_score: i32, a_name: &str, b_score: i32, b_name: &str) -> Ordering {
    match b_score.cmp(&a_score) {
        Ordering::Equal => {}
        other => return other,
    }
    match a_name.len().cmp(&b_name.len()) {
        Ordering::Equal => {}
        other => return other,
    }
    name_order(a_name.as_bytes(), b_name.as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn score(hay: &str, query: &str) -> Option<i32> {
        Fuzzy::new(query).score(hay)
    }

    #[test]
    fn the_operators_own_example_matches_across_the_separator() {
        // "dwnhelp should find downloads/helper.txt", which substring matching never could.
        assert!(score("downloads/helper.txt", "dwnhelp").is_some());
        assert!(score("downloads/helper.txt", "help").is_some());
        assert!(score("downloads/helper.txt", "zzz").is_none());
    }

    #[test]
    fn a_query_out_of_order_is_not_a_match() {
        assert!(score("helper.txt", "pleh").is_none());
        assert!(score("abc", "abcd").is_none());
    }

    #[test]
    fn case_folds_both_ways_including_beyond_ascii() {
        assert!(score("Bench-Notes.md", "bench").is_some());
        assert!(score("BENCH", "bench").is_some());
        assert!(score("CAFÉ.txt", "café").is_some());
        assert!(score("café.txt", "CAFÉ").is_some());
    }

    #[test]
    fn an_empty_query_matches_every_candidate() {
        assert_eq!(score("anything", ""), Some(0));
        assert_eq!(score("", ""), Some(0));
    }

    #[test]
    fn a_contiguous_run_beats_a_scattered_one() {
        let s_run = score("report.txt", "rep").unwrap();
        let s_scattered = score("raspberry-pie.txt", "rep").unwrap();
        assert!(s_run > s_scattered, "run {} scattered {}", s_run, s_scattered);
    }

    #[test]
    fn a_boundary_start_beats_one_inside_a_word() {
        let s_boundary = score("my-notes.txt", "notes").unwrap();
        let s_inside = score("bignotes.txt", "notes").unwrap();
        assert!(s_boundary > s_inside, "boundary {} inside {}", s_boundary, s_inside);
    }

    #[test]
    fn a_camel_hump_counts_as_a_boundary() {
        let s_hump = score("SearchStrip.qml", "strip").unwrap();
        let s_flat = score("searchstrip.qml", "strip").unwrap();
        assert!(s_hump > s_flat, "hump {} flat {}", s_hump, s_flat);
    }

    #[test]
    fn a_match_in_the_name_beats_one_in_a_parent_directory() {
        let s_name = score("notes/bench.txt", "bench").unwrap();
        let s_parent = score("bench/notes.txt", "bench").unwrap();
        assert!(s_name > s_parent, "name {} parent {}", s_name, s_parent);
    }

    #[test]
    fn a_later_start_can_score_better_than_the_first_one() {
        // The first "a" is at 0, but the alignment that reads "ab" contiguously starts at 3.
        let s = score("axxab", "ab").unwrap();
        let greedy_only = score("axxb", "ab").unwrap();
        assert!(s > greedy_only, "restarted {} greedy {}", s, greedy_only);
    }

    #[test]
    fn a_pathological_name_is_scored_from_a_bounded_number_of_starts() {
        let hay = "a".repeat(4096);
        // Bounded work, and still the right answer: every start scores the same here.
        assert!(score(&hay, "aa").is_some());
    }

    #[test]
    fn the_rank_order_is_total_so_one_tree_answers_in_one_order() {
        assert_eq!(rank_order(9, "a.txt", 4, "b.txt"), Ordering::Less);
        assert_eq!(rank_order(4, "a.txt", 9, "b.txt"), Ordering::Greater);
        assert_eq!(rank_order(4, "a.txt", 4, "bb.txt"), Ordering::Less);
        assert_eq!(rank_order(4, "b.txt", 4, "a.txt"), Ordering::Greater);
        assert_eq!(rank_order(4, "a.txt", 4, "a.txt"), Ordering::Equal);
    }

    // Sample input: ["report.txt", "rep", 34] or [bounded + "ab", "ab", 6], one row per entry of the SCORES array below.
    fn js_scores(src: &str, bounded: &str) -> Vec<(String, String, Option<i32>)> {
        let table = src.split("var SCORES = [").nth(1).expect("tests/js/jump.js carries SCORES").split("]]").next().expect("SCORES closes");
        let mut out = Vec::new();
        for entry in table.split("],") {
            let entry = entry.trim().trim_start_matches('[').trim();
            if entry.is_empty() { continue; }
            let (hay, rest) = match entry.strip_prefix('"') {
                Some(quoted) => {
                    let end = quoted.find('"').expect("a SCORES row closes its file");
                    (quoted[..end].to_string(), &quoted[end + 1..])
                }
                // The one row jump.js builds programmatically rather than spelling out.
                None => {
                    assert!(entry.starts_with("bounded + \"ab\""), "a SCORES row names its file first: {entry}");
                    (bounded.to_string(), &entry["bounded + \"ab\"".len()..])
                }
            };
            let rest = &rest[rest.find('"').expect("a SCORES row names its query") + 1..];
            let end = rest.find('"').expect("a SCORES row closes its query");
            let (query, rest) = (rest[..end].to_string(), &rest[end + 1..]);
            let digits = rest.rsplit(',').next().expect("a SCORES row carries its score").trim().trim_end_matches(']');
            out.push((hay, query, match digits {
                "null" => None,
                _ => Some(digits.parse().expect("a SCORES score parses as an integer")),
            }));
        }
        out
    }

    // SCORES is read out of tests/js/jump.js, so a weight changed here fails this test until the JS table is changed with it.
    #[test]
    fn the_exact_scores_the_jump_port_mirrors() {
        let bounded = format!("{}ab", "ax".repeat(16));
        let rows = js_scores(include_str!("../../tests/js/jump.js"), &bounded);
        assert_eq!(rows.len(), 15, "SCORES grew or shrank; change both tables together");
        for (hay, query, expected) in &rows {
            assert_eq!(score(hay, query), *expected, "{query} against {hay}");
        }
    }
}
