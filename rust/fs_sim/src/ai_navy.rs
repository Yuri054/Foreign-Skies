//! The AI at sea (`scripts/ai/ai_navy.gd`) and its landings (`ai_landing.gd`). A nation at war sorts its fleets by role in port (transports and
//! submarines apart, cruisers and destroyers detached as patrols), then gives every warfleet a sea zone: the cordon that would seal an enemy's
//! ports from the open sea, the waters by its own ports where enemy ships lie, and the zone a landing needs an escort in. A fleet goes only where
//! its power, with what is already sent there, is at least the nation's required odds times the enemy's power in and around the zone. Building
//! ships is part of the monthly budget. A landing gathers armies and transports in a port, waits until the ships hold the zone, and sends them.

use crate::gd::{clampf, maxf, sort_custom};
use crate::state::{Data, Fleet, GameState};
use serde_json::Value;
use std::collections::{HashMap, HashSet};

/// A landing being prepared (`GameState.ai_landing`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Landing {
    pub enemy: String,
    pub target: usize,
    pub port: usize,
    pub fleet: u32,
    pub armies: Vec<u32>,
    /// "gather", "escort" or "sail".
    pub phase: String,
    pub started: i64,
    pub zone: usize,
}

fn nf(c: &Value, k: &str) -> f64 {
    c[k].as_f64().unwrap_or_else(|| panic!("ai.json: navy.{k} is not a number"))
}

/// What the AI keeps for the day about the sea (`AINavy._weight_cache`, `_cordons`).
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct NavyCaches {
    pub weight_day: i64,
    pub weights: HashMap<String, Vec<(usize, f64)>>,
    pub cordons: HashMap<String, Vec<usize>>,
}

impl GameState {
    // ---------------------------------------------------------------- roles

    /// `Navy.fleets_of`: a nation's fleets, in id order (indices into `fleets`).
    pub fn fleets_of(&self, tag: &str) -> Vec<usize> {
        let mut v: Vec<usize> = (0..self.fleets.len()).filter(|&i| self.fleets[i].tag == tag).collect();
        v.sort_by_key(|&i| self.fleets[i].id);
        v
    }

    /// `AINavy.role`: "transport" (carries men, does not fight), "raider" (only submarines) or "warfleet".
    pub fn ai_role(f: &Fleet) -> &'static str {
        let (mut war, mut subs) = (0, 0);
        for s in &f.ships {
            if s.kind == "submarine" {
                subs += 1;
            } else if s.kind != "transport" {
                war += 1;
            }
        }
        if war == 0 && subs == 0 {
            "transport"
        } else if war == 0 {
            "raider"
        } else {
            "warfleet"
        }
    }

    fn ai_free(&self, f: &Fleet) -> bool {
        f.port > 0 && f.path.is_empty() && !f.entering && !f.fighting && f.landing == 0 && !self.ai_carrying.borrow().contains(&f.id)
    }

    fn is_moving(f: &Fleet) -> bool {
        !f.path.is_empty() || f.entering
    }

    /// `AINavy.step`.
    pub fn ai_navy_step(&mut self, data: &Data, tag: &str) {
        if self.ai_enemies(tag).is_empty() {
            return;
        }
        self.ai_navy.entry(tag.to_string()).or_default();
        *self.ai_carrying.borrow_mut() = self.armies.iter().filter(|a| a.fleet_id > 0).map(|a| a.fleet_id).collect();
        self.ai_organize(data, tag);
        self.ai_station(data, tag);
    }

    /// `AINavy._organize`: splits mixed fleets in port.
    fn ai_organize(&mut self, data: &Data, tag: &str) {
        let c = &data.ai.raw["navy"];
        let mut splits = 0;
        let mut patrols = self.fleets_of(tag).iter().filter(|&&i| self.fleets[i].name.ends_with("patrol")).count() as i64;
        for fi in self.fleets_of(tag) {
            let fid = self.fleets[fi].id;
            // A fleet may need more than one split (transports, then submarines, then a patrol).
            for _ in 0..3 {
                if splits >= nf(c, "max_splits") as i64 {
                    return;
                }
                let Some(fi) = self.fleet_index(fid) else { break };
                let f = &self.fleets[fi];
                if !self.ai_free(f) || f.ships.len() < 2 {
                    break;
                }
                let (carry, subs) = (Self::count_of(f, "transport"), Self::count_of(f, "submarine"));
                let mut picked: Vec<usize> = vec![];
                let mut label = String::new();
                if carry > 0 && carry < f.ships.len() {
                    picked = Self::indices_of_type(f, "transport", carry);
                    label = format!("{} transports", f.name);
                } else if subs > 0 && subs < f.ships.len() {
                    picked = Self::indices_of_type(f, "submarine", subs);
                    label = format!("{} submarines", f.name);
                } else if Self::count_of(f, "dreadnought") > 0 && patrols < nf(c, "max_patrols") as i64 && (Self::count_of(f, "cruiser") + Self::count_of(f, "destroyer")) as i64 >= nf(c, "patrol_min_screen") as i64 {
                    picked = Self::indices_of_type(f, "cruiser", Self::count_of(f, "cruiser") >> 1);
                    picked.extend(Self::indices_of_type(f, "destroyer", Self::count_of(f, "destroyer") >> 1));
                    label = format!("{} patrol", f.name);
                    patrols += 1;
                }
                if picked.is_empty() || picked.len() >= f.ships.len() {
                    break;
                }
                let Some(new_id) = self.split_fleet(tag, fid, &picked) else { break };
                let ni = self.fleet_index(new_id).unwrap();
                self.fleets[ni].name = label;
                splits += 1;
            }
        }
    }

    /// `SplitFleet.indices_of_type`.
    pub fn indices_of_type(f: &Fleet, kind: &str, count: usize) -> Vec<usize> {
        let mut out = vec![];
        for (i, s) in f.ships.iter().enumerate() {
            if out.len() >= count {
                break;
            }
            if s.kind == kind {
                out.push(i);
            }
        }
        out
    }

    /// `SplitFleet.execute`: detaches some of a fleet's ships into a new fleet that stands where it does. Returns the new fleet's id.
    pub fn split_fleet(&mut self, tag: &str, fleet_id: u32, indices: &[usize]) -> Option<u32> {
        let fi = self.fleet_index(fleet_id)?;
        if self.fleets[fi].tag != tag || self.fleets[fi].fighting || indices.is_empty() || indices.len() >= self.fleets[fi].ships.len() {
            return None;
        }
        if !self.armies_aboard(fleet_id).is_empty() {
            return None;
        }
        let mut seen: Vec<usize> = vec![];
        for &i in indices {
            if i >= self.fleets[fi].ships.len() || seen.contains(&i) {
                return None;
            }
            seen.push(i);
        }
        let (port, name) = (self.fleets[fi].port, format!("{} detachment", self.fleets[fi].name));
        let picked_ships: Vec<crate::state::Ship> = indices.iter().map(|&i| self.fleets[fi].ships[i].clone()).collect();
        // remove from the back so that the positions stay true
        let mut order = indices.to_vec();
        order.sort_by(|a, b| b.cmp(a));
        for i in order {
            self.fleets[fi].ships.remove(i);
        }
        let ni = self.new_fleet(tag, &name, port);
        let fi = self.fleet_index(fleet_id)?;
        let (zone, mission, path, dest_port, entering, move_days_left) = {
            let f = &self.fleets[fi];
            (f.zone, f.mission.clone(), f.path.clone(), f.dest_port, f.entering, f.move_days_left)
        };
        let d = &mut self.fleets[ni];
        d.ships = picked_ships;
        d.zone = zone;
        d.mission = mission;
        d.path = path;
        d.dest_port = dest_port;
        d.entering = entering;
        d.move_days_left = move_days_left;
        Some(d.id)
    }

    /// `MergeFleets.execute`: combines fleets of one nation standing together into the first one listed.
    pub fn merge_fleets(&mut self, tag: &str, fleet_ids: &[u32]) -> bool {
        if fleet_ids.len() < 2 {
            return false;
        }
        let Some(ti) = self.fleet_index(fleet_ids[0]) else { return false };
        if self.fleets[ti].tag != tag || self.fleets[ti].fighting {
            return false;
        }
        let (port, zone) = (self.fleets[ti].port, self.fleets[ti].zone);
        for &id in &fleet_ids[1..] {
            match self.fleet_index(id) {
                Some(fi) if id != fleet_ids[0] && self.fleets[fi].tag == tag && self.fleets[fi].port == port && self.fleets[fi].zone == zone && !self.fleets[fi].fighting => {}
                _ => return false,
            }
        }
        let target_id = fleet_ids[0];
        for &id in &fleet_ids[1..] {
            let fi = self.fleet_index(id).unwrap();
            let f = self.fleets.remove(fi);
            let ti = self.fleet_index(target_id).unwrap();
            self.fleets[ti].ships.extend(f.ships);
            for a in &mut self.armies {
                if a.fleet_id == id {
                    a.fleet_id = target_id;
                }
            }
        }
        let ti = self.fleet_index(target_id).unwrap();
        let t = &mut self.fleets[ti];
        t.path.clear();
        t.landing = 0;
        t.entering = false;
        t.dest_port = 0;
        true
    }

    // ---------------------------------------------------------------- where the enemy is

    /// `AINavy.enemy_map`: enemy fighting power bearing on each sea zone.
    pub fn ai_enemy_map(&self, data: &Data, tag: &str) -> HashMap<usize, f64> {
        let c = &data.ai.raw["navy"];
        let mut out: HashMap<usize, f64> = HashMap::new();
        for f in &self.fleets {
            if f.tag == tag || !self.at_war(tag, &f.tag) {
                continue;
            }
            let p = self.fleet_power(data, f);
            if p <= 0.0 {
                continue;
            }
            let (bases, weight): (Vec<usize>, f64) = if f.port > 0 {
                (data.map.zones_of_port(f.port), nf(c, "port_share"))
            } else if f.zone > 0 {
                (vec![f.zone], 1.0)
            } else {
                (vec![], 1.0)
            };
            for z in bases {
                *out.entry(z).or_insert(0.0) += p * weight;
                for &n in data.map.sea_neighbors(z) {
                    *out.entry(n).or_insert(0.0) += p * weight * nf(c, "adj_decay");
                }
            }
        }
        out
    }

    /// `AINavy.enemy_power_at`.
    pub fn ai_enemy_power_at(&self, data: &Data, tag: &str, zone: usize) -> f64 {
        self.ai_enemy_map(data, tag).get(&zone).copied().unwrap_or(0.0)
    }

    /// `AINavy._weights`: `Blockade.port_weights`, kept for the day.
    fn ai_weights(&self, data: &Data, tag: &str) -> Vec<(usize, f64)> {
        let today = self.calendar.days_elapsed as i64;
        let mut cache = self.ai_navy_caches.borrow_mut();
        if cache.weight_day != today {
            cache.weights.clear();
            cache.weight_day = today;
        }
        if let Some(w) = cache.weights.get(tag) {
            return w.clone();
        }
        let w = self.port_weights(data, tag);
        cache.weights.insert(tag.to_string(), w.clone());
        w
    }

    // ---------------------------------------------------------------- cordons

    /// `AINavy.cordon_zones`: the zones that, held together, would cut an enemy's ports off from the open sea (kept for a few days).
    pub fn ai_cordon_zones(&self, data: &Data, enemy: &str) -> Vec<usize> {
        let key = format!("{enemy}:{}:{}", self.owner_version, self.calendar.days_elapsed as i64 / 6);
        if let Some(k) = self.ai_navy_caches.borrow().cordons.get(&key) {
            return k.clone();
        }
        if self.ai_navy_caches.borrow().cordons.len() > 200 {
            self.ai_navy_caches.borrow_mut().cordons.clear();
        }
        let out = self.ai_cordon_search(data, enemy);
        self.ai_navy_caches.borrow_mut().cordons.insert(key, out.clone());
        out
    }

    fn outlet_zones(data: &Data) -> Vec<usize> {
        (1..data.map.sea_zone_names.len()).filter(|&z| data.navy.blockade.outlets.contains(&data.map.sea_zone_names[z])).collect()
    }

    fn ai_cordon_search(&self, data: &Data, enemy: &str) -> Vec<usize> {
        let mut out: Vec<usize> = vec![];
        let mut starts: Vec<usize> = self.ai_weights(data, enemy).iter().map(|w| w.0).collect();
        starts.sort();
        if starts.is_empty() {
            return out;
        }
        let outlets = Self::outlet_zones(data);
        for _ in 0..nf(&data.ai.raw["navy"], "cordon_max") as i64 {
            let path = Self::ai_sea_route(data, &starts, &outlets, &out);
            if path.is_empty() {
                return out;
            }
            let mut pick = 0;
            let mut best = f64::INFINITY;
            for &z in &path {
                let mut score = data.map.sea_neighbors(z).len() as f64 + if starts.contains(&z) { 4.0 } else { 0.0 } + if outlets.contains(&z) { 3.0 } else { 0.0 };
                if data.map.sea_neighbors(z).iter().any(|n| starts.contains(n)) {
                    score += 1.5;
                }
                if score < best - 0.000001 {
                    best = score;
                    pick = z;
                }
            }
            out.push(pick);
        }
        out
    }

    /// `AINavy._route`: a shortest route (fewest zones) from any start to any goal avoiding the blocked zones.
    fn ai_sea_route(data: &Data, starts: &[usize], goals: &[usize], blocked: &[usize]) -> Vec<usize> {
        let mut prev: HashMap<usize, usize> = HashMap::new();
        let mut seen: HashSet<usize> = HashSet::new();
        let mut queue: Vec<usize> = vec![];
        for &z in starts {
            if !blocked.contains(&z) {
                seen.insert(z);
                queue.push(z);
            }
        }
        let mut i = 0;
        while i < queue.len() {
            let z = queue[i];
            i += 1;
            if goals.contains(&z) {
                let mut path = vec![z];
                while let Some(&p) = prev.get(&path[0]) {
                    path.insert(0, p);
                }
                return path;
            }
            for &n in data.map.sea_neighbors(z) {
                if !seen.contains(&n) && !blocked.contains(&n) {
                    seen.insert(n);
                    prev.insert(n, z);
                    queue.push(n);
                }
            }
        }
        vec![]
    }

    // ---------------------------------------------------------------- stationing

    /// `AINavy.targets`: what each sea zone is worth to the nation now: (importance by zone, cordon zones, offence zones).
    fn ai_targets(&self, data: &Data, tag: &str, enemies_at: &HashMap<usize, f64>) -> (HashMap<usize, f64>, HashSet<usize>, HashSet<usize>) {
        let c = &data.ai.raw["navy"];
        let mut value: HashMap<usize, f64> = HashMap::new();
        let mut cordon: HashSet<usize> = HashSet::new();
        let mut offence: HashSet<usize> = HashSet::new();
        let mut trade: HashMap<String, f64> = HashMap::new();
        let mut biggest = 0.0;
        let enemies = self.ai_enemies(tag);
        for e in &enemies {
            let mut sum = 0.0;
            for (_, w) in self.ai_weights(data, e) {
                sum += w;
            }
            trade.insert(e.clone(), sum);
            biggest = maxf(biggest, sum);
        }
        for e in &enemies {
            let zones = self.ai_cordon_zones(data, e);
            let share = if biggest > 0.0 { trade[e] / biggest } else { 0.0 };
            for &z in &zones {
                *value.entry(z).or_insert(0.0) += nf(c, "w_blockade") * share / zones.len() as f64;
                cordon.insert(z);
                offence.insert(z);
            }
        }
        let weights = self.ai_weights(data, tag);
        let mut total = 0.0;
        for (_, w) in &weights {
            total += w;
        }
        for (z, w) in &weights {
            if enemies_at.get(z).copied().unwrap_or(0.0) > 0.0 {
                *value.entry(*z).or_insert(0.0) += nf(c, "w_defend") * w / total;
            }
        }
        for f in &self.fleets {
            if f.tag != tag && self.at_war(tag, &f.tag) && f.zone > 0 && f.port == 0 && self.fleet_power(data, f) >= 1.0 {
                *value.entry(f.zone).or_insert(0.0) += nf(c, "w_kill");
                offence.insert(f.zone);
            }
        }
        if let Some(l) = self.ai_landing.get(tag) {
            if l.zone > 0 {
                *value.entry(l.zone).or_insert(0.0) += nf(c, "w_escort");
                offence.insert(l.zone);
            }
        }
        (value, cordon, offence)
    }

    fn ai_mean_strength(f: &Fleet) -> f64 {
        let mut total = 0.0;
        for s in &f.ships {
            total += s.strength;
        }
        total / maxf(f.ships.len() as f64, 1.0)
    }

    fn ai_shortest_range(data: &Data, f: &Fleet) -> i64 {
        f.ships.iter().map(|s| data.navy.def(&s.kind).range_days).min().unwrap_or(9999).min(9999)
    }

    /// `AINavy._worn`: whether a fleet at sea is worn and should go home.
    fn ai_worn(&self, data: &Data, f: &Fleet) -> bool {
        if f.port > 0 {
            return false;
        }
        let c = &data.ai.raw["navy"];
        Self::ai_mean_strength(f) < nf(c, "repair_below") || f.days_out as f64 > Self::ai_shortest_range(data, f) as f64 * nf(c, "range_factor")
    }

    fn ai_heading_zone(f: &Fleet) -> usize {
        if !f.path.is_empty() && f.dest_port == 0 {
            *f.path.last().unwrap()
        } else {
            0
        }
    }

    fn ai_go_zone(&mut self, data: &Data, tag: &str, fid: u32, zone: usize) {
        let f = &self.fleets[self.fleet_index(fid).unwrap()];
        if f.port == 0 && f.zone == zone && !Self::is_moving(f) {
            return;
        }
        if Self::ai_heading_zone(f) == zone {
            return;
        }
        self.move_fleet(data, tag, fid, zone, 0);
    }

    /// `Navy.nearest_port`: the port of a nation's a fleet could reach soonest (0 for none).
    pub fn nearest_port(&self, data: &Data, f: &Fleet) -> usize {
        let mut targets: Vec<usize> = vec![];
        let mut port_of: HashMap<usize, usize> = HashMap::new();
        for z in 1..data.map.sea_zone_names.len() {
            for &p in data.map.ports_in_zone(z) {
                if self.can_dock(data, &f.tag, p) {
                    targets.push(z);
                    port_of.entry(z).or_insert(p);
                    break;
                }
            }
        }
        let starts: Vec<usize> = if f.zone > 0 { vec![f.zone] } else { data.map.zones_of_port(f.port) };
        let path = Self::sea_find_path(data, self.fleet_speed(data, f), &starts, &targets);
        match path.last() {
            Some(z) => port_of[z],
            None => 0,
        }
    }

    /// `AINavy.go_home`.
    pub fn ai_go_home(&mut self, data: &Data, tag: &str, fid: u32) {
        let f = &self.fleets[self.fleet_index(fid).unwrap()];
        if f.port > 0 && !Self::is_moving(f) {
            return;
        }
        if f.dest_port > 0 {
            return;
        }
        let p = self.nearest_port(data, f);
        let f = &self.fleets[self.fleet_index(fid).unwrap()];
        if p > 0 && !(p == f.port && !Self::is_moving(f)) {
            self.move_fleet(data, tag, fid, 0, p);
        }
    }

    fn ai_set_mission(&mut self, tag: &str, fid: u32, mission: &str) {
        if self.fleets[self.fleet_index(fid).unwrap()].mission != mission {
            self.set_fleet_mission(tag, fid, mission);
        }
    }

    /// `AINavy._theatre`: the sea zones within `theatre_hops` of where a fleet is (or of the zones its port opens on).
    fn ai_theatre(&self, data: &Data, f: &Fleet) -> HashSet<usize> {
        let mut seen: HashSet<usize> = HashSet::new();
        let mut edge: Vec<usize> = if f.port > 0 { data.map.zones_of_port(f.port) } else { vec![f.zone] };
        for &z in &edge {
            seen.insert(z);
        }
        for _ in 0..nf(&data.ai.raw["navy"], "theatre_hops") as i64 {
            let mut next = vec![];
            for &z in &edge {
                for &n in data.map.sea_neighbors(z) {
                    if seen.insert(n) {
                        next.push(n);
                    }
                }
            }
            edge = next;
        }
        seen
    }

    fn ai_in_theatre(data: &Data, theatre: &HashSet<usize>, f: &Fleet) -> bool {
        let zones: Vec<usize> = if f.port > 0 { data.map.zones_of_port(f.port) } else { vec![f.zone] };
        zones.iter().any(|z| theatre.contains(z))
    }

    /// `AINavy._strength`: which of a nation's fleets belong to a force at least as strong as the enemy navies it could meet.
    fn ai_strength(&self, data: &Data, tag: &str, fleets: &[usize]) -> HashMap<u32, bool> {
        let theatres: Vec<HashSet<usize>> = fleets.iter().map(|&i| self.ai_theatre(data, &self.fleets[i])).collect();
        let mut parent: Vec<usize> = (0..fleets.len()).collect();
        for i in 0..fleets.len() {
            for j in (i + 1)..fleets.len() {
                if Self::ai_in_theatre(data, &theatres[i], &self.fleets[fleets[j]]) {
                    let mut a = i;
                    while parent[a] != a {
                        a = parent[a];
                    }
                    let mut b = j;
                    while parent[b] != b {
                        b = parent[b];
                    }
                    parent[a.max(b)] = a.min(b);
                }
            }
        }
        let root_of = |parent: &Vec<usize>, i: usize| {
            let mut r = i;
            while parent[r] != r {
                r = parent[r];
            }
            r
        };
        let mut own: HashMap<usize, f64> = HashMap::new();
        let mut seen: HashMap<usize, HashSet<usize>> = HashMap::new();
        let mut roots_in_order: Vec<usize> = vec![];
        for i in 0..fleets.len() {
            let root = root_of(&parent, i);
            *own.entry(root).or_insert(0.0) += self.fleet_power(data, &self.fleets[fleets[i]]);
            if !seen.contains_key(&root) {
                seen.insert(root, HashSet::new());
                roots_in_order.push(root);
            }
            seen.get_mut(&root).unwrap().extend(theatres[i].iter().copied());
        }
        let mut theirs: HashMap<usize, f64> = HashMap::new();
        for g in &self.fleets {
            if g.tag == tag || !self.at_war(tag, &g.tag) {
                continue;
            }
            for root in &roots_in_order {
                if Self::ai_in_theatre(data, &seen[root], g) {
                    *theirs.entry(*root).or_insert(0.0) += self.fleet_power(data, g);
                }
            }
        }
        let ratio = nf(&data.ai.raw["navy"], "sortie_ratio");
        let mut out = HashMap::new();
        for i in 0..fleets.len() {
            let root = root_of(&parent, i);
            out.insert(self.fleets[fleets[i]].id, own[&root] >= theirs.get(&root).copied().unwrap_or(0.0) * ratio);
        }
        out
    }

    /// `Navy.days_to_all`: days from the starting zones to every zone that can be reached.
    pub fn days_to_all(data: &Data, speed: f64, from_zones: &[usize]) -> HashMap<usize, f64> {
        let mut dist: HashMap<usize, f64> = HashMap::new();
        let mut open: Vec<usize> = vec![];
        for &z in from_zones {
            dist.insert(z, 0.0);
            open.push(z);
        }
        while !open.is_empty() {
            let mut best = 0;
            for i in 0..open.len() {
                if dist[&open[i]] < dist[&open[best]] || (dist[&open[i]] == dist[&open[best]] && open[i] < open[best]) {
                    best = i;
                }
            }
            let z = open.remove(best);
            for &n in data.map.sea_neighbors(z) {
                let d = dist[&z] + Self::zone_days(data, speed, z, n);
                if !dist.contains_key(&n) || d < dist[&n] {
                    dist.insert(n, d);
                    if !open.contains(&n) {
                        open.push(n);
                    }
                }
            }
        }
        dist
    }

    /// `Navy.path_days`: days a fleet of a speed needs to sail along a path of zones.
    pub fn path_days(data: &Data, speed: f64, path: &[usize]) -> f64 {
        let mut total = 0.0;
        for i in 1..path.len() {
            total += Self::zone_days(data, speed, path[i - 1], path[i]);
        }
        total
    }

    /// `AINavy._station`: gives every warfleet a sea zone.
    fn ai_station(&mut self, data: &Data, tag: &str) {
        let c = &data.ai.raw["navy"];
        let odds = self.ai_battle_odds(data, tag);
        let enemies_at = self.ai_enemy_map(data, tag);
        let (importance, cordon, offence) = self.ai_targets(data, tag, &enemies_at);
        let mut zones: Vec<usize> = importance.keys().copied().collect();
        zones.sort();
        let mut committed: HashMap<usize, f64> = HashMap::new();
        let mut fleets: Vec<usize> = vec![];
        for fi in self.fleets_of(tag) {
            let f = &self.fleets[fi];
            if Self::ai_role(f) == "transport" {
                if f.port == 0 && !Self::is_moving(f) && f.landing == 0 && !self.ai_carrying.borrow().contains(&f.id) {
                    let fid = f.id;
                    self.ai_go_home(data, tag, fid);
                }
                continue;
            }
            fleets.push(fi);
        }
        sort_custom(&mut fleets, |&a, &b| {
            let (pa, pb) = (self.fleet_power(data, &self.fleets[a]), self.fleet_power(data, &self.fleets[b]));
            pa > pb || (pa == pb && self.fleets[a].id < self.fleets[b].id)
        });
        let mut day_cache: Vec<((u64, Vec<usize>), HashMap<usize, f64>)> = vec![];
        let strong = self.ai_strength(data, tag, &fleets);
        let alive: HashSet<u32> = self.fleets.iter().map(|f| f.id).collect();
        self.ai_navy.get_mut(tag).unwrap().retain(|id, _| alive.contains(id));
        for fi in fleets {
            let f = self.fleets[fi].clone();
            if f.fighting || f.retreating || self.ai_carrying.borrow().contains(&f.id) {
                if f.zone > 0 {
                    *committed.entry(f.zone).or_insert(0.0) += self.fleet_power(data, &f);
                }
                continue;
            }
            if self.ai_worn(data, &f) {
                self.ai_navy.get_mut(tag).unwrap().remove(&f.id);
                self.ai_go_home(data, tag, f.id);
                continue;
            }
            if f.port > 0 && Self::ai_mean_strength(&f) < nf(c, "ready_strength") {
                self.ai_navy.get_mut(tag).unwrap().remove(&f.id);
                continue;
            }
            let previous = self.ai_navy[tag].get(&f.id).copied().unwrap_or(0);
            let starts: Vec<usize> = if f.port > 0 { data.map.zones_of_port(f.port) } else { vec![f.zone] };
            let mut best = 0;
            let mut best_score = f64::NEG_INFINITY;
            let speed = self.fleet_speed(data, &f);
            let day_key = (speed.to_bits(), starts.clone());
            let pos = match day_cache.iter().position(|d| d.0 == day_key) {
                Some(p) => p,
                None => {
                    day_cache.push((day_key, Self::days_to_all(data, speed, &starts)));
                    day_cache.len() - 1
                }
            };
            let days = &day_cache[pos].1;
            let power = self.fleet_power(data, &f);
            let role = Self::ai_role(&f);
            for &z in &zones {
                if offence.contains(&z) && !importance.contains_key(&z) {
                    continue;
                }
                if offence.contains(&z) && role != "raider" && !strong.get(&f.id).copied().unwrap_or(false) {
                    continue;
                }
                let need = odds * enemies_at.get(&z).copied().unwrap_or(0.0);
                let have = power + committed.get(&z).copied().unwrap_or(0.0);
                if need > 0.0 && have < need {
                    continue;
                }
                if !days.contains_key(&z) {
                    continue;
                }
                // A zone already held is worth less to a second fleet, unless it is still outgunned.
                let mut worth = importance[&z];
                if committed.get(&z).copied().unwrap_or(0.0) >= maxf(need, data.navy.blockade.min_power) {
                    worth *= nf(c, "stack_decay");
                }
                let mut score = worth - nf(c, "w_days") * days[&z];
                if z == previous {
                    score += nf(c, "hysteresis");
                }
                if score > best_score + 0.000001 {
                    best = z;
                    best_score = score;
                }
            }
            if best == 0 || best_score < nf(c, "min_score") {
                self.ai_navy.get_mut(tag).unwrap().remove(&f.id);
                self.ai_go_home(data, tag, f.id);
                continue;
            }
            self.ai_navy.get_mut(tag).unwrap().insert(f.id, best);
            *committed.entry(best).or_insert(0.0) += power;
            // A fleet in a port that opens on a zone it only guards already does so; holding a zone (a cordon, a hunt) means being at sea in it.
            if f.port > 0 && !Self::is_moving(&f) && starts.contains(&best) && !offence.contains(&best) {
                continue;
            }
            self.ai_go_zone(data, tag, f.id, best);
            let mission = if role == "raider" { "raid" } else if cordon.contains(&best) { "blockade" } else { "patrol" };
            self.ai_set_mission(tag, f.id, mission);
        }
    }

    // ---------------------------------------------------------------- building ships

    /// `AINavy.build`: once a month, at war: one squadron if the nation's fleet is smaller than the enemies', the type furthest below its share,
    /// at the best yard, within the nation's means.
    pub fn ai_navy_build(&mut self, data: &Data, tag: &str) {
        let b = &data.ai.raw["navy"]["build"];
        if !b["enabled"].as_bool().unwrap_or(false) || self.wars_of(tag).is_empty() {
            return;
        }
        let n = self.nation(tag);
        if n.shipbuilding.len() as i64 >= nf(b, "max_building") as i64 {
            return;
        }
        let mut theirs = 0.0;
        for f in &self.fleets {
            if f.tag != tag && self.at_war(tag, &f.tag) {
                theirs += self.fleet_power(data, f);
            }
        }
        let mut own = 0.0;
        let mut have: HashMap<String, i64> = HashMap::new();
        for fi in self.fleets_of(tag) {
            let f = &self.fleets[fi];
            own += self.fleet_power(data, f);
            for s in &f.ships {
                *have.entry(s.kind.clone()).or_insert(0) += 1;
            }
        }
        for job in &n.shipbuilding {
            own += data.navy.def(&job.kind).attack;
            *have.entry(job.kind.clone()).or_insert(0) += 1;
        }
        let kind = if self.ai_navy_need.get(tag).map(String::as_str) == Some("transport") {
            "transport".to_string()
        } else if own < nf(b, "build_ratio") * theirs {
            self.ai_next_ship_type(data, tag, &have)
        } else {
            String::new()
        };
        if kind.is_empty() {
            return;
        }
        let yard = self.ai_yard(data, tag, &kind);
        if yard == 0 {
            return;
        }
        let def = data.navy.def(&kind);
        let plan_total = def.cost;
        if n.treasury - plan_total < nf(b, "build_floor") {
            return;
        }
        // The slips draw on the construction pool: hulls already building plus this one may take only a share of it.
        let pool = n.budget.construction_points;
        let mut rate = def.ic / maxf(def.build_days as f64, 1.0);
        for job in &n.shipbuilding {
            rate += job.rate;
        }
        if rate > nf(b, "income_share") * pool {
            return;
        }
        if n.budget.net - def.upkeep < -nf(b, "deficit_tolerance") * n.budget.revenue {
            return;
        }
        if self.raise_ships(data, tag, yard, &kind, 1) {
            self.economy_dirty = true;
            if kind == "transport" {
                self.ai_navy_need.remove(tag);
            }
        }
    }

    /// `AINavy._next_type`: the ship type furthest below its share of the fleet that some yard of the nation can build.
    fn ai_next_ship_type(&self, data: &Data, tag: &str, have: &HashMap<String, i64>) -> String {
        let mix = data.ai.raw["navy"]["build"]["mix"].as_object().unwrap();
        let total: i64 = have.values().sum();
        let mut types: Vec<&String> = mix.keys().collect();
        types.sort();
        let mut best = String::new();
        let mut best_gap = f64::NEG_INFINITY;
        for t in types {
            if self.ai_yard(data, tag, t) == 0 {
                continue;
            }
            let gap = mix[t].as_f64().unwrap() - if total > 0 { have.get(t).copied().unwrap_or(0) as f64 / total as f64 } else { 0.0 };
            if gap > best_gap + 0.000001 {
                best = t.clone();
                best_gap = gap;
            }
        }
        best
    }

    /// `AINavy._yard`: the nation's best yard for a type (highest level, then lowest id), or 0.
    fn ai_yard(&self, data: &Data, tag: &str, kind: &str) -> usize {
        let mut best = 0;
        let mut best_level = 0;
        for &id in &self.nation(tag).provinces {
            // the money is not asked for here
            let why = self.ship_build_problem(data, tag, id, kind, 1);
            if !why.is_empty() && why != "Not enough money" {
                continue;
            }
            let level = self.port_level(id);
            if level > best_level || (level == best_level && (best == 0 || id < best)) {
                best = id;
                best_level = level;
            }
        }
        best
    }

    // ---------------------------------------------------------------- landings

    /// `AILanding.involves`: whether an army is part of a landing being prepared by the nation.
    pub fn ai_landing_involves(&self, tag: &str, army: u32) -> bool {
        self.ai_landing.get(tag).map(|c| c.armies.contains(&army)).unwrap_or(false)
    }

    /// `AILanding.step`.
    pub fn ai_landing_step(&mut self, data: &Data, tag: &str) {
        let c = &data.ai.raw["navy"]["landing"];
        let today = self.calendar.days_elapsed as i64;
        if let Some(mut l) = self.ai_landing.get(tag).cloned() {
            l.armies.retain(|id| self.armies.iter().any(|a| a.id == *id));
            if l.armies.is_empty() || self.fleet_index(l.fleet).is_none() || !self.at_war(tag, &l.enemy) {
                self.ai_landing_end(data, tag);
                return;
            }
            let ended = self.ai_landing_run(data, tag, &mut l);
            if ended {
                self.ai_landing_end(data, tag);
            } else {
                self.ai_landing.insert(tag.to_string(), l);
            }
            return;
        }
        if today < self.ai_landing_wait.get(tag).copied().unwrap_or(0) || self.ai_enemies(tag).is_empty() {
            return;
        }
        match self.ai_landing_start(data, tag) {
            Some(l) => {
                self.ai_landing.insert(tag.to_string(), l);
            }
            None => {
                self.ai_landing_wait.insert(tag.to_string(), today + nf(c, "retry_days") as i64);
            }
        }
    }

    fn ai_landing_end(&mut self, data: &Data, tag: &str) {
        self.ai_landing.remove(tag);
        self.ai_landing_wait.insert(tag.to_string(), self.calendar.days_elapsed as i64 + nf(&data.ai.raw["navy"]["landing"], "retry_days") as i64);
    }

    /// `AILanding._coast`: enemy coast that could be landed on.
    fn ai_coast(&self, data: &Data, tag: &str, enemy: &str) -> Vec<usize> {
        (1..self.province_controller.len()).filter(|&id| self.province_controller[id] == enemy && !data.map.zones_of_port(id).is_empty() && self.can_enter(data, tag, id)).collect()
    }

    /// `AILanding._transports`: fleets of transports in port, biggest first.
    fn ai_transports(&self, data: &Data, tag: &str) -> Vec<usize> {
        let mut out: Vec<usize> = self.fleets_of(tag).into_iter().filter(|&i| {
            let f = &self.fleets[i];
            Self::ai_role(f) == "transport" && self.ai_free(f) && self.fleet_capacity(data, f) > 0
        }).collect();
        sort_custom(&mut out, |&a, &b| {
            let (ca, cb) = (self.fleet_capacity(data, &self.fleets[a]), self.fleet_capacity(data, &self.fleets[b]));
            ca > cb || (ca == cb && self.fleets[a].id < self.fleets[b].id)
        });
        out
    }

    /// `AILanding._force`: the armies, nearest first by land, that a transport fleet can take from its port: (armies, power, units).
    fn ai_landing_force(&self, data: &Data, tf: usize, armies: &[u32]) -> (Vec<u32>, f64, usize) {
        let mil = &data.military;
        let f = &self.fleets[tf];
        let reach: Vec<usize> = self.hops_from(data, f.port, nf(&data.ai.raw["navy"]["landing"], "reach_hops") as i64).into_iter().map(|x| x.0).collect();
        let mut near: Vec<u32> = armies.iter().copied().filter(|&id| reach.contains(&self.army_ref(id).province) && !self.army_ref(id).embarked()).collect();
        sort_custom(&mut near, |&x, &y| {
            let (dx, dy) = (Self::ai_km(data, self.army_ref(x).province, f.port), Self::ai_km(data, self.army_ref(y).province, f.port));
            dx < dy || (dx == dy && x < y)
        });
        let capacity = self.fleet_capacity(data, f) as f64;
        let (mut out, mut power, mut men, mut units) = (vec![], 0.0, 0.0, 0usize);
        for id in near {
            let a = self.army_ref(id);
            if men + a.men(mil) > capacity {
                continue;
            }
            out.push(id);
            men += a.men(mil);
            power += a.power(mil);
            units += a.units.len();
        }
        (out, power, units)
    }

    /// `AILanding._clear`: whether no zone of a route is held against the nation.
    fn ai_route_clear(&self, tag: &str, route: &[usize]) -> bool {
        route.iter().all(|&z| self.blockaders(tag, z).is_empty())
    }

    /// `AILanding._start`.
    fn ai_landing_start(&mut self, data: &Data, tag: &str) -> Option<Landing> {
        let c = &data.ai.raw["navy"]["landing"];
        let armies = self.ai_available(data, tag);
        let mut by_coast: Vec<(String, Vec<usize>)> = vec![];
        for enemy in self.ai_enemies(tag) {
            if self.ai_defensive_plan(tag, &enemy) || !self.ai_frontier(data, tag, &enemy).is_empty() {
                continue;
            }
            let coast = self.ai_coast(data, tag, &enemy);
            if !coast.is_empty() {
                by_coast.push((enemy, coast));
            }
        }
        if by_coast.is_empty() || armies.is_empty() {
            self.ai_navy_need.remove(tag);
            return None;
        }
        let carriers = self.ai_transports(data, tag);
        if carriers.is_empty() {
            let have = self.fleets_of(tag).iter().any(|&i| Self::ai_role(&self.fleets[i]) == "transport");
            if !have {
                self.ai_navy_need.insert(tag.to_string(), "transport".to_string());
            }
            return None;
        }
        self.ai_navy_need.remove(tag);
        let odds = self.ai_battle_odds(data, tag);
        let enemies_at = self.ai_enemy_map(data, tag);
        let mut own_navy = 0.0;
        for fi in self.fleets_of(tag) {
            if Self::ai_role(&self.fleets[fi]) != "transport" {
                own_navy += self.fleet_power(data, &self.fleets[fi]);
            }
        }
        let mut best: Option<(f64, usize, u32, usize, String, Vec<u32>, usize)> = None;
        for tf in carriers {
            let (force_armies, force_power, units) = self.ai_landing_force(data, tf, &armies);
            if (units as i64) < nf(c, "min_force") as i64 {
                continue;
            }
            let f = &self.fleets[tf];
            let speed = self.fleet_speed(data, f);
            for (enemy, coast) in &by_coast {
                for &target in coast {
                    let route = Self::sea_find_path(data, speed, &data.map.zones_of_port(f.port), &data.map.zones_of_port(target));
                    if route.is_empty() || !self.ai_route_clear(tag, &route) {
                        continue;
                    }
                    let zone = *route.last().unwrap();
                    if enemies_at.get(&zone).copied().unwrap_or(0.0) * odds > own_navy * nf(c, "escort_share") {
                        continue;
                    }
                    let required = odds * self.ai_resistance(data, tag, target) / nf(c, "landing_penalty");
                    if force_power < required {
                        continue;
                    }
                    let margin = clampf(force_power / required - 1.0, 0.0, 2.0);
                    let utility = self.ai_worth(data, tag, enemy, target) + nf(c, "w_margin") * margin - nf(c, "w_days") * Self::path_days(data, speed, &route);
                    if best.as_ref().map(|b| utility > b.0 + 0.000001).unwrap_or(true) {
                        best = Some((utility, target, f.id, f.port, enemy.clone(), force_armies.clone(), zone));
                    }
                }
            }
        }
        let (utility, target, fleet, port, enemy, ids, zone) = best?;
        if utility < nf(c, "min_utility") {
            return None;
        }
        Some(Landing { enemy, target, port, fleet, armies: ids, phase: "gather".to_string(), started: self.calendar.days_elapsed as i64, zone })
    }

    /// `AILanding._run`: one day of a landing. Returns whether it has ended.
    fn ai_landing_run(&mut self, data: &Data, tag: &str, c: &mut Landing) -> bool {
        let cfg = &data.ai.raw["navy"]["landing"];
        let today = self.calendar.days_elapsed as i64;
        let fi = self.fleet_index(c.fleet).unwrap();
        let age = today - c.started;
        match c.phase.as_str() {
            "gather" => {
                let f = &self.fleets[fi];
                let mut ready = f.port > 0 && f.port == c.port && !Self::is_moving(f);
                if !ready && (!Self::is_moving(f) || f.dest_port != c.port) {
                    self.move_fleet(data, tag, c.fleet, 0, c.port);
                }
                for id in c.armies.clone() {
                    let a = self.army_ref(id);
                    if a.province == c.port && a.path.is_empty() && !a.fighting {
                        continue;
                    }
                    ready = false;
                    if a.path.last() == Some(&c.port) {
                        continue;
                    }
                    if !self.order_army_to(data, tag, id, c.port) {
                        c.armies.retain(|x| *x != id);
                    }
                }
                if c.armies.is_empty() || age > nf(cfg, "gather_days") as i64 {
                    return true;
                } else if ready {
                    c.phase = "escort".to_string();
                    c.started = today;
                }
            }
            "escort" => {
                let f = &self.fleets[fi];
                let route = Self::sea_find_path(data, self.fleet_speed(data, f), &data.map.zones_of_port(c.port), &data.map.zones_of_port(c.target));
                if route.is_empty() || age > nf(cfg, "escort_days") as i64 || self.province_controller[c.target] == tag {
                    return true;
                }
                c.zone = *route.last().unwrap();
                let open = self.ai_route_clear(tag, &route);
                let held = self.holds_sea(tag, c.zone) || self.ai_enemy_power_at(data, tag, c.zone) <= 0.0;
                if open && held {
                    if self.send_overseas(data, tag, c.fleet, &c.armies, c.target) {
                        c.phase = "sail".to_string();
                        c.started = today;
                    } else {
                        return true;
                    }
                }
            }
            "sail" => {
                let aboard = c.armies.iter().any(|&id| self.army_ref(id).embarked());
                let f = &self.fleets[fi];
                if aboard && f.port > 0 && !Self::is_moving(f) {
                    // Turned back by an enemy fleet and put into a port: the landing is off; the men go ashore there.
                    let port = f.port;
                    for id in c.armies.clone() {
                        self.disembark_army(data, tag, id, port);
                    }
                    return true;
                } else if !aboard || age > nf(cfg, "sail_days") as i64 {
                    return true;
                }
            }
            _ => {}
        }
        false
    }
}
