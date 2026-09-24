// The scoring half of docs/protocol.md "search"; search.rs owns the walk that calls it.
// A subsequence match over a whole home directory returns far too much to read, so the score is what
// makes the result usable: a contiguous run, a match at a word or path boundary, and a match in the
// file's own name all beat a match scattered through a parent directory's spelling.
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
// A candidate with more occurrences of the query's first character than this is scored from the
// first ones alone: an alignment nobody can see is not worth an unbounded scan inside the read loop.
const MAX_STARTS: usize = 16;

// The characters a word or a path segment starts after.
fn is_separator(c: char) -> bool {
    c == '/' || c == '-' || c == '_' || c == '.' || c == ' '
}

// One candidate character, folded once per candidate so the scan compares by index rather than
// re-folding at every start position it tries.
// corner: a character whose lowercase form is more than one char (Turkish dotted capital I) keeps
// only the first, the same corner ui/js/Match.js documents for the accent run it paints.
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

// Holds the folded query for the whole walk and reuses one candidate buffer, so a subtree walk
// allocates twice rather than once per entry.
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

    // None means the query is not a subsequence of the candidate at all, which is the gate every
    // ranking sits behind. Some carries the best alignment's score, higher being the better match.
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
                // A greedy scan from the earliest start takes the earliest position for every needle
                // character, so a start that cannot finish means no later start can either.
                None => return best,
            }
            starts += 1;
            if starts == MAX_STARTS {
                break;
            }
        }
        best
    }

    // Greedy from one start: every needle character takes the next candidate character that matches
    // it, which is the alignment a reader tracing the two strings by hand would find.
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

    // What one matched character is worth: a run, a boundary and the base name each add, and the
    // characters skipped to reach it are charged back.
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

// The order results are answered in: the better score first, then the shorter path, then the
// listing's own name order, so one walk over one tree always answers in exactly one order.
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

    // The same table, value for value, is SCORES in tests/js/jump.js: ui/js/Jump.js ports this scorer, so a
    // weight changed here fails this test until the port and its table are changed with it.
    #[test]
    fn the_exact_scores_the_jump_port_mirrors() {
        let bounded = format!("{}ab", "ax".repeat(16));
        let table: [(&str, &str, Option<i32>); 15] = [
            ("report.txt", "rep", Some(34)), ("raspberry-pie.txt", "rep", Some(16)),
            ("my-notes.txt", "notes", Some(58)), ("bignotes.txt", "notes", Some(52)),
            ("SearchStrip.qml", "strip", Some(58)), ("searchstrip.qml", "strip", Some(52)),
            ("notes/bench.txt", "bench", Some(58)), ("bench/notes.txt", "bench", Some(38)),
            ("axxab", "ab", Some(16)), ("axxb", "ab", Some(12)),
            // The run at the seventeenth "a" is never tried, so the sixteenth start's gapped 6 is the answer.
            (&bounded, "ab", Some(6)),
            ("downloads/helper.txt", "dwnhelp", Some(53)), ("~/Documents/claude/omarchy", "o", Some(10)),
            ("~/Documents/claude/omarchy", "src", Some(5)), ("~/Projects/homelab/nix", "tax", Some(-7)),
        ];
        for (hay, query, expected) in table {
            assert_eq!(score(hay, query), expected, "{} against {}", query, hay);
        }
    }
}
