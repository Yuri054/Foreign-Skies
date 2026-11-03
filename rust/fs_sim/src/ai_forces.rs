//! The AI's recruiting and the queries it weighs it by (`scripts/ai/ai_forces.gd` and the shared queries of `ai.gd`: hops, threat, what a
//! province is worth): a nation at war with a front to hold raises units behind its most threatened line; in peace it rebuilds what a war
//! cost it and, some time after its last war, sends home the men it no longer needs.

use crate::gd::{maxf, clampf};
use crate::state::{Data, GameState};
use serde_json::Value;
use std::collections::HashMap;

fn ff(c: &Value, k: &str) -> f64 {
    c[k].as_f64().unwrap_or_else(|| panic!("ai.json: {k} is not a number"))
}

impl GameState {
    /// `AI.hops_from`: provinces within `hops` steps of `id` (itself included) as (province, hops), in the order they were found.
    pub fn hops_from(&self, data: &Data, id: usize, hops: i64) -> Vec<(usize, i64)> {
        let mut seen: std::collections::HashSet<usize> = [id].into_iter().collect();
        let mut out = vec![(id, 0)];
        let mut frontier = vec![id];
        for step in 1..=hops {
            let mut next = vec![];
            for &cur in &frontier {
                for n in data.map.neighbors(cur) {
                    if seen.insert(n) {
                        out.push((n, step));
                        next.push(n);
                    }
                }
            }
            frontier = next;
        }
        out
    }

    /// `AI.enemy_power`: the power of the armies of every nation `tag` is at war with, in full inside the province and cut by `hop_decay`
    /// per hop around it.
    pub fn ai_enemy_power(&self, data: &Data, tag: &str, province: usize) -> f64 {
        let t = &data.ai.raw["threat"];
        let near = self.hops_from(data, province, t["hops"].as_i64().unwrap());
        let decay = ff(t, "hop_decay");
        let mut power = 0.0;
        self.ai_refresh_index();
        for (id, hops) in near {
            for aid in self.ai_index_at(id) {
                let a = self.army_ref(aid);
                if a.tag != tag && self.at_war(tag, &a.tag) {
                    power += a.power(&data.military) * decay.powf(hops as f64);
                }
            }
        }
        power
    }

    /// `AI.armies_by_province`: builds the day's index of armies by province if the day, the number of armies or wars, or the next army's
    /// number is not what it was built for (an army that moves afterwards stays where it was listed).
    pub fn ai_refresh_index(&self) {
        let key = self.calendar.days_elapsed as i64 * 1000003 + self.armies.len() as i64 * 1009 + self.next_army_id as i64 * 7 + self.wars.len() as i64;
        let mut idx = self.ai_index.borrow_mut();
        if idx.0 != key {
            let mut map: HashMap<usize, Vec<u32>> = HashMap::new();
            for a in &self.armies {
                map.entry(a.province).or_default().push(a.id);
            }
            *idx = (key, map);
            self.ai_threat_cache.borrow_mut().clear();
        }
    }

    /// The armies listed in a province by the day's index.
    pub fn ai_index_at(&self, province: usize) -> Vec<u32> {
        self.ai_index.borrow().1.get(&province).cloned().unwrap_or_default()
    }

    /// `AI.value`: what a province is worth to its owner, 0 to about 1.5.
    pub fn ai_value(&self, data: &Data, province: usize) -> f64 {
        let v = &data.ai.raw["value"];
        let owner = &self.province_owner[province];
        let n = self.nation(owner);
        let (mut people, mut output) = (0.0, 0.0);
        if n.population > 0 {
            people = self.province_population[province] as f64 / n.population as f64;
        }
        // a nation's output, kept for the day and while its land is unchanged (`AI._output_total`)
        let key = self.calendar.days_elapsed as i64 * 1000003 + self.owner_version as i64;
        let cached = self.ai_worth_cache.borrow().get(owner.as_str()).filter(|e| e.0 == key).map(|e| e.1);
        let total = match cached {
            Some(t) => t,
            None => {
                let mut t = 0.0;
                for &id in &n.provinces {
                    t += self.province_gdp[id] as f64 + self.province_industry[id] as f64;
                }
                self.ai_worth_cache.borrow_mut().insert(owner.clone(), (key, t));
                t
            }
        };
        if total > 0.0 {
            output = (self.province_gdp[province] as f64 + self.province_industry[province] as f64) / total;
        }
        let mut score = ff(v, "people") * people + ff(v, "output") * output;
        if province as i64 == n.capital {
            score += ff(v, "capital_bonus");
        }
        score
    }

    /// `AI.threat`: the enemy power bearing on a province held by `tag`, times 1 + stakes * value(province).
    pub fn ai_threat(&self, data: &Data, tag: &str, province: usize) -> f64 {
        self.ai_refresh_index();
        if let Some(t) = self.ai_threat_cache.borrow().get(&(tag.to_string(), province)) {
            return *t;
        }
        let t = self.ai_enemy_power(data, tag, province) * (1.0 + ff(&data.ai.raw["threat"], "stakes") * self.ai_value(data, province));
        self.ai_threat_cache.borrow_mut().insert((tag.to_string(), province), t);
        t
    }

    // ---------------------------------------------------------------- recruiting

    /// `AIForces.step`: a nation at war with a front to hold (or home ground to retake) raises a couple of units a turn behind its most
    /// threatened line, up to its war strength.
    pub fn ai_forces_step(&mut self, data: &Data, tag: &str) {
        if !self.ai_needs_forces(tag) {
            return;
        }
        let f = &data.ai.raw["forces"];
        let target = self.nation(tag).peacetime_army as f64 * ff(f, "war_multiplier");
        let province = self.ai_where(data, tag);
        if province == 0 {
            return;
        }
        for _ in 0..ff(f, "per_turn") as i64 {
            if self.nation(tag).recruiting.len() as i64 >= ff(f, "max_training") as i64 || self.men_in_service(data, tag) as f64 >= target {
                return;
            }
            let kind = self.ai_next_type(data, tag);
            if !self.ai_unit_affordable(data, tag, &kind) {
                return;
            }
            if !self.raise_units(data, tag, province, &kind, 1) {
                return;
            }
            self.economy_dirty = true;
        }
    }

    /// `AIForces.rebuild`: in peace, a nation well under its peacetime army raises units at its capital.
    pub fn ai_forces_rebuild(&mut self, data: &Data, tag: &str) {
        let a = &data.ai.raw["ambition"];
        let n = self.nation(tag);
        if !a["enabled"].as_bool().unwrap_or(false) || n.provinces.is_empty() || self.province_controller[n.capital as usize] != tag {
            return;
        }
        let target = n.peacetime_army as f64 * ff(a, "rebuild_share");
        let capital = n.capital as usize;
        let f = &data.ai.raw["forces"];
        for _ in 0..ff(f, "per_turn") as i64 {
            if self.nation(tag).recruiting.len() as i64 >= ff(f, "max_training") as i64 || self.men_in_service(data, tag) as f64 >= target {
                return;
            }
            let kind = self.ai_next_type(data, tag);
            if !self.ai_unit_affordable(data, tag, &kind) {
                return;
            }
            if !self.raise_units(data, tag, capital, &kind, 1) {
                return;
            }
            self.economy_dirty = true;
        }
    }

    /// `AIForces.demobilize`: in peace, some time after its last war, a nation that is not alarmed, not mobilized and not working toward a
    /// war sends home a share of the men it has above its peacetime army.
    pub fn ai_forces_demobilize(&mut self, data: &Data, tag: &str) {
        let f = &data.ai.raw["forces"];
        let n = self.nation(tag);
        if n.mobilization >= data.diplomacy.crisis.alarm_level || self.ai_ambition.contains_key(tag) {
            return;
        }
        let mut last_end = -1;
        for w in &self.war_history {
            if w.a == tag || w.b == tag {
                last_end = last_end.max(w.end_day);
            }
        }
        if last_end >= 0 && (self.calendar.days_elapsed as i64 - last_end) < ff(f, "demob_after_days") as i64 {
            return;
        }
        let suffix = format!(">{tag}");
        if self.alarms.keys().any(|k| k.ends_with(&suffix)) {
            return;
        }
        if self.crises.iter().any(|c| c.a == tag || c.b == tag) {
            return;
        }
        let excess = n.men_in_units as f64 - n.peacetime_army as f64 * ff(f, "demob_margin");
        if excess <= 0.0 {
            return;
        }
        let units: usize = self.armies.iter().filter(|a| a.tag == tag).map(|a| a.units.len()).sum();
        if units == 0 {
            return;
        }
        let per_unit = n.men_in_units as f64 / units as f64;
        let count = (excess * ff(f, "demob_share") / maxf(per_unit, 1.0)).ceil() as i64;
        if self.demobilize_units(data, tag, 0, count) {
            self.economy_dirty = true;
        }
    }

    /// `AIForces._needs_forces`: whether there is a war to raise troops for: a front to hold, or home ground in enemy hands.
    fn ai_needs_forces(&self, tag: &str) -> bool {
        if self.wars_of(tag).is_empty() {
            return false;
        }
        if self.fronts.iter().any(|f| f.tag == tag) {
            return true;
        }
        self.nation(tag).provinces.iter().any(|&p| self.province_controller[p] != tag)
    }

    /// `AIForces._affordable`: whether the nation can pay for a unit and stay within its limits.
    fn ai_unit_affordable(&self, data: &Data, tag: &str, kind: &str) -> bool {
        let f = &data.ai.raw["forces"];
        let n = self.nation(tag);
        let def = data.military.unit_type(kind);
        if n.manpower < def.size {
            return false;
        }
        let cost = def.cost;
        let cushion = maxf(0.0, -n.budget.net / 12.0) * ff(f, "deficit_months");
        if n.treasury - cost < ff(f, "treasury_floor") + cushion {
            return false;
        }
        let mut in_training = cost;
        for job in &n.recruiting {
            in_training += data.military.unit_type(&job.unit_type).cost;
        }
        let monthly = maxf(0.0, n.budget.revenue) / 12.0;
        in_training <= ff(f, "income_share") * monthly * ff(f, "horizon_months")
    }

    /// `AIForces._next_type`: the unit type furthest below its share of the force (men in armies and in training).
    fn ai_next_type(&self, data: &Data, tag: &str) -> String {
        let mut have: Vec<(String, f64)> = vec![];
        let add = |have: &mut Vec<(String, f64)>, k: &str, by: f64| match have.iter_mut().find(|(t, _)| t == k) {
            Some(s) => s.1 += by,
            None => have.push((k.to_string(), by)),
        };
        let mut total = 0.0;
        for a in self.armies.iter().filter(|a| a.tag == tag) {
            for u in &a.units {
                let m = u.men(&data.military);
                add(&mut have, &u.unit_type, m);
                total += m;
            }
        }
        for job in &self.nation(tag).recruiting {
            let size = data.military.unit_type(&job.unit_type).size as f64;
            add(&mut have, &job.unit_type, size);
            total += size;
        }
        let mix = data.ai.raw["forces"]["mix"].as_object().unwrap();
        let mut types: Vec<&String> = mix.keys().collect();
        types.sort();
        let mut best = String::new();
        let mut best_gap = f64::NEG_INFINITY;
        for t in types {
            let h = have.iter().find(|(k, _)| k == t).map(|x| x.1).unwrap_or(0.0);
            let gap = mix[t].as_f64().unwrap() - if total > 0.0 { h / total } else { 0.0 };
            if gap > best_gap + 0.000001 {
                best = t.clone();
                best_gap = gap;
            }
        }
        best
    }

    /// `AIForces._where`: the safest province the nation owns and holds within `train_hops` of its most threatened line province (the capital
    /// if there is no line); 0 for none.
    fn ai_where(&self, data: &Data, tag: &str) -> usize {
        let mut hot = 0usize;
        let mut hot_threat = -1.0;
        for fr in self.fronts.iter().filter(|f| f.tag == tag) {
            for &p in &fr.provinces {
                let t = self.ai_threat(data, tag, p);
                if t > hot_threat + 0.000001 || ((t - hot_threat).abs() <= 0.000001 && p < hot) {
                    hot = p;
                    hot_threat = t;
                }
            }
        }
        let n = self.nation(tag);
        if hot == 0 {
            return if self.province_controller[n.capital as usize] == tag { n.capital as usize } else { 0 };
        }
        let mut ids: Vec<usize> = self.hops_from(data, hot, data.ai.raw["forces"]["train_hops"].as_i64().unwrap()).into_iter().map(|x| x.0).collect();
        ids.sort();
        let mut best = 0;
        let mut best_threat = f64::INFINITY;
        for id in ids {
            if self.province_owner[id] != tag || self.province_controller[id] != tag {
                continue;
            }
            let t = self.ai_threat(data, tag, id);
            if t < best_threat - 0.000001 {
                best = id;
                best_threat = t;
            }
        }
        best
    }
}

#[allow(dead_code)]
fn _unused() -> f64 {
    clampf(0.0, 0.0, 1.0)
}
