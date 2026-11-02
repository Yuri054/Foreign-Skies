//! War score, peace offers and peace terms (`scripts/sim/peace.gd`, `war_goal.gd`, and the parts of `capitulation.gd` and
//! `diplomacy.gd` they use): what a war's score is, what a demand costs, whether terms can be made, and what making peace does.
//!
//! Whether an AI nation accepts an offer is the AI's decision (`AIPeace.accepts`), which is not part of this port: `propose`
//! takes the answer as an argument. A conference, the AI's own offers and the dictated peace after a capitulation are not
//! ported; nor is a war's log. Separate peaces inside a conflict (`_separate_peace`) need the join groups of a war, which
//! only declaring war opens: they are not ported.

use crate::gd::{clampf, maxf, minf};
use crate::pressure::GREAT;
use crate::state::{Data, GameState, Indemnity, Restriction};
use serde_json::{json, Value};

/// One demand of a peace (`{kind: "province", ids}`, `{kind: "indemnity", share, months}`, ...).
#[derive(Debug, Clone, PartialEq)]
pub enum Demand {
    Province(Vec<usize>),
    Indemnity { share: f64, months: i64 },
    ReleaseAlly(String),
    DisarmBorder(i64),
    FleetLimit(i64),
}

impl Demand {
    pub fn kind(&self) -> &'static str {
        match self {
            Demand::Province(_) => "province",
            Demand::Indemnity { .. } => "indemnity",
            Demand::ReleaseAlly(_) => "release_ally",
            Demand::DisarmBorder(_) => "disarm_border",
            Demand::FleetLimit(_) => "fleet_limit",
        }
    }
}

/// A proposal waiting for the player, or being resolved (`GameState.pending_offers`).
#[derive(Debug, Clone, PartialEq)]
pub struct Offer {
    pub id: u32,
    pub war_id: u32,
    pub from: String,
    pub to: String,
    pub mode: String,
    pub taker: String,
    pub giver: String,
    pub demands: Vec<Demand>,
    pub cost: f64,
    pub forced: bool,
    pub day: i64,
    pub note: String,
}

/// What `Peace.check` finds: {ok, reason, cost, budget, taker, giver, forced, war}.
#[derive(Debug, Clone, Default)]
pub struct Check {
    pub ok: bool,
    pub reason: String,
    pub cost: f64,
    pub budget: f64,
    pub taker: String,
    pub giver: String,
    pub forced: bool,
    pub war: Option<usize>,
}

/// What `Peace.propose` answers: `accepted` is None while the player still has to answer.
#[derive(Debug, Clone)]
pub struct Proposed {
    pub ok: bool,
    pub reason: String,
    pub accepted: Option<bool>,
}

impl GameState {
    fn day_p(&self) -> i64 {
        self.calendar.days_elapsed as i64
    }

    // ---------------------------------------------------------------- war score

    /// `Peace.occupation_points`: score `holder` earns for the share of `owner`'s value it holds.
    pub fn occupation_points(&self, data: &Data, holder: &str, owner: &str) -> f64 {
        self.capitulation_progress_by(data, owner, holder) * data.diplomacy.peace.score_occupation_points
    }

    /// `Peace.capital_points`: the part of `occupation_points` that is the capital bonus.
    pub fn capital_points(&self, data: &Data, holder: &str, owner: &str) -> f64 {
        let bonus = self.capital_bonus(data, owner);
        let whole = bonus + self.provinces_value(data, owner);
        if whole <= 0.0 {
            return 0.0;
        }
        let mut held = 0.0;
        let home = self.home_capital(owner);
        if home > 0 && self.province_controller[home as usize] == holder {
            held += bonus;
        }
        if self.relocated(owner) && self.province_controller[self.nation(owner).capital as usize] == holder {
            held += bonus * data.diplomacy.capitulation.relocated_bonus;
        }
        held / whole * data.diplomacy.peace.score_occupation_points
    }

    /// `Peace.occupied_share`: the share of `owner`'s weight that `holder` occupies, 0 to 1.
    pub fn occupied_share(&self, data: &Data, holder: &str, owner: &str) -> f64 {
        self.occupation_points(data, holder, owner) / data.diplomacy.peace.score_occupation_points
    }

    /// `Peace.score_parts`: the parts of `tag`'s war score in a war and their sum: (occupation, capital, battles,
    /// capitulation, total).
    pub fn score_parts(&self, data: &Data, war: usize, tag: &str) -> (f64, f64, f64, f64, f64) {
        let c = &data.diplomacy.peace;
        let w = &self.wars[war];
        let other = w.other(tag).to_string();
        let capital = self.capital_points(data, tag, &other) - self.capital_points(data, &other, tag);
        let occupation = self.occupation_points(data, tag, &other) - self.occupation_points(data, &other, tag) - capital;
        let battles = w.battle_points.get(tag).copied().unwrap_or(0.0) - w.battle_points.get(&other).copied().unwrap_or(0.0);
        let mut surrender = 0.0;
        let points = data.diplomacy.capitulation.score;
        if w.capitulated.contains_key(&other) {
            surrender += points;
        }
        if w.capitulated.contains_key(tag) {
            surrender -= points;
        }
        (occupation, capital, battles, surrender, clampf(occupation + capital + battles + surrender, -c.score_max, c.score_max))
    }

    pub fn war_score(&self, data: &Data, war: usize, tag: &str) -> f64 {
        self.score_parts(data, war, tag).4
    }

    /// `Peace.capital_taken_by`: who holds a nation's (home) capital if it is not the nation itself, else "".
    fn capital_taken_by(&self, tag: &str) -> String {
        let home = self.home_capital(tag);
        if home <= 0 {
            return String::new();
        }
        let holder = &self.province_controller[home as usize];
        if holder == tag {
            String::new()
        } else {
            holder.clone()
        }
    }

    /// `Peace.is_forced`: whether `giver` is beaten badly enough that `taker` may dictate terms.
    pub fn is_forced(&self, data: &Data, taker: &str, giver: &str) -> bool {
        if self.nation(giver).capitulated {
            return true;
        }
        let support = self.nation(giver).war_support;
        let p = &data.diplomacy.peace;
        if support <= p.surrender_at {
            return true;
        }
        if self.capital_taken_by(giver) == taker && support <= p.support_floor {
            return true;
        }
        self.occupied_share(data, taker, giver) >= p.forced_occupied_share
    }

    // ---------------------------------------------------------------- prices and checks

    /// `Capitulation.whole_value`.
    pub fn whole_value(&self, data: &Data, tag: &str) -> f64 {
        self.capital_bonus(data, tag) + self.provinces_value(data, tag)
    }

    /// `Capitulation.value_of`: the value one province carries for its owner, capital bonuses included.
    pub fn value_of(&self, data: &Data, id: usize, tag: &str) -> f64 {
        let mut v = self.province_value(data, id);
        if id as i64 == self.home_capital(tag) {
            v += self.capital_bonus(data, tag);
        } else if self.relocated(tag) && id as i64 == self.nation(tag).capital {
            v += self.capital_bonus(data, tag) * data.diplomacy.capitulation.relocated_bonus;
        }
        v
    }

    /// `Peace.province_share`: the share of a nation's whole value that one province carries, 0 to 1.
    pub fn province_share(&self, data: &Data, id: usize, tag: &str) -> f64 {
        let whole = self.whole_value(data, tag);
        if whole > 0.0 {
            self.value_of(data, id, tag) / whole
        } else {
            0.0
        }
    }

    /// `Peace.province_price`: score a province costs to take from `giver`.
    pub fn province_price(&self, data: &Data, id: usize, taker: &str, giver: &str) -> f64 {
        let p = &data.diplomacy.peace;
        let mut price = p.province_scale * self.province_share(data, id, giver);
        if self.province_controller[id] == taker {
            price *= p.occupied_discount;
        }
        price
    }

    fn sea_link(&self, data: &Data, taker: &str, id: usize) -> bool {
        for zone in data.map.zones_of_port(id) {
            // (Whether the taker's ships hold the water is not ported: none do.)
            if let Some(ports) = data.map.ports_of_zone.get(&zone) {
                if ports.iter().any(|&q| self.province_owner[q] == taker) {
                    return true;
                }
            }
        }
        false
    }

    fn touches(&self, data: &Data, taker: &str, id: usize) -> bool {
        data.map.neighbors(id).any(|n| self.province_owner[n] == taker) || self.sea_link(data, taker, id)
    }

    /// `Peace.detached`: the provinces of `ids` that would not touch the taker's land, by land or by a sea it holds.
    pub fn detached(&self, data: &Data, taker: &str, ids: &[usize]) -> Vec<usize> {
        let mut reached: Vec<usize> = vec![];
        let mut queue: Vec<usize> = vec![];
        for &id in ids {
            if self.touches(data, taker, id) {
                reached.push(id);
                queue.push(id);
            }
        }
        while let Some(p) = queue.pop() {
            for n in data.map.neighbors(p) {
                if ids.contains(&n) && !reached.contains(&n) {
                    reached.push(n);
                    queue.push(n);
                }
            }
        }
        ids.iter().copied().filter(|id| !reached.contains(id)).collect()
    }

    /// `Peace.province_problem`: why a set of the giver's provinces cannot be taken ("" if it can).
    pub fn province_problem(&self, data: &Data, taker: &str, giver: &str, ids: &[usize]) -> &'static str {
        let cap = self.nation(giver).capital;
        if ids.iter().any(|&i| i as i64 == cap) && ids.len() < self.nation(giver).provinces.len() {
            return "capital";
        }
        if !self.detached(data, taker, ids).is_empty() {
            return "detached";
        }
        ""
    }

    /// `Peace.can_add`: whether `id` could join `chosen` and keep the set takeable.
    pub fn can_add(&self, data: &Data, taker: &str, giver: &str, id: usize, chosen: &[usize]) -> bool {
        if id as i64 == self.nation(giver).capital && chosen.len() + 1 < self.nation(giver).provinces.len() {
            return false;
        }
        if self.touches(data, taker, id) {
            return true;
        }
        data.map.neighbors(id).any(|n| chosen.contains(&n))
    }

    /// `Peace.max_cession`: the most provinces `giver` may hand over in one treaty.
    pub fn max_cession(&self, data: &Data, giver: &str) -> usize {
        let count = self.nation(giver).provinces.len();
        if !GREAT.contains(&giver) {
            return count;
        }
        ((count as f64 * data.diplomacy.peace.great_power_max_share).floor() as usize).max(1)
    }

    /// `Peace.pick_takeable`: picks from `candidates` what `budget` pays for at `price_of(id)` and can be taken together, at most
    /// `max_cession` of them. Returns (ids, spent).
    pub fn pick_takeable(&self, data: &Data, taker: &str, giver: &str, candidates: &[usize], price_of: &dyn Fn(usize) -> f64, budget: f64) -> (Vec<usize>, f64) {
        let mut ids: Vec<usize> = vec![];
        let mut spent = 0.0;
        let mut added = true;
        let cap = self.max_cession(data, giver);
        while added && ids.len() < cap {
            added = false;
            for &id in candidates {
                if ids.len() >= cap {
                    break;
                }
                if ids.contains(&id) {
                    continue;
                }
                let price = price_of(id);
                if spent + price <= budget && self.can_add(data, taker, giver, id, &ids) {
                    ids.push(id);
                    spent += price;
                    added = true;
                }
            }
        }
        (ids, spent)
    }

    /// `WarGoal.price_factor`: the price multiplier for one demand: the discount for what the aggressor's goal asks, the premium for
    /// the rest.
    pub fn price_factor(&self, data: &Data, war: Option<usize>, taker: &str, d: &Demand, province_id: usize) -> f64 {
        let Some(w) = war else { return 1.0 };
        let w = &self.wars[w];
        if taker != w.a {
            return 1.0;
        }
        let p = &data.diplomacy.peace;
        let goal = &w.goal;
        let empty = goal.is_null() || goal.as_object().map(|o| o.is_empty()).unwrap_or(false);
        if empty {
            return if w.casus_belli == "none" { p.goal_none_premium } else { 1.0 };
        }
        let kind = d.kind();
        match goal.get("kind").and_then(Value::as_str).unwrap_or("") {
            "provinces" | "nationality" => {
                if kind == "province" {
                    let ids: Vec<usize> = goal.get("ids").and_then(Value::as_array).map(|a| a.iter().filter_map(|x| x.as_u64().map(|x| x as usize)).collect()).unwrap_or_default();
                    return if ids.contains(&province_id) { p.goal_discount } else { p.goal_premium };
                }
                p.goal_premium
            }
            "concession" => {
                if Some(kind) == goal.get("demand").and_then(|d| d.get("kind")).and_then(Value::as_str) {
                    p.goal_discount
                } else {
                    p.goal_premium
                }
            }
            "defence" => {
                if ["indemnity", "disarm_border", "release_ally", "fleet_limit"].contains(&kind) {
                    p.goal_discount
                } else {
                    p.goal_premium
                }
            }
            _ => 1.0,
        }
    }

    /// `Military.border_provinces`: provinces a nation holds that touch ground held by another nation, in province order.
    pub fn border_provinces(&self, data: &Data, tag: &str, other: &str) -> Vec<usize> {
        (1..self.province_controller.len()).filter(|&id| self.province_controller[id] == tag && data.map.neighbors(id).any(|n| self.province_controller[n] == other)).collect()
    }

    /// `Navy.strength_of`: the strength of all a nation's ships, afloat and in port.
    pub fn naval_strength(&self, tag: &str) -> f64 {
        self.fleets.iter().filter(|f| f.tag == tag).flat_map(|f| f.ships.iter()).map(|s| s.strength).sum()
    }

    fn release_treaties(&self, giver: &str, other: &str) -> Vec<usize> {
        let day = self.day_p();
        (0..self.treaties.len()).filter(|&i| {
            let t = &self.treaties[i];
            t.active_on(day) && ((t.a == giver && t.b == other) || (t.a == other && t.b == giver)) && (t.kind == "alliance" || t.kind == "guarantee")
        }).collect()
    }

    /// `Peace.demand_cost`: what one demand costs the taker in score, or -1 if it cannot be made.
    pub fn demand_cost(&self, data: &Data, taker: &str, giver: &str, d: &Demand) -> f64 {
        let p = &data.diplomacy.peace;
        let war = self.war_between(taker, giver);
        let f = self.price_factor(data, war, taker, d, 0);
        match d {
            Demand::Province(ids) => {
                if ids.is_empty() {
                    return -1.0;
                }
                let mut total = 0.0;
                for &id in ids {
                    if id < 1 || id >= self.province_owner.len() || self.province_owner[id] != giver {
                        return -1.0;
                    }
                    total += self.province_price(data, id, taker, giver) * self.price_factor(data, war, taker, d, id);
                }
                if !self.province_problem(data, taker, giver, ids).is_empty() {
                    return -1.0;
                }
                total
            }
            Demand::Indemnity { share, months } => {
                if *share <= 0.0 || *share > p.max_share || *months < 1 || *months > p.max_months {
                    return -1.0;
                }
                p.indemnity_points_per_year * share * *months as f64 / 12.0 * f
            }
            Demand::ReleaseAlly(other) => {
                if !self.nation_index.contains_key(other) || other == taker || other == giver || self.release_treaties(giver, other).is_empty() {
                    return -1.0;
                }
                p.release_ally * f
            }
            Demand::DisarmBorder(years) => {
                if *years < 1 || *years > p.disarm_years_max || self.border_provinces(data, giver, taker).is_empty() {
                    return -1.0;
                }
                p.disarm_border_per_year * *years as f64 * f
            }
            Demand::FleetLimit(years) => {
                if *years < 1 || *years > p.disarm_years_max || self.naval_strength(giver) <= 0.0 {
                    return -1.0;
                }
                p.fleet_limit_per_year * *years as f64 * f
            }
        }
    }

    fn owned_by(&self, ids: &[usize], tag: &str) -> bool {
        !ids.is_empty() && ids.iter().all(|&id| id >= 1 && id < self.province_owner.len() && self.province_owner[id] == tag)
    }

    /// `Peace.check`: checks a proposal. Reasons: no_war, pending, cooldown, detached, capital, invalid, forced_terms, too_much,
    /// too_expensive.
    pub fn check_peace(&self, data: &Data, from: &str, to: &str, mode: &str, demands: &[Demand]) -> Check {
        let mut out = Check::default();
        let war = self.war_between(from, to);
        if war.is_none() || (mode != "demand" && mode != "offer") {
            out.reason = "no_war".to_string();
            return out;
        }
        out.war = war;
        out.taker = if mode == "demand" { from } else { to }.to_string();
        out.giver = if mode == "demand" { to } else { from }.to_string();
        let war_id = self.wars[war.unwrap()].id;
        if self.pending_offers.iter().any(|o| o.war_id == war_id) {
            out.reason = "pending".to_string();
            return out;
        }
        if self.peace_cooldown.get(&Self::pair_key(from, to)).copied().unwrap_or(-1) > self.day_p() && from != self.player_tag {
            out.reason = "cooldown".to_string();
            return out;
        }
        let (taker, giver) = (out.taker.clone(), out.giver.clone());
        let t = self.check_terms(data, war.unwrap(), &taker, &giver, demands);
        out.reason = t.reason;
        out.cost = t.cost;
        out.budget = t.budget;
        out.forced = t.forced;
        out.ok = out.reason.is_empty();
        out
    }

    /// `Peace.check_terms`: the part of `check` that looks at the terms alone.
    pub fn check_terms(&self, data: &Data, war: usize, taker: &str, giver: &str, demands: &[Demand]) -> Check {
        let mut out = Check { taker: taker.to_string(), giver: giver.to_string(), ..Default::default() };
        let mut cost = 0.0;
        let ceded: usize = demands.iter().map(|d| if let Demand::Province(ids) = d { ids.len() } else { 0 }).sum();
        if ceded > self.max_cession(data, giver) {
            out.reason = "too_much".to_string();
            return out;
        }
        for d in demands {
            let c = self.demand_cost(data, taker, giver, d);
            if c < 0.0 {
                out.reason = "invalid".to_string();
                if let Demand::Province(ids) = d {
                    if self.owned_by(ids, giver) {
                        let problem = self.province_problem(data, taker, giver, ids);
                        if !problem.is_empty() {
                            out.reason = problem.to_string();
                        }
                    }
                }
                return out;
            }
            cost += c;
        }
        out.cost = cost;
        out.forced = self.is_forced(data, taker, giver);
        let score = self.war_score(data, war, taker);
        out.budget = score;
        if out.forced {
            // A beaten nation gives more than the score pays for, but only the ground the taker holds, the war's goal and money.
            out.budget = maxf(score, 0.0) * data.diplomacy.peace.forced_budget_mult;
            let w = &self.wars[war];
            let goal_ids: Vec<usize> = if w.a == taker {
                w.goal.get("ids").and_then(Value::as_array).map(|a| a.iter().filter_map(|x| x.as_u64().map(|x| x as usize)).collect()).unwrap_or_default()
            } else {
                vec![]
            };
            for d in demands {
                if let Demand::Province(ids) = d {
                    for &id in ids {
                        if self.province_controller[id] != taker && !goal_ids.contains(&id) {
                            out.reason = "forced_terms".to_string();
                            return out;
                        }
                    }
                }
            }
        }
        if cost > 0.0 && cost > out.budget {
            out.reason = "too_expensive".to_string();
        }
        out
    }

    // ---------------------------------------------------------------- offers

    /// `Peace.propose`: makes a proposal. An AI target answers at once (`ai_accepts` is its answer: `AIPeace.accepts`); the
    /// player is asked, unless they have capitulated, when the terms are imposed. A refusal puts the proposer on a cooldown.
    pub fn propose_peace(&mut self, data: &Data, from: &str, to: &str, mode: &str, demands: Vec<Demand>, ai_accepts: bool) -> Proposed {
        let c = self.check_peace(data, from, to, mode, &demands);
        if !c.ok {
            return Proposed { ok: false, reason: c.reason, accepted: Some(false) };
        }
        let offer = Offer {
            id: self.next_offer_id,
            war_id: self.wars[c.war.unwrap()].id,
            from: from.to_string(),
            to: to.to_string(),
            mode: mode.to_string(),
            taker: c.taker.clone(),
            giver: c.giver.clone(),
            demands,
            cost: c.cost,
            forced: c.forced,
            day: self.day_p(),
            note: String::new(),
        };
        self.next_offer_id += 1;
        if to == self.player_tag && self.nation(to).capitulated && mode == "demand" {
            // The player has capitulated: the victor's terms are not asked, they are imposed.
            self.resolve_offer(data, &offer, true);
            return Proposed { ok: true, reason: String::new(), accepted: Some(true) };
        }
        if to == self.player_tag {
            self.pending_offers.push(offer);
            return Proposed { ok: true, reason: String::new(), accepted: None };
        }
        self.resolve_offer(data, &offer, ai_accepts);
        Proposed { ok: true, reason: String::new(), accepted: Some(ai_accepts) }
    }

    /// `Peace.answer`: the player's answer to a pending offer. Returns false if no such offer is waiting.
    pub fn answer_offer(&mut self, data: &Data, offer_id: u32, accept: bool) -> bool {
        let Some(i) = self.pending_offers.iter().position(|o| o.id == offer_id) else { return false };
        let offer = self.pending_offers.remove(i);
        // The war may have changed under it (the other side made peace, a province was lost).
        let accept = accept && self.offer_still_valid(data, &offer);
        self.resolve_offer(data, &offer, accept);
        true
    }

    pub fn offer_still_valid(&self, data: &Data, offer: &Offer) -> bool {
        let Some(w) = self.war_between(&offer.from, &offer.to) else { return false };
        if self.wars[w].id != offer.war_id {
            return false;
        }
        for d in &offer.demands {
            if self.demand_cost(data, &offer.taker, &offer.giver, d) < 0.0 {
                return false;
            }
        }
        self.check_terms(data, w, &offer.taker, &offer.giver, &offer.demands).reason.is_empty()
    }

    /// `Peace._resolve`, for the tests.
    pub fn resolve_offer_pub(&mut self, data: &Data, offer: &Offer, accepted: bool) {
        self.resolve_offer(data, offer, accepted);
    }

    fn resolve_offer(&mut self, data: &Data, offer: &Offer, accepted: bool) {
        let war = self.war_between(&offer.from, &offer.to);
        if accepted {
            if let Some(w) = war {
                self.make_peace(data, w, offer);
            }
        } else {
            self.peace_cooldown.insert(Self::pair_key(&offer.from, &offer.to), self.day_p() + data.diplomacy.peace.refuse_cooldown_days);
        }
    }

    // ---------------------------------------------------------------- making peace

    /// `GameState.set_war(a, b, false)`: the war ends and is filed.
    pub fn end_war(&mut self, index: usize) {
        let mut w = self.wars.remove(index);
        w.end_day = self.day_p();
        self.war_history.push(w);
    }

    /// `GameState.transfer_province`: transfers ownership (and control) of a province.
    pub fn transfer_province(&mut self, data: &Data, id: usize, tag: &str) {
        let old = self.province_owner[id].clone();
        if old == tag {
            return;
        }
        self.province_owner[id] = tag.to_string();
        self.province_controller[id] = tag.to_string();
        self.control_version += 1;
        self.owner_version += 1;
        self.occupation.remove(&id);
        // Construction by the old owner is lost with the province.
        let oi = self.nation_index[&old];
        self.nations[oi].construction.retain(|j| j.province != id);
        let _ = self.rebuild_nation_provinces();
        self.recompute(data);
    }

    /// `Diplomacy.revanche`: ground handed over at a peace leaves the loser a reconquest claim to it, and a lasting resentment
    /// of the winner.
    pub fn revanche(&mut self, data: &Data, loser: &str, winner: &str, ids: &[usize], from_war: bool) {
        if ids.is_empty() || !self.nation_index.contains_key(loser) || self.nation(loser).provinces.is_empty() {
            return;
        }
        let c = &data.diplomacy.peace;
        let until = self.day_p() + (c.revanche_years * 365.0) as i64;
        let mut at = None;
        for (i, old) in self.claims.iter().enumerate() {
            if old.get("holder").and_then(Value::as_str) == Some(loser) && old.get("against").and_then(Value::as_str).unwrap_or("") == winner {
                at = Some(i);
            }
        }
        let i = match at {
            Some(i) => i,
            None => {
                let name = self.nation(winner).display_name.clone();
                self.claims.push(json!({"holder": loser, "against": winner, "kind": "reconquest", "ids": [], "note": format!("lost to {name}")}));
                self.claims.len() - 1
            }
        };
        let day = self.day_p();
        let claim = self.claims[i].as_object_mut().unwrap();
        let list = claim.get_mut("ids").unwrap().as_array_mut().unwrap();
        for &id in ids {
            if !list.iter().any(|x| x.as_u64() == Some(id as u64)) {
                list.push(json!(id));
            }
        }
        let count = list.len();
        claim.insert("expires_day".to_string(), json!(until));
        claim.insert("made_day".to_string(), json!(day));
        let was = claim.get("war").and_then(Value::as_bool).unwrap_or(false);
        claim.insert("war".to_string(), json!(was || from_war));
        let key = format!("{loser}>{winner}");
        let floor_now = minf(c.revanche_rivalry_max, c.revanche_rivalry + c.revanche_rivalry_per_province * count as f64);
        let now = self.rivalries.get(&key).copied().unwrap_or(0.0);
        self.rivalries.insert(key, maxf(now, floor_now));
    }

    /// `Peace._move_capital`: a nation that loses its capital province moves to its most populous remaining one.
    fn move_capital_peace(&mut self, tag: &str) {
        let mut best = 0usize;
        for &id in &self.nation(tag).provinces {
            if best == 0 || self.province_population[id] > self.province_population[best] {
                best = id;
            }
        }
        let i = self.nation_index[tag];
        self.nations[i].capital = best as i64;
        self.nations[i].home_capital = best as i64;
    }

    /// `Peace._apply_demand`: carries out one demand. `at_war` is false for a demand yielded in a crisis.
    pub fn apply_demand(&mut self, data: &Data, taker: &str, giver: &str, d: &Demand, at_war: bool) {
        match d {
            Demand::Province(ids) => {
                let mut capital_lost = false;
                for &id in ids {
                    capital_lost = capital_lost || id as i64 == self.nation(giver).capital;
                    self.transfer_province(data, id, taker);
                }
                self.revanche(data, giver, taker, ids, at_war);
                if capital_lost {
                    self.move_capital_peace(giver);
                }
            }
            Demand::Indemnity { share, months } => {
                let monthly = share * self.nation(giver).budget.revenue / 12.0;
                self.indemnities.push(Indemnity { payer: giver.to_string(), receiver: taker.to_string(), monthly, months_left: *months });
            }
            Demand::ReleaseAlly(other) => {
                for i in self.release_treaties(giver, other) {
                    self.end_treaty_at(data, i);
                }
            }
            Demand::DisarmBorder(years) => {
                let provinces = self.border_provinces(data, giver, taker);
                self.restrictions.push(Restriction { nation: giver.to_string(), holder: taker.to_string(), kind: String::new(), provinces, until_day: self.day_p() + (*years as f64 * 365.0) as i64 });
            }
            Demand::FleetLimit(years) => {
                self.restrictions.push(Restriction { nation: giver.to_string(), holder: taker.to_string(), kind: "fleet_limit".to_string(), provinces: vec![], until_day: self.day_p() + (*years as f64 * 365.0) as i64 });
            }
        }
    }

    /// `Peace.make_peace`: ends a war on the terms of an accepted offer: demands are carried out, ground still held goes back to
    /// its owner, armies on ground they may no longer stand on withdraw, and the war is filed.
    pub fn make_peace(&mut self, data: &Data, war: usize, offer: &Offer) {
        let (taker, giver) = (offer.taker.clone(), offer.giver.clone());
        let score_taker = self.war_score(data, war, &taker);
        let _ = score_taker;
        let (a, b) = (self.wars[war].a.clone(), self.wars[war].b.clone());
        self.end_war(war);
        for d in &offer.demands {
            self.apply_demand(data, &taker, &giver, d, true);
        }
        for id in 1..self.province_owner.len() {
            let (o, c) = (self.province_owner[id].clone(), self.province_controller[id].clone());
            if o != c && (o == a || o == b) && (c == a || c == b) {
                self.set_controller(id, &o);
                self.occupation.remove(&id);
            }
        }
        self.withdraw_armies(data, &a, &b);
        self.recompute(data);
        if !offer.demands.is_empty() {
            // Terms earn the taker standing, and cost the giver some of it.
            let p = &data.diplomacy.peace;
            let earned = minf(p.peace_cap, offer.cost * p.peace_per_score);
            self.gain_prestige(&taker, earned);
            self.gain_prestige(&giver, -earned * p.peace_loser_share);
        }
        // (A separate peace inside a conflict needs the join groups of a war: not ported.)
    }

    /// `Peace._withdraw_armies`: armies that now stand on ground their nation may not enter go to the nearest ground it may.
    fn withdraw_armies(&mut self, data: &Data, a: &str, b: &str) {
        let ids: Vec<u32> = self.armies.iter().map(|x| x.id).collect();
        for id in ids {
            let Some(i) = self.armies.iter().position(|x| x.id == id) else { continue };
            let (tag, province) = (self.armies[i].tag.clone(), self.armies[i].province);
            if (tag != a && tag != b) || self.armies[i].embarked() || self.can_enter(data, &tag, province) {
                continue;
            }
            self.armies[i].path.clear();
            self.armies[i].still_days = 0;
            self.armies[i].attacking = false;
            let mut seen: Vec<usize> = vec![province];
            let mut queue = std::collections::VecDeque::from([province]);
            let mut home = 0usize;
            while !queue.is_empty() && home == 0 {
                let here = queue.pop_front().unwrap();
                for n in data.map.neighbors(here) {
                    if seen.contains(&n) {
                        continue;
                    }
                    seen.push(n);
                    if self.can_enter(data, &tag, n) {
                        home = n;
                        break;
                    }
                    queue.push_back(n);
                }
            }
            if home == 0 {
                self.armies.remove(i);
            } else {
                self.armies[i].province = home;
            }
        }
    }

    // ---------------------------------------------------------------- restrictions, indemnities, the month

    /// `Peace.restricted`: whether a peace clause keeps `tag`'s armies out of a province.
    pub fn restricted(&self, tag: &str, id: usize) -> bool {
        self.restrictions.iter().any(|r| r.nation == tag && self.day_p() < r.until_day && r.provinces.contains(&id) && !self.at_war(tag, &r.holder))
    }

    /// `Peace.fleet_limited`: whether a clause forbids `tag` new warships.
    pub fn fleet_limited(&self, tag: &str) -> bool {
        self.restrictions.iter().any(|r| r.nation == tag && r.kind == "fleet_limit" && self.day_p() < r.until_day && !self.at_war(tag, &r.holder))
    }

    /// `Peace.step_month`: battle points fade, indemnities are paid, old clauses lapse. (The AI nations at war that put an offer
    /// on the table, `AIPeace.overtures`, are not part of this port.)
    pub fn peace_step_month(&mut self, data: &Data) {
        let keep = 1.0 - data.diplomacy.peace.score_decay_per_month;
        for w in &mut self.wars {
            for v in w.battle_points.values_mut() {
                *v *= keep;
            }
        }
        for i in (0..self.indemnities.len()).rev() {
            let ind = self.indemnities[i].clone();
            let pi = self.nation_index[&ind.payer];
            let pay = minf(ind.monthly, maxf(self.nations[pi].treasury, 0.0));
            self.nations[pi].treasury -= pay;
            let ri = self.nation_index[&ind.receiver];
            self.nations[ri].treasury += pay;
            self.indemnities[i].months_left -= 1;
            if self.indemnities[i].months_left <= 0 {
                self.indemnities.remove(i);
            }
        }
        let today = self.day_p();
        self.restrictions.retain(|r| today < r.until_day);
    }
}
