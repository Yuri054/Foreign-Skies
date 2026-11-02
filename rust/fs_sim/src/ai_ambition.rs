//! What an AI nation wants once the opening crisis is over (`scripts/ai/ai_ambition.gd`): a neighbour it could beat and has a reason to fight.
//! It makes a plan against it (the demand, the mobilization and the declaring are the rest of the AI's diplomacy, not ported yet).

use crate::gd::{clampf, maxf};
use crate::navy::string_hash;
use crate::state::{Data, GameState};
use serde_json::{json, Value};

fn af(c: &Value, k: &str) -> f64 {
    c[k].as_f64().unwrap_or_else(|| panic!("ai.json: ambition.{k} is not a number"))
}

impl GameState {
    /// `AIAmbition.step`: once a month per nation.
    pub fn ai_ambition_step(&mut self, data: &Data, tag: &str) {
        let c = &data.ai.raw["ambition"];
        if !c["enabled"].as_bool().unwrap_or(false) || self.nation(tag).provinces.is_empty() {
            return;
        }
        let today = self.calendar.days_elapsed as i64;
        if today < af(c, "start_delay_days") as i64 {
            return;
        }
        if !self.wars_of(tag).is_empty() {
            if self.ai_ambition.contains_key(tag) {
                self.ai_ambition_drop(tag, 0);
            }
            return;
        }
        if let Some((target, since)) = self.ai_ambition.get(tag).cloned() {
            if self.ai_unfit(data, tag, &target) || today - since > af(c, "give_up_days") as i64 {
                self.ai_ambition_drop(tag, af(c, "cooldown_days") as i64);
            }
            return;
        }
        let think = data.ai.raw["think_days"].as_i64().unwrap();
        if today < self.ai_ambition_wait.get(tag).copied().unwrap_or(0) || (today + string_hash(tag) % 90) % af(c, "review_days") as i64 >= think {
            return;
        }
        let Some((target, _)) = self.ai_best_target(data, tag) else { return };
        self.ai_ambition.insert(tag.to_string(), (target.clone(), today));
        self.ai_make_plan(data, tag, &target);
    }

    /// `AIAmbition._unfit`: whether `target` is no longer a fit for `tag`.
    fn ai_unfit(&self, data: &Data, tag: &str, target: &str) -> bool {
        let c = &data.ai.raw["ambition"];
        if !self.nation_index.contains_key(target) || self.nation(target).provinces.is_empty() {
            return true;
        }
        if !self.declare_block(data, tag, target).is_empty() || self.in_truce(data, tag, target) {
            return true;
        }
        self.odds_against(data, tag, target) < self.required_odds(data, tag) * af(c, "odds_margin") * 0.8
    }

    /// `AIAmbition.best_target`: the land neighbour `tag` would most like to fight, with its score.
    pub fn ai_best_target(&self, data: &Data, tag: &str) -> Option<(String, f64)> {
        let c = &data.ai.raw["ambition"];
        let may_declare = !self.pressure_ai || self.tension >= self.war_gate(data, &self.scenario_war_gate);
        if self.temperament(data, tag).0 < af(c, "min_aggression") || !may_declare {
            return None;
        }
        let mut best: Option<(String, f64)> = None;
        let own_gdp = maxf(self.nation(tag).budget.gdp, 0.01);
        for target in self.neighbor_nations(data, tag) {
            if !self.declare_block(data, tag, &target).is_empty() || self.in_truce(data, tag, &target) {
                continue;
            }
            if self.odds_against(data, tag, &target) < self.required_odds(data, tag) * af(c, "odds_margin") {
                continue;
            }
            let score = self.ai_ambition_score(data, tag, &target, own_gdp);
            if score >= af(c, "threshold") && best.as_ref().map(|b| score > b.1 + 0.000001).unwrap_or(true) {
                best = Some((target, score));
            }
        }
        best
    }

    /// `AIAmbition.score_of`.
    pub fn ai_ambition_score(&self, data: &Data, tag: &str, target: &str, own_gdp: f64) -> f64 {
        let c = &data.ai.raw["ambition"];
        let options = self.casus_belli_options(data, tag, target);
        let claim = if options[0] != "none" { 1.0 } else { 0.0 };
        let hostile = clampf(-self.relation(data, tag, target) / 100.0, 0.0, 1.0);
        let grievance = clampf(self.grievance_of(tag, target) / 100.0, 0.0, 1.0);
        let weak = clampf(1.0 - self.nation(target).budget.gdp / own_gdp, 0.0, 1.0);
        let margin = self.odds_against(data, tag, target) / maxf(self.required_odds(data, tag), 0.01);
        let opportunity = clampf(maxf(margin, 1.0).ln() / 10f64.ln(), 0.0, 1.0);
        let w_tension = c.get("w_tension").and_then(Value::as_f64).unwrap_or(0.0);
        let w_neutral = if self.is_neutral(data, target) { c.get("w_neutral").and_then(Value::as_f64).unwrap_or(0.0) } else { 0.0 };
        af(c, "w_claim") * claim + af(c, "w_opportunity") * opportunity + af(c, "w_hostile") * hostile + af(c, "w_grievance") * grievance + af(c, "w_weak") * weak
            + w_tension * self.tension / 100.0 * hostile
            - af(c, "w_guarantee") * self.guarantors_of(target).len() as f64
            - w_neutral
    }

    /// `AIAmbition.drop`: ends an ambition: its plan goes, and the nation waits `cooldown` days before the next.
    pub fn ai_ambition_drop(&mut self, tag: &str, cooldown: i64) {
        self.ai_ambition.remove(tag);
        self.ai_ambition_wait.insert(tag.to_string(), self.calendar.days_elapsed as i64 + cooldown);
        self.ai_plans.retain(|p| !(p["nation"] == tag && p.get("dynamic").and_then(Value::as_bool).unwrap_or(false)));
    }

    /// `AIAmbition._make_plan`: an offensive plan whose objectives are the target's provinces along the border, the capital worth most.
    fn ai_make_plan(&mut self, data: &Data, tag: &str, target: &str) {
        let mut border: Vec<usize> = vec![];
        for &id in &self.nation(target).provinces {
            if data.map.neighbors(id).any(|nb| self.province_owner[nb] == tag) {
                border.push(id);
            }
        }
        border.sort();
        let mut objectives: Vec<Value> = border.iter().take(af(&data.ai.raw["ambition"], "objectives") as usize).map(|&id| json!({"province": id, "weight": 1.0})).collect();
        let capital = self.nation(target).capital;
        if capital > 0 && !border.contains(&(capital as usize)) {
            objectives.push(json!({"province": capital, "weight": 2.0}));
        }
        self.ai_plans.push(json!({"nation": tag, "enemy": target, "posture": "offensive", "objectives": objectives, "dynamic": true}));
    }
}
