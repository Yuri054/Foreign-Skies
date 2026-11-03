//! People (`scripts/sim/population.gd`): the rounding rule that takes people from a province (the war dead; the people
//! no longer grow).
//!
//! A province's population is a whole number and the part of a person not yet taken is kept beside it as a 32-bit
//! float, exactly as the game stores them (`PackedInt32Array` and `PackedFloat32Array`).

/// A province is never left under this many people (`Population.MIN_PROVINCE`).
pub const MIN_PROVINCE: i64 = 1000;

/// Adds `delta` people (can be negative) to province `id`, keeping the fraction left over by rounding. Returns the whole
/// people added.
pub fn add(population: &mut [i32], frac: &mut [f32], id: usize, delta: f64) -> f64 {
    let total = frac[id] as f64 + delta;
    let mut whole = total as i64; // GDScript's int() truncates toward zero
    let now = population[id] as i64;
    if now + whole < MIN_PROVINCE {
        whole = MIN_PROVINCE - now;
    }
    population[id] = (now + whole) as i32;
    frac[id] = if now + whole > MIN_PROVINCE { (total - whole as f64) as f32 } else { 0.0 };
    whole as f64
}
