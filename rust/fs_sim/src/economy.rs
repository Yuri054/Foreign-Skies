//! The economy's pure rules (`scripts/sim/economy.gd`): a province's base income, and what a building costs. The sums,
//! the budgets, the construction queue and the daily and monthly steps need the whole state and are in `state.rs` and
//! `budget.rs`.

use crate::config::{BuildingDef, EconomyConfig};

/// A province's base income, gold a month, from its people at the start of the scenario (`Economy.base_income`).
pub fn base_income(cfg: &EconomyConfig, population: f64) -> f64 {
    cfg.per_million * (population.max(0.0) / 1e6).powf(cfg.exponent)
}

/// Everything needed to start a level of a building: its gold, its CP and the days it takes (`Economy.build_plan`).
#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct BuildPlan {
    pub gold: f64,
    pub cp: f64,
    pub days: i32,
}

pub fn build_plan(def: &BuildingDef) -> BuildPlan {
    BuildPlan { gold: def.gold, cp: def.cp, days: def.days }
}

/// A project in the construction queue (`Economy.new_job`): waiting until it can be paid for and its province is free,
/// then `days` long. Hulls on the slips are jobs too (`started` from the first day).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Job {
    pub province: usize,
    pub kind: String,
    pub started: bool,
    pub days_total: i32,
    pub days_left: i32,
}

pub fn new_job(province: usize, kind: &str, days: i32) -> Job {
    Job { province, kind: kind.to_string(), started: false, days_total: days, days_left: days }
}
