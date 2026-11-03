//! The AI on the attack (`scripts/ai/ai_offense.gd`). A nation runs a campaign at a time (several, against different enemies, up to a limit):
//! it picks the enemy province worth most among those it can take (next to ground it supplies, within the share of its army its aggression
//! allows), gathers the armies in a staging province next to it, advances when the combined power beats the defenders by the odds its
//! temperament asks for, and carries on to the next province for as long as the odds hold and supply reaches. It falls back when a battle
//! turns bad. An attack line (`AttackLines`) runs the same campaigns for an army group.

use crate::gd::{clampf, maxf, minf, sort_custom};
use crate::state::{Data, GameState};
use serde_json::Value;
use std::collections::HashMap;

/// A campaign (`GameState.ai_campaign`): who it is against, the province aimed at, where the armies gather, which armies, and whether it is
/// still gathering or already advancing.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Campaign {
    /// Identity inside the port (the game tells campaigns apart by their contents).
    pub uid: u64,
    pub enemy: String,
    pub target: usize,
    pub staging: usize,
    pub armies: Vec<u32>,
    pub advancing: bool,
    pub started: i64,
    /// The attack line that runs it, if one does.
    pub line: Option<u32>,
    /// A line's campaign that has ended.
    pub done: bool,
}

/// What `_best_target` finds.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Pick {
    pub target: usize,
    pub staging: usize,
    pub utility: f64,
    pub armies: Vec<u32>,
}

fn of(c: &Value, k: &str) -> f64 {
    c[k].as_f64().unwrap_or_else(|| panic!("ai.json: offense.{k} is not a number"))
}

impl GameState {
    // ---------------------------------------------------------------- the nation's campaigns

    /// `AIOffense.campaigns`: every campaign the nation has running: the main one and the others it runs at the same time.
    pub fn ai_campaigns(&self, tag: &str) -> Vec<Campaign> {
        let mut out = vec![];
        if let Some(c) = self.ai_campaign.get(tag) {
            out.push(c.clone());
        }
        if let Some(list) = self.ai_campaign_extra.get(tag) {
            out.extend(list.iter().cloned());
        }
        out
    }

    /// `AIOffense.in_campaign`: whether an army is on one of the nation's campaigns (or a landing).
    pub fn ai_in_campaign(&self, tag: &str, army: u32) -> bool {
        self.ai_campaign.get(tag).map(|c| c.armies.contains(&army)).unwrap_or(false) || self.ai_campaign_extra.get(tag).map(|l| l.iter().any(|c| c.armies.contains(&army))).unwrap_or(false) || self.ai_landing_involves(tag, army)
    }

    /// `AIOffense._drop`: removes a campaign from the nation's books.
    fn ai_drop_campaign(&mut self, tag: &str, uid: u64) {
        if self.ai_campaign.get(tag).map(|c| c.uid == uid).unwrap_or(false) {
            self.ai_campaign.remove(tag);
            return;
        }
        if let Some(rest) = self.ai_campaign_extra.get_mut(tag) {
            rest.retain(|c| c.uid != uid);
            if rest.is_empty() {
                self.ai_campaign_extra.remove(tag);
            }
        }
    }

    fn ai_store_campaign(&mut self, tag: &str, c: &Campaign) {
        if self.ai_campaign.get(tag).map(|m| m.uid == c.uid).unwrap_or(false) {
            self.ai_campaign.insert(tag.to_string(), c.clone());
        } else if let Some(list) = self.ai_campaign_extra.get_mut(tag) {
            if let Some(slot) = list.iter_mut().find(|x| x.uid == c.uid) {
                *slot = c.clone();
            }
        }
    }

    /// `AIOffense._alive`: drops dead armies; false if the campaign is over (no armies, or the war is).
    pub fn ai_campaign_alive(&self, tag: &str, c: &mut Campaign) -> bool {
        c.armies.retain(|id| self.armies.iter().any(|a| a.id == *id));
        !c.armies.is_empty() && self.at_war(tag, &c.enemy)
    }

    /// `AIOffense.step`.
    pub fn ai_offense_step(&mut self, data: &Data, tag: &str) {
        for snap in self.ai_campaigns(tag) {
            let mut c = snap;
            if !self.ai_campaign_alive(tag, &mut c) {
                self.ai_drop_campaign(tag, c.uid);
            } else {
                self.ai_store_campaign(tag, &c);
            }
        }
        for snap in self.ai_campaigns(tag) {
            let mut c = snap;
            let ended = self.ai_run(data, tag, &mut c);
            if ended {
                self.ai_drop_campaign(tag, c.uid);
            } else {
                self.ai_store_campaign(tag, &c);
            }
        }
        let today = self.calendar.days_elapsed as i64;
        let o = &data.ai.raw["offense"];
        if self.ai_campaigns(tag).len() as i64 >= of(o, "max_campaigns") as i64 || today < self.ai_campaign_wait.get(tag).copied().unwrap_or(0) {
            return;
        }
        let Some(mut c) = self.ai_start(data, tag) else {
            self.ai_campaign_wait.insert(tag.to_string(), today + of(o, "retry_days") as i64);
            return;
        };
        let ended = self.ai_run(data, tag, &mut c);
        if ended {
            self.ai_drop_campaign(tag, c.uid);
        } else {
            self.ai_store_campaign(tag, &c);
        }
    }

    // ---------------------------------------------------------------- choosing a target

    /// `AIOffense._frontier`: enemy-held provinces next to ground the nation holds, in id order.
    pub fn ai_frontier(&self, data: &Data, tag: &str, enemy: &str) -> Vec<usize> {
        let mut seen: Vec<usize> = vec![];
        for p in self.border_provinces(data, tag, enemy) {
            for n in data.map.neighbors(p) {
                if self.province_controller[n] == enemy && !seen.contains(&n) {
                    seen.push(n);
                }
            }
        }
        seen.sort();
        seen
    }

    /// `AIOffense._beyond`: enemy-held provinces next to where a stack stands.
    fn ai_beyond(&self, data: &Data, enemy: &str, from: usize) -> Vec<usize> {
        let mut out: Vec<usize> = data.map.neighbors(from).filter(|&n| self.province_controller[n] == enemy).collect();
        out.sort();
        out
    }

    pub(crate) fn ai_km(data: &Data, a: usize, b: usize) -> f64 {
        let (pa, pb) = (data.map.provinces[a].center, data.map.provinces[b].center);
        let (dx, dy) = (pa.0 - pb.0, pa.1 - pb.1);
        (dx * dx + dy * dy).sqrt() as f64 * crate::war::KM_PER_PX
    }

    /// `AIOffense._resistance`: what stands against an attack on a province: the defenders there and the enemy power around it, plus a share of
    /// every enemy army within reach.
    pub(crate) fn ai_resistance(&self, data: &Data, tag: &str, target: usize) -> f64 {
        let o = &data.ai.raw["offense"];
        let reach = self.hops_from(data, target, of(o, "support_hops") as i64);
        let mut around = 0.0;
        self.ai_refresh_index();
        for (id, _) in reach {
            for aid in self.ai_index_at(id) {
                let a = self.army_ref(aid);
                if a.tag != tag && self.at_war(tag, &a.tag) {
                    around += a.power(&data.military);
                }
            }
        }
        self.ai_defence_at(data, tag, target) + of(o, "reinforce_weight") * around
    }

    /// `AIOffense.odds_against`: the odds the nation wants before it attacks this enemy.
    pub fn ai_offense_odds(&self, data: &Data, tag: &str, enemy: &str) -> f64 {
        let odds = self.ai_battle_odds(data, tag);
        for plan in &self.ai_plans {
            if plan["nation"] == tag && plan["enemy"] == enemy && plan["posture"] == "offensive" {
                return odds * of(&data.ai.raw["offense"], "plan_odds_factor");
            }
        }
        odds
    }

    /// `AIOffense._plan_weight`: what a plan wants: the heaviest objective against this enemy, less the nearer it is the more.
    fn ai_plan_weight(&self, data: &Data, tag: &str, enemy: &str, target: usize) -> f64 {
        let mut best = 0.0;
        let hops_n = of(&data.ai.raw["offense"], "plan_hops") as i64;
        for plan in &self.ai_plans {
            if plan["nation"] != tag || plan["enemy"] != enemy {
                continue;
            }
            for o in plan["objectives"].as_array().into_iter().flatten() {
                let hops = self.hops_from(data, o["province"].as_u64().unwrap() as usize, hops_n);
                if let Some((_, h)) = hops.iter().find(|x| x.0 == target) {
                    best = maxf(best, o["weight"].as_f64().unwrap() / (1.0 + *h as f64));
                }
            }
        }
        best
    }

    /// `AIOffense._defensive`: whether a plan against this enemy says to stay on the defensive.
    pub(crate) fn ai_defensive_plan(&self, tag: &str, enemy: &str) -> bool {
        self.ai_plans.iter().any(|p| p["nation"] == tag && p["enemy"] == enemy && p["posture"] == "defensive")
    }

    /// `AIOffense._worth`: how much taking a province is worth, before the odds and the cost.
    pub(crate) fn ai_worth(&self, data: &Data, tag: &str, enemy: &str, target: usize) -> f64 {
        let w = &data.ai.raw["offense"];
        let owner = self.province_owner[target].clone();
        let mut points = self.province_share(data, target, &owner) * data.diplomacy.peace.score_occupation_points;
        points /= data.diplomacy.peace.score_max;
        of(w, "w_plan") * self.ai_plan_weight(data, tag, enemy, target) + of(w, "w_value") * self.ai_value(data, target) + of(w, "w_score") * points
    }

    /// `AIOffense._eta`: roughly how many days an army needs to reach a province.
    fn ai_eta(&self, data: &Data, tag: &str, army: u32, target: usize) -> f64 {
        let a = self.army_ref(army);
        Self::ai_km(data, a.province, target) / a.speed(&data.military) / (1.0 + data.military.movement.home_rail * self.nation(tag).development)
    }

    /// `AIOffense._pick_force`: the armies, nearest first, that reach `required` together without going over the budget.
    fn ai_pick_force(&self, data: &Data, tag: &str, target: usize, armies: &[u32], required: f64, budget: f64, exact: bool) -> Option<(Vec<u32>, f64)> {
        let o = &data.ai.raw["offense"];
        let mil = &data.military;
        let reach: Vec<usize> = self.hops_from(data, target, of(o, "reach_hops") as i64).into_iter().map(|x| x.0).collect();
        let mut near: Vec<u32> = vec![];
        for &id in armies {
            let a = self.army_ref(id);
            // Only armies that can be there before the gathering times out are worth waiting for.
            if reach.contains(&a.province) && (exact || self.ai_eta(data, tag, id, target) <= of(o, "gather_days") * of(o, "gather_eta_share")) {
                near.push(id);
            }
        }
        sort_custom(&mut near, |&x, &y| {
            let (dx, dy) = (Self::ai_km(data, self.army_ref(x).province, target), Self::ai_km(data, self.army_ref(y).province, target));
            dx < dy || (dx == dy && x < y)
        });
        let mut out: Vec<u32> = vec![];
        let mut power = 0.0;
        for id in near {
            let p = self.army_ref(id).power(mil);
            if !exact && power + p > budget && !out.is_empty() {
                break;
            }
            out.push(id);
            power += p;
            if !exact && power >= required {
                break;
            }
        }
        // A single army may always go, however small the budget.
        if out.is_empty() || power < required || (!exact && power > budget && out.len() > 1) {
            return None;
        }
        Some((out, power))
    }

    /// `AIOffense._staging`: a province we hold next to the target, nearest to the force.
    fn ai_staging(&self, data: &Data, tag: &str, target: usize, force: &[u32]) -> usize {
        let mut best = 0;
        let mut best_km = f64::INFINITY;
        for n in data.map.neighbors(target) {
            if self.province_controller[n] != tag {
                continue;
            }
            let mut km = 0.0;
            for &id in force {
                km += Self::ai_km(data, self.army_ref(id).province, n);
            }
            if km < best_km - 0.000001 {
                best = n;
                best_km = km;
            }
        }
        best
    }

    /// `AIOffense._best_target`: the best target for a force, or none if none is worth the attempt.
    pub fn ai_offense_target(&self, data: &Data, tag: &str, enemy: &str, candidates: &[usize], armies: &[u32], budget: f64, exact: bool) -> Option<Pick> {
        let w = &data.ai.raw["offense"];
        let mil = &data.military;
        let odds = self.ai_offense_odds(data, tag, enemy);
        let mut best: Option<Pick> = None;
        let claimed = self.ai_claimed(tag);
        for &target in candidates {
            if self.supply_cost(data, tag, target) == f64::INFINITY {
                continue;
            }
            let required = odds * self.ai_resistance(data, tag, target);
            let Some((picked, power)) = self.ai_pick_force(data, tag, target, armies, required, budget, exact) else { continue };
            let staging = self.ai_staging(data, tag, target, &picked);
            if staging == 0 {
                continue;
            }
            let mut days = 0.0;
            for &id in &picked {
                let a = self.army_ref(id);
                days = maxf(days, (Self::ai_km(data, a.province, staging) + Self::ai_km(data, staging, target)) / a.speed(mil));
            }
            let margin = clampf(power / required - 1.0, 0.0, 2.0);
            let cost = of(w, "w_days") * days + of(w, "w_supply") * self.supply_cost(data, tag, target);
            let claim = if claimed.contains(&target) { data.ai.raw["coalition"]["claim_penalty"].as_f64().unwrap() } else { 0.0 };
            let noise = self.ai_noise(&format!("{tag}{target}_{}", self.calendar.days_elapsed as i64 / 30));
            let utility = self.ai_worth(data, tag, enemy, target) + of(w, "w_margin") * margin - cost - claim + data.ai.raw["variety"]["target"].as_f64().unwrap() * noise;
            if best.as_ref().map(|b| utility > b.utility + 0.000001).unwrap_or(true) {
                best = Some(Pick { target, staging, utility, armies: picked });
            }
        }
        best
    }

    /// `AICoalition.claimed`: the provinces allies of `tag` are aiming campaigns at.
    fn ai_claimed(&self, tag: &str) -> Vec<usize> {
        let mut out = vec![];
        for enemy in self.ai_enemies(tag) {
            for ally in self.conference_partners(tag, &enemy) {
                for c in self.ai_campaigns(&ally) {
                    if c.enemy == enemy {
                        out.push(c.target);
                    }
                }
            }
        }
        out
    }

    /// `AIOffense._available`: the armies the nation could send: not the reserve, not busy, and not the last one on a front. Strongest first.
    pub fn ai_available(&self, data: &Data, tag: &str) -> Vec<u32> {
        let mil = &data.military;
        let reserve = self.ai_reserve.get(tag).copied().unwrap_or(0);
        let keep = of(&data.ai.raw["offense"], "front_keep");
        let mut power: HashMap<u32, f64> = HashMap::new();
        let mut floor: HashMap<u32, f64> = HashMap::new();
        for f in self.fronts.iter().filter(|f| f.tag == tag) {
            let p = self.ai_power_on(data, f.id);
            power.insert(f.id, p);
            floor.insert(f.id, keep * p);
        }
        let mut all: Vec<u32> = self.armies.iter().filter(|a| a.tag == tag).map(|a| a.id).collect();
        all.sort();
        sort_custom(&mut all, |&x, &y| {
            let (px, py) = (self.army_ref(x).power(mil), self.army_ref(y).power(mil));
            px > py || (px == py && x < y)
        });
        let mut out = vec![];
        for id in all {
            let a = self.army_ref(id);
            if id == reserve || !a.path.is_empty() || a.fighting || a.embarked() || self.province_controller[a.province] != tag || self.ai_in_campaign(tag, id) {
                continue;
            }
            if a.front_id != 0 && power.contains_key(&a.front_id) {
                // An army may leave its front while the rest keep `front_keep` of what the front stood on.
                let ap = a.power(mil);
                if power[&a.front_id] - ap < floor[&a.front_id] {
                    continue;
                }
                *power.get_mut(&a.front_id).unwrap() -= ap;
            }
            out.push(id);
        }
        out
    }

    /// `AIOffense._start`: begins a campaign, if one is worth it.
    fn ai_start(&mut self, data: &Data, tag: &str) -> Option<Campaign> {
        let mil = &data.military;
        let o = &data.ai.raw["offense"];
        let armies = self.ai_available(data, tag);
        if armies.is_empty() {
            return None;
        }
        let mut mine: Vec<u32> = self.armies.iter().filter(|a| a.tag == tag).map(|a| a.id).collect();
        mine.sort();
        let mut total = 0.0;
        for id in mine {
            total += self.army_ref(id).power(mil);
        }
        let mut committed = 0.0;
        let mut busy: Vec<String> = vec![];
        for c in self.ai_campaigns(tag) {
            busy.push(c.enemy.clone());
            for id in &c.armies {
                if let Some(a) = self.armies.iter().find(|a| a.id == *id) {
                    committed += a.power(mil);
                }
            }
        }
        let budget = total * self.temperament(data, tag).0 * of(o, "max_share") - committed;
        if budget <= 0.0 {
            return None;
        }
        let mut best: Option<(Pick, String)> = None;
        for enemy in self.ai_enemies(tag) {
            if busy.contains(&enemy) || self.ai_defensive_plan(tag, &enemy) {
                continue;
            }
            let pick = self.ai_offense_target(data, tag, &enemy, &self.ai_frontier(data, tag, &enemy), &armies, budget, false);
            if let Some(p) = pick {
                if best.as_ref().map(|b| p.utility > b.0.utility + 0.000001).unwrap_or(true) {
                    best = Some((p, enemy));
                }
            }
        }
        let (pick, enemy) = best?;
        if pick.utility < of(o, "min_utility") {
            return None;
        }
        self.next_campaign_uid += 1;
        let c = Campaign { uid: self.next_campaign_uid, enemy, target: pick.target, staging: pick.staging, armies: pick.armies, advancing: false, started: self.calendar.days_elapsed as i64, line: None, done: false };
        if self.ai_campaign.contains_key(tag) {
            self.ai_campaign_extra.entry(tag.to_string()).or_default().push(c.clone());
        } else {
            self.ai_campaign.insert(tag.to_string(), c.clone());
        }
        Some(c)
    }

    // ---------------------------------------------------------------- running a campaign

    /// `AIOffense._end` (as far as the campaign goes): a campaign of an attack line is the line's to end; any other leaves the nation's books.
    /// Returns whether the campaign has left the books.
    fn ai_end_campaign(&mut self, data: &Data, tag: &str, c: &mut Campaign) -> bool {
        if c.line.is_some() {
            c.done = true;
            return false;
        }
        self.ai_campaign_wait.insert(tag.to_string(), self.calendar.days_elapsed as i64 + of(&data.ai.raw["offense"], "retry_days") as i64);
        true
    }

    /// `AIOffense._order`: sends an army to a province unless it is there or on its way.
    fn ai_order(&mut self, data: &Data, tag: &str, army: u32, province: usize) {
        let a = self.army_ref(army);
        if a.province == province && a.path.is_empty() {
            return;
        }
        if a.path.last() == Some(&province) {
            return;
        }
        self.order_army_to(data, tag, army, province);
    }

    fn ai_power_of(&self, data: &Data, armies: &[u32]) -> f64 {
        let mut total = 0.0;
        for &id in armies {
            total += self.army_ref(id).power(&data.military);
        }
        total
    }

    /// `AIOffense._run`: one day of a campaign. Returns whether it has left the nation's books.
    pub fn ai_run(&mut self, data: &Data, tag: &str, c: &mut Campaign) -> bool {
        let o = &data.ai.raw["offense"];
        let today = self.calendar.days_elapsed as i64;
        let odds = self.ai_offense_odds(data, tag, &c.enemy);
        if self.province_controller[c.target] == tag {
            return self.ai_next(data, tag, c);
        }
        if !c.advancing {
            let mut all_there = true;
            for id in c.armies.clone() {
                let a = self.army_ref(id);
                if a.province != c.staging {
                    all_there = false;
                    self.ai_order(data, tag, id, c.staging);
                } else if !a.path.is_empty() || a.fighting {
                    all_there = false;
                }
            }
            if !all_there {
                if today - c.started > of(o, "gather_days") as i64 {
                    return self.ai_end_campaign(data, tag, c);
                }
                return false;
            }
            if c.armies.len() > 1 {
                let ids = c.armies.clone();
                self.merge_armies(tag, &ids);
                c.armies = vec![ids[0]];
            }
            if self.ai_power_of(data, &c.armies) < odds * self.ai_resistance(data, tag, c.target) || self.supply_cost(data, tag, c.target) == f64::INFINITY {
                if today - c.started > of(o, "gather_days") as i64 {
                    return self.ai_end_campaign(data, tag, c);
                }
                return false;
            }
            c.advancing = true;
            for id in c.armies.clone() {
                self.ai_order(data, tag, id, c.target);
            }
            return false;
        }
        // Advancing.
        let at_target = c.armies.iter().all(|&id| self.army_ref(id).province == c.target);
        if at_target {
            if self.ai_going_badly(data, tag, c) {
                return self.ai_fall_back(data, tag, c);
            }
            return false;
        }
        for id in c.armies.clone() {
            let a = self.army_ref(id);
            if !a.path.is_empty() || a.fighting {
                continue;
            }
            // Stopped short (a battle at the staging point, a routed stack): try again if the odds hold.
            if self.ai_power_of(data, &c.armies) >= odds * self.ai_resistance(data, tag, c.target) {
                self.ai_order(data, tag, id, c.target);
            } else {
                return self.ai_end_campaign(data, tag, c);
            }
        }
        false
    }

    /// `AIOffense._going_badly`: whether the stack at the target is losing: worn down, or outnumbered by what is around.
    fn ai_going_badly(&self, data: &Data, tag: &str, c: &Campaign) -> bool {
        let o = &data.ai.raw["offense"];
        let mil = &data.military;
        let (mut morale, mut men) = (0.0, 0.0);
        for &id in &c.armies {
            let a = self.army_ref(id);
            morale += a.morale(mil) * a.men(mil);
            men += a.men(mil);
        }
        if men <= 0.0 {
            return true;
        }
        let caution = self.temperament(data, tag).1;
        let floor_morale = of(o, "fall_back_morale") * (0.5 + caution);
        if morale / men < floor_morale {
            return true;
        }
        self.ai_power_of(data, &c.armies) < of(o, "fall_back_ratio") * self.ai_enemy_power(data, tag, c.target)
    }

    /// `AIOffense._fall_back`.
    fn ai_fall_back(&mut self, data: &Data, tag: &str, c: &mut Campaign) -> bool {
        let mut to = c.staging;
        if self.province_controller[to] != tag {
            to = self.nation(tag).capital as usize;
        }
        for id in c.armies.clone() {
            self.order_army_to(data, tag, id, to);
        }
        self.ai_end_campaign(data, tag, c)
    }

    /// `AIOffense._next`: the target is ours: go on to the next province if one is worth it and within supply.
    fn ai_next(&mut self, data: &Data, tag: &str, c: &mut Campaign) -> bool {
        let o = &data.ai.raw["offense"];
        if c.armies.is_empty() || self.province_controller[self.army_ref(c.armies[0]).province] != tag {
            return self.ai_end_campaign(data, tag, c);
        }
        let here = self.army_ref(c.armies[0]).province;
        for &id in &c.armies {
            let a = self.army_ref(id);
            if a.province != here || !a.path.is_empty() {
                return false;
            }
        }
        let pick = self.ai_offense_target(data, tag, &c.enemy, &self.ai_beyond(data, &c.enemy, here), &c.armies, f64::INFINITY, true);
        let Some(pick) = pick.filter(|p| p.utility >= of(o, "min_utility")) else {
            return self.ai_end_campaign(data, tag, c);
        };
        c.target = pick.target;
        c.staging = here;
        c.advancing = true;
        c.started = self.calendar.days_elapsed as i64;
        for id in c.armies.clone() {
            self.ai_order(data, tag, id, c.target);
        }
        false
    }

    #[allow(dead_code)]
    fn _unused(&self) -> f64 {
        minf(0.0, 0.0)
    }
}
