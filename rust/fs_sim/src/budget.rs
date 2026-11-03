//! A nation's budget (`Economy.nation_budget` and its helpers): revenue, what the state spends, industry, food and raw
//! materials, from the nation's summed province output.

use crate::config::{EconomyConfig, MilitaryConfig};
use crate::economy::{self, EconNation};
use crate::gd::{clampf, lerpf, maxf, minf};
use crate::state::{Nation, Sums};

/// A nation's raw materials (`Economy.materials_of`).
#[derive(Debug, Clone, Copy, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Materials {
    pub own: f64,
    pub need: f64,
    pub imported: f64,
    pub exported: f64,
    pub ratio: f64,
    pub cost: f64,
    pub income: f64,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Budget {
    pub gdp: f64,
    pub industry: f64,
    pub revenue: f64,
    pub trade: f64,
    pub materials: Materials,
    pub gdp_scale: f64,
    pub trade_scale: f64,
    pub industry_scale: f64,
    pub food_scale: f64,
    pub output_scale: f64,
    pub revenue_per_gdp: f64,
    pub civil: f64,
    pub army: f64,
    pub naval: f64,
    pub food_imports: f64,
    pub materials_cost: f64,
    pub interest: f64,
    pub munitions_storage: f64,
    pub investment: f64,
    pub tax_relief: f64,
    pub arms_mult: f64,
    pub tax_strain: f64,
    pub expenses: f64,
    pub net: f64,
    pub food_production: f64,
    pub food_need: f64,
    pub food_imported: f64,
    pub food_shortage: f64,
    pub construction_points: f64,
    pub manpower_pool: f64,
    pub manpower_max: f64,
}

/// A nation's raw materials: its own supply, what it needs, what it imports (the shortfall up to `import_cap` of the
/// need, cut by the blockade), what it sells, and the share of its need it has.
pub fn materials_of(cfg: &EconomyConfig, materials_k: f64, n: &Nation, raw: &Sums) -> Materials {
    let own = raw.materials;
    let need = raw.industry * materials_k * n.materials_need_mult;
    let short = maxf(0.0, need - own);
    let imported = minf(short, need * cfg.materials_import_cap) * (1.0 - n.blockade);
    let supply = own + imported;
    let ratio = if need <= 0.0 { 1.0 } else { minf(1.0, supply / need) };
    let exported = maxf(0.0, own - need);
    Materials {
        own,
        need,
        imported,
        exported,
        ratio,
        cost: imported * cfg.materials_import_price * cfg.materials_import_markup / 1000.0,
        income: exported * cfg.materials_import_price * cfg.materials_export_share / 1000.0,
    }
}

/// How dear a nation's soldiers are against the reference: its output per head over `soldier_upkeep_ref`, within
/// `wage_min` and `wage_max`.
pub fn wage_factor(cfg: &EconomyConfig, n: &Nation, raw: &Sums) -> f64 {
    if n.population <= 0 {
        return 1.0;
    }
    let per_head = raw.gdp * 1e6 / n.population as f64;
    clampf(per_head / cfg.soldier_upkeep_ref, cfg.wage_min, cfg.wage_max)
}

/// What a nation's soldiers cost against the reference now: `wage_factor` at the start, then the baseline drift.
pub fn soldier_wage(cfg: &EconomyConfig, n: &mut Nation, raw: &Sums) -> f64 {
    if n.wage <= 0.0 {
        n.wage = wage_factor(cfg, n, raw);
    }
    n.wage
}

/// The small works everywhere: `base_ic` for an economy of `base_ic_gdp_ref` or more, a share of it for a smaller one,
/// never under `base_ic_min`. (A negative `gdp`: the full amount.)
pub fn base_ic(cfg: &EconomyConfig, gdp: f64) -> f64 {
    if gdp < 0.0 {
        return cfg.base_ic;
    }
    maxf(cfg.base_ic_min, cfg.base_ic * minf(1.0, gdp / cfg.base_ic_gdp_ref))
}

/// Construction points (IC) a nation can spend in a day.
pub fn construction_points(cfg: &EconomyConfig, n: &Nation, industry: f64, gdp: f64) -> f64 {
    base_ic(cfg, gdp) + n.focus_construction + industry * cfg.ic_per_industry
}

/// Budget of one nation given its summed province output and the war-support multiplier on tax (`tax_mult`).
pub fn nation_budget(
    cfg: &EconomyConfig,
    mil: &MilitaryConfig,
    materials_k: f64,
    n: &mut Nation,
    raw: &Sums,
    tax_mult: f64,
) -> Budget {
    let mob_mult = 1.0 - cfg.mobilization_output_penalty * n.mobilization;

    let food_production = raw.food * mob_mult;
    let food_need = n.population as f64;
    let food_deficit = maxf(0.0, food_need - food_production);
    let food_imported = food_deficit * (1.0 - n.blockade);
    let food_shortage = (food_deficit - food_imported) / maxf(food_need, 1.0);

    let mats = materials_of(cfg, materials_k, n, raw);
    let materials_mult = maxf(cfg.materials_floor, mats.ratio);

    let output_mult = mob_mult * (1.0 - cfg.famine_output_penalty * food_shortage);
    // Factories making munitions are not making the people's goods.
    let arms_mult = 1.0 - clampf(n.arms_share, 0.0, 1.0) * cfg.munitions_output_penalty;
    let gdp_scale = output_mult * (1.0 - cfg.blockade_trade_loss * n.blockade) * lerpf(1.0, materials_mult, 0.4) * arms_mult;
    let econ: EconNation = n.econ();
    let industry_scale = output_mult * materials_mult * economy::worker_share(cfg, &econ);
    let gdp = raw.gdp * gdp_scale;
    let industry = raw.industry * industry_scale;
    let trade_scale = output_mult * (1.0 - n.blockade);
    let trade = raw.trade * trade_scale;

    let tax_drag = 1.0 - cfg.tax_drag * maxf(0.0, n.tax_rate - cfg.default_tax_rate);
    let revenue_per_gdp = n.tax_rate * tax_drag;
    let revenue = gdp * revenue_per_gdp * tax_mult + trade + mats.income;

    // The state's own costs are set at the start and follow the people and the economy's own drift (civil_index).
    if n.civil_base <= 0.0 {
        n.civil_base = raw.gdp * cfg.default_tax_rate * cfg.civil_share * n.civil_mult;
    }
    let civil = n.civil_base * n.civil_index * gdp_scale;
    // A soldier costs what the country pays its people; men on exercise cost more.
    let drilling = n.men_exercising as f64 * mil.training_cost_share;
    let wage = soldier_wage(cfg, n, raw);
    let army = (n.men_in_units as f64 + n.manpower as f64 * cfg.reserve_upkeep + drilling) * cfg.soldier_upkeep * wage / 1e6;
    let naval = n.naval_budget;
    // The whole economy buys the food; the treasury only carries its share (subsidies, duties).
    let food_imports = food_imported * cfg.food_import_cost * cfg.food_state_share / 1e6;
    let interest = maxf(0.0, -n.treasury) * cfg.debt_interest;
    let munitions_storage = n.munitions * cfg.munitions_storage_cost;
    let investment = n.investment * 12.0;
    let expenses = civil + army + naval + food_imports + mats.cost + interest + munitions_storage + investment;

    let pool = raw.pool;
    let peace = minf(n.peacetime_army as f64, pool);
    Budget {
        gdp,
        industry,
        revenue,
        trade,
        materials: mats,
        gdp_scale,
        trade_scale,
        industry_scale,
        food_scale: mob_mult,
        output_scale: output_mult,
        revenue_per_gdp,
        civil,
        army,
        naval,
        food_imports,
        materials_cost: mats.cost,
        interest,
        munitions_storage,
        investment,
        tax_relief: economy::tax_relief(cfg, &econ),
        arms_mult,
        tax_strain: economy::tax_strain(cfg, &econ),
        expenses,
        net: revenue - expenses,
        food_production,
        food_need,
        food_imported,
        food_shortage,
        construction_points: construction_points(cfg, n, industry, gdp),
        manpower_pool: pool,
        manpower_max: peace + (pool - peace) * n.mobilization,
    }
}
