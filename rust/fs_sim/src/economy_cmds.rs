//! What the player does with the economy (`construct_building.gd`, `mass_construct_building.gd`, `prioritize_construction.gd`,
//! `set_economy_policy.gd` and the rules behind them in `economy.gd`: `build_problem`, `levels_planned`, `build_priority`,
//! `mass_candidates`).

use crate::economy::{self, new_job};
use crate::gd::clampf;
use crate::state::{building_level, Data, GameState};

/// What a mass order did (`MassConstructBuilding`): the provinces queued in, the gold and construction points they cost,
/// and what stopped it.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct MassBuild {
    pub built: Vec<usize>,
    pub gold: f64,
    pub cp: f64,
    pub stopped_by: &'static str,
    pub ok: bool,
}

/// `Fmt.money`: a sum of gold as a bare number with one decimal ("0" when it rounds to nothing).
pub fn fmt_money(m: f64) -> String {
    if m.abs() < 0.05 {
        "0".to_string()
    } else {
        crate::gd::format_f(m, 1)
    }
}

impl GameState {
    /// `Economy.levels_planned`: levels of a building a province has, built and queued.
    pub fn levels_planned(&self, nation: usize, id: usize, kind: &str) -> i32 {
        let queued = self.nations[nation].construction.iter().filter(|j| j.province == id && j.kind == kind).count() as i32;
        building_level(&self.province_buildings[id], kind) + queued
    }

    /// `Economy.build_problem`: why a building cannot be queued ("" if it can). With `check_money`, also whether the gold
    /// and construction points are there now.
    pub fn build_problem(&self, data: &Data, tag: &str, id: usize, kind: &str, check_money: bool) -> String {
        let Some(&ni) = self.nation_index.get(tag) else { return "Unknown nation or building".into() };
        let Some(def) = data.economy.building(kind) else { return "Unknown nation or building".into() };
        if id < 1 || id >= self.province_owner.len() || self.province_owner[id] != tag {
            return "Not your province".into();
        }
        if self.province_controller[id] != tag {
            return "Province is occupied".into();
        }
        if def.needs_coast && !data.map.provinces[id].coastal {
            return "Needs a coastal province".into();
        }
        if self.levels_planned(ni, id, kind) >= data.economy.max_level {
            return format!("Fully built ({})", data.economy.max_level);
        }
        if check_money {
            let plan = economy::build_plan(def);
            let n = &self.nations[ni];
            if n.treasury < plan.gold {
                return format!("Not enough gold ({} gold)", fmt_money(plan.gold));
            }
            if n.cp < plan.cp {
                return format!("Not enough construction points ({})", crate::gd::roundi(plan.cp));
            }
        }
        String::new()
    }

    /// `ConstructBuilding.execute`: queues a level of a building; the queue starts it as soon as it can.
    pub fn construct_building(&mut self, data: &Data, tag: &str, id: usize, kind: &str) -> bool {
        if !self.build_problem(data, tag, id, kind, false).is_empty() {
            return false;
        }
        let ni = self.nation_index[tag];
        let days = economy::build_plan(data.economy.building(kind).unwrap()).days;
        self.nations[ni].construction.push(new_job(id, kind, days));
        self.start_queued(data, ni);
        true
    }

    /// `Economy.build_priority`: how much a province gains from a building, for ranking where to build first.
    fn build_priority(&self, id: usize, kind: &str) -> f64 {
        let b = &self.province_buildings[id];
        self.province_base_income[id] as f64 + 0.1 * building_level(b, kind) as f64 + 0.01 * building_level(b, "civilian_factory") as f64
    }

    /// `Economy.mass_candidates`: provinces of a nation where the next level of a building could be queued, best first.
    pub fn mass_candidates(&self, data: &Data, tag: &str, kind: &str) -> Vec<usize> {
        let mut ids: Vec<usize> = self.nation(tag).provinces.iter().copied().filter(|&id| self.build_problem(data, tag, id, kind, false).is_empty()).collect();
        crate::gd::sort_custom(&mut ids, |&a, &b| self.build_priority(a, kind) > self.build_priority(b, kind));
        ids
    }

    /// `MassConstructBuilding.execute`: queues the building in every province that can have it, best first, until the
    /// count or the gold to queue runs out.
    pub fn mass_construct(&mut self, data: &Data, tag: &str, kind: &str, max_count: usize, max_spend: f64) -> MassBuild {
        let mut out = MassBuild { built: vec![], gold: 0.0, cp: 0.0, stopped_by: "all", ok: false };
        if !self.nation_index.contains_key(tag) || data.economy.building(kind).is_none() {
            return out;
        }
        let plan = economy::build_plan(data.economy.building(kind).unwrap());
        for id in self.mass_candidates(data, tag, kind) {
            if out.built.len() >= max_count {
                out.stopped_by = "count";
                break;
            }
            if max_spend > 0.0 && out.gold + plan.gold > max_spend {
                out.stopped_by = "spend";
                break;
            }
            if !self.construct_building(data, tag, id, kind) {
                continue;
            }
            out.gold += plan.gold;
            out.cp += plan.cp;
            out.built.push(id);
        }
        out.ok = !out.built.is_empty();
        out
    }

    /// `PrioritizeConstruction.execute`: moves a project to the head of the queue.
    pub fn prioritize_construction(&mut self, tag: &str, id: usize, kind: &str) -> bool {
        let Some(&ni) = self.nation_index.get(tag) else { return false };
        let q = &mut self.nations[ni].construction;
        match q.iter().position(|j| j.province == id && j.kind == kind) {
            Some(0) | None => false,
            Some(i) => {
                let job = q.remove(i);
                q.insert(0, job);
                true
            }
        }
    }

    /// `SetEconomyPolicy.execute`: mobilization or the standing army.
    pub fn set_economy_policy(&mut self, data: &Data, tag: &str, policy: &str, value: f64) -> bool {
        let Some(&ni) = self.nation_index.get(tag) else { return false };
        match policy {
            "mobilization" => {
                let cap = self.mobilization_range(data, tag).1;
                self.nations[ni].mobilization = clampf(value, 0.0, cap);
            }
            "standing_army" => {
                let cap = self.standing_cap(data, ni).max(0);
                self.nations[ni].peacetime_army = (value as i64).clamp(0, cap);
                // The reserve follows at once: Economy.request works the economy out again (outside the day's step).
                self.economy_request(data);
            }
            _ => return false,
        }
        true
    }
}
