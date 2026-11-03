//! The AI at war on the defensive (`scripts/ai/ai_defense.gd`): for each enemy it shares a border with it keeps a border front, assigns its
//! armies to the fronts by how threatened each line is, holds one army back as a reserve in the most threatened province, merges stacks
//! that stand together and retakes home ground the enemy holds when the odds are good. Everything goes through the commands the player
//! uses. (An army on a campaign of the AI's offence is left alone: the offence is not ported, so none is.)

use crate::gd::{clampf, lerpf, maxf, minf, sort_custom};
use crate::state::{Data, GameState};
use serde_json::Value;
use std::collections::HashMap;

fn df(k: &str, data: &Data) -> f64 {
    data.ai.raw["defense"][k].as_f64().unwrap_or_else(|| panic!("ai.json: defense.{k} is not a number"))
}

impl GameState {
    /// `AI.enemies`: the nations `tag` is at war with, in tag order.
    pub fn ai_enemies(&self, tag: &str) -> Vec<String> {
        let mut out: Vec<String> = self.wars_of(tag).into_iter().map(|w| self.wars[w].other(tag).to_string()).collect();
        out.sort();
        out
    }

    /// `AI.battle_odds`: the odds a nation wants before it fights a battle it chooses.
    pub fn ai_battle_odds(&self, data: &Data, tag: &str) -> f64 {
        let (a, c) = self.temperament(data, tag);
        let boldness = clampf((a + 1.0 - c) / 2.0, 0.0, 1.0);
        let o = &data.ai.raw["offense"];
        lerpf(o["odds_cautious"].as_f64().unwrap(), o["odds_bold"].as_f64().unwrap(), boldness)
    }

    /// `AIDefense.step`.
    pub fn ai_defense_step(&mut self, data: &Data, tag: &str) {
        self.ai_sync_fronts(data, tag);
        self.ai_merge(data, tag);
        let fronts = self.ai_front_ids(tag);
        if !fronts.is_empty() {
            self.ai_anchor(data, tag, &fronts);
            self.ai_reserve_step(data, tag, &fronts);
            self.ai_assign(data, tag, &fronts);
            self.ai_rebalance(data, tag, &fronts);
        }
        self.ai_retake(data, tag);
    }

    /// The nation's fronts (ids), in id order.
    fn ai_front_ids(&self, tag: &str) -> Vec<u32> {
        let mut out: Vec<u32> = self.fronts.iter().filter(|f| f.tag == tag).map(|f| f.id).collect();
        out.sort();
        out
    }

    fn front_ref(&self, id: u32) -> &crate::front::Front {
        self.fronts.iter().find(|f| f.id == id).unwrap()
    }

    /// `AIDefense._sync_fronts`: one border front per enemy the nation touches; fronts against nations it no longer fights are dropped.
    fn ai_sync_fronts(&mut self, data: &Data, tag: &str) {
        let enemies = self.ai_enemies(tag);
        for id in self.ai_front_ids(tag) {
            let f = self.front_ref(id);
            if f.against.is_empty() || !enemies.contains(&f.against) || f.provinces.is_empty() {
                self.delete_front(tag, id);
            }
        }
        let have: Vec<String> = self.ai_front_ids(tag).into_iter().map(|id| self.front_ref(id).against.clone()).collect();
        for enemy in &enemies {
            if have.contains(enemy) || self.border_provinces(data, tag, enemy).is_empty() {
                continue;
            }
            self.designate_front(data, tag, "", &[], enemy, "line", 0);
        }
    }

    /// `AIDefense._anchor`: picks the few provinces of each line its armies mass on.
    fn ai_anchor(&mut self, data: &Data, tag: &str, fronts: &[u32]) {
        let today = self.calendar.days_elapsed as i64;
        let (days, weight, per, max) = (df("anchor_days", data) as i64, df("anchor_value_weight", data), df("anchor_armies", data) as i64, df("anchor_max", data) as i64);
        for &fid in fronts {
            let f = self.front_ref(fid);
            let mut stale = today - self.ai_anchor_stamp.get(&fid).copied().unwrap_or(-1000) >= days;
            for p in &f.anchors {
                if !f.provinces.contains(p) {
                    stale = true;
                }
            }
            if !stale || f.provinces.is_empty() {
                continue;
            }
            let (provinces, n_armies) = (f.provinces.clone(), f.army_ids.len() as i64);
            self.ai_anchor_stamp.insert(fid, today);
            let mut scored: Vec<(f64, usize)> = provinces.iter().map(|&p| (self.ai_threat(data, tag, p) + weight * self.ai_value(data, p), p)).collect();
            sort_custom(&mut scored, |x, y| x.0 > y.0 + 0.000001 || ((x.0 - y.0).abs() <= 0.000001 && x.1 < y.1));
            let count = (n_armies / per).clamp(1, max) as usize;
            let mut picks: Vec<usize> = scored.iter().take(count.min(scored.len())).map(|s| s.1).collect();
            picks.sort();
            self.set_front_anchors(tag, fid, &picks);
        }
    }

    /// `AIDefense._need`: what a front must stand against: the threat on the provinces of its line.
    fn ai_need(&self, data: &Data, fid: u32) -> f64 {
        let f = self.front_ref(fid);
        let mut total = 0.0;
        for &p in &f.provinces {
            total += self.ai_threat(data, &f.tag, p);
        }
        // The theatre an offensive plan aims at is the main effort: it gets a larger share of the army.
        for plan in &self.ai_plans {
            if plan["nation"] == f.tag && plan["enemy"] == f.against && plan["posture"] == "offensive" {
                total *= df("plan_need", data);
                break;
            }
        }
        maxf(total, df("min_need", data))
    }

    pub(crate) fn ai_power_on(&self, data: &Data, fid: u32) -> f64 {
        let mut total = 0.0;
        for id in &self.front_ref(fid).army_ids {
            if let Some(a) = self.armies.iter().find(|a| a.id == *id) {
                total += a.power(&data.military);
            }
        }
        total
    }

    fn ai_tables(&self, data: &Data, fronts: &[u32]) -> (HashMap<u32, f64>, HashMap<u32, f64>) {
        let mut needs = HashMap::new();
        let mut powers = HashMap::new();
        for &f in fronts {
            needs.insert(f, self.ai_need(data, f));
            powers.insert(f, self.ai_power_on(data, f));
        }
        (needs, powers)
    }

    /// `AIDefense._weakest`: the front with the least cover (power over need); ties go to the first.
    fn ai_weakest(fronts: &[u32], needs: &HashMap<u32, f64>, powers: &HashMap<u32, f64>) -> u32 {
        let mut best = 0;
        let mut best_cover = f64::INFINITY;
        for &f in fronts {
            let cover = powers[&f] / needs[&f];
            if cover < best_cover - 0.000001 {
                best = f;
                best_cover = cover;
            }
        }
        best
    }

    /// `AIDefense._idle`: armies standing still and out of battle, in id order, except those on a campaign.
    fn ai_idle(&self, tag: &str) -> Vec<u32> {
        let mut ids: Vec<&crate::military::Army> = self.armies.iter().filter(|a| a.tag == tag).collect();
        ids.sort_by_key(|a| a.id);
        ids.into_iter().filter(|a| a.path.is_empty() && !a.fighting && !a.embarked() && !self.ai_in_campaign(tag, a.id)).map(|a| a.id).collect()
    }

    pub(crate) fn army_ref(&self, id: u32) -> &crate::military::Army {
        self.armies.iter().find(|a| a.id == id).unwrap()
    }

    /// `AIDefense._merge`: joins stacks that stand in one province on the same front (or on none), leaving the reserve.
    fn ai_merge(&mut self, data: &Data, tag: &str) {
        let reserve = self.ai_reserve.get(tag).copied().unwrap_or(0);
        let mut groups: Vec<((usize, u32), Vec<u32>)> = vec![];
        for id in self.ai_idle(tag) {
            if id == reserve {
                continue;
            }
            let a = self.army_ref(id);
            let key = (a.province, a.front_id);
            match groups.iter_mut().find(|g| g.0 == key) {
                Some(g) => g.1.push(id),
                None => groups.push((key, vec![id])),
            }
        }
        groups.sort_by(|x, y| x.0.cmp(&y.0));
        let max_units = df("merge_max_units", data) as usize;
        for (_, ids) in groups {
            let mut chunk: Vec<u32> = vec![];
            let mut units = 0;
            for id in ids {
                let n = self.army_ref(id).units.len();
                if !chunk.is_empty() && units + n > max_units {
                    if chunk.len() > 1 {
                        self.merge_armies(tag, &chunk);
                    }
                    chunk = vec![];
                    units = 0;
                }
                chunk.push(id);
                units += n;
            }
            if chunk.len() > 1 {
                self.merge_armies(tag, &chunk);
            }
        }
    }

    /// `AIDefense._reserve`: keeps one army back, in the most threatened province of any line.
    fn ai_reserve_step(&mut self, data: &Data, tag: &str, fronts: &[u32]) {
        let mil = &data.military;
        let mut armies: Vec<u32> = self.armies.iter().filter(|a| a.tag == tag).map(|a| a.id).collect();
        armies.sort();
        if (armies.len() as i64) < df("reserve_min_armies", data) as i64 {
            self.ai_reserve.remove(tag);
            return;
        }
        let held = self.ai_reserve.get(tag).copied().unwrap_or(0);
        let mut reserve: Option<u32> = self.armies.iter().find(|a| a.id == held && a.tag == tag).map(|a| a.id);
        if reserve.is_none() {
            self.ai_reserve.remove(tag);
            let mut total = 0.0;
            for &a in &armies {
                total += self.army_ref(a).power(mil);
            }
            let share = df("reserve_share", data) * (0.5 + self.temperament(data, tag).1);
            for a in self.ai_idle(tag) {
                let p = self.army_ref(a).power(mil);
                if p <= share * total && reserve.map(|r| p > self.army_ref(r).power(mil)).unwrap_or(true) {
                    reserve = Some(a);
                }
            }
            let Some(r) = reserve else { return };
            self.assign_to_front(tag, 0, &[r]);
            self.ai_reserve.insert(tag.to_string(), r);
        }
        let r = self.army_ref(reserve.unwrap());
        if !r.path.is_empty() || r.fighting {
            return;
        }
        let (rid, rprov) = (r.id, r.province);
        // The most threatened province of any line.
        let mut best = 0usize;
        let mut best_threat = -1.0;
        for &fid in fronts {
            for &p in &self.front_ref(fid).provinces.clone() {
                let t = self.ai_threat(data, tag, p);
                if t > best_threat + 0.000001 || ((t - best_threat).abs() <= 0.000001 && p < best) {
                    best = p;
                    best_threat = t;
                }
            }
        }
        if best == 0 || best == rprov {
            return;
        }
        if self.ai_threat(data, tag, rprov) * df("reserve_stay", data) >= best_threat {
            return;
        }
        self.order_army_to(data, tag, rid, best);
    }

    /// `AIDefense._assign`: puts armies that belong to no front on the front with the least cover.
    fn ai_assign(&mut self, data: &Data, tag: &str, fronts: &[u32]) {
        let mil = &data.military;
        let reserve = self.ai_reserve.get(tag).copied().unwrap_or(0);
        let mut pool: Vec<u32> = vec![];
        for id in self.ai_idle(tag) {
            let a = self.army_ref(id);
            // An army standing on ground the enemy holds is taking it: let it finish.
            let occupier = self.occupation.get(&a.province).map(|o| o.0.as_str()).unwrap_or("");
            if a.front_id == 0 && id != reserve && occupier != tag {
                pool.push(id);
            }
        }
        if pool.is_empty() {
            return;
        }
        sort_custom(&mut pool, |&x, &y| {
            let (px, py) = (self.army_ref(x).power(mil), self.army_ref(y).power(mil));
            px > py || (px == py && x < y)
        });
        let (needs, mut powers) = self.ai_tables(data, fronts);
        let mut batches: Vec<(u32, Vec<u32>)> = vec![];
        // Armies far from every line wait a few days after a new war starts.
        let today = self.calendar.days_elapsed as i64;
        let mut newest = f64::INFINITY;
        for w in self.wars_of(tag) {
            newest = minf(newest, (today - self.wars[w].start_day) as f64);
        }
        let settled = newest >= df("settle_days", data);
        for id in pool {
            let f = self.ai_front_for(data, id, fronts, &needs, &powers);
            if !settled && self.ai_km_to_line(data, id, f) > df("rebalance_max_km", data) {
                continue;
            }
            *powers.get_mut(&f).unwrap() += self.army_ref(id).power(mil);
            match batches.iter_mut().find(|b| b.0 == f) {
                Some(b) => b.1.push(id),
                None => batches.push((f, vec![id])),
            }
        }
        batches.sort_by_key(|b| b.0);
        for (fid, ids) in batches {
            self.assign_to_front(tag, fid, &ids);
        }
    }

    /// `AIDefense._front_for`: the front an unassigned army should join: the least covered, but an army does not march across the country to a
    /// line that is only a little worse covered than one beside it.
    fn ai_front_for(&self, data: &Data, army: u32, fronts: &[u32], needs: &HashMap<u32, f64>, powers: &HashMap<u32, f64>) -> u32 {
        let mut best = 0;
        let mut best_score = f64::INFINITY;
        for &f in fronts {
            let score = powers[&f] / needs[&f] + self.ai_km_to_line(data, army, f) / df("near_km", data);
            if score < best_score - 0.000001 {
                best = f;
                best_score = score;
            }
        }
        best
    }

    /// `AIDefense._rebalance`: moves the army nearest the worst-covered front from the best-covered one when the cover differs by more than
    /// `rebalance_ratio`. One move per turn.
    fn ai_rebalance(&mut self, data: &Data, tag: &str, fronts: &[u32]) {
        if fronts.len() < 2 {
            return;
        }
        let mil = &data.military;
        let (needs, powers) = self.ai_tables(data, fronts);
        let mut best = 0;
        let mut best_cover = -1.0;
        for &f in fronts {
            let cover = powers[&f] / needs[&f];
            if cover > best_cover + 0.000001 {
                best = f;
                best_cover = cover;
            }
        }
        let worst = Self::ai_weakest(fronts, &needs, &powers);
        if best == worst || self.front_ref(best).army_ids.len() < 2 {
            return;
        }
        let worst_cover = powers[&worst] / needs[&worst];
        if best_cover < worst_cover * df("rebalance_ratio", data) {
            return;
        }
        // The donor is the army nearest the line that needs it, if that is not too far to march.
        let mut smallest: Option<u32> = None;
        let mut best_km = f64::INFINITY;
        for &id in &self.front_ref(best).army_ids.clone() {
            let Some(a) = self.armies.iter().find(|a| a.id == id) else { continue };
            if !a.path.is_empty() || a.fighting {
                continue;
            }
            let km = self.ai_km_to_line(data, id, worst);
            if km < best_km - 0.000001 || ((km - best_km).abs() <= 0.000001 && smallest.map(|s| id < s).unwrap_or(false)) {
                smallest = Some(id);
                best_km = km;
            }
        }
        let Some(s) = smallest else { return };
        if best_km > df("rebalance_max_km", data) {
            return;
        }
        // Only if the donor stays better covered than the receiver will be.
        let sp = self.army_ref(s).power(mil);
        if (powers[&best] - sp) / needs[&best] < (powers[&worst] + sp) / needs[&worst] {
            return;
        }
        self.assign_to_front(tag, worst, &[s]);
    }

    /// `AIDefense._km_to_line`: how far an army stands from the provinces a front masses on.
    fn ai_km_to_line(&self, data: &Data, army: u32, fid: u32) -> f64 {
        let f = self.front_ref(fid);
        let points = if f.anchors.is_empty() { &f.provinces } else { &f.anchors };
        let a = data.map.provinces[self.army_ref(army).province].center;
        let mut km = f64::INFINITY;
        for &p in points {
            let b = data.map.provinces[p].center;
            let (dx, dy) = (a.0 - b.0, a.1 - b.1);
            km = minf(km, (dx * dx + dy * dy).sqrt() as f64 * crate::war::KM_PER_PX);
        }
        km
    }

    /// `AIDefense._retake`: sends armies to take back home provinces an enemy holds, when the force that can reach them in step beats the
    /// defenders by the odds the nation's temperament asks for. At most one province a turn.
    fn ai_retake(&mut self, data: &Data, tag: &str) {
        let mil = &data.military;
        let odds = self.ai_battle_odds(data, tag);
        let mut targets: Vec<usize> = vec![];
        for &p in &self.nation(tag).provinces {
            let holder = &self.province_controller[p];
            if holder != tag && self.at_war(tag, holder) {
                targets.push(p);
            }
        }
        sort_custom(&mut targets, |&x, &y| {
            let (vx, vy) = (self.ai_value(data, x), self.ai_value(data, y));
            vx > vy || (vx == vy && x < y)
        });
        let armies = self.ai_idle(tag);
        let hops = df("retake_hops", data) as i64;
        for target in targets {
            if self.ai_under_way(tag, target) {
                continue;
            }
            let required = odds * self.ai_defence_at(data, tag, target);
            // Cheap test first: is there enough idle power within reach at all?
            let near: Vec<usize> = self.hops_from(data, target, hops).into_iter().map(|x| x.0).collect();
            let mut reachable = 0.0;
            for &a in &armies {
                let ar = self.army_ref(a);
                if near.contains(&ar.province) {
                    reachable += ar.power(mil);
                }
            }
            if reachable < required || self.supply_cost(data, tag, target) == f64::INFINITY {
                continue;
            }
            let force = self.ai_force_for(data, tag, target, &armies, required);
            if force.is_empty() {
                continue;
            }
            for a in force {
                self.order_army_to(data, tag, a, target);
            }
            return;
        }
    }

    /// `AIDefense._under_way`: whether one of the nation's armies is already marching on the province.
    fn ai_under_way(&self, tag: &str, target: usize) -> bool {
        self.armies.iter().any(|a| a.tag == tag && a.path.last() == Some(&target))
    }

    /// `AIDefense._defence_at`: what stands in the way of taking a province.
    pub(crate) fn ai_defence_at(&self, data: &Data, tag: &str, target: usize) -> f64 {
        let (mut inside, mut dug) = (0.0, 0.0);
        for a in self.armies.iter().filter(|a| a.province == target && !a.embarked()) {
            if self.at_war(tag, &a.tag) {
                let p = a.power(&data.military);
                inside += p;
                dug += p * self.defense_multiplier(data, a);
            }
        }
        maxf(self.ai_enemy_power(data, tag, target) - inside + dug, 0.01)
    }

    /// `AIDefense._force_for`: the idle armies, nearest first, that together reach the required power and arrive within `retake_eta_spread`
    /// days of each other. Empty if there are not enough.
    fn ai_force_for(&self, data: &Data, tag: &str, target: usize, armies: &[u32], required: f64) -> Vec<u32> {
        let mil = &data.military;
        let near: Vec<usize> = self.hops_from(data, target, df("retake_hops", data) as i64).into_iter().map(|x| x.0).collect();
        let mut options: Vec<(f64, u32)> = vec![];
        for &id in armies {
            let a = self.army_ref(id);
            if !near.contains(&a.province) || a.province == target {
                continue;
            }
            let speed = a.speed(mil);
            let route = self.find_path(data, tag, speed, a.province, target);
            if route.is_empty() {
                continue;
            }
            // `Military.path_etas` with nothing left of the first step
            let (mut total, mut prev) = (0.0, a.province);
            for (i, &p) in route.iter().enumerate() {
                total += if i == 0 { 0.0 } else { self.move_days(data, tag, speed, prev, p) };
                prev = p;
            }
            options.push((total, id));
        }
        sort_custom(&mut options, |x, y| x.0 < y.0 || (x.0 == y.0 && x.1 < y.1));
        let mut force = vec![];
        let mut power = 0.0;
        for o in &options {
            if o.0 - options[0].0 > df("retake_eta_spread", data) {
                break;
            }
            force.push(o.1);
            power += self.army_ref(o.1).power(mil);
            if power >= required {
                return force;
            }
        }
        vec![]
    }
}

#[allow(dead_code)]
fn _unused(_: &Value) {}
