//! Historical pressure (`scripts/sim/pressure.gd`): how close Europe is to a great war, and the events that push it there or
//! hold it off. Tension (0 to 100) is made of the arms race, mobilization, hostile great powers and wars, plus the lasting
//! force of events. Events (`data/events.json`) are the crises of 1900 to 1914: the player answers those that concern their
//! nation, the rest happen by the AI's choice and are news.
//!
//! Not ported: the two events that start a war or open a crisis (the port stops with a message if one comes up), the texts
//! the screens show (`effect_lines`, `advisor_line`, `tip`), and the history log.

use crate::gd::{clampf, inverse_lerp, lerpf, maxf, minf};
use crate::state::{Data, GameState, PendingEvent};
use serde_json::Value;

pub const GREAT: [&str; 6] = ["GBR", "FRA", "GER", "RUS", "AUH", "ITA"];
const CHRONICLE_MAX: usize = 40;

pub type Roles = Vec<(String, String)>;

fn role_get<'a>(roles: &'a Roles, key: &str) -> Option<&'a str> {
    roles.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str())
}

fn role_set(roles: &mut Roles, key: &str, value: &str) {
    match roles.iter_mut().find(|(k, _)| k == key) {
        Some(slot) => slot.1 = value.to_string(),
        None => roles.push((key.to_string(), value.to_string())),
    }
}

/// The parts of tension (`Pressure.parts`).
#[derive(Debug, Clone, Copy, Default, serde::Serialize, serde::Deserialize)]
pub struct TensionParts {
    pub arms: f64,
    pub mobilization: f64,
    pub wars: f64,
    pub rivalry: f64,
    pub events: f64,
    pub total: f64,
}

/// `Pressure._index_of`: an event date [year, month] as year * 12 + month.
fn index_of(date: &Value) -> i64 {
    date[0].as_i64().unwrap_or(0) * 12 + date[1].as_i64().unwrap_or(0)
}

impl GameState {
    fn month_index(&self) -> i64 {
        self.calendar.year as i64 * 12 + self.calendar.month as i64
    }

    /// `Pressure.load_scenario`: no events fired, tension at what the world's armies and quarrels make it.
    pub fn load_pressure(&mut self, data: &Data, scenario: &Value) {
        self.events_fired.clear();
        self.appeal_ready.clear();
        self.pending_events.clear();
        self.chronicle.clear();
        self.tension_history.clear();
        self.pressure_start = self.month_index();
        self.pressure_ai = scenario.get("pressure_ai").and_then(Value::as_bool).unwrap_or(false);
        self.tension_impulse = scenario.get("start_tension").and_then(Value::as_f64).unwrap_or(0.0);
        self.next_event_uid = 1;
        self.tension_arms_base = maxf(self.great_men(), 1.0);
        self.update_tension(data);
        self.tension_history.push(self.tension);
    }

    fn great_men(&self) -> f64 {
        let mut total = 0.0;
        for t in GREAT {
            if let Some(&i) = self.nation_index.get(t) {
                total += self.nations[i].men_in_units as f64;
            }
        }
        total
    }

    /// Whether the great powers stand in two alliance circles of at least two each, the shape of 1914.
    fn two_blocs(&self, data: &Data) -> bool {
        let mut circles = 0;
        let mut seen: Vec<String> = vec![];
        for tag in GREAT {
            if seen.iter().any(|s| s == tag) || !self.nation_index.contains_key(tag) {
                continue;
            }
            let members: Vec<String> = self.alliance_circle(tag).into_iter().filter(|t| GREAT.contains(&t.as_str())).collect();
            seen.extend(members.iter().cloned());
            if members.len() >= 2 {
                circles += 1;
            }
        }
        let _ = data;
        circles >= 2
    }

    /// `Diplomacy.alliance_circle`: nations tied to `tag` by standing alliances (the nation itself first), through however many.
    pub fn alliance_circle(&self, tag: &str) -> Vec<String> {
        let mut out = vec![tag.to_string()];
        let mut i = 0;
        while i < out.len() {
            let allies: Vec<String> = self.treaties_of(&out[i], "alliance").into_iter().map(|t| t.other(&out[i]).to_string()).collect();
            for ally in allies {
                if !out.contains(&ally) {
                    out.push(ally);
                }
            }
            i += 1;
        }
        out
    }

    /// `Pressure.parts`: the parts of tension.
    pub fn tension_parts(&self, data: &Data) -> TensionParts {
        let c = &data.pressure;
        let arms = clampf((self.great_men() / self.tension_arms_base - 1.0) * c.arms_weight, 0.0, c.arms_max);
        let mut mob = 0.0;
        for t in GREAT {
            if let Some(&i) = self.nation_index.get(t) {
                mob += maxf(0.0, self.nations[i].mobilization - c.mobilization_from);
            }
        }
        let mob = clampf(mob * c.mobilization_weight, 0.0, c.mobilization_max);
        let wars = self.wars.iter().filter(|w| GREAT.contains(&w.a.as_str()) || GREAT.contains(&w.b.as_str())).count();
        let war_part = minf(c.war_max, wars as f64 * c.war_each);
        let mut hostility = 0.0;
        let mut pairs = 0;
        for i in 0..GREAT.len() {
            for j in i + 1..GREAT.len() {
                if self.nation_index.contains_key(GREAT[i]) && self.nation_index.contains_key(GREAT[j]) {
                    hostility += clampf(-self.relation(data, GREAT[i], GREAT[j]) / 100.0, 0.0, 1.0);
                    pairs += 1;
                }
            }
        }
        let mut rivalry = hostility / maxf(pairs as f64, 1.0) * c.rivalry_weight;
        rivalry += if self.two_blocs(data) { c.bloc_weight } else { 0.0 };
        let total = clampf(c.base + arms + mob + war_part + rivalry + self.tension_impulse, 0.0, 100.0);
        TensionParts { arms, mobilization: mob, wars: war_part, rivalry, events: self.tension_impulse, total }
    }

    /// `Pressure._update`.
    pub fn update_tension(&mut self, data: &Data) {
        let c = &data.pressure;
        self.tension = self.tension_parts(data).total;
        self.tension_bonus = if !self.pressure_ai { 0.0 } else { c.aggression_gain * clampf((self.tension - c.aggression_from) / (100.0 - c.aggression_from), 0.0, 1.0) };
    }

    /// `Pressure.war_gate`: the tension below which the AI starts no war of its own choosing.
    pub fn war_gate(&self, data: &Data, scenario_gate: &Value) -> f64 {
        match scenario_gate {
            Value::Null => data.pressure.ai_war_gate,
            Value::Object(g) => {
                let f = |k: &str| g.get(k).and_then(Value::as_f64).unwrap_or(0.0);
                let t = inverse_lerp(f("from"), f("to"), self.calendar.year as f64 + (self.calendar.month - 1) as f64 / 12.0);
                lerpf(f("start"), f("end"), clampf(t, 0.0, 1.0))
            }
            other => other.as_f64().unwrap_or(data.pressure.ai_war_gate),
        }
    }

    /// `Pressure.step_month`: the force of events fades, the world's idea of an armed Europe follows its armies, events come up,
    /// and rivalries between the powers harden under tension.
    /// `Pressure.great_war_fought`: whether two great powers have fought each other and made peace.
    pub fn great_war_fought(&self) -> bool {
        self.war_history.iter().any(|w| GREAT.contains(&w.a.as_str()) && GREAT.contains(&w.b.as_str()) && w.end_day >= 0)
    }

    pub fn pressure_step_month(&mut self, data: &Data) {
        let c = &data.pressure;
        self.tension_impulse = minf(self.tension_impulse * (1.0 - c.impulse_decay), c.impulse_max);
        // Once the great powers have fought each other, what counts as armed follows the armies slowly, both ways.
        if self.great_war_fought() {
            self.tension_arms_base = maxf(1.0, self.tension_arms_base + (self.great_men() - self.tension_arms_base) * c.arms_drift);
        }
        self.fire_events(data);
        self.update_tension(data);
        if self.tension >= c.harden_above {
            for i in 0..GREAT.len() {
                for j in i + 1..GREAT.len() {
                    let (a, b) = (GREAT[i], GREAT[j]);
                    if self.nation_index.contains_key(a) && self.nation_index.contains_key(b) && !self.are_allied(data, a, b) && self.relation(data, a, b) < 0.0 {
                        self.shift_baseline_pub(data, a, b, -c.harden_per_month);
                    }
                }
            }
        }
        self.tension_history.push(self.tension);
        if self.tension_history.len() > 240 {
            self.tension_history.remove(0);
        }
    }

    // ---------------------------------------------------------------- events

    fn fire_events(&mut self, data: &Data) {
        let now = self.month_index();
        for e in &data.pressure.events {
            let id = e["id"].as_str().unwrap_or("");
            if now < index_of(&e["date"]) || (e.get("until").is_some() && now > index_of(&e["until"])) {
                continue;
            }
            // A dated event from before the scenario began has already happened (its effects are in the start).
            if index_of(&e["date"]) < self.pressure_start && e.get("repeat_months").is_none() {
                continue;
            }
            let last = self.events_fired.get(id).copied().unwrap_or(-1);
            if last >= 0 && (e.get("repeat_months").is_none() || now - last < e["repeat_months"].as_i64().unwrap_or(0)) {
                continue;
            }
            if let Some(req) = e.get("requires_event").and_then(Value::as_str) {
                if !self.events_fired.contains_key(req) {
                    continue;
                }
            }
            if !self.condition_ok(data, e) {
                continue;
            }
            let roles = self.event_roles(data, e);
            let actors_empty = e["actors"].as_object().map(|a| a.is_empty()).unwrap_or(true);
            if roles.is_empty() && !actors_empty {
                continue;
            }
            self.events_fired.insert(id.to_string(), now);
            self.post_event(data, e, roles);
        }
    }

    fn alive(&self, tag: &str) -> bool {
        self.nation_index.get(tag).map(|&i| !self.nations[i].provinces.is_empty()).unwrap_or(false)
    }

    pub fn condition_ok(&self, data: &Data, e: &Value) -> bool {
        let none = Value::Null;
        let c = e.get("condition").unwrap_or(&none);
        let f = |k: &str| c.get(k).and_then(Value::as_f64);
        if let Some(x) = f("tension_min") {
            if self.tension < x {
                return false;
            }
        }
        if let Some(x) = f("tension_max") {
            if self.tension > x {
                return false;
            }
        }
        if let Some(r) = c.get("relation_above").and_then(Value::as_array) {
            if self.relation(data, r[0].as_str().unwrap(), r[1].as_str().unwrap()) < r[2].as_f64().unwrap() {
                return false;
            }
        }
        if let Some(p) = c.get("peace").and_then(Value::as_array) {
            let (a, b) = (p[0].as_str().unwrap(), p[1].as_str().unwrap());
            if self.at_war(a, b) || !self.alive(a) || !self.alive(b) {
                return false;
            }
        }
        if c.get("pressure_ai").and_then(Value::as_bool).unwrap_or(false) && !self.pressure_ai {
            return false;
        }
        if c.get("player_great_power").and_then(Value::as_bool).unwrap_or(false) && !GREAT.contains(&self.player_tag.as_str()) {
            return false;
        }
        if c.get("player_minor").and_then(Value::as_bool).unwrap_or(false) && (self.player_tag.is_empty() || GREAT.contains(&self.player_tag.as_str()) || !self.alive(&self.player_tag)) {
            return false;
        }
        if let Some(m) = c.get("months_from_start").and_then(Value::as_i64) {
            if self.month_index() - self.pressure_start < m {
                return false;
            }
        }
        if c.get("after_great_war").and_then(Value::as_bool).unwrap_or(false) && !self.great_war_fought() {
            return false;
        }
        if c.get("no_great_war").and_then(Value::as_bool).unwrap_or(false) && self.wars.iter().any(|w| GREAT.contains(&w.a.as_str()) && GREAT.contains(&w.b.as_str())) {
            return false;
        }
        if let Some(actors) = e["actors"].as_object() {
            for tag in actors.values() {
                let tag = tag.as_str().unwrap_or("");
                if !tag.starts_with('$') && !self.nation_index.contains_key(tag) {
                    return false;
                }
            }
        }
        true
    }

    /// `Pressure._roles`: the event's actors by role, `$player` and the other picks filled in; empty if one of them is gone from
    /// the map or nobody fits.
    fn event_roles(&self, data: &Data, e: &Value) -> Roles {
        let mut roles: Roles = vec![];
        if let Some(actors) = e["actors"].as_object() {
            for (role, tag) in actors {
                let tag = tag.as_str().unwrap_or("");
                let picked = if tag.starts_with('$') { self.pick_role(data, tag) } else { tag.to_string() };
                if !self.nation_index.contains_key(&picked) {
                    return vec![];
                }
                roles.push((role.clone(), picked));
            }
        }
        roles
    }

    /// The latest claim made in play (ground lost at a peace) within `days`, by `holder` if given, whose holder is alive and at
    /// peace: (holder, against).
    fn recent_loss(&self, days: i64, holder: &str) -> Option<(String, String)> {
        let mut best: Option<(i64, String, String)> = None;
        for c in &self.claims {
            let h = c.get("holder").and_then(Value::as_str).unwrap_or("");
            if !holder.is_empty() && h != holder {
                continue;
            }
            let made = c.get("made_day").and_then(Value::as_i64).unwrap_or(-999999);
            if self.calendar.days_elapsed as i64 - made > days || !self.alive(h) || self.is_at_war(h) {
                continue;
            }
            let better = match &best {
                None => true,
                Some((bm, bh, _)) => made > *bm || (made == *bm && h < bh.as_str()),
            };
            if better {
                best = Some((made, h.to_string(), c.get("against").and_then(Value::as_str).unwrap_or("").to_string()));
            }
        }
        best.map(|(_, h, a)| (h, a))
    }

    /// `Pressure._pick_role`: a role named by what a nation is now, not by its tag.
    pub fn pick_role(&self, data: &Data, sel: &str) -> String {
        let p = &data.pressure;
        match sel {
            "$player" => self.player_tag.clone(),
            "$lost_ground" | "$winner" => match self.recent_loss(p.recent_months * 30, "") {
                None => String::new(),
                Some((holder, against)) => if sel == "$lost_ground" { holder } else { against },
            },
            "$empire" => {
                let mut best = String::new();
                for tag in &p.empires {
                    if !self.alive(tag) || self.is_at_war(tag) {
                        continue;
                    }
                    let n = self.nation(tag);
                    let lost = self.recent_loss(p.recent_months * 30, tag).is_some();
                    if (n.war_support < p.empire_support || lost) && (best.is_empty() || n.war_support < self.nation(&best).war_support) {
                        best = tag.clone();
                    }
                }
                best
            }
            "$suitor" | "$trade_partner" | "$great_neighbour" => self.player_partner(data, sel),
            "$most_armed" | "$second_armed" => {
                let mut powers: Vec<&str> = GREAT.iter().copied().filter(|t| self.alive(t)).collect();
                // sorted by men under arms, then tag (a stable sort by the same ordering the game uses)
                powers.sort_by(|x, y| {
                    let (mx, my) = (self.nation(x).men_in_units, self.nation(y).men_in_units);
                    my.cmp(&mx).then(x.cmp(y))
                });
                let i = if sel == "$most_armed" { 0 } else { 1 };
                powers.get(i).map(|s| s.to_string()).unwrap_or_default()
            }
            _ => String::new(),
        }
    }

    /// `Pressure._player_partner`: the nations a small player's events turn to, "" if none fits.
    fn player_partner(&self, data: &Data, sel: &str) -> String {
        let me = self.player_tag.clone();
        if !self.alive(&me) {
            return String::new();
        }
        let mut best = String::new();
        let mut best_v = f64::NEG_INFINITY;
        let near = self.neighbor_nations(data, &me);
        let pool: Vec<String> = if sel == "$trade_partner" { near.clone() } else { GREAT.iter().map(|s| s.to_string()).collect() };
        for tag in &pool {
            if *tag == me || !self.alive(tag) || self.at_war(&me, tag) {
                continue;
            }
            let v = match sel {
                "$suitor" => {
                    if self.are_allied(data, &me, tag) {
                        continue;
                    }
                    self.relation(data, tag, &me)
                }
                "$trade_partner" => self.nation(tag).budget.income,
                _ => {
                    if !near.contains(tag) {
                        continue;
                    }
                    -self.relation(data, tag, &me)
                }
            };
            if v > best_v || (v == best_v && tag.as_str() < best.as_str()) {
                best = tag.clone();
                best_v = v;
            }
        }
        if best.is_empty() && sel == "$trade_partner" {
            return self.player_partner(data, "$suitor");
        }
        best
    }

    fn swapped(roles: &Roles) -> Roles {
        let mut out = roles.clone();
        let b = role_get(roles, "b").or(role_get(roles, "a")).unwrap_or("").to_string();
        let a = role_get(roles, "a").unwrap_or("").to_string();
        role_set(&mut out, "a", &b);
        role_set(&mut out, "b", &a);
        out
    }

    fn pick_option(&self, choice: &Value) -> usize {
        if let Some(o) = choice.as_object() {
            let min = o.get("tension_min").and_then(Value::as_f64).unwrap_or(0.0);
            return if self.tension >= min { o["yes"].as_i64().unwrap_or(0) } else { o["no"].as_i64().unwrap_or(0) } as usize;
        }
        choice.as_i64().unwrap_or(0) as usize
    }

    fn fill_text(&self, text: &str, roles: &Roles) -> String {
        let mut text = text.to_string();
        for (role, tag) in roles {
            text = text.replace(&format!("{{{role}}}"), &self.nation(tag).display_name);
        }
        text
    }

    /// `Pressure._record`: what happened goes in the chronicle (newest first). The history log and the news are not kept.
    pub(crate) fn record_event(&mut self, title: &str, text: &str) {
        self.record_event_kind(title, text, "event");
    }

    /// `Pressure._record` with a kind of its own ("crisis"): the chronicle and the history.
    pub(crate) fn record_event_kind(&mut self, title: &str, text: &str, kind: &str) {
        self.note(kind, &format!("{title}: {text}"));
        self.chronicle.insert(0, (self.calendar.date_string(), title.to_string(), text.to_string()));
        self.chronicle.truncate(CHRONICLE_MAX);
    }

    /// `Pressure._post`: an event comes up. The player is asked if it concerns them; otherwise the AI's choice is made.
    fn post_event(&mut self, data: &Data, e: &Value, roles: Roles) {
        let me = self.player_tag.clone();
        let mirrored = e.get("mirror").and_then(Value::as_bool).unwrap_or(false) && role_get(&roles, "b").unwrap_or("") == me;
        let seen = if mirrored { Self::swapped(&roles) } else { roles.clone() };
        let player_is_a = role_get(&seen, "a").unwrap_or("") == me;
        let player_is_b = role_get(&seen, "b").unwrap_or("") == me && e.get("b_options").is_some();
        let title = e["title"].as_str().unwrap_or("").to_string();
        let text = e["text"].as_str().unwrap_or("").to_string();
        if player_is_a || player_is_b {
            let view = if player_is_a { seen.clone() } else { Self::swapped(&roles) };
            let mut deferred: Vec<(Value, Roles)> = vec![];
            if player_is_b {
                // The other side has decided already; a war it chose waits for the player's answer.
                let chosen = &e["options"][self.pick_option(&e["ai_option"])];
                for fx in chosen["effects"].as_array().unwrap() {
                    if fx.get("war").is_some() {
                        deferred.push((fx.clone(), roles.clone()));
                    } else {
                        self.apply_effect(data, fx, &roles);
                    }
                }
            }
            let options: Vec<Value> = if player_is_a { e["options"].as_array().unwrap().clone() } else { e["b_options"].as_array().unwrap().clone() };
            let decision = PendingEvent {
                id: self.next_event_uid,
                event: e["id"].as_str().unwrap_or("").to_string(),
                title,
                text: self.fill_text(&text, &view),
                roles: view,
                options,
                deferred,
                date: self.calendar.date_string(),
                as_b: player_is_b,
            };
            self.next_event_uid += 1;
            self.pending_events.push(decision);
            return;
        }
        let effects = e["options"][self.pick_option(&e["ai_option"])]["effects"].as_array().unwrap().clone();
        for fx in &effects {
            self.apply_effect(data, fx, &roles);
        }
        if e.get("b_options").is_some() && e.get("b_ai_option").is_some() {
            let effects = e["b_options"][self.pick_option(&e["b_ai_option"])]["effects"].as_array().unwrap().clone();
            for fx in &effects {
                self.apply_effect(data, fx, &Self::swapped(&roles));
            }
        }
        let filled = self.fill_text(&text, &roles);
        self.record_event(&title, &filled);
    }

    /// `Pressure._post` for a named event with the given roles (the events fire by date and condition; this is the same step
    /// by hand).
    pub fn post_event_by_id(&mut self, data: &Data, id: &str, roles: Roles) {
        let e = data.pressure.events.iter().find(|e| e["id"].as_str() == Some(id)).cloned().unwrap();
        self.post_event(data, &e, roles);
    }

    /// `Pressure.answer`: the player's answer to a waiting event. Returns false if there is no such decision or option.
    pub fn answer_event(&mut self, data: &Data, decision_id: u32, option: usize) -> bool {
        let Some(i) = self.pending_events.iter().position(|d| d.id == decision_id) else { return false };
        if option >= self.pending_events[i].options.len() {
            return false;
        }
        let d = self.pending_events.remove(i);
        let chosen = d.options[option].clone();
        for fx in chosen["effects"].as_array().unwrap() {
            self.apply_effect(data, fx, &d.roles);
        }
        if !chosen.get("defuse").and_then(Value::as_bool).unwrap_or(false) {
            for (fx, roles) in &d.deferred {
                self.apply_effect(data, fx, roles);
            }
        }
        let e = data.pressure.events.iter().find(|e| e["id"].as_str() == Some(d.event.as_str())).cloned().unwrap_or(Value::Null);
        if e.get("b_options").is_some() && e.get("b_ai_option").is_some() && !d.as_b {
            let effects = e["b_options"][self.pick_option(&e["b_ai_option"])]["effects"].as_array().unwrap().clone();
            for fx in &effects {
                self.apply_effect(data, fx, &Self::swapped(&d.roles));
            }
        }
        if !d.event.starts_with("crisis:") {
            let me = self.nation(&self.player_tag).display_name.clone();
            let label = chosen["label"].as_str().unwrap_or("").to_lowercase();
            self.record_event(&d.title, &format!("{me} {label}."));
        }
        self.update_tension(data);
        true
    }

    fn tag_of(roles: &Roles, role: &str) -> String {
        role_get(roles, role).unwrap_or(role).to_string()
    }

    fn both(&self, roles: &Roles, a: &str, b: &str) -> bool {
        let (ta, tb) = (Self::tag_of(roles, a), Self::tag_of(roles, b));
        self.nation_index.contains_key(&ta) && self.nation_index.contains_key(&tb) && ta != tb
    }

    /// `Pressure._apply`: applies one effect with the roles of its event.
    pub fn apply_effect(&mut self, data: &Data, fx: &Value, roles: &Roles) {
        let num = |v: &Value| v.as_f64().unwrap_or(0.0);
        if let Some(t) = fx.get("tension") {
            self.tension_impulse += num(t);
        } else if let Some(r) = fx.get("relation").and_then(Value::as_array) {
            let (a, b) = (r[0].as_str().unwrap(), r[1].as_str().unwrap());
            if self.both(roles, a, b) {
                self.change_relation(data, &Self::tag_of(roles, a), &Self::tag_of(roles, b), num(&r[2]));
            }
        } else if let Some(g) = fx.get("grievance").and_then(Value::as_array) {
            let (a, b) = (g[0].as_str().unwrap(), g[1].as_str().unwrap());
            if self.both(roles, a, b) {
                self.add_grievance(&Self::tag_of(roles, a), &Self::tag_of(roles, b), num(&g[2]));
            }
        } else if let Some(t) = fx.get("treaty").and_then(Value::as_array) {
            let (a, b) = (t[1].as_str().unwrap(), t[2].as_str().unwrap());
            if self.both(roles, a, b) {
                self.add_treaty(data, t[0].as_str().unwrap(), &Self::tag_of(roles, a), &Self::tag_of(roles, b), -1, t[3].clone(), t[4].as_str().unwrap_or(""));
            }
        } else if let Some(t) = fx.get("end_treaty").and_then(Value::as_array) {
            let (a, b) = (t[1].as_str().unwrap(), t[2].as_str().unwrap());
            if self.both(roles, a, b) {
                let kind = t[0].as_str().unwrap();
                let (ta, tb) = (Self::tag_of(roles, a), Self::tag_of(roles, b));
                let directed = data.diplomacy.treaty_kind(kind).directed;
                let day = self.calendar.days_elapsed as i64;
                let held = self.treaties.iter().position(|x| x.active_on(day) && x.kind == kind && ((x.a == ta && x.b == tb) || (!directed && x.a == tb && x.b == ta)));
                if let Some(i) = held {
                    self.end_treaty_at(data, i);
                }
            }
        } else if let Some(c) = fx.get("crisis") {
            // [crisis id, answer, role of the nation answering]
            let tag = Self::tag_of(roles, c[2].as_str().unwrap());
            self.crisis_respond(data, c[0].as_u64().unwrap() as u32, &tag, c[1].as_str().unwrap());
        } else if let Some(w) = fx.get("war").and_then(Value::as_array) {
            let (a, b) = (Self::tag_of(roles, w[0].as_str().unwrap()), Self::tag_of(roles, w[1].as_str().unwrap()));
            let alive = |t: &str| self.nation_index.get(t).map(|&i| !self.nations[i].provinces.is_empty()).unwrap_or(false);
            if alive(&a) && alive(&b) && !self.at_war(&a, &b) {
                self.start_war(data, &a, &b, w.len() > 2);
            }
        } else {
            for key in ["treasury", "revenue", "prestige", "war_support", "points", "manpower", "mobilize"] {
                if let Some(v) = fx.get(key).and_then(Value::as_array) {
                    let tag = Self::tag_of(roles, v[0].as_str().unwrap());
                    if self.nation_index.contains_key(&tag) {
                        self.apply_to(data, key, &tag, num(&v[1]));
                    }
                }
            }
        }
    }

    /// `Pressure._apply_to`: one effect on one nation.
    fn apply_to(&mut self, data: &Data, key: &str, tag: &str, v: f64) {
        let i = self.nation_index[tag];
        match key {
            "treasury" => self.nations[i].treasury += v,
            "revenue" => self.nations[i].treasury += v * self.nations[i].budget.income,
            "prestige" => self.gain_prestige(tag, v),
            "war_support" => self.nations[i].war_support = clampf(self.nations[i].war_support + v, 0.0, 100.0),
            "points" => self.gain_points(data, tag, v),
            "manpower" => {
                let n = &mut self.nations[i];
                n.manpower = (n.manpower + (n.manpower as f64 * v) as i64).max(0);
            }
            "mobilize" => self.nations[i].mobilization = clampf(self.nations[i].mobilization + v, 0.0, 1.0),
            _ => {}
        }
    }

    // ---------------------------------------------------------------- appeals

    /// `Pressure.appeal_tension`: what a public stand does to tension.
    pub fn appeal_tension(&self, data: &Data, tag: &str, kind: &str) -> f64 {
        let def = &data.pressure.appeals[kind];
        let f = |k: &str| def.get(k).and_then(Value::as_f64).unwrap_or(0.0);
        if kind != "calm" {
            return f("tension");
        }
        let weight = f("tension") + if GREAT.contains(&tag) { f("great_power") } else { 0.0 } + f("per_prestige") * maxf(self.nation(tag).prestige, 0.0);
        -minf(weight * (0.5 + self.tension / 100.0), f("tension_max"))
    }

    /// `Pressure.appeal_block`: whether a nation can take this stand now ("" if it can).
    pub fn appeal_blocked(&self, data: &Data, tag: &str, kind: &str) -> bool {
        let def = &data.pressure.appeals[kind];
        if def.is_null() || !self.nation_index.contains_key(tag) {
            return true;
        }
        if (self.calendar.days_elapsed as i64) < self.appeal_ready.get(tag).copied().unwrap_or(0) {
            return true;
        }
        !self.can_afford(tag, def["cost"].as_f64().unwrap_or(0.0))
    }

    /// `Pressure.appeal`: the nation takes the stand: points spent, tension moved, prestige and war support gained.
    pub fn appeal(&mut self, data: &Data, tag: &str, kind: &str) -> bool {
        if self.appeal_blocked(data, tag, kind) {
            return false;
        }
        let def = data.pressure.appeals[kind].clone();
        let f = |k: &str| def.get(k).and_then(Value::as_f64).unwrap_or(0.0);
        self.spend_points(data, tag, f("cost"));
        let delta = self.appeal_tension(data, tag, kind);
        self.tension_impulse = clampf(self.tension_impulse + delta, 0.0, data.pressure.impulse_max);
        self.apply_to(data, "prestige", tag, f("prestige"));
        if f("war_support") != 0.0 {
            self.apply_to(data, "war_support", tag, f("war_support"));
        }
        // The sabre is rattled at someone: every land neighbour thinks less of the nation.
        if f("neighbour_relation") != 0.0 {
            for other in self.neighbor_nations(data, tag) {
                self.change_relation(data, &other, tag, f("neighbour_relation"));
            }
        }
        self.appeal_ready.insert(tag.to_string(), self.calendar.days_elapsed as i64 + data.pressure.appeals["wait_days"].as_i64().unwrap_or(0));
        let label = def["label"].as_str().unwrap_or("").to_string();
        let tip = def["tip"].as_str().unwrap_or("").to_lowercase();
        let tip = tip.strip_suffix('.').unwrap_or(&tip).to_string();
        let name = self.nation(tag).display_name.clone();
        self.record_event(&label, &format!("{name}: {tip}"));
        self.update_tension(data);
        true
    }
}
