//! The economy's rules (`scripts/sim/economy.gd`): how much a province makes, how heavy taxes and investment weigh on
//! growth, what is left of the workers, and what a building costs. These are the pure rules; the budgets and the
//! daily step, which need the whole state, are not ported yet.

use crate::config::{BuildingDef, EconomyConfig, Effects};
use crate::gd::{clampf, inverse_lerp, lerpf, maxf};

/// What the economy reads of a nation.
#[derive(Debug, Clone, Default)]
pub struct EconNation {
    pub development: f64,
    pub agri_yield: f64,
    pub focus_fx: Effects,
    pub tax_rate: f64,
    /// Monthly state investment (GBP millions).
    pub investment: f64,
    /// The nation's yearly output from its last budget, if it has one yet.
    pub budget_gdp: Option<f64>,
    pub men_in_units: i64,
    pub population: i64,
    pub weariness: f64,
    pub starving: bool,
}

/// A province's output before nation-wide modifiers (`Economy.province_output`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ProvinceOutput {
    pub gdp: f64,
    pub industry: f64,
    pub food: f64,
    pub trade: f64,
    pub pool: f64,
    pub materials: f64,
}

/// Everything needed to start the next level of a building.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BuildPlan {
    pub ic: f64,
    pub days: i32,
    pub gold: f64,
    pub total: f64,
}

/// Summed fractional bonuses from a province's buildings (type, level, in the order the province lists them) and the
/// owner's national focus.
pub fn modifiers(cfg: &EconomyConfig, buildings: &[(&str, i32)], focus_fx: &Effects) -> Effects {
    let mut m = Effects::default();
    for (id, level) in buildings {
        let def = cfg.building(id).unwrap_or_else(|| panic!("unknown building {id}"));
        let level = *level as f64;
        m.gdp += def.effects.gdp * level;
        m.industry += def.effects.industry * level;
        m.food += def.effects.food * level;
        m.trade += def.effects.trade * level;
        m.growth += def.effects.growth * level;
    }
    m.gdp += focus_fx.gdp;
    m.industry += focus_fx.industry;
    m.food += focus_fx.food;
    m.trade += focus_fx.trade;
    m.growth += focus_fx.growth;
    m
}

/// Output of one province: gdp, industry and trade are GBP millions a year; food is the people it can feed; pool is
/// recruitable men; materials is the kt a year its deposits give.
pub fn province_output(
    cfg: &EconomyConfig,
    population: i64,
    area_km2: f64,
    nation: &EconNation,
    buildings: &[(&str, i32)],
    deposit: &[(&str, f64)],
) -> ProvinceOutput {
    let population = population as f64;
    let density = population / maxf(area_km2, 1.0);
    let md = clampf(
        (density / cfg.reference_density).powf(cfg.density_exponent),
        cfg.density_min,
        cfg.density_max,
    );
    let urban = inverse_lerp(cfg.density_min, cfg.density_max, md);
    let fx = modifiers(cfg, buildings, &nation.focus_fx);
    let gdp = population * cfg.gdp_per_capita * nation.development * md / 1e6 * (1.0 + fx.gdp);
    let industry = gdp * lerpf(cfg.industry_share_min, cfg.industry_share_max, urban) * (1.0 + fx.industry);
    let mut materials = 0.0;
    for r in &cfg.resource_ids {
        let have = deposit.iter().find(|(id, _)| id == r).map(|(_, x)| *x).unwrap_or(0.0);
        if have >= cfg.materials_min_deposit {
            materials += have * cfg.materials_extraction_base;
        }
    }
    ProvinceOutput {
        gdp,
        industry,
        food: area_km2 * cfg.food_per_km2 * nation.agri_yield * (1.0 + fx.food),
        trade: gdp * fx.trade,
        pool: population * cfg.manpower_share,
        materials,
    }
}

/// How heavy the taxes are, 0 to 1: the rate's distance above the default toward the maximum.
pub fn tax_strain(cfg: &EconomyConfig, n: &EconNation) -> f64 {
    let span = cfg.max_tax_rate - cfg.default_tax_rate;
    clampf((n.tax_rate - cfg.default_tax_rate) / span, 0.0, 1.0)
}

/// How light the taxes are, 0 to 1: the rate's distance below the default toward the minimum.
pub fn tax_relief(cfg: &EconomyConfig, n: &EconNation) -> f64 {
    let span = cfg.default_tax_rate - cfg.min_tax_rate;
    clampf((cfg.default_tax_rate - n.tax_rate) / maxf(span, 0.0001), 0.0, 1.0)
}

/// The yearly growth of a nation's development from its policies.
pub fn growth_rate(cfg: &EconomyConfig, n: &EconNation) -> f64 {
    cfg.baseline_growth + modifiers(cfg, &[], &n.focus_fx).growth
        - cfg.tax_strain_growth_penalty * tax_strain(cfg, n)
        + cfg.tax_relief_growth_bonus * tax_relief(cfg, n)
        + investment_growth(cfg, n)
}

/// What state investment adds to yearly growth: it compounds, with no ceiling, easing a little past `soft_share`.
pub fn investment_growth(cfg: &EconomyConfig, n: &EconNation) -> f64 {
    let gdp = maxf(n.budget_gdp.unwrap_or(0.0), 0.01);
    let share = maxf(0.0, n.investment * 12.0 / gdp);
    cfg.invest_growth_per_share * share / (1.0 + share / cfg.invest_soft_share)
}

/// Share of the industry's work left after the people called up, in a famine the hunger, and in a long war the
/// weariness.
pub fn worker_share(cfg: &EconomyConfig, n: &EconNation) -> f64 {
    let armed = n.men_in_units as f64 / maxf(n.population as f64, 1.0);
    let mut share = maxf(cfg.labor_floor, 1.0 - cfg.labor_penalty * armed - n.weariness);
    if n.starving {
        share *= 1.0 - cfg.starvation_output;
    }
    share
}

/// Works are built to the size of the place (`Economy.size_factor`): a province with less output than the reference
/// pays that share of the cost, never under the minimum factor. `gdp` and `industry` are the per-province arrays
/// (indexed by province id, element 0 unused), stored as 32-bit floats as the game stores them.
pub fn size_factor(cfg: &EconomyConfig, id: usize, def: Option<&BuildingDef>, gdp: &[f32], industry: &[f32]) -> f64 {
    if id < 1 || id >= gdp.len() {
        return 1.0;
    }
    let by_industry = def.map(|d| d.size_by_industry).unwrap_or(false);
    let size = if by_industry {
        industry[id] as f64 / cfg.cost_ref_industry
    } else {
        gdp[id] as f64 / cfg.cost_ref_gdp
    };
    clampf(size, cfg.cost_min_factor, 1.0)
}

/// The cost of the next level of a building in IC, given the level it already has.
pub fn level_cost(def: &BuildingDef, level: i32, size_factor: f64) -> f64 {
    def.ic * (1.0 + def.ic_growth).powf(level as f64) * size_factor
}

/// `Economy.build_plan`: the cost in IC, the fewest days, and the money share.
pub fn build_plan(cfg: &EconomyConfig, def: &BuildingDef, level: i32, size_factor: f64) -> BuildPlan {
    let ic = level_cost(def, level, size_factor);
    let share = def.gold_share.unwrap_or(cfg.construction_gold_share);
    BuildPlan { ic, days: def.min_days, gold: ic * cfg.ic_value * share, total: ic * cfg.ic_value }
}

/// A project in a nation's queue (`Economy.new_job`): it costs `points_total` IC and takes in at most `rate` a day.
/// `days_left` is the estimate shown to the player, worked out each day from what the project is getting.
#[derive(Debug, Clone, PartialEq)]
pub struct Job {
    pub province: usize,
    pub kind: String,
    pub points_total: f64,
    pub points_left: f64,
    pub rate: f64,
    pub given: f64,
    pub days_total: i32,
    pub days_left: i32,
}

pub fn new_job(province: usize, kind: &str, ic: f64, min_days: i32) -> Job {
    let rate = ic / maxf(min_days as f64, 1.0);
    Job { province, kind: kind.to_string(), points_total: ic, points_left: ic, rate, given: 0.0, days_total: min_days, days_left: min_days }
}
