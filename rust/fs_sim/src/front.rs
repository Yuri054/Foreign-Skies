//! Fronts (`front.gd`, `front_solver.gd`, `Military.step_fronts` and the commands `designate_front.gd`, `delete_front.gd`,
//! `assign_to_front.gd`, `set_front_anchors.gd`, `set_front_line.gd`, `set_front_policy.gd`): the provinces a nation wants held (the
//! border with a nation, a hand-drawn chain, or a few provinces to garrison), with armies assigned to them. Each day the armies are
//! spread along the line by strength (the player's: as detachments of their divisions, `FrontSolver`) or each sent to a province to
//! hold (the AI's), and detachments keep up with their army. Offensives are not ported, so no army is ever under their control.

use crate::military::Army;
use crate::state::{Data, GameState};
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone)]
pub struct Front {
    pub id: u32,
    pub tag: String,
    pub name: String,
    /// The nation the front faces ("" for a hand-drawn line).
    pub against: String,
    /// For a border front, a province to hold only the stretch of the border around it (0: the whole border).
    pub anchor: usize,
    pub provinces: Vec<usize>,
    pub army_ids: Vec<u32>,
    pub anchors: Vec<usize>,
    pub slots: HashMap<u32, usize>,
    pub line_stamp: i64,
    pub dirty: bool,
    pub retry: HashMap<u32, i64>,
    /// "line" or "garrison".
    pub kind: String,
    pub spread: bool,
    pub cohesion: String,
    pub order: Vec<usize>,
    pub weights: Vec<f64>,
    pub weights_day: i64,
    pub deploying: HashSet<u32>,
}

fn dist(data: &Data, a: usize, b: usize) -> f32 {
    let (p, q) = (data.map.provinces[a].center, data.map.provinces[b].center);
    let (dx, dy) = (p.0 - q.0, p.1 - q.1);
    (dx * dx + dy * dy).sqrt()
}

/// `FrontSolver.deal`: whole numbers that add up to `count`, in proportion to the weights, largest remainder first.
pub fn deal(count: i64, w: &[f64]) -> Vec<i64> {
    let mut out = vec![0i64; w.len()];
    let total: f64 = w.iter().sum();
    if total <= 0.0 || count <= 0 {
        return out;
    }
    let mut rests: Vec<(f64, i64)> = vec![];
    let mut given = 0;
    for (i, x) in w.iter().enumerate() {
        let share = count as f64 * x / total;
        out[i] = share.floor() as i64;
        given += out[i];
        rests.push((share - share.floor(), -(i as i64)));
    }
    rests.sort_by(|a, b| a.partial_cmp(b).unwrap());
    rests.reverse();
    for k in 0..(count - given) as usize {
        out[(-rests[k].1) as usize] += 1;
    }
    out
}

impl GameState {
    fn front_pos(&self, id: u32) -> Option<usize> {
        self.fronts.iter().position(|f| f.id == id)
    }

    fn army_at(&self, id: u32) -> Option<usize> {
        self.armies.iter().position(|a| a.id == id)
    }

    fn fday(&self) -> i64 {
        self.calendar.days_elapsed as i64
    }

    // ---------------------------------------------------------------- reading the border

    /// `Military.border_stretch`: the stretch of a border line nearest to a province (the run of provinces joined by land that holds
    /// `anchor`, or the one with a province nearest to it).
    pub fn border_stretch(&self, data: &Data, line: &[usize], anchor: usize) -> Vec<usize> {
        if anchor == 0 || line.is_empty() {
            return line.to_vec();
        }
        let on_line: HashSet<usize> = line.iter().copied().collect();
        let mut seen: HashSet<usize> = HashSet::new();
        let mut best: Vec<usize> = vec![];
        let mut best_d = f64::INFINITY;
        for &p in line {
            if seen.contains(&p) {
                continue;
            }
            let mut run: Vec<usize> = vec![];
            let mut todo = vec![p];
            seen.insert(p);
            let mut d = f64::INFINITY;
            while let Some(q) = todo.pop() {
                run.push(q);
                d = d.min(if q == anchor { 0.0 } else { dist(data, anchor, q) as f64 });
                for n in data.map.neighbors(q) {
                    if on_line.contains(&n) && !seen.contains(&n) {
                        seen.insert(n);
                        todo.push(n);
                    }
                }
            }
            if d < best_d {
                best_d = d;
                best = run;
            }
        }
        line.iter().copied().filter(|q| best.contains(q)).collect()
    }

    // ---------------------------------------------------------------- the commands

    /// `DesignateFront.problem`.
    pub fn designate_front_problem(&self, data: &Data, tag: &str, line: &[usize], against: &str, kind: &str) -> &'static str {
        if kind == "garrison" {
            if !self.nation_index.contains_key(tag) || line.is_empty() {
                return "Pick the provinces to guard.";
            }
            for &p in line {
                if p < 1 || p >= self.province_owner.len() || self.province_controller[p] != tag {
                    return "A garrison guards provinces you hold.";
                }
            }
            return "";
        }
        if !against.is_empty() {
            if !self.nation_index.contains_key(tag) || !self.nation_index.contains_key(against) || against == tag {
                return "Choose another nation to face.";
            }
            if self.border_provinces(data, tag, against).is_empty() {
                return "You share no border.";
            }
            return "";
        }
        if !self.nation_index.contains_key(tag) || line.is_empty() {
            return "A front needs at least one province.";
        }
        for i in 0..line.len() {
            if line[i] < 1 || line[i] >= self.province_owner.len() {
                return "Unknown province.";
            }
            if i > 0 && !data.map.neighbors(line[i - 1]).any(|n| n == line[i]) {
                return "The provinces of a front must border each other.";
            }
        }
        ""
    }

    /// `DesignateFront.execute`: returns the new front's id.
    pub fn designate_front(&mut self, data: &Data, tag: &str, name: &str, provinces: &[usize], against: &str, kind: &str, anchor: usize) -> Option<u32> {
        if !self.designate_front_problem(data, tag, provinces, against, kind).is_empty() {
            return None;
        }
        let id = self.next_front_id;
        self.next_front_id += 1;
        let anchor = if against.is_empty() { 0 } else { anchor };
        let line = if against.is_empty() {
            provinces.to_vec()
        } else {
            let border = self.border_provinces(data, tag, against);
            self.border_stretch(data, &border, anchor)
        };
        self.fronts.push(Front {
            id,
            tag: tag.to_string(),
            name: name.to_string(),
            against: against.to_string(),
            anchor,
            provinces: line,
            army_ids: vec![],
            anchors: vec![],
            slots: HashMap::new(),
            line_stamp: -1,
            dirty: true,
            retry: HashMap::new(),
            kind: kind.to_string(),
            // The player's armies spread their divisions along the line; the AI's hold a province each.
            spread: tag == self.player_tag,
            cohesion: "balanced".to_string(),
            order: vec![],
            weights: vec![],
            weights_day: -1,
            deploying: HashSet::new(),
        });
        Some(id)
    }

    /// `DeleteFront.execute`.
    pub fn delete_front(&mut self, tag: &str, front_id: u32) -> bool {
        let Some(fi) = self.front_pos(front_id) else { return false };
        if self.fronts[fi].tag != tag {
            return false;
        }
        for id in self.fronts[fi].army_ids.clone() {
            if let Some(ai) = self.army_at(id) {
                self.armies[ai].front_id = 0;
            }
        }
        self.fronts.remove(fi);
        true
    }

    /// `Military.leave_front`.
    pub fn leave_front(&mut self, army: usize) {
        let fid = self.armies[army].front_id;
        if fid == 0 {
            return;
        }
        let aid = self.armies[army].id;
        if let Some(fi) = self.front_pos(fid) {
            let f = &mut self.fronts[fi];
            f.army_ids.retain(|x| *x != aid);
            f.slots.remove(&aid);
            f.deploying.remove(&aid);
            f.dirty = true;
        }
        self.armies[army].front_id = 0;
    }

    /// `FrontSolver.root_of`: the army a stack belongs to (itself, or the army it was detached from; none if that is gone).
    pub fn root_of(&self, army: usize) -> Option<usize> {
        let p = self.armies[army].parent_id;
        if p == 0 {
            Some(army)
        } else {
            self.army_at(p)
        }
    }

    /// `FrontSolver.stacks_of`: the army itself and its detachments.
    fn stacks_of(&self, root: usize) -> Vec<usize> {
        let rid = self.armies[root].id;
        let mut out = vec![root];
        for (i, b) in self.armies.iter().enumerate() {
            if b.parent_id == rid {
                out.push(i);
            }
        }
        out
    }

    /// `AssignToFront.execute`: puts armies on a front (front 0: takes them off).
    pub fn assign_to_front(&mut self, tag: &str, front_id: u32, army_ids: &[u32]) -> bool {
        let target = self.front_pos(front_id);
        if front_id != 0 && target.map(|t| self.fronts[t].tag != tag).unwrap_or(true) {
            return false;
        }
        if army_ids.is_empty() {
            return false;
        }
        for id in army_ids {
            match self.army_at(*id) {
                Some(a) if self.armies[a].tag == tag => {}
                _ => return false,
            }
        }
        let mut roots: Vec<u32> = vec![];
        for id in army_ids {
            let ai = self.army_at(*id).unwrap();
            if let Some(r) = self.root_of(ai) {
                let rid = self.armies[r].id;
                if !roots.contains(&rid) {
                    roots.push(rid);
                }
            }
        }
        for id in roots {
            let ai = self.army_at(id).unwrap();
            self.leave_front(ai);
            if let Some(t) = target {
                self.armies[ai].front_id = self.fronts[t].id;
                self.fronts[t].army_ids.push(id);
                self.fronts[t].deploying.insert(id);
            }
        }
        if let Some(t) = target {
            self.fronts[t].dirty = true;
        }
        true
    }

    /// `SetFrontAnchors.execute`.
    pub fn set_front_anchors(&mut self, tag: &str, front_id: u32, provinces: &[usize]) -> bool {
        let Some(fi) = self.front_pos(front_id) else { return false };
        if self.fronts[fi].tag != tag || provinces.iter().any(|p| !self.fronts[fi].provinces.contains(p)) {
            return false;
        }
        if self.fronts[fi].anchors == provinces {
            return true;
        }
        self.fronts[fi].anchors = provinces.to_vec();
        self.fronts[fi].dirty = true;
        true
    }

    /// `SetFrontLine.execute`.
    pub fn set_front_line(&mut self, data: &Data, tag: &str, front_id: u32, provinces: &[usize]) -> bool {
        let Some(fi) = self.front_pos(front_id) else { return false };
        if self.fronts[fi].tag != tag || !self.fronts[fi].against.is_empty() {
            return false;
        }
        let kind = self.fronts[fi].kind.clone();
        if !self.designate_front_problem(data, tag, provinces, "", &kind).is_empty() {
            return false;
        }
        let f = &mut self.fronts[fi];
        f.provinces = provinces.to_vec();
        f.order.clear();
        f.weights_day = -1;
        f.dirty = true;
        true
    }

    /// `SetFrontPolicy.execute`: only the cohesion can be set.
    pub fn set_front_policy(&mut self, tag: &str, front_id: u32, key: &str, value: &str) -> bool {
        let Some(fi) = self.front_pos(front_id) else { return false };
        if self.fronts[fi].tag != tag || key != "cohesion" || !["rigid", "balanced", "flexible"].contains(&value) {
            return false;
        }
        self.fronts[fi].cohesion = value.to_string();
        true
    }

    // ---------------------------------------------------------------- the daily step

    /// `Military._route_blocked`: whether a route runs through a province where enemy armies, together, are stronger than this one.
    fn route_blocked(&self, data: &Data, army: usize, route: &[usize]) -> bool {
        let mine = self.armies[army].power(&data.military);
        for &province in route {
            let mut theirs = 0.0;
            for b in &self.armies {
                if b.province == province && !b.embarked() && self.at_war(&self.armies[army].tag, &b.tag) {
                    theirs += b.power(&data.military);
                }
            }
            if theirs > mine {
                return true;
            }
        }
        false
    }

    /// `Military.step_fronts`: spreads each front's armies along its line and sends idle ones to their province.
    pub fn step_fronts(&mut self, data: &Data) {
        let mut routes_left = data.military.front_paths_per_day;
        for fi in 0..self.fronts.len() {
            if !self.fronts[fi].against.is_empty() && self.fronts[fi].line_stamp != self.control_version as i64 {
                // A border front follows the war: the line is read again when anything has changed hands.
                self.fronts[fi].line_stamp = self.control_version as i64;
                let (tag, against, anchor) = (self.fronts[fi].tag.clone(), self.fronts[fi].against.clone(), self.fronts[fi].anchor);
                let border = self.border_provinces(data, &tag, &against);
                let line = self.border_stretch(data, &border, anchor);
                if line != self.fronts[fi].provinces {
                    self.fronts[fi].provinces = line;
                    self.fronts[fi].dirty = true;
                }
            }
            let live: Vec<u32> = self.fronts[fi].army_ids.iter().copied().filter(|id| self.army_at(*id).is_some()).collect();
            if live.len() != self.fronts[fi].army_ids.len() {
                self.fronts[fi].army_ids = live;
                self.fronts[fi].dirty = true;
            }
            if self.fronts[fi].provinces.is_empty() {
                self.fronts[fi].slots.clear();
                continue;
            }
            if self.fronts[fi].spread {
                self.fronts[fi].slots.clear();
                routes_left = self.solver_step(data, fi, routes_left);
                continue;
            }
            if self.fronts[fi].dirty {
                self.deal_slots(data, fi);
                self.fronts[fi].dirty = false;
            }
            for id in self.fronts[fi].army_ids.clone() {
                let ai = self.army_at(id).unwrap();
                let slot = self.fronts[fi].slots.get(&id).copied().unwrap_or(0);
                if slot == 0 || self.armies[ai].province == slot || !self.armies[ai].path.is_empty() || self.armies[ai].fighting {
                    continue;
                }
                if self.fday() < self.fronts[fi].retry.get(&id).copied().unwrap_or(-1) || routes_left <= 0 {
                    continue;
                }
                routes_left -= 1;
                let (tag, speed, from) = (self.armies[ai].tag.clone(), self.armies[ai].speed(&data.military), self.armies[ai].province);
                let route = self.find_path(data, &tag, speed, from, slot);
                if route.is_empty() || self.route_blocked(data, ai, &route) {
                    let day = self.fday();
                    self.fronts[fi].retry.insert(id, day + 10);
                    continue;
                }
                self.armies[ai].move_days_left = self.move_days(data, &tag, speed, from, route[0]);
                self.armies[ai].path = route;
                self.armies[ai].still_days = 0;
            }
        }
    }

    /// `Military._deal_slots`: gives every army a province of the line to hold, keeping the men spread evenly.
    fn deal_slots(&mut self, data: &Data, fi: usize) {
        self.fronts[fi].slots.clear();
        self.fronts[fi].retry.clear();
        let f = &self.fronts[fi];
        let mut spots: Vec<usize> = f.anchors.iter().copied().filter(|p| f.provinces.contains(p)).collect();
        if spots.is_empty() {
            spots = f.provinces.clone();
        }
        let mut held: HashMap<usize, f64> = spots.iter().map(|&p| (p, 0.0)).collect();
        let mut list: Vec<usize> = f.army_ids.iter().map(|id| self.army_at(*id).unwrap()).collect();
        let mil = &data.military;
        list.sort_by(|&x, &y| self.armies[y].men(mil).partial_cmp(&self.armies[x].men(mil)).unwrap().then(self.armies[x].id.cmp(&self.armies[y].id)));
        let mut slots: Vec<(u32, usize)> = vec![];
        for a in list {
            let mut best = 0usize;
            for &p in &spots {
                if best == 0
                    || held[&p] < held[&best] - 0.5
                    || ((held[&p] - held[&best]).abs() <= 0.5 && dist(data, self.armies[a].province, p) < dist(data, self.armies[a].province, best))
                {
                    best = p;
                }
            }
            slots.push((self.armies[a].id, best));
            *held.get_mut(&best).unwrap() += self.armies[a].men(mil);
        }
        for (id, p) in slots {
            self.fronts[fi].slots.insert(id, p);
        }
    }

    // ---------------------------------------------------------------- FrontSolver

    /// `FrontSolver.order_line`: the provinces of a line in order along it.
    pub fn order_line(&self, data: &Data, provinces: &[usize]) -> Vec<usize> {
        let mut left: Vec<usize> = provinces.to_vec();
        let mut out = vec![];
        if provinces.is_empty() {
            return out;
        }
        let mut start = provinces[0];
        let (mut kx, mut ky) = (f32::INFINITY, f32::INFINITY);
        for &p in provinces {
            let on_line = data.map.neighbors(p).filter(|n| left.contains(n)).count() as f32;
            let cx = data.map.provinces[p].center.0;
            if on_line < kx || (on_line == kx && cx < ky) {
                kx = on_line;
                ky = cx;
                start = p;
            }
        }
        let mut here = start;
        loop {
            out.push(here);
            left.retain(|&x| x != here);
            if left.is_empty() {
                break;
            }
            let mut next = 0usize;
            let mut best = f64::INFINITY;
            for n in data.map.neighbors(here) {
                if left.contains(&n) && (dist(data, here, n) as f64) < best {
                    best = dist(data, here, n) as f64;
                    next = n;
                }
            }
            if next == 0 {
                for &p in &left {
                    if (dist(data, here, p) as f64) < best {
                        best = dist(data, here, p) as f64;
                        next = p;
                    }
                }
            }
            here = next;
        }
        out
    }

    /// `FrontSolver.weights`: how much each province of an ordered line should draw.
    fn line_weights(&self, data: &Data, tag: &str, line: &[usize]) -> Vec<f64> {
        let c = &data.military;
        let mut out = vec![];
        for &p in line {
            let mut enemy = 0i64;
            for n in data.map.neighbors(p) {
                for b in &self.armies {
                    if b.province == n && !b.embarked() && self.at_war(tag, &b.tag) {
                        enemy += b.units.len() as i64;
                    }
                }
            }
            let mut w = 1.0 + (enemy as f64 * c.front_enemy_weight).round();
            w += c.front_fort_weight * self.level_of(p, "fortification") as f64;
            out.push(w);
        }
        out
    }

    fn nearest_index(&self, data: &Data, line: &[usize], p: usize) -> usize {
        let mut best = 0;
        let mut best_d = f64::INFINITY;
        for (i, &q) in line.iter().enumerate() {
            let d = dist(data, p, q) as f64;
            if d < best_d {
                best_d = d;
                best = i;
            }
        }
        best
    }

    /// `FrontSolver.sectors_of`: one contiguous sector of the ordered line per army, by its share of the divisions: army id ->
    /// (first index, one past the last).
    fn sectors_of(&self, data: &Data, line: &[usize], w: &[f64], roots: &[usize]) -> HashMap<u32, (usize, usize)> {
        let mut out = HashMap::new();
        if roots.is_empty() || line.is_empty() {
            return out;
        }
        let index: HashMap<usize, usize> = line.iter().enumerate().map(|(i, &p)| (p, i)).collect();
        let mut placed: Vec<(f64, u32, i64)> = vec![];
        let mut total_units = 0i64;
        for &root in roots {
            let (mut sum, mut n, mut units) = (0.0, 0i64, 0i64);
            for s in self.stacks_of(root) {
                let a = &self.armies[s];
                units += a.units.len() as i64;
                let at = if let Some(&last) = a.path.last() { last } else { a.province };
                sum += match index.get(&at) {
                    Some(&i) => i as f64,
                    None => self.nearest_index(data, line, at) as f64,
                };
                n += 1;
            }
            placed.push((sum / crate::gd::maxf(n as f64, 1.0), self.armies[root].id, units.max(1)));
            total_units += units.max(1);
        }
        placed.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap().then(a.1.cmp(&b.1)));
        let total_w: f64 = w.iter().sum();
        let (mut start, mut done_units, mut cumulative) = (0usize, 0i64, 0.0);
        for k in 0..placed.len() {
            done_units += placed[k].2;
            let boundary = total_w * done_units as f64 / total_units as f64;
            let mut end = start;
            while end < line.len() && (cumulative + w[end] * 0.5 <= boundary || end == start) {
                cumulative += w[end];
                end += 1;
            }
            // Leave at least one province for each army still to come, while there are enough.
            end = end.min((start + 1).max((line.len() as i64 - (placed.len() - k - 1) as i64).max(0) as usize));
            if k == placed.len() - 1 {
                end = line.len();
            }
            if start >= line.len() {
                out.insert(placed[k].1, (line.len() - 1, line.len()));
                continue;
            }
            out.insert(placed[k].1, (start, end.max(start + 1)));
            start = end.max(start + 1);
        }
        out
    }

    /// `FrontSolver.step`: deals and moves the divisions of every army on a spreading front. Returns what is left of the day's budget
    /// of route searches.
    fn solver_step(&mut self, data: &Data, fi: usize, mut routes_left: i64) -> i64 {
        if self.fronts[fi].dirty || self.fronts[fi].order.is_empty() || self.fronts[fi].order.len() != self.fronts[fi].provinces.len() {
            let order = self.order_line(data, &self.fronts[fi].provinces.clone());
            self.fronts[fi].order = order;
            self.fronts[fi].dirty = false;
            self.fronts[fi].weights_day = -1;
        }
        let day = self.fday();
        if self.fronts[fi].weights_day < 0 || day - self.fronts[fi].weights_day >= data.military.front_reweigh_days {
            let (tag, order) = (self.fronts[fi].tag.clone(), self.fronts[fi].order.clone());
            self.fronts[fi].weights = self.line_weights(data, &tag, &order);
            self.fronts[fi].weights_day = day;
        }
        let roots: Vec<usize> = self.fronts[fi].army_ids.iter().filter_map(|id| self.army_at(*id)).collect();
        let (order, weights) = (self.fronts[fi].order.clone(), self.fronts[fi].weights.clone());
        let sectors = self.sectors_of(data, &order, &weights, &roots);
        let fallback = self.is_fallback_front(data, fi);
        for &root in &roots {
            let (a, b) = sectors[&self.armies[root].id];
            let line: Vec<usize> = order[a..b].to_vec();
            let w: Vec<f64> = weights[a..b].to_vec();
            // (a launched spearhead has the army's stacks in hand: offensives are not ported)
            routes_left = self.redeploy(data, fi, root, &line, &w, routes_left);
            if fallback {
                for s in self.stacks_of(root) {
                    let on = self.armies[s].path.is_empty() && line.contains(&self.armies[s].province);
                    self.armies[s].prepared = on;
                }
            }
        }
        routes_left
    }

    /// `Front.is_fallback`: a line in the nation's own ground that touches no enemy.
    fn is_fallback_front(&self, data: &Data, fi: usize) -> bool {
        let f = &self.fronts[fi];
        if f.kind != "line" || !f.against.is_empty() {
            return false;
        }
        for &p in &f.provinces {
            for n in data.map.neighbors(p) {
                let holder = &self.province_controller[n];
                if *holder != f.tag && self.at_war(&f.tag, holder) {
                    return false;
                }
            }
        }
        true
    }

    fn reach(&self, data: &Data, fi: usize) -> i64 {
        match self.fronts[fi].cohesion.as_str() {
            "rigid" => data.military.front_rigid_hops,
            "flexible" => -1,
            _ => data.military.front_balanced_hops,
        }
    }

    /// `FrontSolver._nearest_short`.
    fn nearest_short(&self, data: &Data, line: &[usize], want: &[i64], have: &[i64], from_index: i64, from: usize, reach: i64) -> i64 {
        let mut best = -1i64;
        let mut best_d = f64::INFINITY;
        for i in 0..line.len() {
            if have[i] >= want[i] {
                continue;
            }
            let d: f64;
            if from_index >= 0 {
                d = (i as i64 - from_index).abs() as f64;
                if reach >= 0 && d > reach as f64 {
                    continue;
                }
            } else {
                d = dist(data, from, line[i]) as f64;
            }
            if d < best_d {
                best_d = d;
                best = i as i64;
            }
        }
        best
    }

    /// `FrontSolver._giver`: the stack that should give `surplus` divisions: the one whose size is nearest to it.
    fn giver(&self, stacks: &[usize], surplus: i64) -> Option<usize> {
        let mut best: Option<usize> = None;
        for &s in stacks {
            if self.armies[s].units.is_empty() {
                continue;
            }
            let diff = (self.armies[s].units.len() as i64 - surplus).abs();
            let better = match best {
                None => true,
                Some(b) => {
                    let bd = (self.armies[b].units.len() as i64 - surplus).abs();
                    diff < bd || (diff == bd && self.armies[s].parent_id != 0 && self.armies[b].parent_id == 0)
                }
            };
            if better {
                best = Some(s);
            }
        }
        best
    }

    /// `FrontSolver.detach`: splits `count` divisions off a stack into a new detachment of its army; returns its index.
    fn detach(&mut self, from: usize, count: usize) -> usize {
        let root = self.root_of(from).unwrap();
        let (tag, province) = (self.armies[from].tag.clone(), self.armies[from].province);
        let name = if self.armies[from].parent_id != 0 { self.armies[from].name.clone() } else { format!("{}, detachment", self.armies[from].name) };
        let rid = self.armies[root].id;
        let d = self.new_army(&tag, &name, province);
        self.armies[d].parent_id = rid;
        self.armies[d].general_skill = self.armies[root].general_skill;
        let at = self.armies[from].units.len() - count;
        let moved: Vec<_> = self.armies[from].units.drain(at..).collect();
        self.armies[d].units = moved;
        self.armies[d].still_days = self.armies[from].still_days;
        d
    }

    /// `FrontSolver._redeploy`: moves an army's surplus divisions to the provinces of its stretch of line that are short of them.
    fn redeploy(&mut self, data: &Data, fi: usize, root: usize, line: &[usize], w: &[f64], mut routes_left: i64) -> i64 {
        let stacks = self.stacks_of(root);
        let total: i64 = stacks.iter().map(|&s| self.armies[s].units.len() as i64).sum();
        let want = deal(total, w);
        let index: HashMap<usize, usize> = line.iter().enumerate().map(|(i, &p)| (p, i)).collect();
        let mut have = vec![0i64; line.len()];
        // province -> the stacks idle there that may give, in the order the provinces were first met
        let mut idle: Vec<(usize, Vec<u32>)> = vec![];
        for &s in &stacks {
            let a = &self.armies[s];
            if a.embarked() {
                continue;
            }
            let mut at = if let Some(&last) = a.path.last() { last } else { a.province };
            if a.pin != 0 {
                at = a.pin;
            }
            if let Some(&i) = index.get(&at) {
                have[i] += a.units.len() as i64;
            }
            if a.path.is_empty() && a.pin == 0 && !a.fighting {
                match idle.iter_mut().find(|(p, _)| *p == a.province) {
                    Some(slot) => slot.1.push(a.id),
                    None => idle.push((a.province, vec![a.id])),
                }
            }
        }
        // Every province has its share (counting those on their way): the army is in place, and from now on the cohesion limit holds.
        let rid = self.armies[root].id;
        let mut placed = true;
        for i in 0..line.len() {
            placed = placed && have[i] >= want[i];
        }
        if placed {
            self.fronts[fi].deploying.remove(&rid);
        }
        let reach = if self.fronts[fi].deploying.contains(&rid) { -1 } else { self.reach(data, fi) };
        let garrison = self.fronts[fi].kind == "garrison";
        for k in 0..idle.len() {
            let p = idle[k].0;
            let mut surplus: i64 = match index.get(&p) {
                Some(&i) => have[i] - want[i],
                None => idle[k].1.iter().map(|id| self.armies[self.army_at(*id).unwrap()].units.len() as i64).sum(),
            };
            while surplus > 0 && routes_left > 0 {
                // A garrison's provinces are not a line: what is short is found by distance, anywhere.
                let from_index = if garrison { -1 } else { index.get(&p).map(|&i| i as i64).unwrap_or(-1) };
                let to = self.nearest_short(data, line, &want, &have, from_index, p, if garrison { -1 } else { reach });
                if to < 0 {
                    break;
                }
                let to = to as usize;
                let stack_idx: Vec<usize> = idle[k].1.iter().map(|id| self.army_at(*id).unwrap()).collect();
                let Some(stack) = self.giver(&stack_idx, surplus) else { break };
                let count = surplus.min(want[to] - have[to]).min(self.armies[stack].units.len() as i64);
                let sid = self.armies[stack].id;
                if self.fday() < self.fronts[fi].retry.get(&sid).copied().unwrap_or(-1) {
                    break;
                }
                routes_left -= 1;
                let (tag, speed, from) = (self.armies[stack].tag.clone(), self.armies[stack].speed(&data.military), self.armies[stack].province);
                let route = self.find_path(data, &tag, speed, from, line[to]);
                if route.is_empty() || self.route_blocked(data, stack, &route) {
                    let day = self.fday();
                    self.fronts[fi].retry.insert(sid, day + 10);
                    break;
                }
                let mover = if (count as usize) < self.armies[stack].units.len() {
                    self.detach(stack, count as usize)
                } else {
                    idle[k].1.retain(|x| *x != sid);
                    self.army_at(sid).unwrap()
                };
                let mspeed = self.armies[mover].speed(&data.military);
                let first = route[0];
                self.armies[mover].move_days_left = self.move_days(data, &tag, mspeed, self.armies[mover].province, first);
                self.armies[mover].path = route;
                self.armies[mover].still_days = 0;
                have[to] += count;
                surplus -= count;
                if let Some(&i) = index.get(&p) {
                    have[i] -= count;
                }
            }
        }
        routes_left
    }

    /// `FrontSolver.step_detachments`: detachments keep up with their army: two of one army idle in the same province merge, those
    /// of an army that is not on a spreading front march back to it, and a detachment whose army is gone takes its place. A pinned
    /// stack that has arrived is let go. Runs each day.
    pub fn step_detachments(&mut self, data: &Data) {
        let ids: Vec<u32> = self.armies.iter().map(|a| a.id).collect();
        for id in ids {
            let Some(ai) = self.army_at(id) else { continue };
            self.armies[ai].prepared = false;
            if self.armies[ai].pin != 0 && self.armies[ai].path.is_empty() {
                self.armies[ai].pin = 0;
            }
            if self.armies[ai].parent_id == 0 {
                continue;
            }
            let Some(root) = self.army_at(self.armies[ai].parent_id) else {
                self.promote(ai);
                continue;
            };
            self.armies[ai].general_skill = self.armies[root].general_skill;
            let a = &self.armies[ai];
            if !a.path.is_empty() || a.fighting || a.embarked() || a.pin != 0 {
                continue;
            }
            let rfront = self.armies[root].front_id;
            let spreading = rfront != 0 && self.front_pos(rfront).map(|f| self.fronts[f].spread).unwrap_or(false);
            // Merge with another idle stack of the same army here (into the army itself if it is here).
            let mut host: Option<usize> = None;
            for (bi, b) in self.armies.iter().enumerate() {
                if b.province == self.armies[ai].province && !b.embarked() && bi != ai && self.root_of(bi) == Some(root) && b.path.is_empty() && !b.fighting && b.pin == 0 && (host.is_none() || bi == root) {
                    host = Some(bi);
                }
            }
            if let Some(h) = host {
                let units = std::mem::take(&mut self.armies[ai].units);
                self.armies[h].units.extend(units);
                let still = self.armies[ai].still_days;
                self.armies[h].still_days = self.armies[h].still_days.min(still);
                self.armies.remove(ai);
                continue;
            }
            if !spreading {
                let goal = if let Some(&l) = self.armies[root].path.last() { l } else { self.armies[root].province };
                if goal != self.armies[ai].province {
                    let (tag, speed, from) = (self.armies[ai].tag.clone(), self.armies[ai].speed(&data.military), self.armies[ai].province);
                    let route = self.find_path(data, &tag, speed, from, goal);
                    if !route.is_empty() {
                        self.armies[ai].move_days_left = self.move_days(data, &tag, speed, from, route[0]);
                        self.armies[ai].path = route;
                    }
                }
            }
        }
    }

    /// `FrontSolver._promote`: the army is gone and this detachment is left: it becomes the army.
    fn promote(&mut self, ai: usize) {
        let old = self.armies[ai].parent_id;
        let id = self.armies[ai].id;
        self.armies[ai].parent_id = 0;
        if let Some(stripped) = self.armies[ai].name.strip_suffix(", detachment") {
            self.armies[ai].name = stripped.to_string();
        }
        for b in &mut self.armies {
            if b.parent_id == old {
                b.parent_id = id;
            }
        }
        for f in &mut self.fronts {
            if let Some(i) = f.army_ids.iter().position(|x| *x == old) {
                f.army_ids[i] = id;
                self.armies[ai].front_id = f.id;
                f.deploying.remove(&old);
                f.dirty = true;
            }
        }
    }
}

#[allow(dead_code)]
fn _unused(_: &Army) {}
