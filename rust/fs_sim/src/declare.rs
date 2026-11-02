//! Declaring war and the join decisions of a conflict (`scripts/sim/diplomacy.gd`, the "Declaring war" and "Conflicts and join
//! decisions" parts, and `war_goal.gd`'s `for_declaration`): the casus belli a nation has, what may stop it, what a declaration
//! costs and does, the conflict it opens, and the choice every ally and guarantor then faces.
//!
//! Whether an AI nation joins is the AI's decision (`AIDiplomacy.joins`), which is not part of this port: it is read from
//! `GameState::ai_join_answers`, which a test fills, and the port stops with a message if an answer is missing. The AI's
//! bookkeeping of the wars it opens is kept (`ai_declarations`).

use crate::pressure::GREAT;
use crate::state::{CasusBelli, Data, GameState};
use serde_json::{json, Value};

/// A conflict: the pairwise wars opened together (`GameState.war_groups`).
#[derive(Debug, Clone, PartialEq)]
pub struct WarGroup {
    pub id: u32,
    pub attacker: String,
    pub defender: String,
    /// tag -> "attack" or "defend".
    pub members: Vec<(String, String)>,
    pub declined: Vec<String>,
    pub called: Vec<String>,
    pub violation: bool,
}

impl WarGroup {
    fn side_of(&self, tag: &str) -> Option<&str> {
        self.members.iter().find(|(t, _)| t == tag).map(|(_, s)| s.as_str())
    }

    fn set_member(&mut self, tag: &str, side: &str) {
        match self.members.iter_mut().find(|(t, _)| t == tag) {
            Some(slot) => slot.1 = side.to_string(),
            None => self.members.push((tag.to_string(), side.to_string())),
        }
    }
}

/// The decision a nation faces because of its tie to a member of a conflict (`Diplomacy._make_decision`).
#[derive(Debug, Clone, PartialEq)]
pub struct JoinDecision {
    pub id: u32,
    pub tag: String,
    pub group: u32,
    pub side: String,
    pub kind: String,
    pub ally: String,
    pub treaty_id: i64,
    pub cb: String,
    /// Whether it would have to fight an ally or pact partner.
    pub conflict: bool,
    pub enemies: Vec<String>,
    /// The day an AI nation was called, while it mobilizes.
    pub since: Option<i64>,
}

fn opposite(side: &str) -> &'static str {
    if side == "attack" {
        "defend"
    } else {
        "attack"
    }
}

impl GameState {
    fn day_d(&self) -> i64 {
        self.calendar.days_elapsed as i64
    }

    // ---------------------------------------------------------------- treaties read as lists

    /// `Diplomacy.allies_of`: allies of a nation (defensive-only ones included).
    pub fn allies_of(&self, tag: &str) -> Vec<String> {
        self.treaties_of(tag, "alliance").into_iter().map(|t| t.other(tag).to_string()).collect()
    }

    /// `Diplomacy.guarantors_of`: nations that guarantee `tag`.
    pub fn guarantors_of(&self, tag: &str) -> Vec<String> {
        self.treaties_of(tag, "guarantee").into_iter().filter(|t| t.b == tag).map(|t| t.a.clone()).collect()
    }

    /// `Diplomacy.guaranteed_by`: nations that `tag` guarantees.
    pub fn guaranteed_by(&self, tag: &str) -> Vec<String> {
        self.treaties_of(tag, "guarantee").into_iter().filter(|t| t.a == tag).map(|t| t.b.clone()).collect()
    }

    /// `Diplomacy.is_neutral`: whether a nation stands apart from the powers' quarrels: in no bloc, allied to no great power, not
    /// mobilized.
    pub fn is_neutral(&self, data: &Data, tag: &str) -> bool {
        if !self.nation_index.contains_key(tag) || !self.bloc_of(tag).is_empty() {
            return false;
        }
        if self.nation(tag).mobilization >= data.diplomacy.crisis.alarm_level {
            return false;
        }
        !self.allies_of(tag).iter().any(|a| GREAT.contains(&a.as_str()))
    }

    // ---------------------------------------------------------------- claims

    /// `Diplomacy.claim_provinces`: province ids named by a claim (a scenario claim names provinces; one made in play holds ids).
    pub fn claim_provinces(&self, data: &Data, claim: &Value) -> Vec<usize> {
        if let Some(ids) = claim.get("ids").and_then(Value::as_array) {
            return ids.iter().filter_map(|x| x.as_u64().map(|x| x as usize)).collect();
        }
        let mut out = vec![];
        for pname in claim.get("provinces").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
            for id in 1..data.map.provinces.len() {
                if data.map.provinces[id].name == pname {
                    out.push(id);
                }
            }
        }
        out
    }

    /// `Diplomacy._claim_applies`: whether `b` holds a claimed province (a border claim also needs it to touch the claimant).
    fn claim_applies(&self, data: &Data, claim: &Value, b: &str) -> bool {
        let holder = claim.get("holder").and_then(Value::as_str).unwrap_or("");
        for id in self.claim_provinces(data, claim) {
            if self.province_owner[id] != b {
                continue;
            }
            if claim.get("kind").and_then(Value::as_str) != Some("border_claim") {
                return true;
            }
            if data.map.neighbors(id).any(|n| self.province_owner[n] == holder) {
                return true;
            }
        }
        false
    }

    /// `Diplomacy.all_claims`: the scenario's claims and those made in play.
    pub fn all_claims(&self) -> Vec<Value> {
        self.scenario_claims.iter().chain(self.claims.iter()).cloned().collect()
    }

    /// `WarGoal.for_declaration`: the goal a war declared now by `a` on `b` with this casus belli would have (null for none).
    pub fn goal_for_declaration(&self, data: &Data, a: &str, b: &str, cb: &str) -> Value {
        match cb {
            "none" | "unprovoked_aggression" => return Value::Null,
            "guarantee_defence" | "ally_called" => return json!({"kind": "defence", "label": ""}),
            "fabricated_claim" => {
                for held in &self.casus_belli {
                    if held.holder == a && held.target == b && held.kind == cb && !held.goal.is_null() {
                        return held.goal.clone();
                    }
                }
                return Value::Null;
            }
            _ => {}
        }
        for claim in self.all_claims() {
            if claim.get("holder").and_then(Value::as_str) == Some(a) && claim.get("kind").and_then(Value::as_str) == Some(cb) && self.claim_applies(data, &claim, b) {
                let owned: Vec<usize> = self.nation(b).provinces.clone();
                let ids: Vec<usize> = self.claim_provinces(data, &claim).into_iter().filter(|id| owned.contains(id)).collect();
                if !ids.is_empty() {
                    let kind = if claim.get("kind").and_then(Value::as_str) == Some("border_claim") { "provinces" } else { "nationality" };
                    return json!({"kind": kind, "ids": ids, "label": claim.get("note").and_then(Value::as_str).unwrap_or("")});
                }
            }
        }
        Value::Null
    }

    // ---------------------------------------------------------------- may a nation declare war

    /// `Diplomacy.casus_belli_options`: casus belli ids `a` could use against `b` today, best first ("none" is always last).
    pub fn casus_belli_options(&self, data: &Data, a: &str, b: &str) -> Vec<String> {
        let mut out: Vec<String> = vec![];
        if a == b || !self.nation_index.contains_key(a) || !self.nation_index.contains_key(b) {
            return out;
        }
        for claim in self.all_claims() {
            let kind = claim.get("kind").and_then(Value::as_str).unwrap_or("").to_string();
            if claim.get("holder").and_then(Value::as_str) == Some(a) && self.claim_applies(data, &claim, b) && !out.contains(&kind) {
                out.push(kind);
            }
        }
        if self.guaranteed_by(a).iter().any(|w| self.at_war(w, b)) {
            out.push("guarantee_defence".to_string());
        }
        if self.allies_of(a).iter().any(|w| self.at_war(w, b)) {
            out.push("ally_called".to_string());
        }
        if let Some(cb) = self.casus_belli.iter().find(|cb| cb.holder == a && cb.target == b && cb.expires_day > self.day_d()) {
            out.push(cb.kind.clone());
        }
        out.push("none".to_string());
        out
    }

    /// `Diplomacy.declare_block`: why `a` may not declare war on `b` at all ("" if it may).
    pub fn declare_block(&self, data: &Data, a: &str, b: &str) -> &'static str {
        if a == b {
            return "same";
        }
        if !self.nation_index.contains_key(a) || !self.nation_index.contains_key(b) {
            return "unknown";
        }
        if self.nation(a).provinces.is_empty() || self.nation(b).provinces.is_empty() {
            return "no_land";
        }
        if self.at_war(a, b) {
            return "at_war";
        }
        if self.are_allied(data, a, b) {
            return "allied";
        }
        if self.has_treaty(data, "nap", a, b) {
            return "nap";
        }
        ""
    }

    /// `Diplomacy.declare_gate`: "mobilization" if `a` has not mobilized enough for a war with no casus belli.
    pub fn declare_gate(&self, data: &Data, a: &str, cb: &str) -> &'static str {
        if cb == "none" && self.nation(a).mobilization < data.diplomacy.min_mobilization {
            return "mobilization";
        }
        ""
    }

    pub fn can_declare(&self, data: &Data, a: &str, b: &str, cb: &str) -> bool {
        self.declare_block(data, a, b).is_empty() && self.casus_belli_options(data, a, b).iter().any(|c| c == cb) && self.declare_gate(data, a, cb).is_empty()
    }

    // ---------------------------------------------------------------- declaring

    /// `GameState.set_war(a, b, true, cb, group, goal)`: `a` starts the war; it joins the conflict `group` (0 starts a new one).
    pub fn set_war_full(&mut self, a: &str, b: &str, cb: &str, group: u32, goal: Value) {
        if a == b || self.at_war(a, b) {
            return;
        }
        self.set_war(a, b);
        let i = self.war_between(a, b).unwrap();
        self.wars[i].casus_belli = cb.to_string();
        self.wars[i].goal = goal;
        if group != 0 {
            // the war did not start a conflict of its own: give back the number it took
            self.next_war_group -= 1;
            self.wars[i].war_group = group;
        }
    }

    /// `Diplomacy.declare_war`: `a` declares war on `b` with the given casus belli. Returns false (changing nothing) if that is not
    /// allowed. `group` ties the war to a conflict already begun (0 starts one).
    pub fn declare_war(&mut self, data: &Data, a: &str, b: &str, cb: &str, group: u32) -> bool {
        if !self.can_declare(data, a, b, cb) {
            return false;
        }
        let rules = data.diplomacy.casus_belli.iter().find(|(k, _)| k == cb).map(|(_, r)| *r).unwrap_or_else(|| panic!("unknown casus belli {cb}"));
        // A war with no reason at all on a nation that stood apart shocks the world beyond the usual.
        let on_neutral = cb == "none" && self.is_neutral(data, b);
        let goal = self.goal_for_declaration(data, a, b, cb);
        self.set_war_full(a, b, cb, group, goal);
        if on_neutral {
            let tags: Vec<String> = self.nations.iter().map(|n| n.tag.clone()).collect();
            for tag in tags {
                if tag != a && tag != b {
                    self.change_relation(data, &tag, a, data.diplomacy.neutral_world_relations);
                }
            }
            self.gain_prestige(a, data.diplomacy.neutral_prestige);
            self.tension_impulse += data.diplomacy.neutral_tension;
        }
        let war = self.war_between(a, b).unwrap();
        let conflict = self.open_group(a, b, self.wars[war].war_group);
        // A dated casus belli is used up.
        self.casus_belli.retain(|h| !(h.holder == a && h.target == b && h.kind == cb));
        self.change_relation(data, a, b, rules.target_relations);
        let tags: Vec<String> = self.nations.iter().map(|n| n.tag.clone()).collect();
        for tag in tags {
            if tag != a && tag != b {
                self.change_relation(data, a, &tag, rules.world_relations);
            }
        }
        let ai = self.nation_index[a];
        self.nations[ai].prestige += rules.prestige;
        self.change_war_support(a, rules.war_support);
        if cb == "none" {
            self.earn_unprovoked_aggression(data, a, b);
        }
        self.note_declaration(a, cb);
        let gid = self.war_groups[conflict].id;
        self.offer_joins(data, gid, &[a.to_string(), b.to_string()]);
        true
    }

    /// `AIDiplomacy.note_declaration`: records a war the AI opened (by declaration or by joining).
    fn note_declaration(&mut self, tag: &str, cb: &str) {
        if tag == self.player_tag {
            return;
        }
        self.ai_declarations.0 += 1;
        if cb == "none" {
            self.ai_declarations.1 += 1;
        }
    }

    /// `Diplomacy._earn_unprovoked_aggression`: an unjustified war gives the aggressor's land neighbours and the victim's guarantors
    /// a casus belli against it for a few years, and stirs up their resentment.
    fn earn_unprovoked_aggression(&mut self, data: &Data, aggressor: &str, victim: &str) {
        let mut holders = self.neighbor_nations(data, aggressor);
        for g in self.guarantors_of(victim) {
            if !holders.contains(&g) {
                // The GDScript appends to the list it got from the cache: the aggressor's "neighbours" keep the guarantor.
                self.neighbor_cache_push(aggressor, &g);
                holders.push(g);
            }
        }
        let expires = self.day_d() + (data.diplomacy.cb_years * 365.0) as i64;
        for tag in holders {
            if tag == victim || tag == aggressor {
                continue;
            }
            self.casus_belli.push(CasusBelli { holder: tag.clone(), target: aggressor.to_string(), kind: "unprovoked_aggression".to_string(), expires_day: expires, goal: Value::Null });
            self.add_grievance(&tag, aggressor, data.diplomacy.grievance_on_unprovoked_war);
        }
    }

    /// `Diplomacy.start_war`: registers a war that exists from the start of the scenario. With `call_allies` the allies are called at
    /// once.
    pub fn start_war(&mut self, data: &Data, a: &str, b: &str, call_allies: bool) {
        self.set_war_full(a, b, "", 0, Value::Null);
        let war = self.war_between(a, b).unwrap();
        let g = self.open_group(a, b, self.wars[war].war_group);
        if call_allies {
            let gid = self.war_groups[g].id;
            self.offer_joins(data, gid, &[a.to_string(), b.to_string()]);
        }
    }

    /// The end of `GameState.load_scenario`: the scenario's own wars begin (with the allies called when it is a crisis). The loader
    /// does this before it sets the player, so no decision is waiting for them: it is done with no player here, too. The AI's answers
    /// to the calls must be in `ai_join_answers`.
    pub fn start_scenario_wars(&mut self, data: &Data) {
        let player = std::mem::take(&mut self.player_tag);
        for (a, b) in self.starting_wars.clone() {
            self.start_war(data, &a, &b, self.start_crisis);
        }
        self.player_tag = player;
    }

    // ---------------------------------------------------------------- conflicts and join decisions

    /// `Diplomacy._open_group`: the conflict record for a war group, created on first use. Returns its index.
    fn open_group(&mut self, a: &str, b: &str, group_id: u32) -> usize {
        let i = match self.war_groups.iter().position(|g| g.id == group_id) {
            Some(i) => i,
            None => {
                self.war_groups.push(WarGroup { id: group_id, attacker: a.to_string(), defender: b.to_string(), members: vec![], declined: vec![], called: vec![], violation: false });
                self.war_groups.len() - 1
            }
        };
        let g = &mut self.war_groups[i];
        let mut side_a = g.side_of(a).unwrap_or("").to_string();
        if side_a.is_empty() {
            if let Some(sb) = g.side_of(b) {
                side_a = opposite(sb).to_string();
            }
        }
        if side_a.is_empty() {
            side_a = "attack".to_string();
        }
        g.set_member(a, &side_a);
        if g.side_of(b).is_none() {
            g.set_member(b, opposite(&side_a));
        }
        i
    }

    /// `Diplomacy.group_side`: members of a conflict on one side, in tag order.
    pub fn group_side(&self, group_id: u32, side: &str) -> Vec<String> {
        let mut out: Vec<String> = self.war_groups.iter().find(|g| g.id == group_id).map(|g| g.members.iter().filter(|(_, s)| s == side).map(|(t, _)| t.clone()).collect()).unwrap_or_default();
        out.sort();
        out
    }

    fn pending_for(&self, tag: &str, group: u32) -> bool {
        self.pending_joins.iter().any(|d| d.tag == tag && d.group == group)
    }

    /// `Diplomacy._candidates`: nations that are allied with, or guarantee, a member and have not been asked already.
    fn join_candidates(&self, gi: usize, member: &str) -> Vec<String> {
        let g = &self.war_groups[gi];
        let mut out: Vec<String> = vec![];
        for t in self.treaties_of(member, "") {
            if t.kind != "alliance" && t.kind != "guarantee" {
                continue;
            }
            if t.kind == "guarantee" && t.b != member {
                continue;
            }
            let tag = t.other(member).to_string();
            if g.side_of(&tag).is_some() || g.declined.contains(&tag) || g.called.contains(&tag) || out.contains(&tag) || !self.nation_index.contains_key(&tag) {
                continue;
            }
            if self.nation(&tag).provinces.is_empty() || self.pending_for(&tag, g.id) {
                continue;
            }
            out.push(tag);
        }
        out.sort();
        out
    }

    /// `Diplomacy._make_decision`: the decision `tag` faces because of its tie to `member`, or none if the tie asks nothing of it.
    fn make_decision(&mut self, data: &Data, gi: usize, tag: &str, member: &str) -> Option<JoinDecision> {
        let g = self.war_groups[gi].clone();
        let attacked = g.defender == member && g.side_of(member) == Some("defend");
        let mut kind = "";
        let mut treaty_id = -1i64;
        let guarantee = self.find_treaty(data, "guarantee", tag, member).map(|t| t.id);
        let alliance = self.find_treaty(data, "alliance", tag, member).map(|t| (t.id, t.term("entente"), t.term("defensive_only")));
        if let (Some(gid), true) = (guarantee, attacked) {
            kind = "guarantee";
            treaty_id = gid as i64;
        } else if let Some((aid, entente, defensive)) = alliance {
            treaty_id = aid as i64;
            if entente {
                kind = "entente";
            } else if attacked {
                kind = "alliance_defence";
            } else if !defensive {
                kind = "alliance_called";
            }
        }
        if kind.is_empty() {
            return None;
        }
        let side = g.side_of(member).unwrap_or("").to_string();
        let enemies = self.group_side(g.id, opposite(&side));
        let mut conflict = enemies.is_empty() || self.at_war(tag, member);
        for e in &enemies {
            let b = self.declare_block(data, tag, e);
            if b != "" && b != "at_war" {
                conflict = true;
            }
        }
        let cb = if kind == "guarantee" { "guarantee_defence" } else { "ally_called" };
        let d = JoinDecision { id: self.next_decision_id, tag: tag.to_string(), group: g.id, side, kind: kind.to_string(), ally: member.to_string(), treaty_id, cb: cb.to_string(), conflict, enemies, since: None };
        self.next_decision_id += 1;
        Some(d)
    }

    /// The AI's answer to a join decision (`AIDiplomacy.joins`), from the answers a test provides.
    fn ai_joins(&self, d: &JoinDecision) -> bool {
        *self.ai_join_answers.get(&format!("{}|{}", d.tag, d.group)).unwrap_or_else(|| panic!("the AI's answer for {} joining conflict {} is needed: the AI is not ported", d.tag, d.group))
    }

    /// `Diplomacy.offer_joins`: offers every ally and guarantor of `seeds` (members of the conflict) the choice to join. Each nation
    /// that joins brings its own allies in turn. An AI nation that is bound to join is called up: it mobilizes and enters the war when
    /// ready. The player gets a pending decision.
    pub fn offer_joins(&mut self, data: &Data, group_id: u32, seeds: &[String]) {
        let Some(gi) = self.war_groups.iter().position(|g| g.id == group_id) else { return };
        let mut queue: std::collections::VecDeque<String> = seeds.iter().cloned().collect();
        while let Some(member) = queue.pop_front() {
            for tag in self.join_candidates(gi, &member) {
                let Some(mut d) = self.make_decision(data, gi, &tag, &member) else { continue };
                if tag == self.player_tag {
                    self.pending_joins.push(d);
                } else if d.conflict || !self.ai_joins(&d) {
                    self.decline_join(data, &d);
                } else {
                    // The AI mobilizes first and joins when it is ready (see step_join_calls).
                    self.war_groups[gi].called.push(tag.clone());
                    d.since = Some(self.day_d());
                    let key = format!("{tag}|{}", group_id);
                    match self.join_calls.iter_mut().find(|(k, _)| *k == key) {
                        Some(slot) => slot.1 = d,
                        None => self.join_calls.push((key, d)),
                    }
                }
            }
        }
    }

    /// `Diplomacy._join`: `tag` enters the conflict on the side of the nation that asked, opening a war against every member of the
    /// other side. Returns false if there is no one to fight.
    fn join_conflict(&mut self, data: &Data, d: &JoinDecision) -> bool {
        let gi = self.war_groups.iter().position(|g| g.id == d.group).unwrap();
        let tag = d.tag.clone();
        let enemies = self.group_side(d.group, opposite(&d.side));
        let rules = data.diplomacy.casus_belli.iter().find(|(k, _)| *k == d.cb).map(|(_, r)| *r).unwrap();
        let mut opened = false;
        for e in enemies {
            if e == tag || self.at_war(&tag, &e) {
                continue;
            }
            self.set_war_full(&tag, &e, &d.cb, d.group, Value::Null);
            self.note_declaration(&tag, &d.cb);
            opened = true;
            self.change_relation(data, &tag, &e, rules.target_relations);
        }
        if !opened && self.war_groups[gi].side_of(&tag).is_none() {
            return false;
        }
        self.war_groups[gi].set_member(&tag, &d.side);
        let ti = self.nation_index[&tag];
        self.nations[ti].prestige += rules.prestige;
        self.change_war_support(&tag, rules.war_support);
        true
    }

    /// `Diplomacy._decline`: `tag` stays out. Failing a bound obligation costs what the config says.
    fn decline_join(&mut self, data: &Data, d: &JoinDecision) {
        let gi = self.war_groups.iter().position(|g| g.id == d.group).unwrap();
        self.war_groups[gi].declined.push(d.tag.clone());
        let cost = data.diplomacy.join_decline.iter().find(|(k, _)| *k == d.kind).map(|(_, c)| *c).unwrap();
        if !d.conflict {
            self.change_relation(data, &d.tag, &d.ally, cost.ally_relations);
            let ti = self.nation_index[&d.tag];
            self.nations[ti].prestige += cost.prestige;
            if cost.end_treaty {
                let day = self.day_d();
                if let Some(i) = self.treaties.iter().position(|t| t.id as i64 == d.treaty_id && t.active_on(day) && ((t.a == d.tag && t.b == d.ally) || (t.a == d.ally && t.b == d.tag))) {
                    self.end_treaty_at(data, i);
                }
            }
        }
    }

    /// `Diplomacy.answer_join`: the player's answer to a pending decision. Returns false if no such decision is waiting.
    pub fn answer_join(&mut self, data: &Data, decision_id: u32, joins: bool) -> bool {
        let Some(i) = self.pending_joins.iter().position(|d| d.id == decision_id) else { return false };
        let d = self.pending_joins.remove(i);
        if joins && !d.conflict && self.join_conflict(data, &d) {
            self.offer_joins(data, d.group, &[d.tag.clone()]);
        } else {
            self.decline_join(data, &d);
        }
        true
    }

    /// `Diplomacy.violate_border`: a nation's armies crossed into a guaranteed nation's land without a war being declared: the
    /// guarantors are asked to defend it, as if it had been attacked.
    pub fn violate_border(&mut self, data: &Data, violator: &str, victim: &str) {
        let group_id = self.next_war_group;
        self.next_war_group += 1;
        let gi = self.open_group(violator, victim, group_id);
        self.war_groups[gi].violation = true;
        let gid = self.war_groups[gi].id;
        self.offer_joins(data, gid, &[victim.to_string()]);
    }

    fn group_active(&self, group_id: u32) -> bool {
        if self.war_groups.iter().find(|g| g.id == group_id).map(|g| g.violation).unwrap_or(false) {
            return true;
        }
        self.wars.iter().any(|w| w.war_group == group_id)
    }

    /// `Diplomacy._step_join_calls`: called nations that have mobilized enough enter their wars (and call their own allies).
    pub fn step_join_calls(&mut self, data: &Data) {
        let keys: Vec<String> = self.join_calls.iter().map(|(k, _)| k.clone()).collect();
        for key in keys {
            let Some(pos) = self.join_calls.iter().position(|(k, _)| *k == key) else { continue };
            let d = self.join_calls[pos].1.clone();
            let exists = self.war_groups.iter().any(|g| g.id == d.group);
            if !exists || !self.group_active(d.group) {
                self.join_calls.remove(pos);
                continue;
            }
            if self.nation(&d.tag).mobilization < data.diplomacy.join_mobilization {
                continue;
            }
            self.join_calls.remove(pos);
            if self.join_conflict(data, &d) {
                self.offer_joins(data, d.group, &[d.tag.clone()]);
            } else {
                let gi = self.war_groups.iter().position(|g| g.id == d.group).unwrap();
                self.war_groups[gi].declined.push(d.tag.clone());
            }
        }
    }
}
