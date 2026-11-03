//! A nation's budget for a month (`Economy.nation_budget`): income by source, expenses by kind, net, construction
//! points a day and manpower, from the nation's summed provinces.

use crate::config::EconomyConfig;
use crate::gd::{maxf, minf};
use crate::state::{Nation, Sums};

#[derive(Debug, Clone, Copy, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Budget {
    pub base: f64,
    pub factories: f64,
    pub ports: f64,
    pub occupied: f64,
    pub income: f64,
    pub administration: f64,
    pub army: f64,
    pub navy: f64,
    pub buildings: f64,
    pub interest: f64,
    pub expenses: f64,
    pub net: f64,
    pub cp: f64,
    pub manpower_pool: f64,
    pub manpower_max: f64,
}

/// `Economy.nation_budget`. `war_mult` is the war support multiplier on income (`WarSupport.economy_mult`), `army` the
/// month's upkeep of the nation's units (`Economy.army_upkeep`), `capital_held` whether it holds its capital.
pub fn nation_budget(cfg: &EconomyConfig, n: &Nation, raw: &Sums, war_mult: f64, army: f64, capital_held: bool) -> Budget {
    let base = raw.base * (1.0 - cfg.mobilization_loss * n.mobilization) * (1.0 + n.focus_income);
    let factories = raw.factories * (1.0 - cfg.blockade_factory_loss * n.blockade);
    let ports = raw.ports * (1.0 - n.blockade);
    let occupied = raw.occupied;
    let income = (base + factories + ports + occupied) * war_mult;
    let administration = (base + factories + ports) * war_mult * cfg.administration;
    let navy = n.naval_budget / 12.0;
    let buildings = raw.upkeep;
    let interest = maxf(0.0, -n.treasury) * cfg.debt_interest / 12.0;
    let expenses = administration + army + navy + buildings + interest;
    let mut cp = raw.cp + n.focus_cp;
    if capital_held {
        cp += cfg.capital_cp;
    }
    let pool = raw.pool;
    let peace = minf(n.peacetime_army as f64, pool);
    Budget {
        base: base * war_mult,
        factories: factories * war_mult,
        ports: ports * war_mult,
        occupied: occupied * war_mult,
        income,
        administration,
        army,
        navy,
        buildings,
        interest,
        expenses,
        net: income - expenses,
        cp,
        manpower_pool: pool,
        manpower_max: peace + (pool - peace) * n.mobilization,
    }
}
