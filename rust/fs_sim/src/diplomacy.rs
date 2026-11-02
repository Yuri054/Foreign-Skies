//! Diplomacy (`scripts/sim/diplomacy.gd`) as far as it is ported: the treaties, relations and rivalries a scenario loads
//! with, the day's mobilization and alarms, and the month's points, projects, prestige, grievance, gifts and drift of
//! opinion, with war support's monthly step. Declaring war, proposing treaties, crises, peace and the AI's choices are not
//! ported yet.

use crate::config::DiplomacyConfig;
use crate::gd::{clampf, lerpf, maxf, minf};
use crate::state::{Data, GameState, MobilizationCall, Treaty};
use serde_json::{json, Value};


/// Godot's `is_equal_approx` for floats.
pub fn is_equal_approx(a: f64, b: f64) -> bool {
    if a == b {
        return true;
    }
    let mut tolerance = 0.00001 * a.abs();
    if tolerance < 0.00001 {
        tolerance = 0.00001;
    }
    (a - b).abs() < tolerance
}

/// Godot's `move_toward`: `from` one step of at most `delta` toward `to`.
pub fn move_toward(from: f64, to: f64, delta: f64) -> f64 {
    if (to - from).abs() <= delta {
        to
    } else {
        from + (to - from).signum() * delta
    }
}

impl GameState {
    fn day(&self) -> i64 {
        self.calendar.days_elapsed as i64
    }

    fn clamp_relation(cfg: &DiplomacyConfig, v: f64) -> f64 {
        clampf(v, cfg.relation_min, cfg.relation_max)
    }

    // ---------------------------------------------------------------- blocs and treaties

    /// `Diplomacy.bloc_of`: the bloc a nation belongs to in the scenario, or "" if it stands alone.
    pub fn bloc_of(&self, tag: &str) -> &str {
        for (name, members) in &self.blocs {
            if members.iter().any(|m| m == tag) {
                return name;
            }
        }
        ""
    }

    /// The treaties in force today.
    pub fn active_treaties(&self) -> impl Iterator<Item = &Treaty> {
        let day = self.day();
        self.treaties.iter().filter(move |t| t.active_on(day))
    }

    /// `Diplomacy.treaties_between`: treaties of any kind between two nations, in either direction.
    pub fn treaties_between(&self, a: &str, b: &str) -> Vec<&Treaty> {
        self.active_treaties().filter(|t| (t.a == a && t.b == b) || (t.a == b && t.b == a)).collect()
    }

    /// `Diplomacy.treaties_of`: treaties a nation is party to, optionally of one kind ("" for any).
    pub fn treaties_of(&self, tag: &str, kind: &str) -> Vec<&Treaty> {
        self.active_treaties().filter(|t| t.involves(tag) && (kind.is_empty() || t.kind == kind)).collect()
    }

    /// `Diplomacy.find_treaty`: the treaty of this kind between a and b. Directed kinds only match a -> b.
    pub fn find_treaty(&self, data: &Data, kind: &str, a: &str, b: &str) -> Option<&Treaty> {
        let directed = data.diplomacy.treaty_kind(kind).directed;
        self.active_treaties().find(|t| t.kind == kind && ((t.a == a && t.b == b) || (!directed && t.a == b && t.b == a)))
    }

    pub fn has_treaty(&self, data: &Data, kind: &str, a: &str, b: &str) -> bool {
        self.find_treaty(data, kind, a, b).is_some()
    }

    pub fn are_allied(&self, data: &Data, a: &str, b: &str) -> bool {
        self.has_treaty(data, "alliance", a, b)
    }

    fn seed_treaty(&mut self, data: &Data, kind: &str, a: &str, b: &str, entry: &Value) -> Result<(), String> {
        if !self.nation_index.contains_key(a) || !self.nation_index.contains_key(b) {
            return Err(format!("treaty names an unknown nation: {a}, {b}"));
        }
        if self.has_treaty(data, kind, a, b) {
            return Ok(());
        }
        let terms = entry.get("terms").cloned().unwrap_or_else(|| json!({}));
        let note = entry.get("note").and_then(Value::as_str).unwrap_or("").to_string();
        let t = Treaty { id: self.next_treaty_id, kind: kind.to_string(), a: a.to_string(), b: b.to_string(), start_day: self.day(), end_day: -1, terms, note };
        self.next_treaty_id += 1;
        self.treaties.push(t);
        Ok(())
    }

    /// What the pair's opinion settles at: bloc loyalty plus the bonus of every treaty between them.
    fn baseline(&self, data: &Data, a: &str, b: &str) -> f64 {
        let cfg = &data.diplomacy;
        let mut v = cfg.relation_neutral;
        let (bloc_a, bloc_b) = (self.bloc_of(a), self.bloc_of(b));
        if !bloc_a.is_empty() && !bloc_b.is_empty() {
            v += if bloc_a == bloc_b { cfg.relation_same_bloc } else { cfg.relation_opposed_blocs };
        }
        for t in self.treaties_between(a, b) {
            v += cfg.treaty_kind(&t.kind).relation_bonus;
        }
        Self::clamp_relation(cfg, v)
    }

    /// `Diplomacy.load_scenario`: the treaty web, every pair's opinion and what it settles at, and the old rivalries.
    pub fn load_diplomacy(&mut self, data: &Data, scenario: &Value) -> Result<(), String> {
        self.treaties.clear();
        self.next_treaty_id = 1;
        self.relations.clear();
        self.relation_base.clear();
        self.casus_belli.clear();
        self.grievance.clear();
        self.rivalries.clear();
        self.alarms.clear();
        self.mobilization_calls.clear();
        self.relation_projects.clear();
        self.gift_memory.clear();
        let s = |key: &str| scenario.get(key).and_then(Value::as_array).cloned().unwrap_or_default();
        let text = |e: &Value, k: &str| e.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        for e in s("alliances") {
            self.seed_treaty(data, "alliance", &text(&e, "a"), &text(&e, "b"), &e)?;
        }
        // A neutral pact: the first member is free to stay out of a war the others start. It is an alliance that binds
        // defensively only, plus the clause itself.
        if let Some(pacts) = scenario.get("neutral_pacts").and_then(Value::as_object) {
            for pact in pacts.values() {
                let members: Vec<&str> = pact.as_array().map(|a| a.iter().filter_map(Value::as_str).collect()).unwrap_or_default();
                for i in 1..members.len() {
                    self.seed_treaty(data, "alliance", members[0], members[i], &json!({"terms": {"defensive_only": true}}))?;
                    self.seed_treaty(data, "neutral_pact", members[0], members[i], &json!({}))?;
                }
            }
        }
        for e in s("guarantees") {
            self.seed_treaty(data, "guarantee", &text(&e, "guarantor"), &text(&e, "guaranteed"), &e)?;
        }
        for e in s("passage") {
            self.seed_treaty(data, "passage", &text(&e, "host"), &text(&e, "mover"), &e)?;
        }
        for e in s("nap") {
            self.seed_treaty(data, "nap", &text(&e, "a"), &text(&e, "b"), &e)?;
        }
        let tags: Vec<String> = self.nations.iter().map(|n| n.tag.clone()).collect();
        for i in 0..tags.len() {
            for j in i + 1..tags.len() {
                let key = Self::pair_key(&tags[i], &tags[j]);
                let base = self.baseline(data, &tags[i], &tags[j]);
                self.relation_base.insert(key.clone(), base);
                self.relations.insert(key, base);
            }
        }
        for e in s("relations") {
            let key = Self::pair_key(&text(&e, "a"), &text(&e, "b"));
            if !self.relations.contains_key(&key) {
                return Err(format!("relations entry names an unknown nation pair: {key}"));
            }
            let base = Self::clamp_relation(&data.diplomacy, e.get("value").and_then(Value::as_f64).unwrap_or(0.0));
            self.relation_base.insert(key.clone(), base);
            self.relations.insert(key, base);
        }
        for e in s("rivalries") {
            let (holder, target) = (text(&e, "holder"), text(&e, "target"));
            if self.nation_index.contains_key(&holder) && self.nation_index.contains_key(&target) {
                let g = e.get("grievance").and_then(Value::as_f64).unwrap_or(0.0);
                self.rivalries.insert(format!("{holder}>{target}"), clampf(g, 0.0, 100.0));
            }
        }
        Ok(())
    }

    /// `Diplomacy.add_treaty`: adds a treaty and moves the pair's baseline by its relation bonus. Returns false if one of
    /// this kind already stands between the pair. (The note it makes in the history is not kept.)
    pub fn add_treaty(&mut self, data: &Data, kind: &str, a: &str, b: &str, end_day: i64, terms: Value, note: &str) -> bool {
        if a == b || self.has_treaty(data, kind, a, b) {
            return false;
        }
        let t = Treaty { id: self.next_treaty_id, kind: kind.to_string(), a: a.to_string(), b: b.to_string(), start_day: self.day(), end_day, terms, note: note.to_string() };
        self.next_treaty_id += 1;
        self.treaties.push(t);
        let bonus = data.diplomacy.treaty_kind(kind).relation_bonus;
        self.shift_baseline(data, a, b, bonus);
        true
    }

    /// `Diplomacy.end_treaty`: ends a treaty now (it stays in the list as a record).
    pub fn end_treaty_at(&mut self, data: &Data, index: usize) {
        let day = self.day();
        if !self.treaties[index].active_on(day) {
            return;
        }
        self.treaties[index].end_day = day;
        let (kind, a, b) = (self.treaties[index].kind.clone(), self.treaties[index].a.clone(), self.treaties[index].b.clone());
        let bonus = data.diplomacy.treaty_kind(&kind).relation_bonus;
        self.shift_baseline(data, &a, &b, -bonus);
    }

    /// `Diplomacy.can_afford` and `spend`: a nation's diplomacy points against a price.
    pub fn can_afford(&self, tag: &str, cost: f64) -> bool {
        self.nation(tag).diplomacy_points >= cost
    }

    pub fn spend_points(&mut self, data: &Data, tag: &str, amount: f64) {
        if amount > 0.0 {
            let i = self.nation_index[tag];
            let v = clampf(self.nations[i].diplomacy_points - amount, 0.0, data.diplomacy.points_max);
            if !is_equal_approx(v, self.nations[i].diplomacy_points) {
                self.nations[i].diplomacy_points = v;
            }
        }
    }

    // ---------------------------------------------------------------- grievance

    /// `Diplomacy.add_grievance`: `holder` resents `target` more.
    pub fn add_grievance(&mut self, holder: &str, target: &str, amount: f64) {
        let key = format!("{holder}>{target}");
        let now = self.grievance.get(&key).copied().unwrap_or(0.0);
        self.grievance.insert(key, clampf(now + amount, 0.0, 100.0));
    }

    /// `Diplomacy.neighbor_nations`: nations with land touching `tag`, not counting open-sea links, in the order met.
    pub fn neighbor_nations(&self, data: &Data, tag: &str) -> Vec<String> {
        let mut out: Vec<String> = vec![];
        for &id in &self.nation(tag).provinces {
            for n in data.map.neighbors(id) {
                let o = &self.province_owner[n];
                if o != tag && !out.contains(o) {
                    out.push(o.clone());
                }
            }
        }
        out
    }

    // ---------------------------------------------------------------- the day

    /// `Diplomacy.step_day`: mobilization, the alarms it raises, and the call-ups that follow. Returns whether any nation's
    /// mobilization moved (the economy is then worked out again).
    pub fn diplomacy_step_day(&mut self, data: &Data) -> bool {
        self.step_alarms(data);
        let changed = self.step_mobilization(data);
        // Called nations that have mobilized enough enter their wars (war groups are not ported yet: none are open).
        if changed {
            self.recompute(data);
        }
        changed
    }

    fn step_alarms(&mut self, data: &Data) {
        let c = &data.diplomacy.crisis;
        for ni in 0..self.nations.len() {
            let tag = self.nations[ni].tag.clone();
            if self.nations[ni].provinces.is_empty() {
                // A nation gone from the map stands down: its alarms and the call-ups against it lapse.
                self.nations[ni].mobilization = 0.0;
                self.clear_alarms(&tag);
                continue;
            }
            let mobilization = self.nations[ni].mobilization;
            if mobilization >= c.alarm_level {
                for other in self.neighbor_nations(data, &tag) {
                    let key = format!("{tag}>{other}");
                    if self.alarms.contains_key(&key) || self.at_war(&tag, &other) || self.are_allied(data, &tag, &other) {
                        continue;
                    }
                    self.alarms.insert(key, self.day());
                    self.change_relation(data, &tag, &other, c.alarm_relations);
                    self.add_grievance(&other, &tag, c.alarm_grievance);
                    self.call_up_allies(data, &other, &tag);
                }
            } else if mobilization < c.alarm_clear_level {
                self.clear_alarms(&tag);
            }
        }
    }

    /// The alarms `tag` raised and the call-ups against it end.
    fn clear_alarms(&mut self, tag: &str) {
        let prefix = format!("{tag}>");
        self.alarms.retain(|k, _| !k.starts_with(&prefix));
        self.mobilization_calls.retain(|_, c| c.against != tag);
    }

    /// The allies of an alarmed nation may call up too (they follow the threat).
    fn call_up_allies(&mut self, data: &Data, threatened: &str, threat: &str) {
        let calls: Vec<(String, MobilizationCall)> = self
            .treaties_of(threatened, "alliance")
            .into_iter()
            .filter_map(|t| {
                let ally = t.other(threatened);
                if ally == threat || t.term("entente") || t.term("defensive_only") || self.are_allied(data, ally, threat) {
                    return None;
                }
                Some((format!("{ally}|{threat}"), MobilizationCall { tag: ally.to_string(), for_tag: threatened.to_string(), against: threat.to_string(), day: self.day() }))
            })
            .collect();
        for (k, c) in calls {
            self.mobilization_calls.insert(k, c);
        }
    }

    /// `Diplomacy.mobilization_target`: the level an AI nation wants: match_response of what threatens it, call_response of
    /// what threatens an ally, war_floor if at war. (What the AI's own ambitions and called-to-war joins want is not here.)
    pub fn mobilization_target(&self, data: &Data, tag: &str) -> f64 {
        let c = &data.diplomacy.crisis;
        let mut target = 0.0;
        for key in self.alarms.keys() {
            let mut parts = key.split('>');
            let (from, to) = (parts.next().unwrap(), parts.next().unwrap());
            if to == tag {
                target = maxf(target, self.nation(from).mobilization * c.match_response);
            }
        }
        for call in self.mobilization_calls.values() {
            if call.tag == tag {
                target = maxf(target, self.nation(&call.against).mobilization * c.call_response);
            }
        }
        if self.is_at_war(tag) {
            target = maxf(target, c.war_floor);
        }
        target
    }

    /// Moves every nation's mobilization one day: the AI toward what it wants, the player only up to the war floor.
    fn step_mobilization(&mut self, data: &Data) -> bool {
        let c = &data.diplomacy.crisis;
        let mut changed = false;
        for ni in 0..self.nations.len() {
            if self.nations[ni].provinces.is_empty() {
                continue;
            }
            let tag = self.nations[ni].tag.clone();
            let at_war = self.is_at_war(&tag);
            let before = self.nations[ni].mobilization;
            let mut m = before;
            if tag == self.player_tag {
                if at_war && m < c.war_floor {
                    m = minf(c.war_floor, m + c.war_step_up);
                }
            } else {
                let target = self.mobilization_target(data, &tag);
                if m < target {
                    m = minf(target, m + c.ai_step_up);
                } else if m > target && !at_war {
                    m = maxf(target, m - c.ai_step_down);
                }
            }
            // The range the nation may mobilize in: down to its ceiling at once, up to its floor a step a day.
            let (least, cap) = self.mobilization_range(data, &tag);
            if m > cap {
                m = cap;
            } else if m < least {
                m = minf(least, m + c.war_step_up);
            }
            self.nations[ni].mobilization = m;
            if !is_equal_approx(before, m) {
                changed = true;
            }
        }
        changed
    }

    // ---------------------------------------------------------------- the month

    /// `Standings.value` for output: what the economy produces each month.
    fn gdp_standing(&self, tag: &str) -> f64 {
        self.nation(tag).budget.gdp / 12.0
    }

    /// `Standings.rank_of` for output: 1 for the best, or 0 if the nation holds no land. Ties keep tag order.
    pub fn output_rank(&self, tag: &str) -> usize {
        let mut list: Vec<(&str, f64)> =
            self.nations.iter().filter(|n| !n.provinces.is_empty()).map(|n| (n.tag.as_str(), self.gdp_standing(&n.tag))).collect();
        // an insertion sort by the game's comparison (best output first, then tag order)
        let before = |a: &(&str, f64), b: &(&str, f64)| if !is_equal_approx(a.1, b.1) { a.1 > b.1 } else { a.0 < b.0 };
        for i in 1..list.len() {
            let mut j = i;
            while j > 0 && before(&list[j], &list[j - 1]) {
                list.swap(j, j - 1);
                j -= 1;
            }
        }
        list.iter().position(|(t, _)| *t == tag).map(|i| i + 1).unwrap_or(0)
    }

    /// `Diplomacy.point_income`: what a nation earns each month in diplomacy points.
    pub fn point_income(&self, data: &Data, tag: &str) -> f64 {
        let c = &data.diplomacy;
        let n = self.nation(tag);
        let base = c.income_base;
        let prestige = n.prestige * c.income_prestige_weight;
        let rank = self.output_rank(tag);
        let output = if rank > 0 && (rank as i64) <= c.income_top_output_count { c.income_top_output_bonus } else { 0.0 };
        let focus = n.focus_diplomacy;
        maxf(base + prestige + output + focus, c.income_min)
    }

    /// `Diplomacy._shift_baseline`, for the other modules.
    pub fn shift_baseline_pub(&mut self, data: &Data, a: &str, b: &str, delta: f64) {
        self.shift_baseline(data, a, b, delta);
    }

    fn shift_baseline(&mut self, data: &Data, a: &str, b: &str, delta: f64) {
        let key = Self::pair_key(a, b);
        let now = self.relation_base.get(&key).copied().unwrap_or(data.diplomacy.relation_neutral);
        self.relation_base.insert(key, Self::clamp_relation(&data.diplomacy, now + delta));
    }

    /// `Diplomacy.step_month`: points are earned, opinion projects work, prestige fades, resentment cools, gifts are
    /// forgotten, war support moves, and every opinion drifts a step toward its baseline. (The month's peace business,
    /// the war scores, indemnities, restrictions and the AI's overtures, is not ported yet.)
    pub fn diplomacy_step_month(&mut self, data: &Data) {
        let cfg = &data.diplomacy;
        // points
        for i in 0..self.nations.len() {
            if !self.nations[i].provinces.is_empty() {
                let tag = self.nations[i].tag.clone();
                let income = self.point_income(data, &tag);
                self.gain_points(data, &tag, income);
            }
        }
        // projects
        for i in (0..self.relation_projects.len()).rev() {
            let (from, to) = (self.relation_projects[i].from.clone(), self.relation_projects[i].to.clone());
            if self.at_war(&from, &to) {
                self.relation_projects.remove(i);
                continue;
            }
            self.change_relation(data, &from, &to, cfg.improve_monthly);
            self.shift_baseline(data, &from, &to, cfg.improve_base_monthly);
            self.relation_projects[i].months_left -= 1;
            if self.relation_projects[i].months_left <= 0 {
                self.relation_projects.remove(i);
            }
        }
        // prestige fades
        let keep = 1.0 - cfg.prestige_decay_per_month;
        for n in &mut self.nations {
            n.prestige *= keep;
            n.points_price = lerpf(1.0, n.points_price, cfg.price_decay);
        }
        // grievance
        for v in self.grievance.values_mut() {
            *v = maxf(0.0, *v - cfg.grievance_decay_per_month);
        }
        let fade = cfg.rivalry_fade_per_year / 12.0;
        for v in self.rivalries.values_mut() {
            *v = maxf(0.0, *v - fade);
        }
        self.rivalries.retain(|_, v| *v > 0.0);
        let today = self.day();
        self.casus_belli.retain(|cb| cb.expires_day > today);
        // gifts
        let decay = cfg.gift_memory_decay;
        for v in self.gift_memory.values_mut() {
            *v *= decay;
        }
        self.gift_memory.retain(|_, v| *v >= 0.05);
        self.war_support_step_month(data);
        // every opinion moves a step toward its baseline
        let keys: Vec<String> = self.relations.keys().cloned().collect();
        for key in keys {
            let base = self.relation_base[&key];
            let v = self.relations[&key];
            if is_equal_approx(v, base) {
                continue;
            }
            let (a, b) = key.split_once('|').unwrap();
            let (a, b) = (a.to_string(), b.to_string());
            self.set_relation(data, &a, &b, move_toward(v, base, cfg.relation_drift_per_month));
        }
    }

    // ---------------------------------------------------------------- war support (`scripts/sim/war_support.gd`)

    /// `WarSupport.occupied_share`: the share of a nation's people living in provinces an enemy holds.
    pub fn occupied_share(&self, tag: &str) -> f64 {
        let n = self.nation(tag);
        let mut held = 0.0;
        for &id in &n.provinces {
            let holder = &self.province_controller[id];
            if holder != tag && self.at_war(tag, holder) {
                held += self.province_population[id] as f64;
            }
        }
        held / maxf(n.population as f64, 1.0)
    }

    /// `WarSupport.monthly_changes`: what moves a nation's war support this month, by cause, in the game's order.
    pub fn war_support_changes(&self, data: &Data, tag: &str) -> Vec<(&'static str, f64)> {
        let (c, e) = (&data.war_support, &data.economy);
        let n = self.nation(tag);
        let econ = n.econ();
        let strain = crate::economy::tax_strain(e, &econ);
        if !self.is_at_war(tag) {
            // Heavy taxes lower the level the people settle at; light ones raise it a little.
            let settle = n.war_support_base - e.tax_strain_support_penalty * strain + e.tax_relief_support_bonus * crate::economy::tax_relief(e, &econ);
            return vec![("settling back", clampf(settle - n.war_support, -c.recovery_per_month, c.recovery_per_month))];
        }
        let total_men = (n.manpower + n.men_in_units) as f64;
        let lost = n.men_lost_month / maxf(total_men + n.men_lost_month, 1.0);
        let debt = maxf(-n.treasury, 0.0) / maxf(n.budget.revenue, 1.0);
        vec![
            ("the war itself", -c.weariness),
            ("heavy taxes", -e.tax_strain_war_weariness * strain),
            ("men lost", -c.casualty_weight * lost),
            ("blockade", -c.blockade_weight * n.blockade),
            ("ground lost", -c.occupied_weight * self.occupied_share(tag)),
            ("debt", -minf(c.debt_cap, c.debt_weight * debt)),
        ]
    }

    /// `WarSupport.step_month`: support moves with what the war has cost. (A nation whose support has collapsed is forced
    /// into a white peace by the game, which needs the peace rules: not ported, so this stops if it would happen.)
    pub fn war_support_step_month(&mut self, data: &Data) {
        for i in 0..self.nations.len() {
            if self.nations[i].provinces.is_empty() {
                continue;
            }
            let tag = self.nations[i].tag.clone();
            let mut total = 0.0;
            for (_, v) in self.war_support_changes(data, &tag) {
                total += v;
            }
            self.change_war_support(&tag, total);
            self.nations[i].men_lost_month = 0.0;
        }
        self.recompute(data);
        for n in &self.nations {
            if n.war_support <= data.war_support.white_peace_below && self.is_at_war(&n.tag) {
                panic!("{} would be forced into a white peace: the peace rules are not ported yet", n.tag);
            }
        }
    }
}
