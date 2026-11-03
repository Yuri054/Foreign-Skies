//! The AI's diplomacy step (`scripts/ai/ai_diplomacy.gd`, the rest of it): a nation weighs the wars it could declare and declares the best,
//! or makes a demand of a neighbour it has a plan against; once a month it proposes the treaty that is worth most to it and tries to
//! better its standing with a neighbour it needs.

use crate::gd::{clampf, maxf, sort_custom};
use crate::peace::Demand;
use crate::state::{Data, GameState};
use serde_json::{json, Value};
use std::collections::HashMap;

const PROPOSABLE: [&str; 4] = ["alliance", "guarantee", "nap", "passage"];

fn tf(data: &Data, group: &str, k: &str) -> f64 {
    data.ai.diplomacy[group][k].as_f64().unwrap_or_else(|| panic!("ai.json: diplomacy.{group}.{k} is not a number"))
}

impl GameState {
    fn side_of(&self, tag: &str) -> Vec<String> {
        let mut out = vec![tag.to_string()];
        out.extend(self.allies_of(tag));
        out
    }

    /// `AIDiplomacy._may_strike`: whether a nation is mobilized, or resents someone past the retaliation threshold.
    fn ai_may_strike(&self, data: &Data, tag: &str) -> bool {
        if self.nation(tag).mobilization >= data.diplomacy.min_mobilization {
            return true;
        }
        let prefix = format!("{tag}>");
        let threshold = data.diplomacy.raw_war["provocation"]["retaliation_threshold"].as_f64().unwrap();
        self.grievance.iter().any(|(k, v)| k.starts_with(&prefix) && *v >= threshold)
    }

    /// `AIDiplomacy.best_war`: the best war a nation could declare now: (target, cb, desire).
    pub fn ai_best_war(&self, data: &Data, tag: &str) -> Option<(String, String, f64)> {
        if !self.ai_may_strike(data, tag) {
            return None;
        }
        let mut best: Option<(String, String, f64)> = None;
        for target in self.neighbor_nations(data, tag) {
            let c = self.war_check(data, tag, &target);
            if !c.reason.is_empty() {
                continue;
            }
            if best.as_ref().map(|b| c.desire > b.2 + 0.000001).unwrap_or(true) {
                best = Some((target, c.cb, c.desire));
            }
        }
        best
    }

    /// `AIDiplomacy.consider_war`.
    pub fn ai_consider_war(&mut self, data: &Data, tag: &str) {
        if let Some((target, cb, _)) = self.ai_best_war(data, tag) {
            // `issue_quiet(DeclareWar)`: the economy is worked out again at the end of the day
            if self.declare_war_for_points(data, tag, &target, &cb, 0).is_empty() {
                self.economy_dirty = true;
            }
        } else {
            self.ai_consider_press(data, tag);
        }
    }

    /// `Crisis.demand_for`: the demand a goal stands for.
    pub fn crisis_demand_for(goal: &Value) -> Demand {
        if goal["kind"] == "concession" {
            return crate::ai_peace::demand_of(&goal["demand"]).expect("a concession goal names its demand");
        }
        Demand::Province(goal["ids"].as_array().into_iter().flatten().filter_map(|x| x.as_u64().map(|x| x as usize)).collect())
    }

    /// `AIDiplomacy.consider_press`: a nation with a plan against a neighbour, the temper for it and the odds, but no casus belli, makes a
    /// demand of it instead of striking with no cause.
    pub fn ai_consider_press(&mut self, data: &Data, tag: &str) {
        if self.crises.iter().any(|c| c.a == tag) {
            return;
        }
        let w = |k: &str| tf(data, "war", k);
        if self.temperament(data, tag).0 < w("unjustified_min_aggression") {
            return;
        }
        let mut best = String::new();
        let mut best_goal = Value::Null;
        let mut best_desire = f64::NEG_INFINITY;
        for target in self.neighbor_nations(data, tag) {
            if !self.press_block(data, tag, &target, true).is_empty() || self.in_truce(data, tag, &target) || !self.has_plan(tag, &target) {
                continue;
            }
            let options = self.casus_belli_options(data, tag, &target);
            if options[0] != "none" {
                continue;
            }
            let desire = self.war_desire(data, tag, &target, false);
            if desire < w("min_motive") || self.odds_against(data, tag, &target) < self.required_odds(data, tag) * w("odds_margin") {
                continue;
            }
            let goal = self.ai_choose_goal(data, tag, &target);
            if !self.custom_problem(data, tag, &target, &Self::crisis_demand_for(&goal), &goal).is_empty() {
                continue;
            }
            let cost = self.press_cost(data, tag, &goal) + self.points_cost(data, "declare_war", "fabricated_claim");
            if !self.can_afford(tag, cost) {
                continue;
            }
            if desire > best_desire {
                best = target;
                best_goal = goal;
                best_desire = desire;
            }
        }
        if !best.is_empty() {
            let demand = Self::crisis_demand_for(&best_goal);
            if self.press_demand(data, tag, &best, "", Some((demand, best_goal))).is_empty() {
                self.economy_dirty = true;
            }
        }
    }

    /// `AIDiplomacy.choose_goal`: what `tag` would fight `target` for: the provinces its campaign plans aim at, else the richest of the
    /// target's provinces on its border, else (with no border to take) an indemnity.
    pub fn ai_choose_goal(&self, data: &Data, tag: &str, target: &str) -> Value {
        let goals = &data.diplomacy.raw_war["goals"];
        let limit = (goals["max_provinces"].as_i64().unwrap()).min(3);
        let mut wanted: Vec<(usize, f64)> = vec![];
        let put = |wanted: &mut Vec<(usize, f64)>, id: usize, v: f64| match wanted.iter_mut().find(|w| w.0 == id) {
            Some(w) => w.1 = v,
            None => wanted.push((id, v)),
        };
        for plan in &self.ai_plans {
            if plan["nation"] == tag && plan["enemy"] == target {
                for o in plan["objectives"].as_array().into_iter().flatten() {
                    let id = o["province"].as_u64().unwrap() as usize;
                    if self.province_owner[id] == target {
                        put(&mut wanted, id, o["weight"].as_f64().unwrap());
                    }
                }
            }
        }
        if wanted.is_empty() {
            for &id in &self.nation(target).provinces {
                if data.map.neighbors(id).any(|n| self.province_owner[n] == tag) {
                    put(&mut wanted, id, self.province_share(data, id, target));
                }
            }
        }
        if !wanted.is_empty() {
            let lookup: HashMap<usize, f64> = wanted.iter().copied().collect();
            let mut ids: Vec<usize> = wanted.iter().map(|w| w.0).collect();
            sort_custom(&mut ids, |&x, &y| lookup[&x] > lookup[&y] || (lookup[&x] == lookup[&y] && x < y));
            // Only ground that could be handed over at peace: touching its own, and never the capital alone.
            let (takeable, _) = self.pick_takeable(data, tag, target, &ids, &|_| 1.0, limit as f64);
            if !takeable.is_empty() {
                return json!({"kind": "provinces", "ids": takeable, "label": ""});
            }
        }
        let c = &goals["concession"];
        json!({"kind": "concession", "demand": {"kind": "indemnity", "share": c["indemnity_share"], "months": c["indemnity_months"]}, "label": ""})
    }

    // ---------------------------------------------------------------- treaties and relations

    /// `AIDiplomacy.neediness`: how much `tag` needs friends.
    pub fn ai_neediness(&self, data: &Data, tag: &str) -> f64 {
        let mine = maxf(self.side_power(data, &self.side_of(tag)), 0.01);
        let mut worst = 0.0;
        for other in self.neighbor_nations(data, tag) {
            if self.relation(data, &other, tag) < tf(data, "treaties", "rival_relation") {
                worst = maxf(worst, self.side_power(data, &self.side_of(&other)) / mine);
            }
        }
        let mut need = clampf(worst, 0.0, 2.0) / 2.0;
        // A demand made of it makes a nation look for friends, whatever its neighbours' strength.
        if self.crises.iter().any(|c| c.b == tag) {
            need = maxf(need, 0.8);
        }
        need
    }

    fn ai_same_bloc(&self, a: &str, b: &str) -> bool {
        let ba = self.bloc_of(a);
        !ba.is_empty() && ba == self.bloc_of(b)
    }

    /// `AIDiplomacy.treaty_value`: utility of proposing a treaty of this kind, or -1 if it should not.
    pub fn ai_treaty_value(&self, data: &Data, from: &str, to: &str, kind: &str) -> f64 {
        let t = |k: &str| tf(data, "treaties", k);
        if !self.proposal_block(data, from, to, kind).is_empty() || !self.treaty_acceptable(data, from, to, kind) {
            return -1.0;
        }
        let bloc = if self.ai_same_bloc(from, to) { 1.0 } else { 0.0 };
        let friendly = clampf(self.relation(data, to, from) / 100.0, 0.0, 1.0);
        match kind {
            "alliance" => {
                if self.has_plan(from, to) || self.has_plan(to, from) {
                    return -1.0;
                }
                t("w_need") * self.ai_neediness(data, from) + t("w_bloc") * bloc + t("w_relation") * friendly
            }
            "guarantee" => {
                // Guarantee a weaker friend whose neighbour is no friend of ours.
                let mut menace = 0.0;
                for n in self.neighbor_nations(data, to) {
                    if n != from && self.relation(data, from, &n) < t("rival_relation") {
                        menace = maxf(menace, self.side_power(data, &[n]) / maxf(self.side_power(data, &[to.to_string()]), 0.01));
                    }
                }
                if self.side_power(data, &[from.to_string()]) < self.side_power(data, &[to.to_string()]) {
                    return -1.0;
                }
                t("w_menace") * clampf(menace, 0.0, 2.0) / 2.0 + t("w_bloc") * bloc + t("w_relation") * friendly
            }
            "nap" => {
                if self.has_plan(from, to) || !self.neighbor_nations(data, from).iter().any(|n| n == to) {
                    return -1.0;
                }
                let stronger = clampf(self.side_power(data, &[to.to_string()]) / maxf(self.side_power(data, &[from.to_string()]), 0.01), 0.0, 2.0) / 2.0;
                t("w_need") * stronger + t("w_relation") * friendly
            }
            "passage" => {
                let mut value = 0.0;
                for e in self.ai_enemies(from) {
                    if self.neighbor_nations(data, to).contains(&e) && !self.neighbor_nations(data, from).contains(&e) {
                        value = t("w_passage");
                    }
                }
                if value > 0.0 {
                    value
                } else {
                    -1.0
                }
            }
            _ => -1.0,
        }
    }

    fn sorted_tags(&self) -> Vec<String> {
        let mut tags: Vec<String> = self.nations.iter().map(|n| n.tag.clone()).collect();
        tags.sort();
        tags
    }

    /// `AIDiplomacy.best_treaty`: the best treaty to propose this month, as (to, kind), within the nation's points.
    pub fn ai_best_treaty(&self, data: &Data, tag: &str) -> Option<(String, String)> {
        let mut best: Option<(String, String, f64)> = None;
        for other in self.sorted_tags() {
            if other == tag || self.nation(&other).provinces.is_empty() {
                continue;
            }
            for kind in PROPOSABLE {
                let cost = self.points_cost(data, "propose", kind);
                if self.nation(tag).diplomacy_points - cost < tf(data, "treaties", "points_reserve") {
                    continue;
                }
                let value = self.ai_treaty_value(data, tag, &other, kind);
                if value >= tf(data, "treaties", "propose_threshold") && best.as_ref().map(|b| value > b.2 + 0.000001).unwrap_or(true) {
                    best = Some((other.clone(), kind.to_string(), value));
                }
            }
        }
        best.map(|b| (b.0, b.1))
    }

    /// `AIDiplomacy.best_friend`: the nation worth befriending.
    pub fn ai_best_friend(&self, data: &Data, tag: &str) -> Option<String> {
        let t = |k: &str| tf(data, "treaties", k);
        let bar = data.diplomacy.raw_actions["treaty_accept"]["alliance"].as_f64().unwrap();
        let mut best: Option<(String, f64)> = None;
        for other in self.sorted_tags() {
            if other == tag || self.nation(&other).provinces.is_empty() || !self.improve_block(data, tag, &other).is_empty() {
                continue;
            }
            let rel = self.relation(data, &other, tag);
            let mut value = 0.0;
            if self.ai_same_bloc(tag, &other) && rel < bar && rel >= bar - t("improve_window") {
                value = t("w_bloc") + t("w_need") * self.ai_neediness(data, tag);
            } else if self.neighbor_nations(data, tag).contains(&other) && rel < 0.0 && self.ai_neediness(data, tag) > 0.0 && !self.has_plan(tag, &other) {
                value = t("w_need") * self.ai_neediness(data, tag);
            }
            if value >= t("improve_threshold") && best.as_ref().map(|b| value > b.1 + 0.000001).unwrap_or(true) {
                best = Some((other, value));
            }
        }
        best.map(|b| b.0)
    }

    /// `AIDiplomacy.consider_treaties`: once a month, one treaty proposal and one effort to improve relations, within the points the nation
    /// can spare.
    pub fn ai_consider_treaties(&mut self, data: &Data, tag: &str) {
        let stamp = self.calendar.year as i64 * 12 + self.calendar.month as i64;
        if self.ai_diplo_stamp.get(tag).copied().unwrap_or(0) == stamp {
            return;
        }
        self.ai_diplo_stamp.insert(tag.to_string(), stamp);
        let reserve = tf(data, "treaties", "points_reserve");
        // each nation's power added up once while the options are weighed
        let mut powers: HashMap<String, f64> = HashMap::new();
        for a in &self.armies {
            *powers.entry(a.tag.clone()).or_insert(0.0) += a.power(&data.military);
        }
        *self.ai_powers.borrow_mut() = Some(powers);
        let proposal = self.ai_best_treaty(data, tag);
        let friend = self.ai_best_friend(data, tag);
        *self.ai_powers.borrow_mut() = None;
        if let Some((to, kind)) = proposal {
            self.propose_treaty(data, tag, &to, &kind);
        }
        if let Some(to) = friend {
            if self.nation(tag).diplomacy_points - self.points_cost(data, "improve_relations", "") >= reserve {
                self.improve_relations(data, tag, &to);
            }
        }
    }

    /// `AIDiplomacy.step`.
    pub fn ai_diplomacy_step(&mut self, data: &Data, tag: &str) {
        self.ai_consider_war(data, tag);
        self.ai_consider_treaties(data, tag);
    }
}
