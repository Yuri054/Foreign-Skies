//! Plans of attack (`offensive.gd`, `offensives.gd`, `plan_offensive.gd`, `set_offensive.gd`): a broad push toward a target line, a
//! spearhead at one province, or an invasion from a port. While a plan is made the army's stacks on their front build up planning;
//! launched, they attack as aggressively as the plan says.

use crate::state::{Data, GameState};

#[derive(Debug, Clone, PartialEq)]
pub struct Offensive {
    pub id: u32,
    pub tag: String,
    pub army_id: u32,
    /// "broad", "spearhead" or "invasion".
    pub kind: String,
    pub phases: Vec<Vec<usize>>,
    pub phase: usize,
    pub aggressiveness: String,
    pub port: usize,
    pub active: bool,
    pub launched: bool,
    pub done: bool,
}

impl Offensive {
    /// The provinces of the phase being fought for (none when done).
    pub fn targets(&self) -> Vec<usize> {
        self.phases.get(self.phase).cloned().unwrap_or_default()
    }
}

/// The keys of `military.json`'s "offensive" (the game checks an aggressiveness by `has`, so any of them passes there).
const OFFENSIVE_KEYS: [&str; 9] = ["_note", "planning_days", "planning_decay_days", "planning_max", "planning_ready", "gather", "careful", "balanced", "aggressive"];

fn fdist(data: &Data, a: usize, b: usize) -> f32 {
    let (p, q) = (data.map.provinces[a].center, data.map.provinces[b].center);
    let (dx, dy) = (p.0 - q.0, p.1 - q.1);
    (dx * dx + dy * dy).sqrt()
}

impl GameState {
    fn off_pos(&self, id: u32) -> Option<usize> {
        self.offensives.iter().position(|o| o.id == id)
    }

    /// `Offensives.of_army`: the plan of an army (its army, if `a` is a detachment), or none.
    pub fn offensive_of(&self, army: usize) -> Option<usize> {
        let root = self.root_of(army)?;
        let rid = self.armies[root].id;
        self.offensives.iter().position(|o| o.army_id == rid && !o.done)
    }

    /// `Offensives.controls`: whether a plan has the army's stacks in hand (a launched spearhead or invasion).
    pub fn offensive_controls(&self, root: usize) -> bool {
        self.offensive_of(root).map(|o| self.offensives[o].active && self.offensives[o].kind != "broad").unwrap_or(false)
    }

    fn planning_of(&self, root: usize) -> f64 {
        let (mut total, mut units) = (0.0, 0i64);
        for s in self.stacks_pub(root) {
            total += self.armies[s].planning * self.armies[s].units.len() as f64;
            units += self.armies[s].units.len() as i64;
        }
        if units > 0 {
            total / units as f64
        } else {
            0.0
        }
    }

    /// `Offensives._plan`: planning goes up for stacks with a plan standing still on their front, and down for the rest.
    fn plan_planning(&mut self, data: &Data) {
        let up = 1.0 / crate::gd::maxf(data.military.offensive_planning_days, 1.0);
        let down = 1.0 / crate::gd::maxf(data.military.offensive_decay_days, 1.0);
        for i in 0..self.armies.len() {
            let root = self.root_of(i);
            let planned = root.map(|r| self.offensive_of(r).is_some()).unwrap_or(false);
            let mut on_front = false;
            if let (true, Some(r)) = (planned, root) {
                let fid = self.armies[r].front_id;
                if fid != 0 {
                    if let Some(f) = self.fronts.iter().find(|f| f.id == fid) {
                        on_front = f.provinces.contains(&self.armies[i].province);
                    }
                }
            }
            let a = &mut self.armies[i];
            if planned && on_front && a.path.is_empty() && !a.fighting {
                a.planning = crate::gd::minf(1.0, a.planning + up);
            } else {
                a.planning = crate::gd::maxf(0.0, a.planning - down);
            }
        }
    }

    /// `Offensives.odds`: the odds of an attack on a province by this much power: it over what defends the province.
    fn attack_odds(&self, data: &Data, tag: &str, power: f64, province: usize) -> f64 {
        let mut theirs = 0.0;
        for b in &self.armies {
            if b.province == province && !b.embarked() && self.at_war(tag, &b.tag) {
                theirs += b.power(&data.military) * self.defense_multiplier(data, b);
            }
        }
        if theirs <= 0.0 {
            f64::INFINITY
        } else {
            power / theirs
        }
    }

    fn may_attack(data: &Data, aggressiveness: &str, chances: f64, morale: f64) -> bool {
        let (odds, need) = data.military.offensive_rules.iter().find(|(k, _, _)| k == aggressiveness).map(|(_, o, m)| (*o, *m)).unwrap_or((1.3, 0.5));
        chances >= odds && morale >= need
    }

    /// `Offensives.attack_power`: a stack's power as it would attack, with its planning.
    fn attack_power(&mut self, data: &Data, a: usize) -> f64 {
        let was = self.armies[a].attacking;
        self.armies[a].attacking = true;
        let p = self.armies[a].power(&data.military);
        self.armies[a].attacking = was;
        p
    }

    fn off_free(a: &crate::military::Army) -> bool {
        a.path.is_empty() && !a.fighting && a.pin == 0 && !a.embarked() && !a.units.is_empty()
    }

    fn off_hostile(&self, tag: &str, p: usize) -> bool {
        let holder = &self.province_controller[p];
        holder != tag && self.at_war(tag, holder)
    }

    fn to_targets(&self, data: &Data, p: usize, targets: &[usize]) -> f64 {
        let mut best = f64::INFINITY;
        for &t in targets {
            best = crate::gd::minf(best, fdist(data, p, t) as f64);
        }
        best
    }

    /// `Offensives._send`: sends a stack into a province; the front leaves it alone until it gets there (pin).
    fn off_send(&mut self, data: &Data, a: usize, to: usize) -> bool {
        let (tag, speed, from) = (self.armies[a].tag.clone(), self.armies[a].speed(&data.military), self.armies[a].province);
        let route = self.find_path(data, &tag, speed, from, to);
        if route.is_empty() {
            return false;
        }
        self.armies[a].move_days_left = self.move_days(data, &tag, speed, from, route[0]);
        self.armies[a].path = route;
        self.armies[a].still_days = 0;
        self.armies[a].pin = to;
        true
    }

    fn next_phase(&mut self, oi: usize, root: usize) {
        let o = &mut self.offensives[oi];
        o.phase += 1;
        o.launched = false;
        if o.phase >= o.phases.len() {
            o.done = true;
            o.active = false;
        }
        for s in self.stacks_pub(root) {
            self.armies[s].planning = 0.0;
        }
    }

    /// `Offensives.step_day`.
    pub fn offensives_step_day(&mut self, data: &Data) {
        self.plan_planning(data);
        let ids: Vec<u32> = self.offensives.iter().map(|o| o.id).collect();
        for id in ids {
            let Some(oi) = self.off_pos(id) else { continue };
            let Some(root) = self.armies.iter().position(|a| a.id == self.offensives[oi].army_id) else {
                self.offensives.remove(oi);
                continue;
            };
            if self.offensives[oi].done || !self.offensives[oi].active {
                continue;
            }
            if self.offensives[oi].kind == "invasion" {
                self.invasion(data, oi, root);
                continue;
            }
            let tag = self.offensives[oi].tag.clone();
            let mut targets = self.offensives[oi].targets();
            while !targets.is_empty() && targets.iter().all(|&p| self.province_controller[p] == tag) {
                self.next_phase(oi, root);
                targets = self.offensives[oi].targets();
            }
            if self.offensives[oi].done {
                continue;
            }
            if !self.offensives[oi].launched {
                if self.offensives[oi].aggressiveness == "aggressive" || self.planning_of(root) >= data.military.offensive_ready {
                    self.offensives[oi].launched = true;
                } else {
                    continue;
                }
            }
            let left: Vec<usize> = targets.iter().copied().filter(|&p| self.province_controller[p] != tag).collect();
            if self.offensives[oi].kind == "spearhead" {
                self.spearhead(data, oi, root, targets[0]);
            } else {
                self.push(data, oi, root, &left);
            }
        }
    }

    /// `Offensives._push`: a broad push: every free stack picks the enemy province next to it that leads toward the targets (the one
    /// with the best odds), and the stacks that picked the same one attack it together when their power gives good enough odds.
    fn push(&mut self, data: &Data, oi: usize, root: usize, targets: &[usize]) {
        let (tag, aggr) = (self.offensives[oi].tag.clone(), self.offensives[oi].aggressiveness.clone());
        let mut by_target: Vec<(usize, Vec<usize>)> = vec![];
        for s in self.stacks_pub(root) {
            let morale = self.armies[s].morale(&data.military);
            if !Self::off_free(&self.armies[s]) || !Self::may_attack(data, &aggr, f64::INFINITY, morale) {
                continue;
            }
            let here = self.to_targets(data, self.armies[s].province, targets);
            let mut best = 0usize;
            let mut best_odds = -1.0;
            let province = self.armies[s].province;
            for n in data.map.neighbors(province).collect::<Vec<_>>() {
                if !self.off_hostile(&tag, n) || self.to_targets(data, n, targets) >= here {
                    continue;
                }
                let power = self.attack_power(data, s);
                let chances = self.attack_odds(data, &tag, power, n);
                if chances > best_odds {
                    best_odds = chances;
                    best = n;
                }
            }
            if best != 0 {
                match by_target.iter_mut().find(|(t, _)| *t == best) {
                    Some(slot) => slot.1.push(s),
                    None => by_target.push((best, vec![s])),
                }
            }
        }
        for (target, stacks) in by_target {
            let (mut power, mut morale) = (0.0, 1.0);
            for &s in &stacks {
                power += self.attack_power(data, s);
                morale = crate::gd::minf(morale, self.armies[s].morale(&data.military));
            }
            if Self::may_attack(data, &aggr, self.attack_odds(data, &tag, power, target), morale) {
                for s in stacks {
                    self.off_send(data, s, target);
                }
            }
        }
    }

    /// `Offensives._spearhead`.
    fn spearhead(&mut self, data: &Data, oi: usize, root: usize, target: usize) {
        let (tag, aggr) = (self.offensives[oi].tag.clone(), self.offensives[oi].aggressiveness.clone());
        let objective = self.next_objective(data, &tag, target);
        if objective == 0 {
            return;
        }
        let staging: Vec<usize> = data.map.neighbors(objective).filter(|&n| self.province_controller[n] == tag).collect();
        if staging.is_empty() {
            return;
        }
        let (mut gathered, mut total, mut near) = (vec![], 0i64, 0i64);
        for s in self.stacks_pub(root) {
            total += self.armies[s].units.len() as i64;
            if staging.contains(&self.armies[s].province) && self.armies[s].path.is_empty() {
                gathered.push(s);
                near += self.armies[s].units.len() as i64;
            } else if Self::off_free(&self.armies[s]) {
                // Not there yet: to the nearest staging province.
                let mut best = staging[0];
                for &p in &staging {
                    if fdist(data, p, self.armies[s].province) < fdist(data, best, self.armies[s].province) {
                        best = p;
                    }
                }
                self.off_send(data, s, best);
            }
        }
        let enough = near as f64 >= total as f64 * data.military.offensive_gather || aggr == "aggressive";
        if !enough || gathered.is_empty() {
            return;
        }
        let (mut power, mut morale) = (0.0, 0.0);
        for &s in &gathered {
            power += self.attack_power(data, s);
            morale += self.armies[s].morale(&data.military) * self.armies[s].units.len() as f64;
        }
        morale /= crate::gd::maxf(near as f64, 1.0);
        if Self::may_attack(data, &aggr, self.attack_odds(data, &tag, power, objective), morale) {
            for s in gathered {
                if Self::off_free(&self.armies[s]) || (self.armies[s].pin == self.armies[s].province && self.armies[s].path.is_empty()) {
                    self.armies[s].pin = 0;
                    self.off_send(data, s, objective);
                }
            }
        }
    }

    /// `Offensives._invasion`: the army's stacks march to the port; once enough of its divisions are there and a fleet of the nation
    /// in the port has room for them, they sail to land on the target.
    fn invasion(&mut self, data: &Data, oi: usize, root: usize) {
        let o = self.offensives[oi].clone();
        let Some(&target) = o.targets().first() else { return };
        let (mut total, mut there, mut near, mut men) = (0i64, vec![], 0i64, 0.0);
        for s in self.stacks_pub(root) {
            total += self.armies[s].units.len() as i64;
            if self.armies[s].province == o.port && self.armies[s].path.is_empty() && !self.armies[s].embarked() {
                there.push(self.armies[s].id);
                near += self.armies[s].units.len() as i64;
                men += self.armies[s].men(&data.military);
            } else if Self::off_free(&self.armies[s]) && self.armies[s].province != o.port {
                self.off_send(data, s, o.port);
            }
        }
        let share = if o.aggressiveness != "aggressive" { 1.0 } else { data.military.offensive_gather };
        if there.is_empty() || (near as f64) < total as f64 * share {
            return;
        }
        for fi in self.fleets_in_port(o.port) {
            let f = &self.fleets[fi];
            if f.tag == o.tag && self.free_capacity(data, f) >= men {
                let fid = f.id;
                if self.send_overseas(data, &o.tag, fid, &there, target) {
                    self.offensives[oi].done = true;
                    self.offensives[oi].active = false;
                    return;
                }
            }
        }
    }

    /// `Offensives.next_objective`: the enemy province a spearhead strikes next on its way to `target`.
    pub fn next_objective(&self, data: &Data, tag: &str, target: usize) -> usize {
        if !self.off_hostile(tag, target) && self.province_controller[target] == tag {
            return 0;
        }
        let (mut best, mut best_d) = (0usize, f64::INFINITY);
        for id in 1..self.province_controller.len() {
            if !self.off_hostile(tag, id) {
                continue;
            }
            if !data.map.neighbors(id).any(|n| self.province_controller[n] == tag) {
                continue;
            }
            let d = fdist(data, target, id) as f64;
            if d < best_d {
                best_d = d;
                best = id;
            }
        }
        best
    }

    // ---------------------------------------------------------------- the commands

    /// `PlanOffensive.problem`.
    pub fn plan_offensive_problem(&self, data: &Data, tag: &str, army_id: u32, kind: &str, line: &[usize], aggr: &str, port: usize) -> &'static str {
        match self.armies.iter().find(|a| a.id == army_id) {
            Some(a) if a.tag == tag => {}
            _ => return "Choose one of your armies.",
        }
        if !["broad", "spearhead", "invasion"].contains(&kind) || !OFFENSIVE_KEYS.contains(&aggr) {
            return "Unknown kind of attack.";
        }
        if line.is_empty() || (kind != "broad" && line.len() != 1) {
            return "Mark the line to reach.";
        }
        if line.iter().any(|&p| p < 1 || p >= self.province_owner.len()) {
            return "Unknown province.";
        }
        if kind == "invasion" {
            if port < 1 || port >= self.province_owner.len() || self.province_controller[port] != tag || !self.can_dock(data, tag, port) {
                return "Choose a port of yours to sail from.";
            }
            if data.map.zones_of_port(line[0]).is_empty() {
                return "Choose a coastal province to land on.";
            }
            if !self.can_enter_pub(data, tag, line[0]) {
                return "You may not land there.";
            }
        }
        ""
    }

    /// `PlanOffensive.execute`: returns the plan's id.
    pub fn plan_offensive(&mut self, data: &Data, tag: &str, army_id: u32, kind: &str, provinces: &[usize], aggr: &str, port: usize) -> Option<u32> {
        if !self.plan_offensive_problem(data, tag, army_id, kind, provinces, aggr, port).is_empty() {
            return None;
        }
        let ai = self.armies.iter().position(|a| a.id == army_id).unwrap();
        let root = self.armies[self.root_of(ai)?].id;
        self.offensives.retain(|o| o.army_id != root);
        let id = self.next_offensive_id;
        self.next_offensive_id += 1;
        self.offensives.push(Offensive {
            id,
            tag: tag.to_string(),
            army_id: root,
            kind: kind.to_string(),
            phases: vec![provinces.to_vec()],
            phase: 0,
            aggressiveness: aggr.to_string(),
            port,
            active: false,
            launched: false,
            done: false,
        });
        Some(id)
    }

    /// `SetOffensive.execute` with a list of provinces (`phase`, `targets`), a flag (`launch`), a word (`aggressiveness`) or nothing
    /// (`cancel`).
    pub fn set_offensive(&mut self, tag: &str, id: u32, key: &str, flag: bool, word: &str, line: &[usize]) -> bool {
        let Some(oi) = self.off_pos(id) else { return false };
        if self.offensives[oi].tag != tag {
            return false;
        }
        match key {
            "launch" => {
                let o = &mut self.offensives[oi];
                o.active = flag && !o.done;
                if !o.active {
                    o.launched = false;
                }
            }
            "aggressiveness" => {
                if !["careful", "balanced", "aggressive"].contains(&word) {
                    return false;
                }
                self.offensives[oi].aggressiveness = word.to_string();
            }
            "phase" => {
                let o = &mut self.offensives[oi];
                if line.is_empty() || (o.kind == "spearhead" && line.len() != 1) {
                    return false;
                }
                o.phases.push(line.to_vec());
                o.done = false;
            }
            "targets" => {
                let o = &self.offensives[oi];
                if line.is_empty() || o.done || (o.kind != "broad" && line.len() != 1) || line.iter().any(|&p| p < 1 || p >= self.province_owner.len()) {
                    return false;
                }
                let phase = o.phase;
                self.offensives[oi].phases[phase] = line.to_vec();
            }
            "cancel" => {
                self.offensives.remove(oi);
            }
            _ => return false,
        }
        true
    }
}
