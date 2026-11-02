//! What the player does with the economy (`construct_building.gd`, `mass_construct_building.gd`, `prioritize_construction.gd`,
//! `set_economy_policy.gd`, `buy_munitions.gd` and the rules behind them in `economy.gd`: `build_problem`, `mass_candidates`).

use crate::economy::{self, new_job};
use crate::gd::clampf;
use crate::state::{Data, GameState};

/// What a mass order did (`MassConstructBuilding`): the provinces built in, the IC spent, the money paid, and what stopped it.
#[derive(Debug, Clone, PartialEq)]
pub struct MassBuild {
    pub built: Vec<usize>,
    pub spent: f64,
    pub gold: f64,
    pub stopped_by: &'static str,
    pub ok: bool,
}

impl GameState {
    /// `Economy.build_plan` for the next level of a building in a province: (IC, days, money).
    pub fn plan_for(&self, data: &Data, id: usize, kind: &str) -> (f64, i32, f64) {
        let def = data.economy.buildings.iter().find(|b| b.id == kind).unwrap_or_else(|| panic!("unknown building {kind}"));
        let sf = economy::size_factor(&data.economy, id, Some(def), &self.province_gdp, &self.province_industry);
        let level = self.level_of(id, kind) as i32;
        let plan = economy::build_plan(&data.economy, def, level, sf);
        (plan.ic, plan.days, plan.gold)
    }

    /// `Economy.build_problem`: why a building cannot be started now ("" if it can). The money is checked unless `check_money` is false.
    pub fn build_problem(&self, data: &Data, tag: &str, id: usize, kind: &str, check_money: bool) -> &'static str {
        let Some(&ni) = self.nation_index.get(tag) else { return "Unknown nation or building" };
        let Some(def) = data.economy.buildings.iter().find(|b| b.id == kind) else { return "Unknown nation or building" };
        if !def.enabled {
            return "Not available yet";
        }
        if id < 1 || id >= self.province_owner.len() || self.province_owner[id] != tag {
            return "Not your province";
        }
        if self.province_controller[id] != tag {
            return "Province is occupied";
        }
        if def.needs_coast && !data.map.provinces[id].coastal {
            return "Needs a coastal province";
        }
        if self.nations[ni].construction.iter().any(|j| j.province == id && j.kind == kind) {
            return "Already under construction";
        }
        if self.level_of(id, kind) >= def.max_level as i64 {
            return "Fully built";
        }
        if check_money {
            let gold = self.plan_for(data, id, kind).2;
            if gold > 0.0 && self.nations[ni].treasury < gold {
                return "Not enough money";
            }
        }
        ""
    }

    /// `ConstructBuilding.execute`: starts the next level of a building; the money is paid when it is begun.
    pub fn construct_building(&mut self, data: &Data, tag: &str, id: usize, kind: &str) -> bool {
        if !self.build_problem(data, tag, id, kind, true).is_empty() {
            return false;
        }
        let ni = self.nation_index[tag];
        let (ic, days, gold) = self.plan_for(data, id, kind);
        self.nations[ni].treasury -= gold;
        self.nations[ni].construction.push(new_job(id, kind, ic, days));
        true
    }

    /// `Economy.build_priority`: how much a province gains from a building, for ranking where to build first.
    fn build_priority(&self, id: usize, kind: &str) -> f64 {
        if kind == "factory" {
            self.province_industry[id] as f64
        } else {
            self.province_gdp[id] as f64
        }
    }

    /// `Economy.mass_candidates`: provinces of a nation where the next level of a building could be started, best first.
    pub fn mass_candidates(&self, data: &Data, tag: &str, kind: &str) -> Vec<usize> {
        let mut ids: Vec<usize> = self.nation(tag).provinces.iter().copied().filter(|&id| self.build_problem(data, tag, id, kind, false).is_empty()).collect();
        crate::gd::sort_custom(&mut ids, |&a, &b| self.build_priority(a, kind) > self.build_priority(b, kind));
        ids
    }

    /// `MassConstructBuilding.execute`: starts the building in every province that can have it, best first, until the count, the
    /// IC to spend or the money runs out.
    pub fn mass_construct(&mut self, data: &Data, tag: &str, kind: &str, max_count: usize, max_spend: f64) -> MassBuild {
        let mut out = MassBuild { built: vec![], spent: 0.0, gold: 0.0, stopped_by: "all", ok: false };
        if !self.nation_index.contains_key(tag) || !data.economy.buildings.iter().any(|b| b.id == kind) {
            return out;
        }
        for id in self.mass_candidates(data, tag, kind) {
            if out.built.len() >= max_count {
                out.stopped_by = "count";
                break;
            }
            let (ic, _, gold) = self.plan_for(data, id, kind);
            if max_spend > 0.0 && out.spent + ic > max_spend {
                out.stopped_by = "spend";
                break;
            }
            if !self.construct_building(data, tag, id, kind) {
                out.stopped_by = "money";
                break;
            }
            out.spent += ic;
            out.gold += gold;
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

    /// `SetEconomyPolicy.execute`: the tax rate, mobilization, arms share, investment or standing army.
    pub fn set_economy_policy(&mut self, data: &Data, tag: &str, policy: &str, value: f64) -> bool {
        let Some(&ni) = self.nation_index.get(tag) else { return false };
        match policy {
            "tax_rate" => self.nations[ni].tax_rate = clampf(value, data.economy.min_tax_rate, data.economy.max_tax_rate),
            "mobilization" => {
                let cap = self.mobilization_range(data, tag).1;
                self.nations[ni].mobilization = clampf(value, 0.0, cap);
            }
            "arms_share" => self.nations[ni].arms_share = clampf(value, 0.0, 1.0),
            "investment" => self.nations[ni].investment = clampf(value, 0.0, self.nations[ni].budget.gdp / 12.0 * 0.1),
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

    /// `BuyMunitions.execute`: munitions bought abroad with money, cut by the blockade.
    pub fn buy_munitions(&mut self, data: &Data, tag: &str, amount: f64) -> bool {
        let Some(&ni) = self.nation_index.get(tag) else { return false };
        if amount <= 0.0 || self.nations[ni].treasury < amount {
            return false;
        }
        self.nations[ni].treasury -= amount;
        let bought = amount / data.economy.munitions_import_price * (1.0 - self.nations[ni].blockade);
        self.nations[ni].munitions += bought;
        true
    }
}
