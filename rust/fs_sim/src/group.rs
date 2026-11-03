//! Army groups and attack lines (`army_group.gd`, `attack_line.gd`, `attack_lines.gd`, the group parts of `military.gd` and the commands
//! `create_army_group.gd`, `disband_army_group.gd`, `assign_to_group.gd`, `set_marshal.gd`, `create_attack_line.gd`,
//! `delete_attack_line.gd`, `set_attack_line.gd`): armies of a nation gathered under a field marshal from its generals, who adds a
//! share of his skill to theirs, and an order for a group to attack one enemy along a front. The campaign an attack line runs is the
//! AI's (`AIOffense`), which is not ported: a line may be made and switched on, and is switched off again when it cannot go on, but a
//! day on which it would run a campaign stops the port with a message.

use crate::state::{Data, GameState};

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct ArmyGroup {
    pub id: u32,
    pub tag: String,
    pub name: String,
    pub army_ids: Vec<u32>,
    pub marshal_id: u32,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct AttackLine {
    pub id: u32,
    pub tag: String,
    pub name: String,
    pub group_id: u32,
    pub enemy: String,
    pub front_id: u32,
    pub active: bool,
    pub wait: i64,
    /// The campaign it runs for its group (`AttackLine.campaign`), if one is under way.
    pub campaign: Option<crate::ai_offense::Campaign>,
}

impl GameState {
    fn group_pos(&self, id: u32) -> Option<usize> {
        self.army_groups.iter().position(|g| g.id == id)
    }

    fn army_idx(&self, id: u32) -> Option<usize> {
        self.armies.iter().position(|a| a.id == id)
    }

    /// `Military.marshal_mult`, for every army: 1 plus the marshal's skill above 1 times the share he adds.
    pub fn refresh_marshals(&mut self, data: &Data) {
        for i in 0..self.armies.len() {
            let m = if self.armies[i].group_id == 0 {
                1.0
            } else if let Some(g) = self.group_pos(self.armies[i].group_id).map(|g| &self.army_groups[g]) {
                match self.generals.iter().find(|x| x.id == g.marshal_id) {
                    Some(m) => 1.0 + (m.skill - 1.0) * data.military.marshal_share,
                    None => 1.0,
                }
            } else {
                1.0
            };
            self.armies[i].marshal = m;
        }
    }

    /// `Military.put_in_group`: moves armies into a group (none takes them out of their groups).
    fn put_in_group(&mut self, group: Option<u32>, army_ids: &[u32]) {
        for id in army_ids {
            let Some(ai) = self.army_idx(*id) else { continue };
            if let Some(old) = self.group_pos(self.armies[ai].group_id) {
                self.army_groups[old].army_ids.retain(|x| x != id);
            }
            self.armies[ai].group_id = 0;
            if let Some(g) = group {
                self.armies[ai].group_id = g;
                let gi = self.group_pos(g).unwrap();
                self.army_groups[gi].army_ids.push(*id);
            }
        }
    }

    /// `Military.set_marshal`: sets the group's marshal (none relieves him); the old marshal goes back to the pool.
    fn set_marshal_of(&mut self, group: usize, general: Option<u32>) {
        let old = self.army_groups[group].marshal_id;
        if let Some(oi) = self.generals.iter().position(|g| g.id == old) {
            self.generals[oi].group_id = 0;
        }
        self.army_groups[group].marshal_id = 0;
        if let Some(gid) = general {
            let gi = self.generals.iter().position(|g| g.id == gid).unwrap();
            self.generals[gi].group_id = self.army_groups[group].id;
            self.army_groups[group].marshal_id = gid;
        }
    }

    fn remove_group(&mut self, group: usize) {
        let ids = std::mem::take(&mut self.army_groups[group].army_ids);
        for id in ids {
            if let Some(ai) = self.army_idx(id) {
                self.armies[ai].group_id = 0;
            }
        }
        self.set_marshal_of(group, None);
        self.army_groups.remove(group);
    }

    /// `Military.prune_groups`: drops armies that no longer exist from their groups and dissolves groups left empty.
    pub fn prune_groups(&mut self, data: &Data) {
        let ids: Vec<u32> = self.army_groups.iter().map(|g| g.id).collect();
        for id in ids {
            let Some(gi) = self.group_pos(id) else { continue };
            for i in (0..self.army_groups[gi].army_ids.len()).rev() {
                let aid = self.army_groups[gi].army_ids[i];
                if self.army_idx(aid).map(|a| self.armies[a].group_id != id).unwrap_or(true) {
                    self.army_groups[gi].army_ids.remove(i);
                }
            }
            if self.army_groups[gi].army_ids.is_empty() {
                self.remove_group(gi);
            }
        }
        self.refresh_marshals(data);
    }

    // ---------------------------------------------------------------- the commands

    /// `CreateArmyGroup.execute`: returns the new group's id.
    pub fn create_army_group(&mut self, data: &Data, tag: &str, name: &str, army_ids: &[u32]) -> Option<u32> {
        if army_ids.is_empty() || army_ids.iter().any(|id| self.army_idx(*id).map(|a| self.armies[a].tag != tag).unwrap_or(true)) {
            return None;
        }
        let id = self.next_group_id;
        self.next_group_id += 1;
        let name = if name.is_empty() { format!("Army Group {id}") } else { name.to_string() };
        self.army_groups.push(ArmyGroup { id, tag: tag.to_string(), name, army_ids: vec![], marshal_id: 0 });
        self.put_in_group(Some(id), army_ids);
        self.prune_groups(data);
        Some(id)
    }

    /// `DisbandArmyGroup.execute`.
    pub fn disband_army_group(&mut self, data: &Data, tag: &str, group_id: u32) -> bool {
        let Some(gi) = self.group_pos(group_id) else { return false };
        if self.army_groups[gi].tag != tag {
            return false;
        }
        self.remove_group(gi);
        self.refresh_marshals(data);
        true
    }

    /// `AssignToGroup.execute` (group 0 takes the armies out of their groups).
    pub fn assign_to_group(&mut self, data: &Data, tag: &str, group_id: u32, army_ids: &[u32]) -> bool {
        if army_ids.is_empty() {
            return false;
        }
        let g = self.group_pos(group_id);
        if group_id != 0 && g.map(|g| self.army_groups[g].tag != tag).unwrap_or(true) {
            return false;
        }
        if army_ids.iter().any(|id| self.army_idx(*id).map(|a| self.armies[a].tag != tag).unwrap_or(true)) {
            return false;
        }
        self.put_in_group(g.map(|g| self.army_groups[g].id), army_ids);
        self.prune_groups(data);
        true
    }

    /// `SetMarshal.execute` (general 0 relieves the marshal).
    pub fn set_marshal(&mut self, data: &Data, tag: &str, group_id: u32, general_id: u32) -> bool {
        let Some(gi) = self.group_pos(group_id) else { return false };
        if self.army_groups[gi].tag != tag {
            return false;
        }
        if general_id == 0 {
            if self.army_groups[gi].marshal_id == 0 {
                return false;
            }
            self.set_marshal_of(gi, None);
        } else {
            match self.generals.iter().find(|g| g.id == general_id) {
                Some(g) if g.tag == tag && g.army_id == 0 && g.group_id == 0 => {}
                _ => return false,
            }
            self.set_marshal_of(gi, Some(general_id));
        }
        self.refresh_marshals(data);
        true
    }

    // ---------------------------------------------------------------- attack lines

    /// `CreateAttackLine.execute`: returns the new line's id.
    pub fn create_attack_line(&mut self, tag: &str, group_id: u32, enemy: &str, front_id: u32) -> Option<u32> {
        let gi = self.group_pos(group_id)?;
        if self.army_groups[gi].tag != tag || enemy == tag || !self.nation_index.contains_key(enemy) {
            return None;
        }
        if self.attack_lines.iter().any(|l| l.group_id == group_id) {
            return None;
        }
        if front_id != 0 && !self.fronts.iter().any(|f| f.id == front_id && f.tag == tag) {
            return None;
        }
        let id = self.next_attack_line_id;
        self.next_attack_line_id += 1;
        let name = format!("{} vs {}", self.army_groups[gi].name, self.nation(enemy).display_name);
        self.attack_lines.push(AttackLine { id, tag: tag.to_string(), name, group_id, enemy: enemy.to_string(), front_id, active: false, wait: 0, campaign: None });
        Some(id)
    }

    /// `AttackLines.block`: why a line cannot be switched on ("" if it can).
    pub fn attack_line_block(&self, line: usize) -> &'static str {
        let l = &self.attack_lines[line];
        if self.group_pos(l.group_id).is_none() {
            return "no_group";
        }
        if !self.at_war(&l.tag, &l.enemy) {
            return "no_war";
        }
        ""
    }

    /// `AttackLines.stop`: calls the attack off: armies on the march halt and the group's armies go back to the front.
    fn stop_attack_line(&mut self, data: &Data, line: usize) {
        self.attack_lines[line].active = false;
        let c = self.attack_lines[line].campaign.take();
        self.attack_lines[line].wait = 0;
        let Some(c) = c else { return };
        let tag = self.attack_lines[line].tag.clone();
        let mut ids = vec![];
        for id in c.armies {
            let Some(a) = self.armies.iter().find(|a| a.id == id) else { continue };
            ids.push(id);
            if !a.path.is_empty() && !a.embarked() {
                let province = a.province;
                self.order_army_to(data, &tag, id, province);
            }
        }
        self.attack_line_rejoin_front(line, &ids);
    }

    /// `AttackLines._rejoin_front`.
    fn attack_line_rejoin_front(&mut self, line: usize, ids: &[u32]) {
        let (tag, front) = (self.attack_lines[line].tag.clone(), self.attack_lines[line].front_id);
        if ids.is_empty() || !self.fronts.iter().any(|f| f.id == front) {
            return;
        }
        self.assign_to_front(&tag, front, ids);
    }

    /// `DeleteAttackLine.execute`.
    pub fn delete_attack_line(&mut self, data: &Data, tag: &str, line_id: u32) -> bool {
        let Some(li) = self.attack_lines.iter().position(|l| l.id == line_id) else { return false };
        if self.attack_lines[li].tag != tag {
            return false;
        }
        if self.attack_lines[li].active {
            self.stop_attack_line(data, li);
        }
        self.attack_lines.remove(li);
        true
    }

    /// `SetAttackLine.execute`.
    pub fn set_attack_line(&mut self, data: &Data, tag: &str, line_id: u32, active: bool) -> bool {
        let Some(li) = self.attack_lines.iter().position(|l| l.id == line_id) else { return false };
        if self.attack_lines[li].tag != tag || self.attack_lines[li].active == active {
            return false;
        }
        if active {
            if !self.attack_line_block(li).is_empty() {
                return false;
            }
            self.attack_lines[li].active = true;
            self.attack_lines[li].wait = 0;
        } else {
            self.stop_attack_line(data, li);
        }
        true
    }

    /// `AttackLines.step_day`: a line whose group is gone is dropped; an active one that can no longer go on stops; the others look for a
    /// campaign for their group (the AI's offence picks the target and the force) or run the one they have.
    pub fn attack_lines_step_day(&mut self, data: &Data) {
        let ids: Vec<u32> = self.attack_lines.iter().map(|l| l.id).collect();
        for id in ids {
            let Some(li) = self.attack_lines.iter().position(|l| l.id == id) else { continue };
            if self.group_pos(self.attack_lines[li].group_id).is_none() {
                self.attack_lines.remove(li);
                continue;
            }
            if !self.attack_lines[li].active {
                continue;
            }
            if !self.attack_line_block(li).is_empty() {
                self.stop_attack_line(data, li);
                continue;
            }
            self.attack_line_step(data, li);
        }
    }

    /// `AttackLines._step_line`.
    fn attack_line_step(&mut self, data: &Data, li: usize) {
        let retry = data.ai.raw["offense"]["retry_days"].as_i64().unwrap();
        let today = self.calendar.days_elapsed as i64;
        let tag = self.attack_lines[li].tag.clone();
        let mut c = self.attack_lines[li].campaign.take();
        if let Some(cc) = c.as_mut() {
            if !self.ai_campaign_alive(&tag, cc) {
                c = None;
                self.attack_lines[li].wait = today + retry;
            }
        }
        let mut c = match c {
            Some(c) => c,
            None => {
                if today < self.attack_lines[li].wait {
                    return;
                }
                match self.attack_line_start(data, li) {
                    Some(c) => c,
                    None => {
                        self.attack_lines[li].wait = today + retry;
                        return;
                    }
                }
            }
        };
        self.ai_run(data, &tag, &mut c);
        if c.done {
            let ids: Vec<u32> = c.armies.iter().copied().filter(|id| self.armies.iter().any(|a| a.id == *id)).collect();
            self.attack_lines[li].campaign = None;
            self.attack_lines[li].wait = today + retry;
            self.attack_line_rejoin_front(li, &ids);
        } else {
            self.attack_lines[li].campaign = Some(c);
        }
    }

    /// `AttackLines._candidates`: the provinces the attack may aim at: enemy ground next to the front's line, or next to any ground the nation
    /// holds when the line is tied to no front.
    fn attack_line_candidates(&self, data: &Data, li: usize) -> Vec<usize> {
        let l = &self.attack_lines[li];
        let Some(front) = self.fronts.iter().find(|f| f.id == l.front_id) else { return self.ai_frontier(data, &l.tag, &l.enemy) };
        let mut seen: Vec<usize> = vec![];
        for &p in &front.provinces {
            for n in data.map.neighbors(p) {
                if self.province_controller[n] == l.enemy && !seen.contains(&n) {
                    seen.push(n);
                }
            }
        }
        seen.sort();
        seen
    }

    /// `AttackLines._start`: picks a target and the group's armies to send; returns the campaign (none if nothing fits).
    fn attack_line_start(&mut self, data: &Data, li: usize) -> Option<crate::ai_offense::Campaign> {
        let (tag, enemy, group_id, line_id) = (self.attack_lines[li].tag.clone(), self.attack_lines[li].enemy.clone(), self.attack_lines[li].group_id, self.attack_lines[li].id);
        let gi = self.group_pos(group_id)?;
        let mut armies: Vec<u32> = vec![];
        for &id in &self.army_groups[gi].army_ids {
            if let Some(a) = self.armies.iter().find(|a| a.id == id) {
                if a.path.is_empty() && !a.fighting && !a.embarked() && self.province_controller[a.province] == tag {
                    armies.push(id);
                }
            }
        }
        let mil = &data.military;
        crate::gd::sort_custom(&mut armies, |&x, &y| {
            let (px, py) = (self.army_ref(x).power(mil), self.army_ref(y).power(mil));
            px > py || (px == py && x < y)
        });
        if armies.is_empty() {
            return None;
        }
        let candidates = self.attack_line_candidates(data, li);
        let pick = self.ai_offense_target(data, &tag, &enemy, &candidates, &armies, f64::INFINITY, false)?;
        // The armies sent leave their front for the attack; they return to it afterwards.
        self.assign_to_front(&tag, 0, &pick.armies);
        self.next_campaign_uid += 1;
        Some(crate::ai_offense::Campaign {
            uid: self.next_campaign_uid,
            enemy,
            target: pick.target,
            staging: pick.staging,
            armies: pick.armies,
            advancing: false,
            started: self.calendar.days_elapsed as i64,
            line: Some(line_id),
            done: false,
        })
    }
}
