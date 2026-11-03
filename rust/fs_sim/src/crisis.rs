//! Dynamic crises between nations (`scripts/sim/crisis.gd`, `crisis_action.gd`, `press_demand.gd`; `data/crises.json`): a nation makes a
//! demand of a rival with a deadline, and the rival yields, refuses, mobilizes or appeals; third nations may mediate or back a side.
//! Each month the quarrels of the world are weighed and the worst may open a crisis. The titles and texts are written as the game
//! writes them, in the chronicle; the AI's weighing of a declaration after a refusal is `ai_diplomacy.rs`.

use crate::ai_peace::demand_of;
use crate::gd::{clampf, maxf, minf};
use crate::peace::Demand;
use crate::pressure::GREAT;
use crate::state::{CasusBelli, Data, GameState, PendingEvent};
use serde_json::{json, Value};

/// A crisis under way (`GameState.crises`): `a` is the demander, `b` the nation asked.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Crisis {
    pub id: u32,
    pub kind: String,
    pub a: String,
    pub b: String,
    pub demand: Demand,
    pub goal: Value,
    pub start_day: i64,
    pub think_day: i64,
    pub deadline_day: i64,
    pub backers_a: Vec<String>,
    pub backers_b: Vec<String>,
    pub title: String,
    pub text: String,
    pub mediators_tried: Vec<String>,
}

/// A finished crisis (`GameState.crisis_log`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct CrisisEnded {
    pub id: u32,
    pub kind: String,
    pub a: String,
    pub b: String,
    pub start: i64,
    pub end_day: i64,
    pub outcome: String,
}

/// One demand `a` could make of `b` (`Crisis.demand_options`).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DemandOption {
    pub kind: String,
    pub demand: Demand,
    pub goal: Value,
    pub weight: f64,
}

fn f(v: &Value) -> f64 {
    v.as_f64().unwrap_or_else(|| panic!("crises.json: {v} is not a number"))
}

pub fn demand_json(d: &Demand) -> Value {
    match d {
        Demand::Province(ids) => json!({"kind": "province", "ids": ids}),
        Demand::Indemnity { share, months } => json!({"kind": "indemnity", "share": share, "months": months}),
        Demand::ReleaseAlly(n) => json!({"kind": "release_ally", "nation": n}),
        Demand::DisarmBorder(y) => json!({"kind": "disarm_border", "years": y}),
        Demand::FleetLimit(y) => json!({"kind": "fleet_limit", "years": y}),
    }
}

impl GameState {
    fn cday(&self) -> i64 {
        self.calendar.days_elapsed as i64
    }

    pub fn crisis_find(&self, id: u32) -> Option<usize> {
        self.crises.iter().position(|c| c.id == id)
    }

    /// `Peace.describe_demand`.
    pub fn describe_demand(&self, data: &Data, d: &Demand) -> String {
        match d {
            Demand::Province(ids) => {
                let names: Vec<&str> = ids.iter().map(|&i| data.map.provinces[i].name.as_str()).collect();
                if names.len() <= 6 {
                    format!("the provinces of {}", names.join(", "))
                } else {
                    format!("{} provinces ({} and {} more)", names.len(), names[..4].join(", "), names.len() - 4)
                }
            }
            Demand::Indemnity { share, months } => format!("an indemnity of {}% of revenue a year for {} months", (share * 100.0).round() as i64, months),
            Demand::ReleaseAlly(n) => format!("an end to its ties with {}", self.nation(n).display_name),
            Demand::DisarmBorder(y) => format!("its border armies withdrawn for {y} years"),
            Demand::FleetLimit(y) => format!("no new warships for {y} years"),
        }
    }

    // ---------------------------------------------------------------- reading

    /// `Crisis.side`: the nations on a side of a crisis (`a` or `b`): the party, its allies and guarantors (those not allied to the
    /// other side), and whoever was asked to back it.
    pub fn crisis_side(&self, data: &Data, c: &Crisis, which: char) -> Vec<String> {
        let (own, other) = if which == 'a' { (&c.a, &c.b) } else { (&c.b, &c.a) };
        let mut out = vec![own.clone()];
        let mut friends = self.allies_of(own);
        if which == 'b' {
            friends.extend(self.guarantors_of(own));
        }
        let backers = if which == 'a' { &c.backers_a } else { &c.backers_b };
        friends.extend(backers.iter().cloned());
        for t in friends {
            if !out.contains(&t) && t != *other && self.nation_index.contains_key(&t) && !self.are_allied(data, &t, other) && !self.at_war(&t, own) {
                out.push(t);
            }
        }
        out
    }

    /// `Crisis.odds_a`: how much stronger `a`'s side is than `b`'s.
    pub fn crisis_odds_a(&self, data: &Data, c: &Crisis) -> f64 {
        self.side_power(data, &self.crisis_side(data, c, 'a')) / maxf(self.side_power(data, &self.crisis_side(data, c, 'b')), 0.01)
    }

    /// `Crisis.mediation_chance`: the chance that `tag` brings the two to a compromise: its standing and the goodwill it holds with both.
    pub fn mediation_chance(&self, data: &Data, c: &Crisis, tag: &str) -> f64 {
        let m = &data.crises["mediate"];
        let rel = self.relation(data, tag, &c.a) + self.relation(data, tag, &c.b);
        clampf(f(&m["base"]) + f(&m["prestige_weight"]) * self.nation(tag).prestige + f(&m["relation_weight"]) * rel, 0.0, 0.95)
    }

    /// `Crisis.mediators`: the great powers (not the parties) that could mediate, best chance first.
    pub fn crisis_mediators(&self, data: &Data, c: &Crisis) -> Vec<(String, f64)> {
        let mut out: Vec<(String, f64)> = vec![];
        for tag in GREAT {
            if tag == c.a || tag == c.b || !self.nation_index.contains_key(tag) || self.nation(tag).provinces.is_empty() {
                continue;
            }
            if self.at_war(tag, &c.a) || self.at_war(tag, &c.b) {
                continue;
            }
            out.push((tag.to_string(), self.mediation_chance(data, c, tag)));
        }
        crate::gd::sort_custom(&mut out, |x, y| x.1 > y.1 || (x.1 == y.1 && x.0 < y.0));
        out
    }

    fn crisis_succeeds(&self, data: &Data, c: &Crisis, tag: &str) -> bool {
        self.mediation_chance(data, c, tag) + 0.2 * self.ai_noise(&format!("mediate|{}|{}", c.id, tag)) >= f(&data.crises["mediate"]["threshold"])
    }

    // ---------------------------------------------------------------- opening

    /// `Crisis.step_month`: old crises that nobody answered lapse, and the worst quarrel in the world may open a new one.
    pub fn crisis_step_month(&mut self, data: &Data) {
        let g = &data.crises["gate"];
        if !self.pressure_ai || self.cday() < f(&g["start_days"]) as i64 {
            return;
        }
        if self.crisis_cooldown.get("_any").copied().unwrap_or(-1) > self.cday() {
            return;
        }
        // Europe already at war has no attention for new quarrels.
        if self.wars.len() as i64 > f(&g["max_wars"]) as i64 {
            return;
        }
        let mut opened = 0;
        while opened < f(&g["per_month"]) as i64 && (self.crises.len() as i64) < f(&g["max_active"]) as i64 {
            let Some((a, b)) = self.best_candidate(data) else { break };
            if self.crisis_open(data, &a, &b, None).is_some() {
                let gap = f(&g["min_gap_months"]) as i64 * 30;
                self.crisis_cooldown.insert("_any".to_string(), self.cday() + gap);
            }
            opened += 1;
        }
    }

    /// `Crisis.score`: how much `a` is set against `b` and able to press it.
    pub fn crisis_score(&self, data: &Data, a: &str, b: &str) -> f64 {
        let w = &data.crises["score"];
        let hostile = clampf(-self.relation(data, b, a) / 100.0, 0.0, 1.0);
        let mut s = f(&w["hostile"]) * hostile;
        s += f(&w["grievance"]) * self.grievance_of(a, b) / 100.0;
        // Ground lost at a living memory's peace is pressed at any tension; an old scenario claim only once Europe is tense.
        let claim_min = data.crises["gate"].get("claim_min_tension").and_then(Value::as_f64).unwrap_or(0.0);
        if !self.revanche_ids(a, b, false).is_empty() {
            s += f(&w["claim"]);
        } else if !self.claim_cb(data, a, b).is_empty() && self.tension >= claim_min {
            s += f(&w["claim"]);
        }
        if self.alarms.contains_key(&format!("{b}>{a}")) {
            s += f(&w["alarm"]);
        }
        s += f(&w["tension"]) * self.tension / 100.0;
        let odds = self.side_power(data, &[a.to_string()]) / maxf(self.side_power(data, &[b.to_string()]), 0.01);
        s += f(&w["edge"]) * clampf(odds - 1.0, 0.0, 1.0);
        s
    }

    fn claim_cb(&self, data: &Data, a: &str, b: &str) -> String {
        for cb in self.casus_belli_options(data, a, b) {
            if ["reconquest", "border_claim", "national_claim"].contains(&cb.as_str()) {
                return cb;
            }
        }
        String::new()
    }

    /// `Crisis.may_quarrel`: whether a crisis may open between the two now.
    pub fn may_quarrel(&self, data: &Data, a: &str, b: &str) -> bool {
        if a == self.player_tag || !self.nation_index.contains_key(a) || !self.nation_index.contains_key(b) {
            return false;
        }
        if self.nation(a).provinces.is_empty() || self.nation(b).provinces.is_empty() {
            return false;
        }
        if !self.declare_block(data, a, b).is_empty() || self.in_truce(data, a, b) {
            return false;
        }
        for c in &self.crises {
            if c.a == a || c.b == a || c.a == b || c.b == b {
                return false;
            }
        }
        if self.crisis_cooldown.get(&Self::pair_key(a, b)).copied().unwrap_or(-1) > self.cday() {
            return false;
        }
        // The odds of the two sides, allies and guarantors with them, as the nation asked will weigh them.
        let draft = Crisis { id: 0, kind: String::new(), a: a.to_string(), b: b.to_string(), demand: Demand::Province(vec![]), goal: Value::Null, start_day: 0, think_day: 0, deadline_day: 0, backers_a: vec![], backers_b: vec![], title: String::new(), text: String::new(), mediators_tried: vec![] };
        self.crisis_odds_a(data, &draft) >= f(&data.crises["gate"]["min_odds"])
    }

    /// `Crisis.best_candidate`: the best quarrel at or above the gate.
    pub fn best_candidate(&self, data: &Data) -> Option<(String, String)> {
        let g = &data.crises["gate"];
        let mut best: Option<(String, String, f64)> = None;
        let mut tags: Vec<String> = self.nations.iter().map(|n| n.tag.clone()).collect();
        tags.sort();
        for a in &tags {
            if self.nation(a).provinces.is_empty() || *a == self.player_tag {
                continue;
            }
            let mut targets = self.neighbor_nations(data, a);
            if GREAT.contains(&a.as_str()) {
                for g2 in GREAT {
                    if g2 != a && !targets.iter().any(|t| t == g2) {
                        targets.push(g2.to_string());
                    }
                }
            }
            targets.sort();
            for b in &targets {
                if !self.may_quarrel(data, a, b) {
                    continue;
                }
                let key = format!("crisis|{a}|{b}|{}", self.calendar.year * 12 + self.calendar.month);
                let mut s = self.crisis_score(data, a, b) + 0.05 * self.ai_noise(&key);
                // A quarrel with the player's nation comes a little sooner: the player is asked things.
                if *b == self.player_tag {
                    s += data.crises["score"].get("player").and_then(Value::as_f64).unwrap_or(0.0);
                }
                if s >= f(&g["min_score"]) && best.as_ref().map(|x| s > x.2).unwrap_or(true) {
                    best = Some((a.clone(), b.clone(), s));
                }
            }
        }
        best.map(|(a, b, _)| (a, b))
    }

    /// `Crisis.demand_options`: every demand `a` could make of `b` now, best first.
    pub fn demand_options(&self, data: &Data, a: &str, b: &str) -> Vec<DemandOption> {
        let mut options: Vec<DemandOption> = vec![];
        // Revanche: ground `a` lost to `b` at a peace, as much of it as could be handed over.
        let lost = self.revanche_ids(a, b, false);
        if !lost.is_empty() {
            let (back, _) = self.pick_takeable(data, a, b, &lost, &|_| 0.0, f64::INFINITY);
            if !back.is_empty() {
                options.push(DemandOption { kind: "revanche".to_string(), demand: Demand::Province(back.clone()), goal: json!({"kind": "provinces", "ids": back, "label": ""}), weight: 0.0 });
            }
        }
        let kinds = &data.crises["kinds"];
        let cb = self.claim_cb(data, a, b);
        let claim_min = data.crises["gate"].get("claim_min_tension").and_then(Value::as_f64).unwrap_or(0.0);
        // An old claim is pressed only once Europe is tense enough for it.
        if !cb.is_empty() && self.tension >= claim_min {
            let mut goal = self.goal_for_declaration(data, a, b, &cb);
            let ids: Vec<usize> = goal["ids"].as_array().into_iter().flatten().filter_map(|x| x.as_u64().map(|x| x as usize)).collect();
            if !ids.is_empty() {
                // Only what could be handed over: the claimed ground that touches the demander's, never the capital alone.
                let (picked, _) = self.pick_takeable(data, a, b, &ids, &|_| 0.0, f64::INFINITY);
                if !picked.is_empty() {
                    goal["ids"] = json!(picked);
                    options.push(DemandOption { kind: "claim".to_string(), demand: Demand::Province(picked), goal, weight: 0.0 });
                }
            }
        }
        let border = &kinds["border"];
        let mut edge: Vec<(usize, f64)> = vec![];
        for &id in &self.nation(b).provinces {
            if id as i64 == self.nation(b).capital {
                continue;
            }
            for n in data.map.neighbors(id) {
                if self.province_owner[n] == a {
                    let share = self.province_share(data, id, b);
                    if share <= f(&border["max_share"]) {
                        edge.push((id, share));
                    }
                    break;
                }
            }
        }
        if !edge.is_empty() {
            edge.sort_by(|x, y| y.1.partial_cmp(&x.1).unwrap().then(x.0.cmp(&y.0)));
            let ids: Vec<usize> = edge.iter().take(f(&border["max_provinces"]) as usize).map(|e| e.0).collect();
            options.push(DemandOption { kind: "border".to_string(), demand: Demand::Province(ids.clone()), goal: json!({"kind": "provinces", "ids": ids, "label": ""}), weight: 0.0 });
        }
        let ind = &kinds["indemnity"];
        if self.grievance_of(a, b) >= f(&ind["min_grievance"]) {
            let d = Demand::Indemnity { share: f(&ind["share"]), months: f(&ind["months"]) as i64 };
            options.push(DemandOption { kind: "indemnity".to_string(), goal: json!({"kind": "concession", "demand": demand_json(&d), "label": ""}), demand: d, weight: 0.0 });
        }
        if self.alarms.contains_key(&format!("{b}>{a}")) && !self.border_provinces(data, b, a).is_empty() {
            let d = Demand::DisarmBorder(f(&kinds["disarm"]["years"]) as i64);
            options.push(DemandOption { kind: "disarm".to_string(), goal: json!({"kind": "concession", "demand": demand_json(&d), "label": ""}), demand: d, weight: 0.0 });
        }
        // A naval rivalry: a great power with a fleet of some weight asks another to build no more warships.
        let naval = &kinds["naval"];
        if GREAT.contains(&a) && GREAT.contains(&b) && !self.fleet_limited(b) {
            let theirs = self.naval_strength(b);
            if theirs > 0.0 && self.naval_strength(a) >= theirs * f(&naval["min_ratio"]) {
                let d = Demand::FleetLimit(f(&naval["years"]) as i64);
                options.push(DemandOption { kind: "naval".to_string(), goal: json!({"kind": "concession", "demand": demand_json(&d), "label": ""}), demand: d, weight: 0.0 });
            }
        }
        for o in &mut options {
            o.weight = f(&kinds[o.kind.as_str()]["weight"]) + 0.05 * self.ai_noise(&format!("kind|{a}|{b}|{}", o.kind));
        }
        crate::gd::sort_custom(&mut options, |x, y| x.weight > y.weight);
        options
    }

    /// `Crisis.press_block`: why `a` cannot press a demand on `b` now ("" if it can).
    pub fn press_block(&self, data: &Data, a: &str, b: &str, full: bool) -> &'static str {
        let why = self.declare_block(data, a, b);
        if !why.is_empty() {
            return why;
        }
        for c in &self.crises {
            if c.a == a || c.b == a || c.a == b || c.b == b {
                return "busy";
            }
        }
        if self.crisis_cooldown.get(&Self::pair_key(a, b)).copied().unwrap_or(-1) > self.cday() {
            return "rest";
        }
        if full {
            return "";
        }
        if !self.can_afford(a, f(&data.crises["press"]["cost_points"])) {
            return "points";
        }
        if self.demand_options(data, a, b).is_empty() {
            return "nothing";
        }
        ""
    }

    /// `WarGoal.cost_mult`: the goal's price multiplier for the points to press it.
    fn goal_cost_mult(&self, data: &Data, goal: &Value) -> f64 {
        let goals = &data.diplomacy.raw_war["goals"];
        let def = &goals[goal["kind"].as_str().unwrap_or("")];
        let mut m = def.get("cost_mult").and_then(Value::as_f64).unwrap_or(1.0);
        let n = goal["ids"].as_array().map(|a| a.len()).unwrap_or(0) as i64;
        m += def.get("cost_per_province").and_then(Value::as_f64).unwrap_or(0.0) * (n - 1).max(0) as f64;
        m
    }

    /// `Crisis.press_cost`: what pressing a demand for `goal` costs `a` in diplomacy points.
    pub fn press_cost(&self, data: &Data, a: &str, goal: &Value) -> f64 {
        let u = &data.diplomacy.raw_points["prestige_uses"];
        let (disc, max) = (f(&u["demand_discount"]), f(&u["demand_discount_max"]));
        let cut = clampf(self.nation(a).prestige * disc, -max, max);
        let empty = goal.as_object().map(|o| o.is_empty()).unwrap_or(true);
        f(&data.crises["press"]["cost_points"]) * (1.0 - cut) * if empty { 1.0 } else { self.goal_cost_mult(data, goal) }
    }

    /// `WarGoal.invalid`: why `goal` cannot be pursued by `a` against `b` ("" if it can).
    fn goal_invalid(&self, data: &Data, a: &str, b: &str, goal: &Value) -> &'static str {
        match goal["kind"].as_str().unwrap_or("") {
            "provinces" => {
                let ids: Vec<usize> = goal["ids"].as_array().into_iter().flatten().filter_map(|x| x.as_u64().map(|x| x as usize)).collect();
                if ids.is_empty() {
                    return "provinces";
                }
                if ids.len() as i64 > f(&data.diplomacy.raw_war["goals"]["max_provinces"]) as i64 {
                    return "count";
                }
                for &id in &ids {
                    if id < 1 || id >= self.province_owner.len() || self.province_owner[id] != b {
                        return "provinces";
                    }
                }
                self.province_problem(data, a, b, &ids)
            }
            "concession" => match demand_of(&goal["demand"]) {
                Some(Demand::Indemnity { .. }) | Some(Demand::DisarmBorder(_)) | Some(Demand::FleetLimit(_)) => "",
                Some(Demand::ReleaseAlly(other)) => {
                    if !self.nation_index.contains_key(&other) || other == a || other == b || self.release_treaties(b, &other).is_empty() {
                        "demand"
                    } else {
                        ""
                    }
                }
                _ => "demand",
            },
            _ => "kind",
        }
    }

    /// `Crisis.custom_problem`: why a demand chosen in full cannot be pressed ("" if it can).
    pub fn custom_problem(&self, data: &Data, a: &str, b: &str, demand: &Demand, goal: &Value) -> &'static str {
        let why = self.goal_invalid(data, a, b, goal);
        if !why.is_empty() {
            return why;
        }
        if self.demand_cost(data, a, b, demand) < 0.0 {
            "demand"
        } else {
            ""
        }
    }

    /// `Crisis.kind_of`: the crisis kind of a demand.
    pub fn crisis_kind_of(d: &Demand) -> &'static str {
        match d {
            Demand::Indemnity { .. } => "indemnity",
            Demand::DisarmBorder(_) => "disarm",
            Demand::FleetLimit(_) => "naval",
            Demand::ReleaseAlly(_) => "release",
            Demand::Province(_) => "border",
        }
    }

    /// `PressDemand.execute` with `Crisis.press`: `a` presses a demand on `b` (of `kind` among the options, or in full): opens the
    /// crisis, for points. Returns the reason it could not ("" if it did).
    pub fn press_demand(&mut self, data: &Data, a: &str, b: &str, kind: &str, custom: Option<(Demand, Value)>) -> &'static str {
        if !self.nation_index.contains_key(a) || !self.nation_index.contains_key(b) {
            return "unknown";
        }
        let reason = self.press_block(data, a, b, custom.is_some());
        if !reason.is_empty() {
            return reason;
        }
        let pick: DemandOption;
        if let Some((demand, goal)) = custom {
            let why = self.custom_problem(data, a, b, &demand, &goal);
            if !why.is_empty() {
                return why;
            }
            if !self.can_afford(a, self.press_cost(data, a, &goal)) {
                return "points";
            }
            pick = DemandOption { kind: Self::crisis_kind_of(&demand).to_string(), demand, goal, weight: 0.0 };
        } else {
            let Some(o) = self.demand_options(data, a, b).into_iter().filter(|o| o.kind == kind).last() else { return "nothing" };
            pick = o;
        }
        let cost = self.press_cost(data, a, &pick.goal);
        if !self.can_afford(a, cost) {
            return "points";
        }
        self.spend_points(data, a, cost);
        if self.crisis_open(data, a, b, Some(pick)).is_none() {
            return "nothing";
        }
        ""
    }

    /// `Crisis.open`: opens a crisis for a found quarrel.
    pub fn crisis_open(&mut self, data: &Data, a: &str, b: &str, chosen: Option<DemandOption>) -> Option<usize> {
        let pick = match chosen {
            Some(p) => Some(p),
            None => self.demand_options(data, a, b).into_iter().next(),
        };
        let Some(pick) = pick else {
            self.crisis_cooldown.insert(Self::pair_key(a, b), self.cday() + 90);
            return None;
        };
        let g = &data.crises["gate"];
        let today = self.cday();
        let id = self.next_crisis_id;
        self.next_crisis_id += 1;
        let mut c = Crisis {
            id,
            kind: pick.kind.clone(),
            a: a.to_string(),
            b: b.to_string(),
            demand: pick.demand.clone(),
            goal: pick.goal.clone(),
            start_day: today,
            think_day: today + f(&g["think_days"]) as i64,
            deadline_day: today + f(&g["deadline_days"]) as i64,
            backers_a: vec![],
            backers_b: vec![],
            title: String::new(),
            text: String::new(),
            mediators_tried: vec![],
        };
        self.ai_backers(data, &mut c);
        let def = &data.crises["kinds"][pick.kind.as_str()];
        let deadline = self.calendar.date_after(f(&g["deadline_days"]) as i32);
        let na = self.nation(a).display_name.clone();
        let nb = self.nation(b).display_name.clone();
        c.title = def["title"].as_str().unwrap().replace("{a}", &na).replace("{b}", &nb);
        c.text = def["text"].as_str().unwrap().replace("{a}", &na).replace("{b}", &nb).replace("{what}", &self.describe_demand(data, &c.demand)).replace("{date}", &deadline);
        self.tension_impulse += f(&data.crises["open"]["tension"]);
        self.change_relation(data, a, b, f(&data.crises["open"]["relation"]));
        self.crisis_cooldown.insert(Self::pair_key(a, b), today + f(&g["pair_cooldown_months"]) as i64 * 30);
        let (title, text) = (c.title.clone(), c.text.clone());
        self.record_event_kind(&title, &text, "crisis");
        self.crises.push(c);
        let ci = self.crises.len() - 1;
        if b == self.player_tag {
            self.crisis_ask_player(data, ci);
        }
        Some(ci)
    }

    /// `Crisis._ai_backers`: AI nations with a tie to one side and none to the other stand behind it from the start.
    fn ai_backers(&self, data: &Data, c: &mut Crisis) {
        let need = f(&data.crises["back"]["ai_relation"]);
        for tag in GREAT {
            if tag == c.a || tag == c.b || tag == self.player_tag || !self.nation_index.contains_key(tag) {
                continue;
            }
            let (ra, rb) = (self.relation(data, tag, &c.a), self.relation(data, tag, &c.b));
            if rb >= need && ra < 0.0 {
                c.backers_b.push(tag.to_string());
            } else if ra >= need && rb < 0.0 {
                c.backers_a.push(tag.to_string());
            }
        }
    }

    // ---------------------------------------------------------------- answering

    /// `Crisis.choose_response`: what `b` does when the AI answers for it: yield, refuse, mobilize or appeal.
    pub fn choose_response(&self, data: &Data, c: &Crisis) -> &'static str {
        let ai = &data.crises["ai"];
        let odds_b = 1.0 / maxf(self.crisis_odds_a(data, c), 0.01);
        let caution = self.temperament(data, &c.b).1;
        if odds_b >= f(&ai["resist_odds"]) * (0.7 + 0.6 * caution) {
            return if odds_b >= f(&ai["mobilize_below"]) { "refuse" } else { "mobilize" };
        }
        let med = self.crisis_mediators(data, c);
        if !med.is_empty() && med[0].1 >= f(&ai["mediator_chance_min"]) {
            return "appeal";
        }
        let cost = self.demand_cost(data, &c.a, &c.b, &c.demand);
        if cost >= 0.0 && (cost <= f(&ai["yield_cost_max"]) || odds_b < f(&ai["yield_odds"])) {
            return "yield";
        }
        "mobilize"
    }

    /// `Crisis.step_day`: the AI answers when it has thought long enough; a crisis whose demand has gone stale, or whose time is up, ends.
    pub fn crisis_step_day(&mut self, data: &Data) {
        if self.crises.is_empty() {
            return;
        }
        let today = self.cday();
        for c in self.crises.clone() {
            if !self.declare_block(data, &c.a, &c.b).is_empty() || !self.demand_valid(&c) {
                let text = format!("The quarrel between {} and {} has been overtaken by events.", self.nation(&c.a).display_name, self.nation(&c.b).display_name);
                self.crisis_end(&c, "lapsed", &text);
                continue;
            }
            if c.b == self.player_tag {
                if today >= c.deadline_day {
                    self.crisis_cancel_prompt(&c);
                    self.crisis_respond(data, c.id, &c.b, "refuse");
                }
                continue;
            }
            if today >= c.think_day {
                let action = self.choose_response(data, &c);
                self.crisis_respond(data, c.id, &c.b, action);
            }
        }
    }

    fn demand_valid(&self, c: &Crisis) -> bool {
        if let Demand::Province(ids) = &c.demand {
            return ids.iter().all(|&id| self.province_owner[id] == c.b);
        }
        true
    }

    /// `Crisis.respond`: `tag` answers the crisis as the nation asked. Returns false if it cannot.
    pub fn crisis_respond(&mut self, data: &Data, id: u32, tag: &str, action: &str) -> bool {
        let Some(ci) = self.crisis_find(id) else { return false };
        let c = self.crises[ci].clone();
        if tag != c.b || !["yield", "refuse", "mobilize", "appeal"].contains(&action) {
            return false;
        }
        let mut action = action;
        if action == "appeal" {
            let cost = f(&data.crises["mediate"]["appeal_cost_points"]);
            if tag == self.player_tag {
                if !self.can_afford(tag, cost) {
                    return false;
                }
                self.spend_points(data, tag, cost);
            }
            let med = self.crisis_mediators(data, &c);
            if !med.is_empty() && self.crisis_succeeds(data, &c, &med[0].0) {
                self.compromise(data, ci, &med[0].0.clone());
                return true;
            }
            let text = format!("{} asks the powers to step in, but no one can bring {} to terms.", self.nation(&c.b).display_name, self.nation(&c.a).display_name);
            self.record_event(&c.title, &text);
            action = "refuse";
        }
        match action {
            "yield" => self.crisis_yield(data, ci),
            "refuse" => self.crisis_refuse(data, ci),
            _ => self.crisis_mobilize(data, ci),
        }
        true
    }

    fn crisis_yield(&mut self, data: &Data, ci: usize) {
        let y = &data.crises["yield"];
        let c = self.crises[ci].clone();
        let terms = self.apply_demand(data, &c.a, &c.b, &c.demand, false);
        self.gain_prestige(&c.a, f(&y["a_prestige"]));
        self.gain_prestige(&c.b, f(&y["b_prestige"]));
        self.change_war_support(&c.b, f(&y["b_war_support"]));
        self.tension_impulse += f(&y["tension"]);
        self.change_relation(data, &c.a, &c.b, f(&y["relation"]));
        self.recompute(data);
        let text = format!("{} yields to {}: {}.", self.nation(&c.b).display_name, self.nation(&c.a).display_name, terms);
        self.crisis_end(&c, "yielded", &text);
    }

    fn crisis_refuse(&mut self, data: &Data, ci: usize) {
        let r = &data.crises["refuse"];
        let c = self.crises[ci].clone();
        self.change_relation(data, &c.a, &c.b, f(&r["relation"]));
        self.add_grievance(&c.a, &c.b, f(&r["grievance"]));
        self.tension_impulse += f(&r["tension"]);
        // The demand becomes a casus belli with the demand as its goal.
        let expires = self.cday() + (data.diplomacy.cb_years * 365.0) as i64;
        self.casus_belli.push(CasusBelli { holder: c.a.clone(), target: c.b.clone(), kind: "fabricated_claim".to_string(), expires_day: expires, goal: c.goal.clone(), refused_day: self.cday() });
        let text = format!("{} refuses {}. {} now has a claim to press.", self.nation(&c.b).display_name, self.nation(&c.a).display_name, self.nation(&c.a).display_name);
        self.crisis_end(&c, "refused", &text);
        if c.a != self.player_tag {
            if let Some(cb) = self.war_option(data, &c.a, &c.b) {
                // `issue_quiet(DeclareWar)`: the economy is worked out again at the end of the day
                if self.declare_war_for_points(data, &c.a, &c.b, &cb, 0).is_empty() {
                    self.economy_dirty = true;
                }
            }
        }
    }

    fn crisis_mobilize(&mut self, data: &Data, ci: usize) {
        let m = &data.crises["mobilize"];
        let c = self.crises[ci].clone();
        let bi = self.nation_index[&c.b];
        self.nations[bi].mobilization = clampf(self.nations[bi].mobilization + f(&m["mobilization"]), 0.0, 1.0);
        self.tension_impulse += f(&m["tension"]);
        // Mobilization changes the odds: a demander that can no longer win backs down.
        if self.crisis_odds_a(data, &c) < self.required_odds(data, &c.a) * f(&m["deter_margin"]) && c.a != self.player_tag {
            self.gain_prestige(&c.a, f(&m["a_backdown_prestige"]));
            self.gain_prestige(&c.b, f(&m["b_prestige"]));
            self.tension_impulse += f(&m["backdown_tension"]);
            let text = format!("{} mobilizes and {} backs down.", self.nation(&c.b).display_name, self.nation(&c.a).display_name);
            self.crisis_end(&c, "backed_down", &text);
            return;
        }
        self.crisis_refuse(data, ci);
    }

    /// `Crisis._compromise`: the powers' mediator brings the two to a smaller demand: a modest indemnity, or nothing.
    fn compromise(&mut self, data: &Data, ci: usize, mediator: &str) {
        let m = &data.crises["mediate"];
        let c = self.crises[ci].clone();
        let mut terms = "no concession".to_string();
        if matches!(c.demand, Demand::Province(_)) {
            let d = Demand::Indemnity { share: f(&m["compromise_share"]), months: f(&m["compromise_months"]) as i64 };
            terms = self.apply_demand(data, &c.a, &c.b, &d, false);
        }
        self.tension_impulse += f(&m["tension"]);
        self.gain_prestige(mediator, f(&m["prestige"]));
        self.change_relation(data, mediator, &c.a, 3.0);
        self.change_relation(data, mediator, &c.b, 3.0);
        let text = format!("{} brings {} and {} to terms: {}.", self.nation(mediator).display_name, self.nation(&c.a).display_name, self.nation(&c.b).display_name, terms);
        self.crisis_end(&c, "mediated", &text);
    }

    /// `Crisis.act`: a third nation acts: "mediate", "back_a" or "back_b". Returns false if it cannot.
    pub fn crisis_act(&mut self, data: &Data, id: u32, tag: &str, action: &str) -> bool {
        let Some(ci) = self.crisis_find(id) else { return false };
        let c = self.crises[ci].clone();
        if tag == c.a || tag == c.b || !self.nation_index.contains_key(tag) || !["mediate", "back_a", "back_b"].contains(&action) {
            return false;
        }
        if action != "mediate" && (c.backers_a.iter().any(|t| t == tag) || c.backers_b.iter().any(|t| t == tag)) {
            return false;
        }
        if action == "mediate" && c.mediators_tried.iter().any(|t| t == tag) {
            return false;
        }
        let cost = if action == "mediate" { f(&data.crises["mediate"]["cost_points"]) } else { f(&data.crises["back"]["cost_points"]) };
        if !self.can_afford(tag, cost) {
            return false;
        }
        self.spend_points(data, tag, cost);
        if action == "mediate" {
            self.crises[ci].mediators_tried.push(tag.to_string());
            let c = self.crises[ci].clone();
            if self.crisis_succeeds(data, &c, tag) {
                self.compromise(data, ci, tag);
            } else {
                self.gain_prestige(tag, f(&data.crises["mediate"]["failed_prestige"]));
                let text = format!("{} tries to mediate between {} and {} and fails.", self.nation(tag).display_name, self.nation(&c.a).display_name, self.nation(&c.b).display_name);
                self.record_event(&c.title, &text);
            }
            return true;
        }
        let (backed, against) = if action == "back_a" { (c.a.clone(), c.b.clone()) } else { (c.b.clone(), c.a.clone()) };
        if backed == c.a {
            self.crises[ci].backers_a.push(tag.to_string());
        } else {
            self.crises[ci].backers_b.push(tag.to_string());
        }
        let b = &data.crises["back"];
        self.change_relation(data, tag, &backed, f(&b["relation"]));
        self.change_relation(data, tag, &against, f(&b["against_relation"]));
        self.tension_impulse += f(&b["tension"]);
        let text = format!("{} stands behind {}.", self.nation(tag).display_name, self.nation(&backed).display_name);
        self.record_event(&c.title, &text);
        true
    }

    /// `CrisisAction.execute`.
    pub fn crisis_action(&mut self, data: &Data, tag: &str, id: u32, action: &str) -> bool {
        let Some(ci) = self.crisis_find(id) else { return false };
        if tag == self.crises[ci].b {
            self.crisis_respond(data, id, tag, action)
        } else {
            self.crisis_act(data, id, tag, action)
        }
    }

    /// `Crisis.end`: files a crisis as ended.
    fn crisis_end(&mut self, c: &Crisis, outcome: &str, text: &str) {
        let c = c.clone();
        if let Some(i) = self.crisis_find(c.id) {
            self.crises.remove(i);
        }
        self.crisis_log.push(CrisisEnded { id: c.id, kind: c.kind.clone(), a: c.a.clone(), b: c.b.clone(), start: c.start_day, end_day: self.cday(), outcome: outcome.to_string() });
        if self.crisis_log.len() > 120 {
            self.crisis_log.remove(0);
        }
        self.crisis_cancel_prompt(&c);
        self.record_event_kind(&c.title, text, "crisis");
    }

    // ---------------------------------------------------------------- the player's side

    /// `Crisis._ask_player`: asks the player (the nation asked) how to answer.
    fn crisis_ask_player(&mut self, data: &Data, ci: usize) {
        let c = self.crises[ci].clone();
        let me = self.player_tag.clone();
        let odds_b = 1.0 / maxf(self.crisis_odds_a(data, &c), 0.01);
        let med = self.crisis_mediators(data, &c);
        let y = &data.crises["yield"];
        let what = self.describe_demand(data, &c.demand);
        let (na, nb) = (self.nation(&c.a).display_name.clone(), String::new());
        let _ = nb;
        let r = |x: f64| x.round() as i64;
        let signed = |x: i64| format!("{}{}", if x < 0 { "-" } else { "+" }, x.abs());
        let mut options = vec![
            json!({"label": "Yield to the demand", "text": format!("Give up {what}. The crisis ends."),
                "effects": [{"crisis": [c.id, "yield", "b"]}],
                "tip": format!("You lose {what}.\nPrestige {}, war support {}; tension eases.", signed(r(f(&y["b_prestige"]))), signed(r(f(&y["b_war_support"]))))}),
            json!({"label": "Refuse", "text": format!("Say no. {na} may take it as a cause for war."),
                "effects": [{"crisis": [c.id, "refuse", "b"]}],
                "tip": format!("{na} gains a casus belli to press the demand, and may declare war.\nRelations with {na} {}.", signed(r(f(&data.crises["refuse"]["relation"]))))}),
            json!({"label": "Mobilize and refuse", "text": "Show that you will fight; they may back down if they cannot win.",
                "effects": [{"crisis": [c.id, "mobilize", "b"]}],
                "tip": format!("Mobilization {}%; tension {}.\nIf {na} cannot win it backs down, otherwise this is a refusal.", signed(r(f(&data.crises["mobilize"]["mobilization"]) * 100.0)), signed(r(f(&data.crises["mobilize"]["tension"]))))}),
        ];
        if !med.is_empty() && self.can_afford(&me, f(&data.crises["mediate"]["appeal_cost_points"])) {
            let m = &med[0];
            let nm = self.nation(&m.0).display_name.clone();
            options.push(json!({"label": format!("Appeal to the powers ({} points)", f(&data.crises["mediate"]["appeal_cost_points"]) as i64),
                "text": format!("Ask {nm} to bring {na} to terms."),
                "effects": [{"crisis": [c.id, "appeal", "b"]}],
                "tip": format!("A {}% chance {nm} succeeds, with a small payment instead of the demand.\nIf it fails, this is a refusal.", r(m.1 * 100.0))}));
        }
        let power = if odds_b >= 1.0 { format!("Your side outweighs theirs {:.1} to 1.", odds_b) } else { format!("Their side outweighs yours {:.1} to 1.", 1.0 / odds_b) };
        let decision = PendingEvent {
            id: self.next_event_uid,
            event: format!("crisis:{}", c.id),
            title: c.title.clone(),
            text: format!("{}\n\n{}", c.text, power),
            roles: vec![("a".to_string(), c.a.clone()), ("b".to_string(), me)],
            options,
            deferred: vec![],
            date: self.calendar.date_string(),
            as_b: true,
        };
        self.next_event_uid += 1;
        self.pending_events.push(decision);
    }

    fn crisis_cancel_prompt(&mut self, c: &Crisis) {
        let key = format!("crisis:{}", c.id);
        self.pending_events.retain(|d| d.event != key);
    }
}

#[allow(dead_code)]
fn _unused() -> f64 {
    minf(0.0, 0.0)
}
