//! Armies at the start of a game (`scripts/sim/unit.gd`, `army.gd` and `Military.deploy_starting`): the divisions a
//! nation's peacetime army is made of, where they stand and under whom, and what they add up to. Movement, battles,
//! supply and the rest of `military.gd` are not ported yet.

use crate::config::MilitaryConfig;
use crate::gd::lerpf;
use serde_json::Value;

#[derive(Debug, Clone)]
pub struct Unit {
    pub unit_type: String,
    /// The share of its full size still fit to fight.
    pub strength: f64,
    pub morale: f64,
    pub experience: f64,
}

impl Unit {
    pub fn new(unit_type: &str, strength: f64) -> Unit {
        Unit { unit_type: unit_type.to_string(), strength, morale: 1.0, experience: 0.0 }
    }

    pub fn men(&self, cfg: &MilitaryConfig) -> f64 {
        cfg.unit_type(&self.unit_type).size as f64 * self.strength
    }

    /// Fighting value: men in thousands times the type's attack, dulled by low morale.
    pub fn power(&self, cfg: &MilitaryConfig) -> f64 {
        let floor_effect = cfg.morale_floor_effect;
        let drill = 1.0 + cfg.training_power_max * self.experience;
        self.men(cfg) / 1000.0 * cfg.unit_type(&self.unit_type).attack * lerpf(floor_effect, 1.0, self.morale) * drill
    }
}

#[derive(Debug, Clone)]
pub struct Army {
    pub id: u32,
    pub tag: String,
    pub name: String,
    pub province: usize,
    pub units: Vec<Unit>,
    pub general_skill: f64,
    pub landing_days: i32,
    /// The provinces still to enter, nearest first, and the days left before the army arrives in the first.
    pub path: Vec<usize>,
    pub move_days_left: f64,
    /// Days spent standing still; entrenchment grows with it.
    pub still_days: i64,
    /// True while this army is the one that attacked in an ongoing battle.
    pub attacking: bool,
    /// Set while the army is in a battle this day.
    pub fighting: bool,
    /// Whether the army can draw supply (updated daily).
    pub supplied: bool,
    /// Days left in which the supplies that came ashore with the army last.
    pub landed_supply: i64,
}

impl Army {
    pub fn men(&self, cfg: &MilitaryConfig) -> f64 {
        let mut total = 0.0;
        for u in &self.units {
            total += u.men(cfg);
        }
        total
    }

    /// The share of the army's fighting power that comes from its guns (units that burn shells).
    pub fn shelling_share(&self, cfg: &MilitaryConfig) -> f64 {
        let (mut guns, mut all) = (0.0, 0.0);
        for u in &self.units {
            let p = u.power(cfg);
            all += p;
            if cfg.unit_type(&u.unit_type).shells {
                guns += p;
            }
        }
        if all > 0.0 {
            guns / all
        } else {
            0.0
        }
    }

    /// The army's power. (No army group, no offensive plan: the multipliers for those are 1.)
    pub fn power(&self, cfg: &MilitaryConfig) -> f64 {
        let mut total = 0.0;
        for u in &self.units {
            total += u.power(cfg);
        }
        let landing = if self.landing_days > 0 { cfg.landing_power_mult } else { 1.0 };
        total * self.general_skill * 1.0 * landing * 1.0
    }
}

/// `Military._starting_units`: the divisions a peacetime field army of `men` is made of, type by type in file order.
pub fn starting_units(cfg: &MilitaryConfig, men: i64) -> Vec<Unit> {
    let mut out = vec![];
    for t in &cfg.unit_types {
        let mut left = men as f64 * t.share;
        while left >= t.size as f64 {
            out.push(Unit::new(&t.id, 1.0));
            left -= t.size as f64;
        }
        // A part-strength unit for the remainder, unless it is only a handful of men.
        if left / t.size as f64 >= 0.02 {
            out.push(Unit::new(&t.id, left / t.size as f64));
        }
    }
    out
}

/// One place a nation's army stands, from the scenario's deployment list.
#[derive(Debug, Clone)]
pub struct Stack {
    pub name: String,
    pub province: usize,
    pub weight: f64,
}

/// `Military._stack_plan` for a nation the scenario lists. (A nation with no list gets its most populous provinces in
/// the game, sorted with an unstable sort; that is not ported, and no scenario needs it.)
pub fn stack_plan(
    listed: &Value,
    tag: &str,
    province_names: &[String],
    province_owner: &[String],
) -> Result<Vec<Stack>, String> {
    let entries = listed.as_array().cloned().unwrap_or_default();
    if entries.is_empty() {
        return Err(format!("{tag} has no deployment list: the default stack plan is not ported"));
    }
    let mut plan = vec![];
    for e in entries {
        let at = e["at"].as_str().ok_or("deployment entry without a province")?;
        let id = (1..province_names.len()).find(|&id| province_names[id] == at && province_owner[id] == tag);
        let id = id.ok_or_else(|| format!("deployment: {tag} has no province {at}"))?;
        plan.push(Stack {
            name: e["name"].as_str().unwrap_or("").to_string(),
            province: id,
            weight: e.get("weight").and_then(Value::as_f64).unwrap_or(1.0),
        });
    }
    Ok(plan)
}

/// Deals the units out to the stacks so each holds men in proportion to its weight (the way the game does, with its
/// running totals kept as 32-bit floats). Returns, for each stack, the units it holds.
pub fn deal_units(cfg: &MilitaryConfig, units: Vec<Unit>, stacks: &[Stack]) -> Vec<Vec<Unit>> {
    let mut dealt = vec![0.0f32; stacks.len()];
    let mut held: Vec<Vec<Unit>> = vec![vec![]; stacks.len()];
    for u in units {
        let mut best = 0;
        for i in 0..stacks.len() {
            if (dealt[i] as f64) / stacks[i].weight < (dealt[best] as f64) / stacks[best].weight {
                best = i;
            }
        }
        dealt[best] = (dealt[best] as f64 + u.men(cfg)) as f32;
        held[best].push(u);
    }
    held
}
