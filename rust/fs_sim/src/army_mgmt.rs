//! Raising, training and handling armies (`military.gd`'s recruiting, drill and generals; `raise_units.gd`, `set_training.gd`,
//! `demobilize_units.gd`, `split_army.gd`, `merge_armies.gd`, `transfer_units.gd`, `assign_general.gd`): units are bought and take
//! days to train before they join an army in their province, armies on exercise gain experience, a nation's generals lead its armies
//! (the AI's nations keep their best free general in command of their biggest army without one), and armies are split, merged and
//! handed units. Army groups, fronts and offensives are not ported, so no army belongs to one.

use crate::military::{Army, Recruit, Unit};
use crate::state::{Data, GameState};

impl GameState {
    fn army_pos(&self, id: u32) -> Option<usize> {
        self.armies.iter().position(|a| a.id == id)
    }

    fn general_pos(&self, id: u32) -> Option<usize> {
        self.generals.iter().position(|g| g.id == id)
    }

    /// `Military.new_army`: an army with no units, in a province; returns its index.
    pub fn new_army(&mut self, tag: &str, name: &str, province: usize) -> usize {
        let a = Army {
            id: self.next_army_id,
            tag: tag.to_string(),
            name: name.to_string(),
            province,
            units: vec![],
            general_skill: 1.0,
            landing_days: 0,
            path: vec![],
            move_days_left: 0.0,
            still_days: 0,
            attacking: false,
            fighting: false,
            supplied: true,
            landed_supply: 0,
            fleet_id: 0,
            general_id: 0,
            front_id: 0,
            parent_id: 0,
            pin: 0,
            prepared: false,
            planning: 0.0,
            group_id: 0,
            marshal: 1.0,
            training: false,
        };
        self.next_army_id += 1;
        self.armies.push(a);
        self.armies.len() - 1
    }

    /// `Military.set_general`: puts a general in command of an army (by id). Whoever led the army goes back to the pool and the
    /// general leaves the army he led before. With no general the army is left without one; with no army the general is only taken
    /// off his army.
    pub fn set_general(&mut self, general: Option<u32>, army: Option<u32>) {
        if let Some(gid) = general {
            let gi = self.general_pos(gid).unwrap();
            if self.generals[gi].army_id != 0 {
                let old_army = self.generals[gi].army_id;
                self.clear_command(old_army, gid);
            }
        }
        if let Some(aid) = army {
            if let Some(ai) = self.army_pos(aid) {
                let old = self.armies[ai].general_id;
                if let Some(oi) = self.general_pos(old) {
                    self.generals[oi].army_id = 0;
                }
                self.armies[ai].general_id = 0;
                self.armies[ai].general_skill = 1.0;
            }
        }
        let (Some(gid), Some(aid)) = (general, army) else { return };
        let (Some(gi), Some(ai)) = (self.general_pos(gid), self.army_pos(aid)) else { return };
        self.generals[gi].army_id = aid;
        self.armies[ai].general_id = gid;
        self.armies[ai].general_skill = self.generals[gi].skill;
    }

    fn clear_command(&mut self, army_id: u32, general_id: u32) {
        let gi = self.general_pos(general_id).unwrap();
        self.generals[gi].army_id = 0;
        if let Some(ai) = self.army_pos(army_id) {
            if self.armies[ai].general_id == general_id {
                self.armies[ai].general_id = 0;
                self.armies[ai].general_skill = 1.0;
            }
        }
    }

    /// `Military.pool_of`: the nation's generals who lead no army and no group, best first.
    fn general_pool(&self, tag: &str) -> Vec<u32> {
        let mut out: Vec<(f64, u32)> = self.generals.iter().filter(|g| g.tag == tag && g.army_id == 0 && g.group_id == 0).map(|g| (g.skill, g.id)).collect();
        out.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap().then(a.1.cmp(&b.1)));
        out.into_iter().map(|(_, id)| id).collect()
    }

    /// `Military.release_orphan_generals`: frees generals whose army is gone, and the AI's nations put their best free general in
    /// command of their biggest army without one.
    pub fn release_orphan_generals(&mut self, data: &Data) {
        for gi in 0..self.generals.len() {
            let army = self.generals[gi].army_id;
            if army != 0 && !self.army_pos(army).map(|ai| self.armies[ai].general_id == self.generals[gi].id).unwrap_or(false) {
                self.generals[gi].army_id = 0;
            }
        }
        for ni in 0..self.nations.len() {
            let tag = self.nations[ni].tag.clone();
            if tag == self.player_tag {
                continue;
            }
            let pool = self.general_pool(&tag);
            if pool.is_empty() {
                continue;
            }
            let mut unled: Vec<(f64, u32)> = self.armies.iter().filter(|a| a.tag == tag && a.general_id == 0 && !a.units.is_empty()).map(|a| (a.men(&data.military), a.id)).collect();
            unled.sort_by(|x, y| y.0.partial_cmp(&x.0).unwrap().then(x.1.cmp(&y.1)));
            for i in 0..pool.len().min(unled.len()) {
                self.set_general(Some(pool[i]), Some(unled[i].1));
            }
        }
    }

    /// `Military._train`: finishes the units whose training is over and puts them in the province they were raised in.
    pub fn train_recruits(&mut self, data: &Data) {
        for ni in 0..self.nations.len() {
            let tag = self.nations[ni].tag.clone();
            for i in (0..self.nations[ni].recruiting.len()).rev() {
                self.nations[ni].recruiting[i].days_left -= 1;
                if self.nations[ni].recruiting[i].days_left > 0 {
                    continue;
                }
                let job = self.nations[ni].recruiting.remove(i);
                let mut host: Option<usize> = None;
                for (ai, a) in self.armies.iter().enumerate() {
                    if a.province == job.province && !a.embarked() && a.tag == tag && a.path.is_empty() && !a.fighting && host.map(|h| a.units.len() < self.armies[h].units.len()).unwrap_or(true) {
                        host = Some(ai);
                    }
                }
                let host = match host {
                    Some(h) => h,
                    None => self.new_army(&tag, &format!("New levies at {}", data.map.provinces[job.province].name), job.province),
                };
                self.armies[host].units.push(Unit::new(&job.unit_type, 1.0));
            }
        }
    }

    /// `Military._drill`: every division of an army on exercise that stands still gains experience.
    pub fn drill(&mut self, data: &Data) {
        let gain = 1.0 / crate::gd::maxf(data.military.training_days_full, 1.0);
        for i in 0..self.armies.len() {
            let drilling = self.root_of(i).map(|r| self.armies[r].training).unwrap_or(false);
            let a = &mut self.armies[i];
            if !drilling || !a.path.is_empty() || a.fighting || a.embarked() {
                continue;
            }
            for u in &mut a.units {
                u.experience = crate::gd::minf(1.0, u.experience + gain);
            }
        }
    }

    // ---------------------------------------------------------------- the commands

    /// `RaiseUnits.problem`.
    pub fn raise_units_problem(&self, data: &Data, tag: &str, province: usize, kind: &str, count: i64) -> &'static str {
        let Some(&ni) = self.nation_index.get(tag) else { return "Invalid order." };
        if !data.military.unit_types.iter().any(|t| t.id == kind) || count < 1 {
            return "Invalid order.";
        }
        if province < 1 || province >= self.province_owner.len() {
            return "Choose a province.";
        }
        if self.province_owner[province] != tag || self.province_controller[province] != tag {
            return "You must own and hold the province.";
        }
        let n = &self.nations[ni];
        if n.capitulated {
            return "A nation that has capitulated raises no armies until peace.";
        }
        let def = data.military.unit_type(kind);
        if n.manpower < def.size * count {
            return "Not enough recruits.";
        }
        if n.treasury < def.cost * count as f64 {
            return "Not enough money.";
        }
        ""
    }

    /// `RaiseUnits.execute`.
    pub fn raise_units(&mut self, data: &Data, tag: &str, province: usize, kind: &str, count: i64) -> bool {
        if !self.raise_units_problem(data, tag, province, kind, count).is_empty() {
            return false;
        }
        let ni = self.nation_index[tag];
        let def = data.military.unit_type(kind);
        self.nations[ni].manpower -= def.size * count;
        self.nations[ni].treasury -= def.cost * count as f64;
        for _ in 0..count {
            self.nations[ni].recruiting.push(Recruit { unit_type: kind.to_string(), province, days_left: def.train_days });
        }
        self.refresh_men(data);
        true
    }

    /// `SetTraining.execute`: puts armies on exercise or takes them off.
    pub fn set_training(&mut self, data: &Data, tag: &str, army_ids: &[u32], on: bool) -> bool {
        let mut changed = false;
        for id in army_ids {
            let Some(ai) = self.army_pos(*id) else { continue };
            if self.armies[ai].tag != tag {
                continue;
            }
            let Some(root) = self.root_of(ai) else { continue };
            if self.armies[root].training != on {
                self.armies[root].training = on;
                changed = true;
            }
        }
        if !changed {
            return false;
        }
        self.refresh_men(data);
        true
    }

    /// `DemobilizeUnits.execute`: sends units home (their men go back to the reserve), infantry and cavalry first and the guns last,
    /// the largest armies giving first. `count` below zero sends home what is above the peacetime army.
    pub fn demobilize_units(&mut self, data: &Data, tag: &str, army_id: u32, count: i64) -> bool {
        let Some(&ni) = self.nation_index.get(tag) else { return false };
        if !self.wars_of(tag).is_empty() {
            return false;
        }
        let mut ids: Vec<u32> = self.armies.iter().filter(|a| a.tag == tag && (army_id == 0 || a.id == army_id) && !a.embarked()).map(|a| a.id).collect();
        if ids.is_empty() {
            return false;
        }
        let mil = &data.military;
        let mut excess = self.nations[ni].men_in_units - self.nations[ni].peacetime_army;
        let to_send: i64 = if count >= 0 { count } else { 1 << 30 };
        let mut sent = 0i64;
        for pass_guns in [false, true] {
            ids.sort_by(|x, y| {
                let (mx, my) = (self.armies[self.army_pos(*x).unwrap()].men(mil), self.armies[self.army_pos(*y).unwrap()].men(mil));
                my.partial_cmp(&mx).unwrap().then(x.cmp(y))
            });
            for id in &ids {
                let ai = self.army_pos(*id).unwrap();
                for i in (0..self.armies[ai].units.len()).rev() {
                    if sent >= to_send || (count < 0 && excess <= 0) {
                        break;
                    }
                    let u = &self.armies[ai].units[i];
                    let guns = mil.unit_type(&u.unit_type).shells;
                    if guns != pass_guns {
                        continue;
                    }
                    let men = u.men(mil).round() as i64;
                    self.nations[ni].manpower += men;
                    excess -= men;
                    self.armies[ai].units.remove(i);
                    sent += 1;
                }
            }
        }
        self.armies.retain(|a| !(ids.contains(&a.id) && a.units.is_empty()));
        if sent == 0 {
            return false;
        }
        self.refresh_men(data);
        true
    }

    /// `SplitArmy.execute`: units (by index) leave an army to form a detachment; returns the new army's id.
    pub fn split_army(&mut self, tag: &str, army_id: u32, unit_indices: &[usize]) -> Option<u32> {
        let ai = self.army_pos(army_id)?;
        let a = &self.armies[ai];
        if a.tag != tag || unit_indices.is_empty() || unit_indices.len() >= a.units.len() {
            return None;
        }
        for (k, &i) in unit_indices.iter().enumerate() {
            if i >= a.units.len() || unit_indices[..k].contains(&i) {
                return None;
            }
        }
        let (name, province, still, attacking) = (format!("{} detachment", a.name), a.province, a.still_days, a.attacking);
        let picked: Vec<Unit> = unit_indices.iter().map(|&i| a.units[i].clone()).collect();
        let di = self.new_army(tag, &name, province);
        let ai = self.army_pos(army_id).unwrap();
        let mut gone: Vec<usize> = unit_indices.to_vec();
        gone.sort_unstable_by(|x, y| y.cmp(x));
        for i in gone {
            self.armies[ai].units.remove(i);
        }
        self.armies[di].units = picked;
        self.armies[di].still_days = still;
        self.armies[di].attacking = attacking;
        Some(self.armies[di].id)
    }

    /// `MergeArmies.execute`: the other armies join the first, which keeps the better general.
    pub fn merge_armies(&mut self, tag: &str, army_ids: &[u32]) -> bool {
        if army_ids.len() < 2 {
            return false;
        }
        let Some(ti) = self.army_pos(army_ids[0]) else { return false };
        if self.armies[ti].tag != tag {
            return false;
        }
        for id in &army_ids[1..] {
            match self.army_pos(*id) {
                Some(ai) if *id != army_ids[0] && self.armies[ai].tag == tag && self.armies[ai].province == self.armies[ti].province => {}
                _ => return false,
            }
        }
        let target = army_ids[0];
        for id in &army_ids[1..] {
            let ai = self.army_pos(*id).unwrap();
            let units = std::mem::take(&mut self.armies[ai].units);
            let ti = self.army_pos(target).unwrap();
            self.armies[ti].units.extend(units);
            let (gid, gskill, still) = (self.armies[ai].general_id, self.armies[ai].general_skill, self.armies[ai].still_days);
            if gid != 0 && (self.armies[ti].general_id == 0 || gskill > self.armies[ti].general_skill) {
                self.set_general(Some(gid), Some(target));
            } else if gid != 0 {
                let gi = self.general_pos(gid).unwrap();
                self.generals[gi].army_id = 0;
            }
            let ti = self.army_pos(target).unwrap();
            self.armies[ti].still_days = self.armies[ti].still_days.min(still);
            let ai = self.army_pos(*id).unwrap();
            self.armies.remove(ai);
        }
        let ti = self.army_pos(target).unwrap();
        self.armies[ti].path.clear();
        true
    }

    /// `TransferUnits.block`: why units cannot pass between two armies ("" if they can).
    pub fn transfer_block(&self, from: Option<usize>, to: Option<usize>) -> &'static str {
        let (Some(f), Some(t)) = (from, to) else { return "not possible" };
        let (f, t) = (&self.armies[f], &self.armies[t]);
        if f.id == t.id || f.tag != t.tag {
            return "not possible";
        }
        if f.province != t.province {
            return "not in the same province";
        }
        if f.embarked() || t.embarked() {
            return "aboard ship";
        }
        if f.fighting || t.fighting {
            return "in a battle";
        }
        ""
    }

    /// `TransferUnits.execute`: units (by index) pass from one army to another in the same province.
    pub fn transfer_units(&mut self, data: &Data, tag: &str, from_id: u32, unit_indices: &[usize], to_id: u32) -> bool {
        let (fi, ti) = (self.army_pos(from_id), self.army_pos(to_id));
        if fi.map(|f| self.armies[f].tag != tag).unwrap_or(true) || unit_indices.is_empty() || !self.transfer_block(fi, ti).is_empty() {
            return false;
        }
        let (fi, ti) = (fi.unwrap(), ti.unwrap());
        for (k, &i) in unit_indices.iter().enumerate() {
            if i >= self.armies[fi].units.len() || unit_indices[..k].contains(&i) {
                return false;
            }
        }
        let picked: Vec<Unit> = unit_indices.iter().map(|&i| self.armies[fi].units[i].clone()).collect();
        let mut gone: Vec<usize> = unit_indices.to_vec();
        gone.sort_unstable_by(|x, y| y.cmp(x));
        for i in gone {
            self.armies[fi].units.remove(i);
        }
        self.armies[ti].units.extend(picked);
        let still = self.armies[fi].still_days;
        self.armies[ti].still_days = self.armies[ti].still_days.min(still);
        if self.armies[fi].units.is_empty() {
            self.armies.remove(fi);
            self.release_orphan_generals(data);
        }
        true
    }

    /// `AssignGeneral.execute`: puts a general in command of an army, or (army 0) takes him off the one he leads.
    pub fn assign_general(&mut self, tag: &str, general_id: u32, army_id: u32) -> bool {
        let Some(gi) = self.general_pos(general_id) else { return false };
        if self.generals[gi].tag != tag || self.generals[gi].group_id != 0 {
            return false;
        }
        if army_id == 0 {
            if self.generals[gi].army_id == 0 {
                return false;
            }
            let led = self.generals[gi].army_id;
            self.set_general(None, Some(led));
        } else {
            let Some(ai) = self.army_pos(army_id) else { return false };
            if self.armies[ai].tag != tag || self.armies[ai].general_id == general_id {
                return false;
            }
            self.set_general(Some(general_id), Some(army_id));
        }
        true
    }
}
