//! A peace conference (`scripts/sim/conference.gd`, `propose_conference.gd`, `answer_conference.gd`): the nations on one side of a war
//! make peace with the same enemy together. Each partner at war with the enemy asks for what its own goal and its own war score pay
//! for; the package is offered to the enemy whole and taken or refused whole. A refusal may bring a counter-offer, the package with
//! the dearest of the demands struck out until the enemy would take it. The partner with the highest war score chairs.

use crate::peace::{Demand, Offer};
use crate::state::{Data, GameState};

/// One partner's part of the package (`{tag, demands}`).
#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub tag: String,
    pub demands: Vec<Demand>,
}

/// A counter-offer waiting for the player (`GameState.conference_counter`).
#[derive(Debug, Clone, PartialEq)]
pub struct Counter {
    pub from: String,
    pub enemy: String,
    pub entries: Vec<Entry>,
    pub day: i64,
    pub until_day: i64,
}

/// What `Conference.propose` answers: `accepted` is None while a player enemy must answer.
#[derive(Debug, Clone, PartialEq)]
pub struct Conferred {
    pub ok: bool,
    pub reason: String,
    pub accepted: Option<bool>,
}

impl GameState {
    /// `Conference.partners`: the nations on `tag`'s side that are at war with `enemy`, in tag order (not `tag` itself).
    pub fn conference_partners(&self, tag: &str, enemy: &str) -> Vec<String> {
        let Some(w) = self.war_between(tag, enemy) else { return vec![] };
        let Some(g) = self.war_groups.iter().find(|g| g.id == self.wars[w].war_group) else { return vec![] };
        let Some(side) = g.side_pub(tag) else { return vec![] };
        self.group_side(g.id, &side).into_iter().filter(|m| m != tag && self.at_war(m, enemy)).collect()
    }

    /// `Conference.partner_terms`: what a partner would ask of the enemy (nothing: a white peace for it, if none).
    pub fn partner_terms(&self, data: &Data, partner: &str, enemy: &str) -> Vec<Demand> {
        let Some(w) = self.war_between(partner, enemy) else { return vec![] };
        let terms = self.price_terms(data, partner, enemy, w);
        if self.check_peace(data, partner, enemy, "demand", &terms).ok {
            terms
        } else {
            vec![]
        }
    }

    /// `Conference.entries_for`: the proposer's own demands first, then each included partner's.
    pub fn entries_for(&self, data: &Data, tag: &str, enemy: &str, own: Vec<Demand>, included: &[String]) -> Vec<Entry> {
        let mut out = vec![Entry { tag: tag.to_string(), demands: own }];
        for p in self.conference_partners(tag, enemy) {
            if included.contains(&p) {
                let demands = self.partner_terms(data, &p, enemy);
                out.push(Entry { tag: p, demands });
            }
        }
        out
    }

    /// `Conference.offer_of`: the offer one entry makes, if it can be made.
    pub fn offer_of(&self, data: &Data, e: &Entry, enemy: &str) -> Option<Offer> {
        let c = self.check_peace(data, &e.tag, enemy, "demand", &e.demands);
        if !c.ok {
            return None;
        }
        Some(Offer {
            id: self.next_offer_id,
            war_id: self.wars[c.war.unwrap()].id,
            from: e.tag.clone(),
            to: enemy.to_string(),
            mode: "demand".to_string(),
            taker: c.taker,
            giver: c.giver,
            demands: e.demands.clone(),
            cost: c.cost,
            forced: c.forced,
            day: self.calendar.days_elapsed as i64,
            note: String::new(),
        })
    }

    /// `Conference.acceptable`: whether every entry can be made and the enemy (an AI) would take the package whole.
    pub fn conference_acceptable(&self, data: &Data, entries: &[Entry], enemy: &str) -> bool {
        let (mut total, mut urge) = (0.0, f64::NEG_INFINITY);
        let mut indemnities: Vec<Demand> = vec![];
        for e in entries {
            let Some(offer) = self.offer_of(data, e, enemy) else { return false };
            if !self.ai_accepts(data, &offer) {
                return false;
            }
            if !offer.forced {
                total += offer.cost;
            }
            let w = self.war_between(&e.tag, enemy).unwrap();
            urge = crate::gd::maxf(urge, self.urge(data, enemy, w));
            for d in &e.demands {
                if matches!(d, Demand::Indemnity { .. }) {
                    indemnities.push(d.clone());
                }
            }
        }
        if entries.len() > 1 && total > 0.0 && total > urge {
            return false;
        }
        indemnities.is_empty() || self.ai_affordable(data, enemy, &indemnities)
    }

    /// `Conference.chairman`: the partner (or proposer) with the highest war score against the enemy.
    pub fn chairman(&self, data: &Data, entries: &[Entry], enemy: &str) -> String {
        let mut best = String::new();
        let mut best_score = f64::NEG_INFINITY;
        for e in entries {
            let Some(w) = self.war_between(&e.tag, enemy) else { continue };
            let s = self.war_score(data, w, &e.tag);
            if s > best_score {
                best = e.tag.clone();
                best_score = s;
            }
        }
        best
    }

    /// `Conference.counter`: the package with demands struck out, the dearest that are not the entry's goal first, until the enemy
    /// would take it; none if nothing smaller will do.
    pub fn conference_counter_for(&self, data: &Data, entries: &[Entry], enemy: &str) -> Option<Vec<Entry>> {
        let mut trimmed: Vec<Entry> = entries.to_vec();
        for _round in 0..12 {
            if self.conference_acceptable(data, &trimmed, enemy) {
                let any = trimmed.iter().any(|e| !e.demands.is_empty());
                return if any { Some(trimmed) } else { None };
            }
            // Strike the dearest demand left, goal demands last.
            let (mut pe, mut pd, mut key) = (usize::MAX, 0usize, f64::NEG_INFINITY);
            for i in 0..trimmed.len() {
                let war = self.war_between(&trimmed[i].tag, enemy);
                for j in 0..trimmed[i].demands.len() {
                    let d = &trimmed[i].demands[j];
                    let cost = self.demand_cost(data, &trimmed[i].tag, enemy, d);
                    let first = if let Demand::Province(ids) = d { ids.first().copied().unwrap_or(0) } else { 0 };
                    let is_goal = war.is_some() && self.price_factor(data, war, &trimmed[i].tag, d, first) < 1.0;
                    let k = cost - if is_goal { 1000.0 } else { 0.0 };
                    if k > key {
                        key = k;
                        pe = i;
                        pd = j;
                    }
                }
            }
            if pe == usize::MAX {
                return None;
            }
            let d = trimmed[pe].demands[pd].clone();
            // A demand for several provinces loses its dearest province first; any other is struck out.
            match d {
                Demand::Province(mut ids) if ids.len() > 1 => {
                    let tag = trimmed[pe].tag.clone();
                    crate::gd::sort_custom(&mut ids, |&x, &y| self.province_price(data, x, &tag, enemy) > self.province_price(data, y, &tag, enemy));
                    let mut drop = 0;
                    for k in 0..ids.len() {
                        let mut rest = ids.clone();
                        rest.remove(k);
                        if self.province_problem(data, &tag, enemy, &rest).is_empty() {
                            drop = k;
                            break;
                        }
                    }
                    ids.remove(drop);
                    trimmed[pe].demands[pd] = Demand::Province(ids);
                }
                _ => {
                    trimmed[pe].demands.remove(pd);
                }
            }
        }
        None
    }

    /// `Conference.execute`: makes the peace of every entry with the enemy; returns the entries that went through.
    pub fn conference_execute(&mut self, data: &Data, entries: &[Entry], enemy: &str) -> Vec<String> {
        let mut done = vec![];
        let chair = self.chairman(data, entries, enemy);
        self.joint_tags = entries.iter().map(|e| e.tag.clone()).collect();
        for e in entries {
            let offer = self.offer_of(data, e, enemy);
            let war = self.war_between(&e.tag, enemy);
            let (Some(offer), Some(war)) = (offer, war) else { continue };
            self.next_offer_id += 1;
            self.make_peace(data, war, &offer);
            done.push(e.tag.clone());
        }
        self.joint_tags.clear();
        if !chair.is_empty() && done.len() > 1 {
            self.gain_prestige(&chair, data.diplomacy.peace.conference_prestige);
        }
        done
    }

    /// `Conference.propose`: the proposer offers the package to the enemy.
    pub fn conference_propose(&mut self, data: &Data, tag: &str, enemy: &str, own: Vec<Demand>, included: &[String]) -> Conferred {
        let mut result = Conferred { ok: false, reason: String::new(), accepted: Some(false) };
        let entries = self.entries_for(data, tag, enemy, own, included);
        if self.war_between(tag, enemy).is_none() {
            result.reason = "no_war".to_string();
            return result;
        }
        for e in &entries {
            if self.offer_of(data, e, enemy).is_none() {
                result.reason = "invalid".to_string();
                return result;
            }
        }
        result.ok = true;
        if enemy == self.player_tag {
            // An enemy that is the player is not asked through a conference: it gets the peace offers one by one.
            for e in &entries {
                self.propose_peace_ai(data, &e.tag, enemy, "demand", e.demands.clone());
            }
            result.accepted = None;
            return result;
        }
        if self.conference_acceptable(data, &entries, enemy) {
            result.accepted = Some(true);
            self.conference_execute(data, &entries, enemy);
            return result;
        }
        // Refused: the proposer may be offered less.
        if let Some(c) = self.conference_counter_for(data, &entries, enemy) {
            if tag == self.player_tag {
                let day = self.calendar.days_elapsed as i64;
                self.conference_counter = Some(Counter { from: tag.to_string(), enemy: enemy.to_string(), entries: c, day, until_day: day + data.diplomacy.peace.counter_days });
            }
        }
        let day = self.calendar.days_elapsed as i64;
        self.peace_cooldown.insert(Self::pair_key(tag, enemy), day + data.diplomacy.peace.refuse_cooldown_days);
        result
    }

    /// `Conference.waiting_counter`: the counter-offer waiting for the player, or none if there is none or it has lapsed.
    pub fn waiting_counter(&mut self) -> Option<Counter> {
        let c = self.conference_counter.clone()?;
        if self.calendar.days_elapsed as i64 > c.until_day || self.war_between(&c.from, &c.enemy).is_none() {
            self.conference_counter = None;
            return None;
        }
        Some(c)
    }

    /// `Conference.answer_counter`: the player's answer to a counter-offer. False if none is waiting, it has lapsed, or the enemy
    /// would no longer take it.
    pub fn answer_counter(&mut self, data: &Data, accept: bool) -> bool {
        let Some(c) = self.waiting_counter() else { return false };
        self.conference_counter = None;
        if !accept {
            return true;
        }
        if !self.conference_acceptable(data, &c.entries, &c.enemy) {
            return false;
        }
        !self.conference_execute(data, &c.entries, &c.enemy).is_empty()
    }
}
