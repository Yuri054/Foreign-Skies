//! The AI's turn (`scripts/ai/ai.gd`, `ai_budget.gd`, `ai_focus.gd`): every `think_days` days each AI nation thinks, and what it does goes
//! through the commands the player uses. Only the parts named in `AiTurn` are ported; the rest of the turn (defence, offence, forces,
//! navy, landing, diplomacy, ambition) is not, and does nothing.

use crate::gd::{clampf, is_equal_approx, maxf, minf, snappedf};
use crate::state::{Data, GameState};
use serde_json::Value;

/// Which parts of the AI's turn are switched on. By default none: the AI does not play.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
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
        let n = self.nation(tag);
        let fx = &f.effects;
        let mut score = f.ai;
        let at_war = !self.wars_of(tag).is_empty();
        if at_war && (fx.army_size.is_some() || fx.construction.is_some() || fx.war_support.is_some()) {
            score += 1.0;
        }
        if !at_war && (fx.gdp.is_some() || fx.industry.is_some() || fx.growth.is_some()) {
            score += 0.5;
        }
        if fx.food.is_some() && n.budget.food_production < n.population as f64 * 0.9 {
            score += 1.0;
        }
        if f.has_claim && !at_war {
            score += 0.3;
        }
        score - f.days as f64 / 1000.0
    }

    // ---------------------------------------------------------------- budget

    /// `AIBudget.step`: once a month a light budget so that the nation does not drift into ruin. (`AINavy.build`, between the buildings
    /// and the points, is not ported yet.)
    pub fn ai_budget_step(&mut self, data: &Data, tag: &str) {
        let c = &data.ai.raw["budget"];
        let stamp = self.calendar.year as i64 * 12 + self.calendar.month as i64;
        if self.ai_budget_stamp.get(tag).copied().unwrap_or(0) == stamp || !c["enabled"].as_bool().unwrap_or(false) {
            return;
        }
        self.ai_budget_stamp.insert(tag.to_string(), stamp);
        self.ai_taxes(data, tag);
        self.ai_arms(data, tag);
        self.ai_buildings(data, tag);
        if self.ai_turn.navy {
            self.ai_navy_build(data, tag);
        }
        self.ai_points(data, tag);
    }

    fn monthly_expenses(&self, tag: &str) -> f64 {
        maxf(self.nation(tag).budget.expenses / 12.0, 0.1)
    }

    /// `AIBudget.wanted_tax`.
    pub fn ai_wanted_tax(&self, data: &Data, tag: &str) -> f64 {
        let c = &data.ai.raw["budget"];
        let n = self.nation(tag);
        let net_m = n.budget.net / 12.0;
        let at_war = !self.wars_of(tag).is_empty();
        let top = if at_war { bf(c, "tax_max_war") } else { bf(c, "tax_max") };
        let rate = n.tax_rate;
        let mut short = n.treasury < 0.0 && net_m * bf(c, "repay_months") < -n.treasury;
        short = short || (net_m < 0.0 && n.treasury < -net_m * bf(c, "cushion_months"));
        if short {
            return minf(rate + bf(c, "tax_step"), top);
        }
        let rich = net_m > 0.0 && n.treasury > self.monthly_expenses(tag) * bf(c, "rich_months");
        let tax_min = c.get("tax_min").and_then(Value::as_f64).unwrap_or(data.economy.default_tax_rate);
        if rich && rate > tax_min + 0.0001 {
            return maxf(rate - bf(c, "tax_step"), tax_min);
        }
        minf(rate, top)
    }

    /// `AIBudget.wanted_investment`.
    pub fn ai_wanted_investment(&self, data: &Data, tag: &str) -> f64 {
        let c = &data.ai.raw["budget"];
        let n = self.nation(tag);
        if !self.wars_of(tag).is_empty() || n.treasury <= 0.0 {
            return 0.0;
        }
        let surplus = (n.budget.net + n.budget.investment) / 12.0;
        if surplus <= 0.0 || n.treasury < self.monthly_expenses(tag) * bf(c, "rich_months") {
            return 0.0;
        }
        let most = n.budget.gdp / 12.0 * c.get("invest_max_share").and_then(Value::as_f64).unwrap_or(1.0);
        snappedf(minf(surplus * c.get("invest_share").and_then(Value::as_f64).unwrap_or(0.0), most), 0.1)
    }

    fn ai_taxes(&mut self, data: &Data, tag: &str) {
        let rate = self.ai_wanted_tax(data, tag);
        if !is_equal_approx(rate, self.nation(tag).tax_rate) {
            self.set_economy_policy(data, tag, "tax_rate", rate);
            self.economy_dirty = true;
        }
        let invest = self.ai_wanted_investment(data, tag);
        if (invest - self.nation(tag).investment).abs() > 0.05 {
            self.set_economy_policy(data, tag, "investment", invest);
            self.economy_dirty = true;
        }
    }

    /// `AIBudget.wanted_arms_share`.
    pub fn ai_wanted_arms_share(&self, data: &Data, tag: &str) -> f64 {
        let c = &data.ai.raw["munitions"];
        let n = self.nation(tag);
        if !self.wars_of(tag).is_empty() {
            return bf(c, "war_share");
        }
        let in_crisis = n.mobilization >= data.diplomacy.crisis.alarm_level || self.crises.iter().any(|x| x.a == tag || x.b == tag);
        if in_crisis {
            return bf(c, "crisis_share");
        }
        clampf(bf(c, "peace_share") + bf(c, "peace_per_tension") * self.tension / 100.0, 0.0, 1.0)
    }

    fn ai_arms(&mut self, data: &Data, tag: &str) {
        let c = &data.ai.raw["munitions"];
        let share = self.ai_wanted_arms_share(data, tag);
        if (share - self.nation(tag).arms_share).abs() > 0.005 {
            self.set_economy_policy(data, tag, "arms_share", share);
            self.economy_dirty = true;
        }
        // At war, a stockpile running low is filled from abroad while the treasury can bear it.
        if self.wars_of(tag).is_empty() {
            return;
        }
        let ni = self.nation_index[tag];
        let need = self.expected_daily(data, ni);
        let days_left = if need <= 0.0 { f64::INFINITY } else { self.nations[ni].munitions / need };
        if days_left >= bf(c, "min_days") {
            return;
        }
        let want = (bf(c, "min_days") * need - self.nations[ni].munitions) * data.economy.munitions_import_price;
        let spend = minf(want, maxf(0.0, self.nations[ni].treasury) * bf(c, "buy_treasury_share"));
        if spend > 0.1 && self.buy_munitions(data, tag, spend) {
            self.economy_dirty = true;
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

    /// `AIBudget.build_return`: what a building would earn a year in a province, per pound it costs.
    pub fn ai_build_return(&self, data: &Data, tag: &str, id: usize, kind: &str, total: f64) -> f64 {
        let c = &data.ai.raw["budget"];
        let def = data.economy.buildings.iter().find(|b| b.id == kind).unwrap();
        let e = &def.effects;
        let (g, ind) = (self.province_gdp[id] as f64, self.province_industry[id] as f64);
        let output = g + ind;
        let mut gain = e.gdp * g + e.industry * ind;
        gain += e.trade * output * 0.5;
        gain += e.food * output * bf(c, "food_value");
        if kind == "railway" && self.ai_near_front(data, tag, id) {
            gain += output * bf(c, "front_railway_bonus");
        }
        if (kind == "trench" || kind == "fortification") && !self.wars_of(tag).is_empty() && self.ai_near_front(data, tag, id) {
            gain += output * bf(c, "front_works_bonus");
        }
        if id as i64 == self.nation(tag).capital {
            gain *= bf(c, "capital_multiplier");
        }
        gain / maxf(total, 0.01)
    }

    /// `AIBudget._buildings`: one building a month, where it earns most.
    fn ai_buildings(&mut self, data: &Data, tag: &str) {
        let c = &data.ai.raw["budget"];
        let n = self.nation(tag);
        if n.construction.len() as i64 >= bf(c, "max_construction") as i64 || n.budget.net < bf(c, "build_min_net") {
            return;
        }
        let mut places: Vec<usize> = vec![];
        let mut owned: Vec<usize> = n.provinces.clone();
        let out = |x: usize| self.province_gdp[x] as f64 + self.province_industry[x] as f64;
        crate::gd::sort_custom(&mut owned, |&x, &y| out(x) > out(y) || (out(x) == out(y) && x < y));
        for &id in owned.iter().take(bf(c, "candidates") as usize) {
            places.push(id);
        }
        let capital = n.capital;
        if capital > 0 && !places.contains(&(capital as usize)) {
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
        let mut best_id = 0;
        let mut best_type = String::new();
        let mut best_value = bf(c, "min_return");
        for &id in &places {
            for def in &data.economy.buildings {
                if !self.build_problem(data, tag, id, &def.id, false).is_empty() {
                    continue;
                }
                let (ic, _, _) = self.plan_for(data, id, &def.id);
                let value = self.ai_build_return(data, tag, id, &def.id, ic * data.economy.ic_value);
                if value > best_value + 0.000001 {
                    best_id = id;
                    best_type = def.id.clone();
                    best_value = value;
                }
            }
        }
        if best_id > 0 && self.construct_building(data, tag, best_id, &best_type) {
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
