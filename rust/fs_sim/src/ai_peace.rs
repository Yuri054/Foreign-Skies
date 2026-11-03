//! How the AI makes and takes peace (`scripts/ai/ai_peace.gd`, `ai_coalition.gd`, and the AI's parts of `ai.gd` that they read): the
//! urge to be out of a war (in the same points as war score), whether an AI nation takes a deal, what it proposes and names as its
//! price, the monthly overtures, and the coalition of a side (partners who make peace together, holding to allies).
//! The AI's war plans (`ai_plans`, made by its offence) are not ported: with none, a nation's war aims are its stated war goal.

use crate::gd::{clampf, maxf, minf};
use crate::peace::{Demand, Offer};
use crate::pressure::GREAT;
use crate::state::{Data, GameState};
use serde_json::Value;

/// The parts of `data/ai.json` the peace rules read.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AiConfig {
    pub k_score: f64,
    pub k_support: f64,
    pub support_ref: f64,
    pub k_debt: f64,
    pub debt_cap_months: f64,
    pub k_days_per_month: f64,
    pub k_quiet: f64,
    pub quiet_grace_months: f64,
    pub capital_lost: f64,
    pub k_ally: f64,
    pub ally_boldness_discount: f64,
    pub seek_threshold: f64,
    pub white_tolerance: f64,
    pub loss_floor: f64,
    pub accept_share: f64,
    pub demand_score: f64,
    pub aims_enough: f64,
    pub demand_budget_share: f64,
    pub indemnity_max_share: f64,
    pub indemnity_months: i64,
    pub afford_share: f64,
    pub hold: bool,
    pub strain_support: f64,
    pub strain_score: f64,
    pub partner_urge: f64,
    pub default_aggression: f64,
    pub default_caution: f64,
    pub variety_temperament: f64,
    pub odds_cautious: f64,
    pub odds_bold: f64,
    pub unjustified_share_max: f64,
    /// `ai.json`'s `diplomacy` as the file has it (join and war weights).
    pub diplomacy: Value,
    /// `ai.json` whole, for the parts of the AI that read it as the file has it.
    pub raw: Value,
}

impl AiConfig {
    pub fn from_json_str(text: &str) -> Result<AiConfig, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("ai.json is invalid: {e}"))?;
        let p = |k: &str| v["peace"][k].as_f64().ok_or_else(|| format!("ai.json: peace.{k}"));
        let c = |k: &str| v["coalition"][k].as_f64().ok_or_else(|| format!("ai.json: coalition.{k}"));
        Ok(AiConfig {
            k_score: p("k_score")?,
            k_support: p("k_support")?,
            support_ref: p("support_ref")?,
            k_debt: p("k_debt")?,
            debt_cap_months: p("debt_cap_months")?,
            k_days_per_month: p("k_days_per_month")?,
            k_quiet: p("k_quiet")?,
            quiet_grace_months: p("quiet_grace_months")?,
            capital_lost: p("capital_lost")?,
            k_ally: p("k_ally")?,
            ally_boldness_discount: p("ally_boldness_discount")?,
            seek_threshold: p("seek_threshold")?,
            white_tolerance: p("white_tolerance")?,
            loss_floor: p("loss_floor")?,
            accept_share: p("accept_share")?,
            demand_score: p("demand_score")?,
            aims_enough: p("aims_enough")?,
            demand_budget_share: p("demand_budget_share")?,
            indemnity_max_share: p("indemnity_max_share")?,
            indemnity_months: p("indemnity_months")? as i64,
            afford_share: p("afford_share")?,
            hold: v["coalition"]["hold"].as_bool().unwrap_or(false),
            strain_support: c("strain_support")?,
            strain_score: c("strain_score")?,
            partner_urge: c("partner_urge")?,
            default_aggression: v["temperament"]["default"]["aggression"].as_f64().unwrap_or(0.5),
            default_caution: v["temperament"]["default"]["caution"].as_f64().unwrap_or(0.5),
            variety_temperament: v["variety"]["temperament"].as_f64().unwrap_or(0.0),
            odds_cautious: v["odds"]["cautious"].as_f64().unwrap_or(2.0),
            odds_bold: v["odds"]["bold"].as_f64().unwrap_or(1.2),
            raw: v.clone(),
            unjustified_share_max: v["unjustified_share_max"].as_f64().unwrap_or(0.15),
            diplomacy: v["diplomacy"].clone(),
        })
    }
}

/// What the urge is made of (`AIPeace.urge_parts`).
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct UrgeParts {
    pub score: f64,
    pub support: f64,
    pub debt: f64,
    pub duration: f64,
    pub quiet: f64,
    pub capital: f64,
    pub allies: f64,
    pub total: f64,
}

/// What an AI nation puts on the table (`AIPeace.proposal`): the mode ("demand" or "offer") and the demands.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Proposal {
    pub mode: String,
    pub demands: Vec<Demand>,
}

pub fn demand_of(v: &Value) -> Option<Demand> {
    Some(match v["kind"].as_str()? {
        "province" => Demand::Province(v["ids"].as_array()?.iter().filter_map(|x| x.as_u64().map(|x| x as usize)).collect()),
        "indemnity" => Demand::Indemnity { share: v["share"].as_f64()?, months: v["months"].as_i64()? },
        "release_ally" => Demand::ReleaseAlly(v["nation"].as_str()?.to_string()),
        "disarm_border" => Demand::DisarmBorder(v["years"].as_i64()?),
        "fleet_limit" => Demand::FleetLimit(v["years"].as_i64()?),
        _ => return None,
    })
}

impl GameState {
    fn aday(&self) -> i64 {
        self.calendar.days_elapsed as i64
    }

    /// `AI.noise`: a repeatable number between -1 and 1 for a key, from the game's seed (0 without one).
    pub fn ai_noise(&self, key: &str) -> f64 {
        if self.ai_seed == 0 {
            return 0.0;
        }
        let h = crate::navy::string_hash(&format!("{}|{}", self.ai_seed, key));
        (h % 20001) as f64 / 10000.0 - 1.0
    }

    /// `AI.base_temperament`: a nation's aggression and caution, bent a little by the game's seed.
    pub fn base_temperament(&self, data: &Data, tag: &str) -> (f64, f64) {
        let (a, c) = self.ai_traits.get(tag).copied().unwrap_or((data.ai.default_aggression, data.ai.default_caution));
        if self.ai_seed == 0 {
            return (a, c);
        }
        let v = data.ai.variety_temperament;
        (clampf(a + v * self.ai_noise(&format!("{tag}agg")), 0.0, 1.0), clampf(c + v * self.ai_noise(&format!("{tag}cau")), 0.0, 1.0))
    }

    /// `AIPeace.aims_met`: the war aims of `tag` against `enemy` that it has met, 0 to 1.
    pub fn aims_met(&self, data: &Data, tag: &str, enemy: &str) -> f64 {
        let war = self.war_between(tag, enemy);
        // A stated war goal is the aim of the war for the nation that declared it.
        if let Some(w) = war {
            if self.wars[w].a == tag && !self.wars[w].goal.is_null() && self.wars[w].goal.as_object().map(|o| !o.is_empty()).unwrap_or(false) {
                return self.goal_progress(data, w);
            }
        }
        let (mut total, mut met) = (0.0, 0.0);
        for plan in &self.ai_plans {
            if plan["nation"] != tag || plan["enemy"] != enemy {
                continue;
            }
            for o in plan["objectives"].as_array().into_iter().flatten() {
                let weight = o["weight"].as_f64().unwrap_or(0.0);
                total += weight;
                if self.province_controller[o["province"].as_u64().unwrap_or(0) as usize] == tag {
                    met += weight;
                }
            }
        }
        if total > 0.0 {
            met / total
        } else {
            1.0
        }
    }

    /// `WarGoal.progress`: how far the aggressor has got toward its goal, 0 to 1 (1 for no goal).
    pub fn goal_progress(&self, data: &Data, war: usize) -> f64 {
        let w = &self.wars[war];
        let goal = &w.goal;
        let Some(kind) = goal["kind"].as_str() else { return 1.0 };
        match kind {
            "provinces" | "nationality" => {
                let ids: Vec<usize> = goal["ids"].as_array().into_iter().flatten().filter_map(|x| x.as_u64().map(|x| x as usize)).collect();
                let held = ids.iter().filter(|&&id| self.province_controller[id] == w.a).count();
                held as f64 / maxf(ids.len() as f64, 1.0)
            }
            "concession" => {
                let need = data.diplomacy.peace.concession_met_score;
                let score = self.war_score(data, war, &w.a.clone());
                if score >= need {
                    1.0
                } else {
                    clampf(score / maxf(need, 1.0), 0.0, 0.99)
                }
            }
            "defence" => {
                for &id in &self.nation(&w.a).provinces {
                    if self.province_controller[id] == w.b {
                        return 0.0;
                    }
                }
                1.0
            }
            _ => 1.0,
        }
    }

    /// `AIPeace.allies_fighting`: allies of `tag` on its side of the conflict still at war with `enemy`.
    pub fn allies_fighting(&self, tag: &str, enemy: &str) -> usize {
        let Some(w) = self.war_between(tag, enemy) else { return 0 };
        let group = self.wars[w].war_group;
        let Some(g) = self.war_groups.iter().find(|g| g.id == group) else { return 0 };
        let side = g.side_pub(tag).unwrap_or_default();
        self.group_side(group, &side).iter().filter(|a| a.as_str() != tag && self.at_war(a, enemy)).count()
    }

    /// `AIPeace.urge_parts`.
    pub fn urge_parts(&self, data: &Data, tag: &str, war: usize) -> UrgeParts {
        let c = &data.ai;
        let w = &self.wars[war];
        let enemy = w.other(tag).to_string();
        let n = self.nation(tag);
        let score = self.war_score(data, war, tag);
        let mut parts = UrgeParts::default();
        let mut u = -score * c.k_score;
        parts.score = u;
        parts.support = maxf(0.0, c.support_ref - n.war_support) * c.k_support;
        u += parts.support;
        let monthly_revenue = maxf(n.budget.revenue, 1.0) / 12.0;
        parts.debt = c.k_debt * minf(c.debt_cap_months, maxf(0.0, -n.treasury) / monthly_revenue);
        u += parts.debt;
        let today = self.aday();
        parts.duration = c.k_days_per_month * (today - w.start_day) as f64 / 30.0;
        u += parts.duration;
        // A war nobody fights wears on both with no end in sight.
        let mut quiet_months = (today - w.last_fight_day.max(w.start_day)) as f64 / 30.0;
        if n.blockade > 0.05 || self.nation(&enemy).blockade > 0.05 {
            quiet_months = 0.0; // a blockade is fighting too
        }
        parts.quiet = c.k_quiet * maxf(0.0, quiet_months - c.quiet_grace_months);
        u += parts.quiet;
        parts.capital = if self.capital_taken_by_pub(tag) == enemy { c.capital_lost } else { 0.0 };
        u += parts.capital;
        let (aggression, caution) = self.base_temperament(data, tag);
        let boldness = clampf((aggression + 1.0 - caution) / 2.0, 0.0, 1.0);
        parts.allies = -c.k_ally * self.allies_fighting(tag, &enemy) as f64 * (1.0 - c.ally_boldness_discount * boldness);
        u += parts.allies;
        parts.total = u;
        parts
    }

    pub fn urge(&self, data: &Data, tag: &str, war: usize) -> f64 {
        self.urge_parts(data, tag, war).total
    }

    /// `AIPeace.accepts`: whether an AI nation (the offer's target) takes the deal.
    pub fn ai_accepts(&self, data: &Data, offer: &Offer) -> bool {
        let Some(war) = self.war_between(&offer.from, &offer.to) else { return false };
        let c = &data.ai;
        let me = offer.to.as_str();
        let u = self.urge(data, me, war);
        let score = self.war_score(data, war, me);
        let white = offer.demands.is_empty();
        if offer.mode == "demand" {
            // I am the one asked to give.
            if white {
                return u >= -c.white_tolerance;
            }
            // A nation that has lost its capital (or the will to fight) can be made to give anything.
            if offer.forced {
                return true;
            }
            if !self.ai_affordable(data, me, &offer.demands) {
                return false;
            }
            return offer.cost <= u && (score <= -c.loss_floor || u >= c.seek_threshold);
        }
        // I am offered terms by the one who gives.
        if white {
            return u >= -c.white_tolerance;
        }
        let parts = self.score_parts(data, war, me);
        let ground = maxf(0.0, parts.0 + parts.1);
        let ceded: usize = offer.demands.iter().map(|d| if let Demand::Province(ids) = d { ids.len() } else { 0 }).sum();
        let giver = offer.giver.as_str();
        if ceded > 0 && GREAT.contains(&giver) && ceded >= self.max_cession(data, giver) {
            return true;
        }
        offer.cost >= c.accept_share * minf(maxf(0.0, score), ground) - 0.000001 || u >= c.seek_threshold
    }

    /// `AIPeace.affordable`: whether `giver` can carry the indemnities in `demands` on top of those it already pays.
    pub fn ai_affordable(&self, data: &Data, giver: &str, demands: &[Demand]) -> bool {
        let revenue = maxf(self.nation(giver).budget.revenue, 0.001);
        let mut committed = 0.0;
        for ind in &self.indemnities {
            if ind.payer == giver {
                committed += ind.monthly / (revenue / 12.0);
            }
        }
        for d in demands {
            if let Demand::Indemnity { share, .. } = d {
                committed += share;
            }
        }
        committed <= data.ai.afford_share + 0.000001
    }

    /// `AIPeace.proposal`: what `tag` would propose in this war, if anything.
    pub fn ai_proposal(&self, data: &Data, tag: &str, war: usize) -> Option<Proposal> {
        let c = &data.ai;
        let enemy = self.wars[war].other(tag).to_string();
        let score = self.war_score(data, war, tag);
        if score >= c.demand_score && self.aims_met(data, tag, &enemy) >= c.aims_enough {
            let terms = self.price_terms(data, tag, &enemy, war);
            if !terms.is_empty() {
                return Some(Proposal { mode: "demand".to_string(), demands: terms });
            }
        }
        if self.urge(data, tag, war) >= c.seek_threshold {
            if score < 0.0 {
                return Some(Proposal { mode: "offer".to_string(), demands: self.surrender_terms(data, war, tag, &enemy) });
            }
            return Some(Proposal { mode: "demand".to_string(), demands: vec![] });
        }
        None
    }

    /// `AIPeace.price_terms`: the ground `taker` holds that is the enemy's, chosen to fit the war score it has: war aims first, then
    /// the dearest, up to `demand_budget_share` of the score; leftover score buys an indemnity the enemy can carry.
    pub fn price_terms(&self, data: &Data, taker: &str, giver: &str, war: usize) -> Vec<Demand> {
        let c = &data.ai;
        let budget = self.war_score(data, war, taker) * c.demand_budget_share;
        let mut aims: Vec<(usize, f64)> = vec![];
        for plan in &self.ai_plans {
            if plan["nation"] == taker && plan["enemy"] == giver {
                for o in plan["objectives"].as_array().into_iter().flatten() {
                    let (p, w) = (o["province"].as_u64().unwrap_or(0) as usize, o["weight"].as_f64().unwrap_or(0.0));
                    match aims.iter_mut().find(|(k, _)| *k == p) {
                        Some(slot) => slot.1 = w,
                        None => aims.push((p, w)),
                    }
                }
            }
        }
        // The goal of the war comes first, ahead of every plan.
        let goal = if self.wars[war].a == taker { self.wars[war].goal.clone() } else { Value::Null };
        let goal_empty = goal.as_object().map(|o| o.is_empty()).unwrap_or(true);
        if !goal_empty {
            for id in goal["ids"].as_array().into_iter().flatten().filter_map(|x| x.as_u64()) {
                match aims.iter_mut().find(|(k, _)| *k == id as usize) {
                    Some(slot) => slot.1 = 1000.0,
                    None => aims.push((id as usize, 1000.0)),
                }
            }
        }
        let aim = |id: usize| aims.iter().find(|(k, _)| *k == id).map(|(_, w)| *w).unwrap_or(0.0);
        let mut held: Vec<usize> = self.nation(giver).provinces.iter().copied().filter(|&id| self.province_controller[id] == taker).collect();
        crate::gd::sort_custom(&mut held, |&x, &y| {
            let (ax, ay) = (aim(x), aim(y));
            if ax != ay {
                return ax > ay;
            }
            let (px, py) = (self.province_price(data, x, taker, giver), self.province_price(data, y, taker, giver));
            px > py || (px == py && x < y)
        });
        let mut spent = 0.0;
        let mut terms: Vec<Demand> = vec![];
        // A concession goal is the first term asked.
        if goal["kind"].as_str() == Some("concession") {
            if let Some(d) = demand_of(&goal["demand"]) {
                let cost = self.demand_cost(data, taker, giver, &d);
                if cost >= 0.0 && cost <= budget && (!matches!(d, Demand::Indemnity { .. }) || self.ai_affordable(data, giver, &[d.clone()])) {
                    terms.push(d);
                    spent += cost;
                }
            }
        }
        let price = |id: usize| self.province_price(data, id, taker, giver) * self.price_factor(data, Some(war), taker, &Demand::Province(vec![id]), id);
        let (ids, picked_spent) = self.pick_takeable(data, taker, giver, &held, &price, budget - spent);
        spent += picked_spent;
        if !ids.is_empty() {
            terms.push(Demand::Province(ids.clone()));
        }
        let ind = self.indemnity_for(data, taker, giver, budget - spent);
        let has_indemnity = terms.iter().any(|t| matches!(t, Demand::Indemnity { .. }));
        if let Some(ind) = ind {
            if !has_indemnity && (!ids.is_empty() || !terms.is_empty()) {
                terms.push(ind);
            }
        }
        terms
    }

    /// `AIPeace.indemnity_for`: an indemnity worth up to `left` of war score that the giver can carry, as a demand.
    pub fn indemnity_for(&self, data: &Data, taker: &str, giver: &str, left: f64) -> Option<Demand> {
        let c = &data.ai;
        let per_year = data.diplomacy.peace.indemnity_points_per_year;
        let months = c.indemnity_months;
        let factor = self.price_factor(data, self.war_between(taker, giver), taker, &Demand::Indemnity { share: 0.0, months: 0 }, 0);
        let share = minf(c.indemnity_max_share, left / (per_year * months as f64 / 12.0 * factor));
        if share < 0.01 {
            return None;
        }
        let snapped = (share / 0.01 + 0.5).floor() * 0.01;
        let ind = Demand::Indemnity { share: snapped, months };
        // An indemnity too small to notice is no term at all.
        if snapped * self.nation(giver).budget.revenue / 12.0 < data.diplomacy.peace.indemnity_min_monthly {
            return None;
        }
        if self.demand_cost(data, taker, giver, &ind) >= 0.0 && self.ai_affordable(data, giver, &[ind.clone()]) {
            return Some(ind);
        }
        None
    }

    // ---------------------------------------------------------------- the coalition

    /// `AICoalition.strained`: too hard pressed to stand by its allies.
    pub fn strained(&self, data: &Data, tag: &str, war: usize) -> bool {
        let c = &data.ai;
        let enemy = self.wars[war].other(tag);
        self.nation(tag).war_support <= c.strain_support || self.capital_taken_by_pub(tag) == enemy || self.war_score(data, war, tag) <= -c.strain_score
    }

    /// `AICoalition.joint_partners`: the allies that would join a peace `tag` proposes: all of those fighting beside it, if every one is
    /// an AI nation that wants peace too; else none.
    pub fn joint_partners(&self, data: &Data, tag: &str, war: usize) -> Vec<String> {
        let enemy = self.wars[war].other(tag).to_string();
        let mut out = vec![];
        for p in self.conference_partners(tag, &enemy) {
            let Some(pw) = self.war_between(&p, &enemy) else { return vec![] };
            if p == self.player_tag {
                return vec![];
            }
            if self.urge(data, &p, pw) < data.ai.partner_urge * data.ai.seek_threshold {
                return vec![];
            }
            out.push(p);
        }
        out
    }

    /// `AICoalition.hold`: whether `tag` should stay in the war rather than make a peace of its own while allies fight on.
    pub fn coalition_hold(&self, data: &Data, tag: &str, war: usize) -> bool {
        if !data.ai.hold {
            return false;
        }
        let enemy = self.wars[war].other(tag).to_string();
        if self.conference_partners(tag, &enemy).is_empty() {
            return false;
        }
        !self.strained(data, tag, war)
    }

    // ---------------------------------------------------------------- the monthly overtures

    /// `AIPeace.overtures`: every AI nation at war decides whether to put a proposal on the table. Offers to the player wait.
    pub fn ai_overtures(&mut self, data: &Data) {
        let ids: Vec<u32> = self.wars.iter().map(|w| w.id).collect();
        for wid in ids {
            for side in 0..2 {
                let Some(war) = self.wars.iter().position(|w| w.id == wid) else { break };
                let tag = if side == 0 { self.wars[war].a.clone() } else { self.wars[war].b.clone() };
                if tag == self.player_tag {
                    continue;
                }
                let Some(p) = self.ai_proposal(data, &tag, war) else { continue };
                let enemy = self.wars[war].other(&tag).to_string();
                // Allies fighting on: a nation that wants to win terms takes them to the table together, if they all want peace too.
                let group = self.joint_partners(data, &tag, war);
                if !group.is_empty() && p.mode == "demand" && enemy != self.player_tag {
                    let joint = self.conference_propose(data, &tag, &enemy, p.demands.clone(), &group);
                    if joint.ok && joint.accepted != Some(false) {
                        break;
                    }
                    if joint.ok {
                        continue;
                    }
                }
                if self.coalition_hold(data, &tag, war) {
                    continue;
                }
                let result = self.propose_peace_ai(data, &tag, &enemy, &p.mode, p.demands);
                if result.ok && result.accepted != Some(false) {
                    break;
                }
            }
        }
    }
}
