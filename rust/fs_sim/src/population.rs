//! People (`scripts/sim/population.gd`): the rounding rule that adds people to a province.
//!
//! A province's population is a whole number and the part of a person its growth has not yet added is kept beside it
//! as a 32-bit float, exactly as the game stores them (`PackedInt32Array` and `PackedFloat32Array`).

use crate::config::EconomyConfig;

/// Yearly growth of a nation's people now: its own rate, less what a food shortage takes.
pub fn growth_rate(cfg: &EconomyConfig, pop_growth: f64, food_shortage: f64) -> f64 {
    pop_growth - cfg.famine_decline * food_shortage
}

/// Adds `delta` people (can be negative) to province `id`, keeping the fraction left over by rounding. A province is
/// never left under `min_province`. Returns the whole people added.
pub fn add(cfg: &EconomyConfig, population: &mut [i32], frac: &mut [f32], id: usize, delta: f64) -> f64 {
    let total = frac[id] as f64 + delta;
    let floor_pop = cfg.min_province;
    let mut whole = total as i64; // GDScript's int() truncates toward zero
    let now = population[id] as i64;
    if ((now + whole) as f64) < floor_pop {
        whole = floor_pop as i64 - now;
    }
    population[id] = (now + whole) as i32;
    frac[id] = if (now + whole) as f64 > floor_pop { (total - whole as f64) as f32 } else { 0.0 };
    whole as f64
}
