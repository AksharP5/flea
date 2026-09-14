// One spelling of "how long did that take" for every request that reports a duration on the wire.
use std::time::Instant;

pub fn since(t: Instant) -> f64 {
    t.elapsed().as_secs_f64() * 1000.0
}
