//! The AI's turn (`scripts/ai/ai.gd`, `ai_budget.gd`, `ai_focus.gd`): every `think_days` days each AI nation thinks, and what it does goes
//! through the commands the player uses. Only the parts named in `AiTurn` are ported; the rest of the turn (defence, offence, forces,
//! navy, landing, diplomacy, ambition) is not, and does nothing.

use crate::gd::{clampf, maxf};
use crate::state::{Data, GameState};
use serde_json::Value;

/// Which parts of the AI's turn are switched on. By default none: the AI does not play.
#[derive(Debug, Clone, Copy, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct AiTurn {
    pub budget: bool,
    pub focus: bool,
    pub forces: bool,
    pub ambition: bool,
    pub defence: bool,
    pub diplomacy: bool,
    pub offence: bool,
    pub navy: bool,
}

impl AiTurn {
    /// The whole of the AI's turn, as the game plays it (`GameState.ai_enabled`).
    pub fn all() -> AiTurn {
        AiTurn { budget: true, focus: true, forces: true, ambition: true, defence: true, diplomacy: true, offence: true, navy: true }
    }
}

fn bf(c: &Value, k: &str) -> f64 {
    c[k].as_f64().unwrap_or_else(|| panic!("ai.json: budget.{k} is not a number"))
}

impl GameState {
    /// `AI.is_ai`: a nation the AI plays: not the player's, and still on the map.
    pub fn is_ai(&self, tag: &str) -> bool {
        self.nation_index.get(tag).map(|&i| tag != self.player_tag && !self.nations[i].provinces.is_empty()).unwrap_or(false)
    }

    /// `AI.due_nations`: the AI nations whose turn it is today, in tag order.
    pub fn due_nations(&self, data: &Data) -> Vec<String> {
        let mut tags: Vec<&String> = self.nation_index.keys().collect();
        tags.sort();
        let interval = data.ai.raw["think_days"].as_i64().unwrap();
        let mut out = vec![];
        for (i, t) in tags.iter().enumerate() {
            if (self.calendar.days_elapsed as i64 + i as i64) % interval == 0 && self.is_ai(t) {
                out.push((*t).clone());
            }
        }
        out
    }

    /// `AI.step_day` (the ported parts of it): the nations due think, each in the order of `AI._think`.
    pub fn ai_step_day(&mut self, data: &Data) {
        if self.ai_turn == AiTurn::default() {
            return;
        }
        for tag in self.due_nations(data) {
            // `AI._think`: the war (defence, offence, recruiting, navy, landing) when at war, else rebuilding and demobilizing
            if !self.wars_of(&tag).is_empty() {
                if self.ai_turn.defence {
                    self.ai_defense_step(data, &tag);
                }
                if self.ai_turn.offence {
                    self.ai_offense_step(data, &tag);
                }
                if self.ai_turn.forces {
                    self.ai_forces_step(data, &tag);
                }
                if self.ai_turn.navy {
                    self.ai_navy_step(data, &tag);
                    self.ai_landing_step(data, &tag);
                }
            } else if self.ai_turn.forces {
                self.ai_forces_rebuild(data, &tag);
                self.ai_forces_demobilize(data, &tag);
            }
            if self.ai_turn.diplomacy {
                self.ai_diplomacy_step(data, &tag);
            }
            if self.ai_turn.budget {
                self.ai_budget_step(data, &tag);
            }
            if self.ai_turn.focus {
                self.ai_focus_step(data, &tag);
            }
            if self.ai_turn.ambition {
                self.ai_ambition_step(data, &tag);
            }
        }
    }

    // ---------------------------------------------------------------- focus

    /// `AIFocus.step`: a nation with no focus in hand takes up the one it likes best.
    pub fn ai_focus_step(&mut self, data: &Data, tag: &str) {
        let n = self.nation(tag);
        if n.focus.is_some() || n.provinces.is_empty() {
            return;
        }
        let mut best = String::new();
        for repeatable in [false, true] {
            let mut best_score = 0.0;
            for f in data.focus.tree_of(tag) {
                if f.repeatable != repeatable || !self.focus_block(data, tag, &f.id).is_empty() {
                    continue;
                }
                let score = self.ai_focus_score(data, tag, f);
                if score > best_score + 0.000001 {
                    best = f.id.clone();
                    best_score = score;
                }
            }
            if !best.is_empty() {
                break;
            }
        }
        if !best.is_empty() {
            // SetFocus does not change the economy figures
            self.focus_start(data, tag, &best);
        }
    }

    /// `AIFocus.score_of`.
    pub fn ai_focus_score(&self, data: &Data, tag: &str, f: &crate::config::FocusDef) -> f64 {
        if let Some(min) = f.min_aggression {
            if self.temperament(data, tag).0 < min {
                return 0.0;
            }
        }
        let fx = &f.effects;
        let mut score = f.ai;
        let at_war = !self.wars_of(tag).is_empty();
        if at_war && (fx.army_size.is_some() || fx.cp.is_some() || fx.war_support.is_some()) {
            score += 1.0;
        }
        if !at_war && (fx.income.is_some() || fx.civilian_factories.is_some()) {
            score += 0.5;
        }
        if f.has_claim && !at_war {
            score += 0.3;
        }
        score - f.days as f64 / 1000.0
    }

    // ---------------------------------------------------------------- budget

    /// `AIBudget.step`: once a month, buildings while the gold and construction points allow, the standing army in peace,
    /// ships (`AINavy.build`, when the navy part of the AI is on) and diplomacy points in a crisis.
    pub fn ai_budget_step(&mut self, data: &Data, tag: &str) {
        let c = &data.ai.raw["budget"];
        let stamp = self.calendar.year as i64 * 12 + self.calendar.month as i64;
        if self.ai_budget_stamp.get(tag).copied().unwrap_or(0) == stamp || !c["enabled"].as_bool().unwrap_or(false) {
            return;
        }
        self.ai_budget_stamp.insert(tag.to_string(), stamp);
        self.ai_buildings(data, tag);
        self.ai_army(data, tag);
        if self.ai_turn.navy {
            self.ai_navy_build(data, tag);
        }
        self.ai_points(data, tag);
    }

    /// `AIBudget.reserve`: the gold the nation keeps in hand: build_floor, plus cushion_months of a deficit, twice that at
    /// war.
    pub fn ai_reserve_gold(&self, data: &Data, tag: &str) -> f64 {
        let c = &data.ai.raw["budget"];
        let n = self.nation(tag);
        let floor_gold = bf(c, "build_floor") + maxf(0.0, -n.budget.net) * bf(c, "cushion_months");
        floor_gold * if !self.wars_of(tag).is_empty() { 2.0 } else { 1.0 }
    }

    /// `AIBudget.want`: how much the nation wants a building now, against a civilian factory (1).
    pub fn ai_want(&self, data: &Data, tag: &str, id: usize, kind: &str) -> f64 {
        let c = &data.ai.raw["budget"];
        let n = self.nation(tag);
        let at_war = !self.wars_of(tag).is_empty();
        match kind {
            "civilian_factory" => {
                if at_war {
                    bf(c, "factory_war")
                } else {
                    1.0
                }
            }
            "construction_sector" => {
                // Gold in hand that CP cannot keep up with: months of gold over months of CP for a factory.
                let factory = crate::economy::build_plan(data.economy.building("civilian_factory").unwrap());
                let cp_month = maxf(n.budget.cp * 30.0, 0.01);
                let gold_month = maxf(n.budget.net, 0.01);
                let ratio = (factory.cp / cp_month) / maxf(factory.gold / gold_month, 0.01);
                clampf(ratio - 1.0, 0.0, 1.5)
            }
            "port" => bf(c, "port_want"),
            "railway" => {
                if at_war && self.ai_near_front(data, tag, id) {
                    bf(c, "front_railway")
                } else {
                    0.0
                }
            }
            "trench" | "fortification" => {
                if at_war && self.ai_near_front(data, tag, id) {
                    bf(c, "front_works")
                } else {
                    0.0
                }
            }
            _ => 0.0,
        }
    }

    /// `AIBudget._near_front`: whether a province lies on or just behind one of the nation's fronts.
    fn ai_near_front(&self, data: &Data, tag: &str, id: usize) -> bool {
        for f in &self.fronts {
            if f.tag != tag {
                continue;
            }
            for &p in &f.provinces {
                if p == id || data.map.neighbors(p).any(|x| x == id) {
                    return true;
                }
            }
        }
        false
    }

    /// `AIBudget._places`: the provinces worth looking at: the best for income, the capital and the ground behind the fronts.
    fn ai_places(&self, data: &Data, tag: &str) -> Vec<usize> {
        let c = &data.ai.raw["budget"];
        let n = self.nation(tag);
        let mut owned: Vec<usize> = n.provinces.clone();
        let inc = |x: usize| self.province_base_income[x];
        crate::gd::sort_custom(&mut owned, |&x, &y| inc(x) > inc(y) || (inc(x) == inc(y) && x < y));
        let mut places: Vec<usize> = owned.iter().take(bf(c, "candidates") as usize).copied().collect();
        let capital = n.capital;
        if capital > 0 && n.provinces.contains(&(capital as usize)) && !places.contains(&(capital as usize)) {
            places.push(capital as usize);
        }
        for f in &self.fronts {
            if f.tag == tag {
                for &p in &f.provinces {
                    for q in data.map.neighbors(p) {
                        if self.province_owner[q] == tag && !places.contains(&q) {
                            places.push(q);
                        }
                    }
                }
            }
        }
        places
    }

    /// `AIBudget._buildings`: starts buildings, the most wanted per gold first, while the gold (above the reserve) and the
    /// CP last, at most max_starts a month and max_construction under way.
    fn ai_buildings(&mut self, data: &Data, tag: &str) {
        let c = &data.ai.raw["budget"];
        let places = self.ai_places(data, tag);
        for _ in 0..bf(c, "max_starts") as i64 {
            let n = self.nation(tag);
            if n.construction.len() as i64 >= bf(c, "max_construction") as i64 {
                return;
            }
            let mut best_id = 0;
            let mut best_type = String::new();
            let mut best_value = 0.0;
            for &id in &places {
                if GameState::province_busy(self.nation(tag), id) {
                    continue;
                }
                for def in &data.economy.buildings {
                    if !self.build_problem(data, tag, id, &def.id, true).is_empty() {
                        continue;
                    }
                    let plan = crate::economy::build_plan(def);
                    if self.nation(tag).treasury - plan.gold < self.ai_reserve_gold(data, tag) {
                        continue;
                    }
                    let value = self.ai_want(data, tag, id, &def.id) / maxf(plan.gold, 1.0);
                    if value > best_value + 0.000001 {
                        best_id = id;
                        best_type = def.id.clone();
                        best_value = value;
                    }
                }
            }
            if best_id == 0 {
                return;
            }
            if self.construct_building(data, tag, best_id, &best_type) {
                self.economy_dirty = true;
            }
        }
    }

    /// `AIBudget._army`: in peace, with a surplus, the standing army grows by army_growth_per_year (a twelfth a month), as
    /// long as the upkeep of the men added takes at most army_surplus_share of the surplus, up to the standing cap.
    fn ai_army(&mut self, data: &Data, tag: &str) {
        let c = &data.ai.raw["budget"];
        let ni = self.nation_index[tag];
        let n = &self.nations[ni];
        let net = n.budget.net;
        if !self.wars_of(tag).is_empty() || net <= 0.0 {
            return;
        }
        let infantry = data.military.unit_type("infantry");
        let per_man = infantry.upkeep / infantry.size as f64;
        let affordable = (net * bf(c, "army_surplus_share") / maxf(per_man, 0.000001)) as i64;
        let grown = (n.peacetime_army as f64 * bf(c, "army_growth_per_year") / 12.0) as i64;
        let target = (n.peacetime_army + grown.min(affordable)).min(self.standing_cap(data, ni));
        if target > n.peacetime_army && self.set_economy_policy(data, tag, "standing_army", target as f64) {
            self.economy_dirty = true;
        }
    }

    /// `AIBudget._points`: in a crisis (mobilized, or at war) a nation short of points buys a batch if it can spare the money.
    fn ai_points(&mut self, data: &Data, tag: &str) {
        let c = &data.ai.raw["budget"];
        let n = self.nation(tag);
        let in_crisis = n.mobilization >= data.diplomacy.min_mobilization || !self.wars_of(tag).is_empty();
        if !in_crisis || n.diplomacy_points >= bf(c, "buy_below") {
            return;
        }
        if n.treasury - self.purchase_price(data, tag) < bf(c, "buy_floor") {
            return;
        }
        if self.buy_points(data, tag) {
            self.economy_dirty = true;
        }
    }
}
