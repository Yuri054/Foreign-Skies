//! War on the map (`scripts/sim/military.gd`, `capitulation.gd` and the parts of `munitions.gd` and `war_support.gd` they use):
//! orders and the routes armies take, their daily march, supply and the reach of the cities, battles, retreats and the
//! pursuit, the ground taken, and the check that a nation has not lost enough to capitulate.
//!
//! Not ported yet: fronts, army groups and offensives (nothing here makes a front), the water
//! between provinces (a short sea crossing is taken as free of enemy ships, and a pocket of ground cut off from home that has
//! a port would need the sea routes), the war's log and the battle records kept for the screens, and what follows a
//! capitulation or the loss of a capital (the port stops with a message if either would happen).

use crate::config::MilitaryConfig;
use crate::gd::{clampf, maxf, minf};
use crate::military::{Army, Unit};
use crate::state::{Data, Engagement, GameState, HomeCache, SupplyCache};
use std::collections::{HashMap, HashSet};

/// Kilometres a bitmap pixel is across (`Military.KM_PER_PX`).
pub const KM_PER_PX: f64 = 0.6928;

impl Army {
    /// The slowest of the army's units, in km a day.
    pub fn speed(&self, cfg: &MilitaryConfig) -> f64 {
        let mut slowest = f64::INFINITY;
        for u in &self.units {
            slowest = minf(slowest, cfg.unit_type(&u.unit_type).speed);
        }
        slowest
    }

    /// Mean morale, weighted by men.
    pub fn morale(&self, cfg: &MilitaryConfig) -> f64 {
        let (mut total, mut weight) = (0.0, 0.0);
        for u in &self.units {
            total += u.morale * u.men(cfg);
            weight += u.men(cfg);
        }
        if weight > 0.0 {
            total / weight
        } else {
            0.0
        }
    }

    /// How dug in the army is: levels, by the days it has stood still.
    pub fn entrenchment(&self, cfg: &MilitaryConfig) -> i64 {
        if !self.path.is_empty() || self.landing_days > 0 {
            return 0;
        }
        let mut top = cfg.combat.max_entrenchment;
        let mut days = self.still_days as f64;
        if self.prepared {
            top += cfg.fallback_extra_levels;
            days *= cfg.fallback_dig_speed;
        }
        ((days as i64) / cfg.combat.entrench_days_per_level).min(top)
    }
}

/// `Unit.full_size`.
fn full_size(cfg: &MilitaryConfig, u: &Unit) -> i64 {
    cfg.unit_type(&u.unit_type).size
}

/// A binary heap of [days, order, province] exactly as the game keeps it, so equal days come out in the order queued.
struct Heap(Vec<(f64, u64, usize)>);

impl Heap {
    fn less(x: &(f64, u64, usize), y: &(f64, u64, usize)) -> bool {
        x.0 < y.0 || (x.0 == y.0 && x.1 < y.1)
    }

    fn push(&mut self, item: (f64, u64, usize)) {
        self.0.push(item);
        let mut i = self.0.len() - 1;
        while i > 0 {
            let parent = (i - 1) >> 1;
            if !Self::less(&self.0[i], &self.0[parent]) {
                break;
            }
            self.0.swap(i, parent);
            i = parent;
        }
    }

    fn pop(&mut self) -> (f64, u64, usize) {
        let top = self.0[0];
        let last = self.0.pop().unwrap();
        if !self.0.is_empty() {
            self.0[0] = last;
            let n = self.0.len();
            let mut i = 0;
            loop {
                let l = 2 * i + 1;
                let r = l + 1;
                let mut m = i;
                if l < n && Self::less(&self.0[l], &self.0[m]) {
                    m = l;
                }
                if r < n && Self::less(&self.0[r], &self.0[m]) {
                    m = r;
                }
                if m == i {
                    break;
                }
                self.0.swap(i, m);
                i = m;
            }
        }
        top
    }
}

impl GameState {
    fn day_i(&self) -> i64 {
        self.calendar.days_elapsed as i64
    }

    // ---------------------------------------------------------------- where armies may go

    /// `Diplomacy.has_passage`: whether `mover`'s armies may cross `host`'s land by treaty. Any alliance opens it.
    pub fn has_passage(&self, data: &Data, host: &str, mover: &str) -> bool {
        host == mover || self.has_treaty(data, "passage", host, mover) || self.find_treaty(data, "alliance", host, mover).is_some()
    }

    /// `Military.can_enter`, for the tests.
    pub fn can_enter_pub(&self, data: &Data, tag: &str, id: usize) -> bool {
        self.can_enter(data, tag, id)
    }

    /// `Military.can_enter`: whether armies of a nation may stand in a province: its own ground, ground it holds, ground of a
    /// nation it is at war with, or ground whose owner and holder both let it cross.
    pub fn can_enter(&self, data: &Data, tag: &str, id: usize) -> bool {
        let (o, c) = (&self.province_owner[id], &self.province_controller[id]);
        if !self.restrictions.is_empty() && self.restricted(tag, id) {
            return false;
        }
        if o == tag || c == tag || self.at_war(tag, o) || self.at_war(tag, c) {
            return true;
        }
        self.has_passage(data, o, tag) && self.has_passage(data, c, tag)
    }

    /// `Military.neighbors_for`: neighbours an army of `tag` can reach from a province: the land and strait neighbours, and
    /// across short stretches of sea the provinces on the other side, as long as no enemy holds the water between (the
    /// water is not ported: it is taken as free).
    pub fn neighbors_for(&self, data: &Data, tag: &str, id: usize) -> Vec<usize> {
        let mut out: Vec<usize> = data.map.neighbors(id).collect();
        for &n in &data.map.adjacency[id] {
            if data.map.sea_links.get(&(id.min(n), id.max(n))).map(String::as_str) == Some("sea") && self.crossing_open(data, tag, id, n) {
                out.push(n);
            }
        }
        out
    }

    /// `Military.crossing_open`: whether a short sea crossing between two provinces is free of enemy ships.
    pub fn crossing_open(&self, data: &Data, tag: &str, a: usize, b: usize) -> bool {
        let mut zones = data.map.zones_of_port(a);
        for z in data.map.zones_of_port(b) {
            if !zones.contains(&z) {
                zones.push(z);
            }
        }
        zones.iter().all(|&z| self.blockaders(tag, z).is_empty())
    }

    /// `Military.railway_ok`: whether a nation's railways run (it has at least half of the raw materials its industry needs).
    pub fn railway_ok(&self, tag: &str) -> bool {
        match self.nation_index.get(tag) {
            Some(&i) => self.nations[i].budget.materials.ratio >= 0.5,
            None => true,
        }
    }

    /// `Military.hop_cost`: the cost of a supply hop into a province: 1, or less where a railway runs.
    pub fn hop_cost(&self, data: &Data, tag: &str, id: usize) -> f64 {
        let level = self.level_of(id, "railway");
        if level <= 0 || !self.railway_ok(tag) {
            return 1.0;
        }
        let s = &data.military.supply;
        maxf(0.2, s.railway_hop_cost * (1.0 - s.railway_level_gain * (level - 1) as f64))
    }

    pub(crate) fn level_of(&self, id: usize, kind: &str) -> i64 {
        self.province_buildings[id].iter().find(|(k, _)| k == kind).map(|(_, l)| *l as i64).unwrap_or(0)
    }

    /// `Military.move_days`: days an army of the given speed needs to walk from one province into a neighbour.
    pub fn move_days(&self, data: &Data, tag: &str, speed: f64, from: usize, to: usize) -> f64 {
        let mil = &data.military;
        let (a, b) = (data.map.provinces[from].center, data.map.provinces[to].center);
        // The distance is a 32-bit vector's, as in the game.
        let (dx, dy) = (b.0 - a.0, b.1 - a.1);
        let dist = (dx * dx + dy * dy).sqrt() as f64;
        let km = dist * KM_PER_PX;
        let mut days = km / speed * mil.terrain_def(&data.map.provinces[to].terrain).move_cost;
        if self.province_controller[to] == tag && self.railway_ok(tag) {
            // Built railways, and over everything an industrial nation owns a network of lesser lines.
            days /= 1.0 + mil.movement.railway_speedup * self.level_of(to, "railway") as f64 + mil.movement.home_rail * self.nation(tag).development;
        }
        match data.map.sea_links.get(&(from.min(to), from.max(to))).map(String::as_str) {
            Some("sea") => days += mil.movement.sea_link_days,
            Some(_) => days += mil.movement.strait_days,
            None => {}
        }
        maxf(days.ceil(), mil.movement.min_days)
    }

    /// `Military.find_path`: the cheapest route for an army, as the provinces to enter (empty if there is none).
    pub fn find_path(&self, data: &Data, tag: &str, speed: f64, from: usize, to: usize) -> Vec<usize> {
        if from == to || !self.can_enter(data, tag, to) {
            return vec![];
        }
        let mut dist: HashMap<usize, f64> = HashMap::from([(from, 0.0)]);
        let mut prev: HashMap<usize, usize> = HashMap::new();
        let mut heap = Heap(vec![(0.0, 0, from)]);
        let mut queued: HashMap<usize, u64> = HashMap::from([(from, 0)]);
        let mut seq = 1u64;
        while !heap.0.is_empty() {
            let top = heap.pop();
            let cur = top.2;
            if top.0 > dist[&cur] {
                continue;
            }
            if cur == to {
                break;
            }
            queued.remove(&cur);
            for n in self.neighbors_for(data, tag, cur) {
                if !self.can_enter(data, tag, n) {
                    continue;
                }
                let nd = dist[&cur] + self.move_days(data, tag, speed, cur, n);
                if !dist.contains_key(&n) || nd < dist[&n] {
                    dist.insert(n, nd);
                    prev.insert(n, cur);
                    if !queued.contains_key(&n) {
                        queued.insert(n, seq);
                        seq += 1;
                    }
                    heap.push((nd, queued[&n], n));
                }
            }
        }
        if !prev.contains_key(&to) {
            return vec![];
        }
        let mut path = vec![];
        let mut step = to;
        while step != from {
            path.push(step);
            step = prev[&step];
        }
        path.reverse();
        path
    }

    /// `MoveArmy.execute` (an army not on a front): orders an army to a province by the cheapest route it may take.
    pub fn order_army_to(&mut self, data: &Data, tag: &str, army_id: u32, destination: usize) -> bool {
        let Some(i) = self.armies.iter().position(|a| a.id == army_id) else { return false };
        if self.armies[i].tag != tag || self.armies[i].embarked() || destination < 1 || destination >= self.province_owner.len() {
            return false;
        }
        // On a spreading front a hand order pins the stack instead of taking its army off the front.
        let spreading = self.root_of(i).map(|r| {
            let fid = self.armies[r].front_id;
            fid != 0 && self.fronts.iter().any(|f| f.id == fid && f.spread)
        }).unwrap_or(false);
        if destination == self.armies[i].province {
            if !spreading {
                self.leave_front(i);
            }
            // Moving to where it stands cancels the order.
            self.armies[i].path.clear();
            self.armies[i].pin = 0;
            return true;
        }
        let speed = self.armies[i].speed(&data.military);
        let path = self.find_path(data, tag, speed, self.armies[i].province, destination);
        if path.is_empty() {
            return false;
        }
        // A hand-given order takes the army off its front, or on a spreading front pins it.
        if spreading {
            self.armies[i].pin = destination;
        } else {
            self.leave_front(i);
        }
        // Keep the progress already made if the army is still heading into the same province.
        if self.armies[i].path.is_empty() || self.armies[i].path[0] != path[0] {
            self.armies[i].move_days_left = self.move_days(data, tag, speed, self.armies[i].province, path[0]);
        }
        self.armies[i].path = path;
        self.armies[i].still_days = 0;
        true
    }

    // ---------------------------------------------------------------- the cities' reach and supply

    /// `Military.city_aura`: the strength of the cities' aura (0 to 1) over a province for the nation that holds it.
    pub fn city_aura(&self, data: &Data, tag: &str, id: usize) -> f64 {
        let stamp = (self.owner_version, self.control_version);
        let stale = !matches!(&*self.aura_cache.borrow(), Some((s, _)) if *s == stamp);
        if stale {
            let built = self.build_aura(data);
            *self.aura_cache.borrow_mut() = Some((stamp, built));
        }
        self.aura_cache.borrow().as_ref().unwrap().1.get(tag).and_then(|m| m.get(&id)).copied().unwrap_or(0.0)
    }

    fn build_aura(&self, data: &Data) -> HashMap<String, HashMap<usize, f64>> {
        let mut out: HashMap<String, HashMap<usize, f64>> = HashMap::new();
        let c = &data.military.cities;
        for city in &self.cities {
            let home = city.province;
            let owner = self.province_owner[home].clone();
            if self.province_controller[home] != owner {
                continue;
            }
            let strength = c.power[(city.rank - 1) as usize];
            let reach = c.radius[(city.rank - 1) as usize];
            let by_tag = out.entry(owner.clone()).or_default();
            let mut dist: HashMap<usize, i64> = HashMap::from([(home, 0)]);
            let mut open = std::collections::VecDeque::from([home]);
            while let Some(cur) = open.pop_front() {
                let here = strength * (1.0 - dist[&cur] as f64 / (reach + 1) as f64);
                if here > by_tag.get(&cur).copied().unwrap_or(0.0) {
                    by_tag.insert(cur, here);
                }
                if dist[&cur] >= reach {
                    continue;
                }
                for nb in data.map.neighbors(cur) {
                    if dist.contains_key(&nb) || self.province_owner[nb] != owner || self.province_controller[nb] != owner {
                        continue;
                    }
                    dist.insert(nb, dist[&cur] + 1);
                    open.push_back(nb);
                }
            }
        }
        out
    }

    /// `Military.home_connected`: whether ground a nation holds is tied to its homeland.
    pub fn home_connected(&self, data: &Data, tag: &str, id: usize) -> bool {
        if self.province_owner[id] == tag {
            return true;
        }
        {
            let mut cache = self.home_cache.borrow_mut();
            if cache.day != self.day_i() {
                *cache = HomeCache { day: self.day_i(), answers: HashMap::new() };
            }
            if let Some(&answer) = cache.answers.get(&(tag.to_string(), id)) {
                return answer;
            }
        }
        // The region of ground the nation holds around this province.
        let mut seen: Vec<usize> = vec![id];
        let mut seen_set: HashSet<usize> = HashSet::from([id]);
        let mut queue = vec![id];
        let mut home = false;
        let mut ports: Vec<usize> = vec![];
        while !queue.is_empty() && !home {
            let cur = queue.pop().unwrap();
            if self.province_owner[cur] == tag {
                home = true;
                break;
            }
            if !data.map.zones_of_port(cur).is_empty() {
                ports.push(cur);
            }
            for n in data.map.neighbors(cur) {
                if !seen_set.contains(&n) && self.province_controller[n] == tag {
                    seen_set.insert(n);
                    seen.push(n);
                    queue.push(n);
                }
            }
        }
        if !home {
            for &p in &ports {
                if self.sea_route_home(data, tag, p) {
                    home = true;
                    break;
                }
            }
        }
        let mut cache = self.home_cache.borrow_mut();
        for k in seen {
            cache.answers.insert((tag.to_string(), k), home);
        }
        home
    }

    /// `Navy.port_level`: the better of the commercial port and the naval base.
    pub fn port_level(&self, id: usize) -> i64 {
        self.level_of(id, "port").max(self.naval_bases.get(&id).copied().unwrap_or(0))
    }

    /// `Navy.sea_route_home`: whether ships of a nation can get from a port to one of its home ports without crossing water an
    /// enemy holds: what keeps a bridgehead supplied.
    pub fn sea_route_home(&self, data: &Data, tag: &str, port: usize) -> bool {
        let mut targets: Vec<usize> = vec![];
        for &id in &self.nation(tag).provinces {
            if self.province_controller[id] == tag && self.port_level(id) > 0 {
                for z in data.map.zones_of_port(id) {
                    if !targets.contains(&z) {
                        targets.push(z);
                    }
                }
            }
        }
        let mut seen: HashSet<usize> = HashSet::new();
        let mut todo: Vec<usize> = vec![];
        for z in data.map.zones_of_port(port) {
            if self.blockaders(tag, z).is_empty() {
                seen.insert(z);
                todo.push(z);
            }
        }
        while let Some(z) = todo.pop() {
            if targets.contains(&z) {
                return true;
            }
            for &n in data.map.sea_neighbors(z) {
                if !seen.contains(&n) && self.blockaders(tag, n).is_empty() {
                    seen.insert(n);
                    todo.push(n);
                }
            }
        }
        false
    }

    /// `Military.supply_cost`: supply distance in hops from the nearest province the nation controls; infinite if it is
    /// farther than the supply range.
    pub fn supply_cost(&self, data: &Data, tag: &str, from: usize) -> f64 {
        if self.province_controller[from] == tag && self.home_connected(data, tag, from) {
            return 0.0;
        }
        let stamp = Some((self.day_i(), self.control_version));
        {
            let mut cache = self.supply_cache.borrow_mut();
            if cache.stamp != stamp {
                *cache = SupplyCache { stamp, costs: HashMap::new() };
            }
            if let Some(&c) = cache.costs.get(&(tag.to_string(), from)) {
                return c;
            }
        }
        let cost = self.supply_search(data, tag, from);
        self.supply_cache.borrow_mut().costs.insert((tag.to_string(), from), cost);
        cost
    }

    fn supply_search(&self, data: &Data, tag: &str, from: usize) -> f64 {
        let limit = data.military.supply.range + data.military.cities.supply_range * self.city_aura(data, tag, from);
        let mut dist: HashMap<usize, f64> = HashMap::from([(from, 0.0)]);
        let mut open = vec![from];
        while !open.is_empty() {
            let mut bi = 0;
            for i in 0..open.len() {
                if dist[&open[i]] < dist[&open[bi]] {
                    bi = i;
                }
            }
            let cur = open.remove(bi);
            if self.province_controller[cur] == tag && self.home_connected(data, tag, cur) {
                return dist[&cur];
            }
            for n in data.map.neighbors(cur) {
                let step = self.hop_cost(data, tag, n);
                let nd = dist[&cur] + step;
                if nd > limit + 0.001 || (dist.contains_key(&n) && dist[&n] <= nd) {
                    continue;
                }
                dist.insert(n, nd);
                if !open.contains(&n) {
                    open.push(n);
                }
            }
        }
        f64::INFINITY
    }

    // ---------------------------------------------------------------- defence

    fn works_level(&self, id: usize, kind: &str) -> f64 {
        self.level_of(id, kind) as f64
    }

    /// `Military.works_defense`: trenches and heavy fortifications add their defence bonus for every level, to the owner.
    pub fn works_defense(&self, data: &Data, a: &Army) -> f64 {
        if self.province_owner[a.province] != a.tag {
            return 0.0;
        }
        let (trench, fort) = (data.economy.building("trench").unwrap(), data.economy.building("fortification").unwrap());
        trench.defense * self.works_level(a.province, "trench") + fort.defense * self.works_level(a.province, "fortification")
    }

    /// `Military.works_reduction`: the share of the damage the province's works take off an attack on an army that holds it.
    pub fn works_reduction(&self, data: &Data, a: &Army, shelling: f64) -> f64 {
        if self.province_owner[a.province] != a.tag {
            return 0.0;
        }
        let (trench, fort) = (data.economy.building("trench").unwrap(), data.economy.building("fortification").unwrap());
        let shell = minf(0.9, trench.shell_reduction * self.works_level(a.province, "trench"));
        let hard = minf(0.9, fort.hard_reduction * self.works_level(a.province, "fortification"));
        shelling * shell + (1.0 - shelling) * hard
    }

    /// `Military.defense_multiplier`: terrain times entrenchment, the works included.
    pub fn defense_multiplier(&self, data: &Data, a: &Army) -> f64 {
        let c = &data.military.combat;
        data.military.terrain_def(&data.map.provinces[a.province].terrain).defense
            * (1.0 + c.entrench_defense_per_level * a.entrenchment(&data.military) as f64 + self.works_defense(data, a))
    }

    // ---------------------------------------------------------------- the day

    /// `Military.step_day`, without fronts, groups and offensives: armies march, fight, are supplied, take ground, and the
    /// nations with no ground left disband their armies. Returns whether a province changed hands (the economy is then worked
    /// out again).
    pub fn military_step_day(&mut self, data: &Data) -> bool {
        
        self.step_detachments(data);
        self.step_fronts(data);
        self.offensives_step_day(data);
        self.prune_groups(data);
        self.attack_lines_step_day();
        self.release_orphan_generals(data);
        self.train_recruits(data);
        self.drill(data);
        for a in &mut self.armies {
            a.fighting = false;
        }
        self.move_armies(data);
        self.fight(data);
        let captured = self.upkeep_and_occupy(data);
        self.collapse_nations(data);
        self.capitulation_step_day(data);
        self.refresh_men(data);
        if captured {
            self.recompute(data);
        }
        captured
    }

    fn move_armies(&mut self, data: &Data) {
        for i in 0..self.armies.len() {
            if self.armies[i].path.is_empty() || self.armies[i].embarked() {
                continue;
            }
            self.armies[i].still_days = 0;
            self.armies[i].move_days_left -= 1.0;
            if self.armies[i].move_days_left > 0.0 {
                continue;
            }
            let dest = self.armies[i].path[0];
            let tag = self.armies[i].tag.clone();
            if !self.can_enter(data, &tag, dest) {
                self.armies[i].path.clear();
                continue;
            }
            self.armies[i].path.remove(0);
            self.armies[i].province = dest;
            self.armies[i].attacking = false;
            let hostile = (0..self.armies.len()).any(|j| j != i && self.armies[j].province == dest && self.at_war(&tag, &self.armies[j].tag));
            self.armies[i].attacking = hostile;
            if hostile {
                self.armies[i].path.clear();
            } else if !self.armies[i].path.is_empty() {
                let speed = self.armies[i].speed(&data.military);
                self.armies[i].move_days_left = self.move_days(data, &tag, speed, dest, self.armies[i].path[0]);
            }
        }
    }

    /// `Military._by_province`: the armies in each province, provinces in the order they first appear.
    fn by_province(&self) -> Vec<(usize, Vec<usize>)> {
        let mut at: Vec<(usize, Vec<usize>)> = vec![];
        for (i, a) in self.armies.iter().enumerate() {
            if a.embarked() {
                continue;
            }
            match at.iter_mut().find(|(p, _)| *p == a.province) {
                Some((_, list)) => list.push(i),
                None => at.push((a.province, vec![i])),
            }
        }
        at
    }

    /// `Munitions.burn`: the day's burning before the fighting. Returns, by nation, the share of the day's need it met.
    fn burn_munitions(&mut self, data: &Data, fighting: &[usize], at: &[(usize, Vec<usize>)]) -> HashMap<String, f64> {
        let (mil, cfg) = (&data.military, &data.economy);
        let mut need: HashMap<String, f64> = HashMap::new();
        for &i in fighting {
            let a = &self.armies[i];
            *need.entry(a.tag.clone()).or_insert(0.0) += a.power(mil) * a.shelling_share(mil) * cfg.munitions_per_gun_power;
        }
        for i in 0..self.armies.len() {
            let a = &self.armies[i];
            if fighting.contains(&i) || a.embarked() || !self.is_at_war(&a.tag) || !self.facing(data, i, at) {
                continue;
            }
            *need.entry(a.tag.clone()).or_insert(0.0) += a.power(mil) * a.shelling_share(mil) * cfg.munitions_per_gun_power * cfg.munitions_idle_share;
        }
        let mut ratios = HashMap::new();
        for n in &mut self.nations {
            let want = need.get(&n.tag).copied().unwrap_or(0.0);
            if want <= 0.0 {
                // Guns that are not firing are not short.
                ratios.insert(n.tag.clone(), 1.0);
                continue;
            }
            let used = minf(want, n.munitions);
            n.munitions -= used;
            n.munitions_used_month += used;
            ratios.insert(n.tag.clone(), used / want);
        }
        ratios
    }

    /// Whether an enemy army stands in a province next to army `i`.
    fn facing(&self, data: &Data, i: usize, at: &[(usize, Vec<usize>)]) -> bool {
        let a = &self.armies[i];
        for p in data.map.neighbors(a.province) {
            if let Some((_, list)) = at.iter().find(|(q, _)| *q == p) {
                for &b in list {
                    if self.at_war(&a.tag, &self.armies[b].tag) {
                        return true;
                    }
                }
            }
        }
        false
    }

    /// `Military.naval_support`: what the nation's warships on shore support off a coastal province add to its armies attacking
    /// there (a share of their power).
    fn naval_support(&self, data: &Data, tag: &str, province: usize) -> f64 {
        let mut squadrons = 0usize;
        for zone in data.map.zones_of_port(province) {
            for fi in self.fleets_in_zone(zone) {
                let f = &self.fleets[fi];
                if f.tag != tag || f.mission != "support" || f.is_moving() {
                    continue;
                }
                squadrons += f.ships.iter().filter(|s| data.navy.def(&s.kind).capacity == 0).count();
            }
        }
        minf(data.navy.shore_max, data.navy.shore_per_squadron * squadrons as f64)
    }

    fn fight(&mut self, data: &Data) {
        let mil = &data.military;
        let at = self.by_province();
        let mut routed: Vec<usize> = vec![];
        // The day's munitions: every army in a battle burns its guns' need first.
        let mut in_battle: Vec<usize> = vec![];
        for (_, here) in &at {
            if here.len() < 2 {
                continue;
            }
            for &a in here {
                for &b in here {
                    if self.armies[a].tag != self.armies[b].tag && self.at_war(&self.armies[a].tag, &self.armies[b].tag) {
                        if !in_battle.contains(&a) {
                            in_battle.push(a);
                        }
                        break;
                    }
                }
            }
        }
        let shells = self.burn_munitions(data, &in_battle, &at);
        for (id, here) in &at {
            let id = *id;
            if here.len() < 2 {
                continue;
            }
            // foes: for each army with an enemy here, its enemies (in the order they stand)
            let mut foes: Vec<(usize, Vec<usize>)> = vec![];
            for &a in here {
                let list: Vec<usize> = here.iter().copied().filter(|&b| self.armies[a].tag != self.armies[b].tag && self.at_war(&self.armies[a].tag, &self.armies[b].tag)).collect();
                if !list.is_empty() {
                    foes.push((a, list));
                }
            }
            if foes.is_empty() {
                continue;
            }
            let mut incoming: HashMap<usize, f64> = foes.iter().map(|(a, _)| (*a, 0.0)).collect();
            let mut parts: HashMap<(usize, usize), f64> = HashMap::new();
            for (b, targets) in &foes {
                let bb = &self.armies[*b];
                let morale = data.war_support_morale_mult(self, &bb.tag);
                let burn = 1.0 - bb.shelling_share(mil) * mil.combat.shell_penalty * clampf(1.0 - shells.get(&bb.tag).copied().unwrap_or(1.0), 0.0, 1.0);
                let support = if bb.attacking { 1.0 + self.naval_support(data, &bb.tag, id) } else { 1.0 };
                let share = bb.power(mil) * morale * burn * support / targets.len() as f64;
                let shelling = bb.shelling_share(mil);
                for &a in targets {
                    let dealt = share * (1.0 - self.works_reduction(data, &self.armies[a], shelling));
                    *incoming.get_mut(&a).unwrap() += dealt;
                    parts.insert((a, *b), dealt);
                }
            }
            let bi = self.engagement(data, id, &foes);
            let mut today: Vec<(String, f64)> = vec![];
            for (a, enemies) in &foes {
                let a = *a;
                self.armies[a].fighting = true;
                let mult = if self.armies[a].attacking { 1.0 } else { self.defense_multiplier(data, &self.armies[a]) };
                let lost = apply_casualties(mil, &mut self.armies[a], incoming[&a] * mil.combat.casualties_per_point / mult);
                let tag = self.armies[a].tag.clone();
                add_to(&mut self.engagements[bi].lost, &tag, lost);
                let ni = self.nation_index[&tag];
                self.nations[ni].men_lost_month += lost;
                self.nations[ni].deaths_month += lost;
                add_to(&mut today, &tag, lost);
                if incoming[&a] > 0.0 {
                    // Charge the loss to the wars with the armies that inflicted it.
                    for &b in enemies {
                        let btag = self.armies[b].tag.clone();
                        if let Some(w) = self.war_between(&tag, &btag) {
                            *self.wars[w].losses.get_mut(&tag).unwrap() += lost * parts[&(a, b)] / incoming[&a];
                        }
                    }
                }
            }
            for (a, _) in &foes {
                if self.armies[*a].units.is_empty() || self.armies[*a].morale(mil) < mil.combat.rout_morale {
                    routed.push(*a);
                }
            }
        }
        for a in routed {
            self.retreat(data, a, &at);
        }
        self.armies.retain(|a| !a.units.is_empty());
        for a in &mut self.armies {
            if !a.fighting {
                a.attacking = false;
            }
        }
        // A battle is over once no hostile armies share the province.
        let ids: Vec<usize> = self.engagements.iter().map(|e| e.province).collect();
        for id in ids {
            let here: Vec<usize> = (0..self.armies.len()).filter(|&i| self.armies[i].province == id && !self.armies[i].embarked()).collect();
            let mut hostile = false;
            for &a in &here {
                for &b in &here {
                    hostile = hostile || self.at_war(&self.armies[a].tag, &self.armies[b].tag);
                }
            }
            if !hostile {
                self.finish_engagement(data, id);
            }
        }
    }

    /// `Military._engagement`: the battle being fought in a province, started if it is new; armies that join later are added
    /// to its starting strengths. Returns its index among the engagements.
    fn engagement(&mut self, data: &Data, id: usize, foes: &[(usize, Vec<usize>)]) -> usize {
        let bi = match self.engagements.iter().position(|e| e.province == id) {
            Some(i) => i,
            None => {
                self.engagements.push(Engagement {
                    id: self.next_battle_id,
                    province: id,
                    start_day: self.day_i(),
                    attacker: String::new(),
                    start_men: vec![],
                    lost: vec![],
                    armies: vec![],
                });
                self.next_battle_id += 1;
                self.engagements.len() - 1
            }
        };
        for (a, _) in foes {
            let army = &self.armies[*a];
            if self.engagements[bi].armies.contains(&army.id) {
                continue;
            }
            self.engagements[bi].armies.push(army.id);
            let men = army.men(&data.military);
            add_to(&mut self.engagements[bi].start_men, &army.tag, men);
            if army.attacking && self.engagements[bi].attacker.is_empty() {
                self.engagements[bi].attacker = army.tag.clone();
            }
        }
        bi
    }

    /// `Military._finish_engagement`: writes a finished battle into the record of each war it was part of. The winner is the
    /// one side still standing in the province.
    fn finish_engagement(&mut self, data: &Data, id: usize) {
        let pos = self.engagements.iter().position(|e| e.province == id).unwrap();
        let battle = self.engagements.remove(pos);
        self.last_battle_day.insert(id, self.day_i());
        let present: HashSet<&str> = self.armies.iter().filter(|a| a.province == id && !a.embarked()).map(|a| a.tag.as_str()).collect();
        let standing: Vec<&String> = battle.start_men.iter().map(|(t, _)| t).filter(|t| present.contains(t.as_str())).collect();
        let winner: String = if standing.len() == 1 { standing[0].clone() } else { String::new() };
        let tags: Vec<String> = battle.start_men.iter().map(|(t, _)| t.clone()).collect();
        let get = |list: &[(String, f64)], t: &str| list.iter().find(|(k, _)| k == t).map(|(_, v)| *v).unwrap_or(0.0);
        for i in 0..tags.len() {
            for j in i + 1..tags.len() {
                let Some(w) = self.war_between(&tags[i], &tags[j]) else { continue };
                let pair = [&tags[i], &tags[j]];
                let record_winner: &str = if pair.iter().any(|t| **t == winner) { &winner } else { "" };
                // Peace.record_battle
                self.wars[w].last_fight_day = self.day_i();
                if !record_winner.is_empty() {
                    let c = &data.diplomacy;
                    let loser = self.wars[w].other(record_winner).to_string();
                    let lost_loser = get(&battle.lost, &loser);
                    let lost_winner = get(&battle.lost, record_winner);
                    let ratio = clampf(lost_loser / maxf(lost_winner, 1.0), c.score_battle_ratio_min, c.score_battle_ratio_max);
                    *self.wars[w].battle_points.get_mut(record_winner).unwrap() += minf(c.score_battle_cap, c.score_battle_per_kmen * lost_loser / 1000.0 * ratio);
                }
                // WarSupport.on_battle
                if !record_winner.is_empty() {
                    let loser = if record_winner == pair[1].as_str() { pair[0].clone() } else { pair[1].clone() };
                    let home = self.province_owner[id] == record_winner;
                    let ws = &data.war_support;
                    self.change_war_support(record_winner, if home { ws.home_win_bonus } else { ws.win_bonus });
                    self.gain_prestige(record_winner, data.diplomacy.prestige_battle_win);
                    self.change_war_support(&loser, -ws.loss_penalty);
                }
            }
        }
    }

    fn enemy_tags(&self, a: usize, at: &[(usize, Vec<usize>)]) -> Vec<String> {
        let me = &self.armies[a];
        let mut tags: Vec<String> = vec![];
        if let Some((_, list)) = at.iter().find(|(p, _)| *p == me.province) {
            for &b in list {
                let t = &self.armies[b].tag;
                if self.at_war(&me.tag, t) && !tags.contains(t) {
                    tags.push(t.clone());
                }
            }
        }
        tags
    }

    /// `Military._add_loss`: men added to a war's tally for a nation, split between the wars with the given enemies (or all
    /// its wars when none are given).
    pub(crate) fn add_loss(&mut self, tag: &str, enemies: &[String], men: f64, field: &str) {
        if men <= 0.0 {
            return;
        }
        let ni = self.nation_index[tag];
        self.nations[ni].men_lost_month += men;
        self.nations[ni].deaths_month += men;
        let wars: Vec<usize> = if enemies.is_empty() {
            self.wars_of(tag)
        } else {
            enemies.iter().filter_map(|e| self.war_between(tag, e)).collect()
        };
        let share = men / wars.len() as f64;
        for w in wars {
            let map = match field {
                "losses" => &mut self.wars[w].losses,
                "attrition" => &mut self.wars[w].attrition,
                _ => &mut self.wars[w].surrendered,
            };
            *map.get_mut(tag).unwrap() += share;
        }
    }

    /// `Military._retreat`: a beaten army falls back to the best neighbouring province that its nation still holds. With
    /// none, it is cut off and lost.
    fn retreat(&mut self, data: &Data, a: usize, at: &[(usize, Vec<usize>)]) {
        let mil = &data.military;
        if self.armies[a].units.is_empty() {
            return;
        }
        let enemies = self.enemy_tags(a, at);
        let tag = self.armies[a].tag.clone();
        let mut best = 0;
        for n in data.map.neighbors(self.armies[a].province) {
            if self.province_controller[n] != tag {
                continue;
            }
            let blocked = at.iter().find(|(p, _)| *p == n).map(|(_, list)| list.iter().any(|&b| self.at_war(&tag, &self.armies[b].tag))).unwrap_or(false);
            if !blocked {
                best = n;
                break;
            }
        }
        if best == 0 {
            let men = self.armies[a].men(mil);
            self.armies[a].units.clear();
            self.add_loss(&tag, &enemies, men, "surrendered");
            return;
        }
        let before = self.armies[a].men(mil);
        let loss = mil.combat.routed_loss + self.pursuit(data, a, at);
        for u in &mut self.armies[a].units {
            u.strength *= 1.0 - loss;
        }
        let after = self.armies[a].men(mil);
        self.add_loss(&tag, &enemies, before - after, "losses");
        let army = &mut self.armies[a];
        army.province = best;
        army.path.clear();
        army.still_days = 0;
        army.attacking = false;
        army.fighting = false;
    }

    /// `Military.pursuit`: the extra share a routed army loses to the pursuit: the cavalry's share of the victors' men.
    fn pursuit(&self, data: &Data, a: usize, at: &[(usize, Vec<usize>)]) -> f64 {
        let mil = &data.military;
        let me = &self.armies[a];
        let (mut men, mut horse) = (0.0, 0.0);
        if let Some((_, list)) = at.iter().find(|(p, _)| *p == me.province) {
            for &b in list {
                if self.at_war(&me.tag, &self.armies[b].tag) {
                    for u in &self.armies[b].units {
                        men += u.men(mil);
                        if u.unit_type == "cavalry" {
                            horse += u.men(mil);
                        }
                    }
                }
            }
        }
        if men <= 0.0 {
            return 0.0;
        }
        minf(mil.combat.pursuit * horse / men, mil.combat.pursuit_max)
    }

    /// `Military._upkeep_and_occupy`: supply attrition, reinforcement, morale recovery, digging in, and taking provinces.
    /// Returns true if any province changed hands.
    fn upkeep_and_occupy(&mut self, data: &Data) -> bool {
        let mil = &data.military;
        for i in 0..self.armies.len() {
            if self.armies[i].embarked() {
                self.armies[i].supplied = true;
                continue;
            }
            if self.armies[i].landing_days > 0 {
                self.armies[i].landing_days -= 1;
            }
            let (tag, province) = (self.armies[i].tag.clone(), self.armies[i].province);
            self.armies[i].supplied = self.supply_cost(data, &tag, province) < f64::INFINITY;
            if !self.armies[i].supplied && self.armies[i].landed_supply > 0 {
                self.armies[i].supplied = true;
            }
            if self.armies[i].landed_supply > 0 {
                self.armies[i].landed_supply -= 1;
            }
            if !self.armies[i].supplied {
                let before = self.armies[i].men(mil);
                let a = &mut self.armies[i];
                for k in (0..a.units.len()).rev() {
                    a.units[k].strength -= mil.supply.attrition;
                    a.units[k].morale = maxf(0.0, a.units[k].morale - mil.supply.attrition_morale);
                    if a.units[k].strength < mil.combat.min_strength {
                        a.units.remove(k);
                    }
                }
                let lost = before - self.armies[i].men(mil);
                self.add_loss(&tag, &[], lost, "attrition");
            } else if !self.armies[i].fighting {
                let ni = self.nation_index[&tag];
                let aura = self.city_aura(data, &tag, province);
                for k in 0..self.armies[i].units.len() {
                    let u = &mut self.armies[i].units[k];
                    u.morale = minf(1.0, u.morale + mil.combat.morale_regain * (1.0 + mil.cities.morale * aura));
                    if u.strength < 1.0 && self.nations[ni].manpower > 0 {
                        let want = minf(1.0 - u.strength, mil.supply.reinforce_rate * (1.0 + mil.cities.reinforce * aura));
                        let size = full_size(mil, u);
                        let taken = self.nations[ni].manpower.min((want * size as f64).ceil() as i64);
                        self.nations[ni].manpower -= taken;
                        u.strength = minf(1.0, u.strength + taken as f64 / size as f64);
                    }
                }
            }
            if self.armies[i].fighting && !self.armies[i].units.is_empty() {
                // A city's aura steadies the men even in battle.
                let steady = self.city_aura(data, &tag, province) * mil.cities.morale * mil.cities.morale_fighting;
                if steady > 0.0 {
                    for u in &mut self.armies[i].units {
                        u.morale = minf(1.0, u.morale + mil.combat.morale_regain * steady);
                    }
                }
            }
            if self.armies[i].path.is_empty() {
                self.armies[i].still_days += 1;
            }
        }
        self.armies.retain(|a| !a.units.is_empty());

        let mut captured = false;
        let at = self.by_province();
        for (id, here) in &at {
            let id = *id;
            let holder = self.province_controller[id].clone();
            let mut occupier = String::new();
            for &a in here {
                let t = &self.armies[a].tag;
                if *t == holder || !self.at_war(t, &holder) {
                    continue;
                }
                let contested = here.iter().any(|&b| self.at_war(t, &self.armies[b].tag));
                if !contested {
                    occupier = t.clone();
                    break;
                }
            }
            if occupier.is_empty() {
                self.occupation.remove(&id);
                continue;
            }
            let mut progress = match self.occupation.get(&id) {
                Some((t, d)) if *t == occupier => (t.clone(), *d),
                _ => (occupier.clone(), 0),
            };
            progress.1 += 1;
            self.occupation.insert(id, progress.clone());
            // An army that walks into a province nobody defends takes it the same day; where a battle was just fought it takes
            // the terrain's time to hold it (the mopping up).
            let mopping = self.day_i() - self.last_battle_day.get(&id).copied().unwrap_or(-1000) <= mil.occupation_mop_up_days;
            let mut need = if mopping { mil.terrain_def(&data.map.provinces[id].terrain).occupy_days } else { 1 };
            // Cavalry sweeps the ground in a fraction of the time.
            if need > 1 && here.iter().any(|&a| self.armies[a].tag == occupier && self.armies[a].units.iter().any(|u| u.unit_type == "cavalry")) {
                need = ((need as f64 * mil.occupation_cavalry_mult).ceil() as i64).max(1);
            }
            if progress.1 >= need {
                self.occupation.remove(&id);
                self.set_controller(id, &occupier);
                captured = true;
                if let Some(w) = self.war_between(&occupier, &holder) {
                    let pop = self.province_population[id] as i64;
                    let e = self.wars[w].captured.get_mut(&occupier).unwrap();
                    e.0 += 1;
                    e.1 += pop;
                }
            }
        }
        let held: Vec<usize> = self.occupation.keys().copied().collect();
        for id in held {
            if !at.iter().any(|(p, _)| *p == id) {
                self.occupation.remove(&id);
            }
        }
        captured
    }

    /// `Military._collapse_nations`: a nation with no province left in its hands cannot keep an army.
    fn collapse_nations(&mut self, data: &Data) {
        let holding: HashSet<&String> = self.province_controller.iter().skip(1).collect();
        let gone: Vec<String> = self.nations.iter().map(|n| n.tag.clone()).filter(|t| !holding.contains(t)).collect();
        for tag in gone {
            let mut men = 0.0;
            let ni = self.nation_index[&tag];
            let mut had_any = !self.nations[ni].recruiting.is_empty();
            self.nations[ni].recruiting.clear();
            for a in self.armies.iter().filter(|a| a.tag == tag) {
                men += a.men(&data.military);
                had_any = true;
            }
            self.armies.retain(|a| a.tag != tag);
            if !had_any {
                continue;
            }
            self.add_loss(&tag, &[], men, "surrendered");
        }
    }

    // ---------------------------------------------------------------- capitulation (`scripts/sim/capitulation.gd`)

    /// `Peace.province_value`: what a province is worth in a war: its people, its city and its buildings. Worked out once a day
    /// (the first time it is asked that day), as the game does: a change in the people later in the day is not seen until the next.
    pub fn province_value(&self, data: &Data, id: usize) -> f64 {
        let today = self.calendar.days_elapsed as i64;
        {
            let mut cache = self.value_cache.borrow_mut();
            if cache.0 != today {
                *cache = (today, HashMap::new(), HashMap::new());
                for c in &self.cities {
                    let pop = self.city_population(c);
                    *cache.2.entry(c.province).or_insert(0) += pop;
                }
            }
            if let Some(&v) = cache.1.get(&id) {
                return v;
            }
        }
        let w = &data.diplomacy.capitulation;
        let city_pop = self.value_cache.borrow().2.get(&id).copied().unwrap_or(0);
        let mut v = w.value_population * self.province_population[id] as f64 / 1e6 + w.value_city * city_pop as f64 / 1e6;
        for (kind, level) in &self.province_buildings[id] {
            let weight = w.value_buildings.iter().find(|(k, _)| k == kind).map(|(_, x)| *x).unwrap_or(0.0);
            v += weight * *level as f64;
        }
        let v = maxf(v, w.value_minimum);
        self.value_cache.borrow_mut().1.insert(id, v);
        v
    }

    /// `Cities.population`: a city grows and shrinks with its province's people.
    pub fn city_population(&self, city: &crate::state::City) -> i64 {
        let id = city.province;
        if id < 1 || id >= self.province_population.len() || id >= self.province_pop_base.len() || self.province_pop_base[id] <= 0 {
            return city.pop;
        }
        let ratio = self.province_population[id] as f64 / self.province_pop_base[id] as f64;
        (city.pop as f64 * clampf(ratio, 0.4, 3.0)).round() as i64
    }

    pub fn home_capital(&self, tag: &str) -> i64 {
        let n = self.nation(tag);
        if n.home_capital > 0 {
            n.home_capital
        } else {
            n.capital
        }
    }

    pub fn provinces_value(&self, data: &Data, tag: &str) -> f64 {
        let mut total = 0.0;
        for &id in &self.nation(tag).provinces {
            total += self.province_value(data, id);
        }
        total
    }

    /// `Capitulation.capital_bonus`: what the home capital adds to its province value so that it is `capital_share` of the
    /// nation's whole.
    pub fn capital_bonus(&self, data: &Data, tag: &str) -> f64 {
        let home = self.home_capital(tag);
        let total = self.provinces_value(data, tag);
        let own = if home > 0 { self.province_value(data, home as usize) } else { 0.0 };
        let share = data.diplomacy.capitulation.capital_share;
        maxf(0.0, (share * total - own) / (1.0 - share))
    }

    pub fn relocated(&self, tag: &str) -> bool {
        let n = self.nation(tag);
        n.capital > 0 && n.capital != self.home_capital(tag)
    }

    /// `Capitulation.progress`: the share of the nation's whole value its enemies hold: 0 to 1.
    pub fn capitulation_progress(&self, data: &Data, tag: &str) -> f64 {
        self.capitulation_progress_by(data, tag, "")
    }

    /// `Capitulation.progress` with a holder: the share of the whole that one enemy holds.
    pub fn capitulation_progress_by(&self, data: &Data, tag: &str, holder_filter: &str) -> f64 {
        let provinces_value = self.provinces_value(data, tag);
        let bonus = self.capital_bonus(data, tag);
        let whole = bonus + provinces_value;
        if whole <= 0.0 {
            return 0.0;
        }
        let c = &data.diplomacy.capitulation;
        let home = self.home_capital(tag);
        let n = self.nation(tag);
        let mut lost = 0.0;
        for &id in &n.provinces {
            let holder = &self.province_controller[id];
            if holder == tag || (!holder_filter.is_empty() && holder != holder_filter) || !self.at_war(tag, holder) {
                continue;
            }
            let mut v = self.province_value(data, id);
            if id as i64 == home {
                v += bonus;
            } else if self.relocated(tag) && id as i64 == n.capital {
                v += bonus * c.relocated_bonus;
            }
            lost += v;
        }
        minf(1.0, lost / whole)
    }
}

/// `Military._apply_casualties`: men lost by the army in this call.
fn apply_casualties(cfg: &MilitaryConfig, a: &mut Army, casualties: f64) -> f64 {
    let total = a.men(cfg);
    if total <= 0.0 {
        return 0.0;
    }
    let frac = minf(casualties / total, 1.0);
    let morale_loss = frac * cfg.combat.morale_loss_per_casualty + cfg.combat.morale_loss_base;
    let dilution = cfg.training_loss_dilution;
    for i in (0..a.units.len()).rev() {
        let u = &mut a.units[i];
        u.strength *= 1.0 - frac;
        u.experience *= 1.0 - frac * dilution;
        u.morale = maxf(0.0, u.morale - morale_loss);
        if u.strength < cfg.combat.min_strength {
            a.units.remove(i);
        }
    }
    total - a.men(cfg)
}

/// Adds to a tag's entry in an ordered list, appending it the first time.
fn add_to(list: &mut Vec<(String, f64)>, tag: &str, x: f64) {
    match list.iter_mut().find(|(k, _)| k == tag) {
        Some(slot) => slot.1 += x,
        None => list.push((tag.to_string(), x)),
    }
}

impl Data {
    /// `WarSupport.morale_mult`: the multiplier on the fighting power of a nation's armies; 1 in peace.
    pub fn war_support_morale_mult(&self, gs: &GameState, tag: &str) -> f64 {
        if !gs.is_at_war(tag) {
            return 1.0;
        }
        self.war_support.morale_mult_at(gs.nation(tag).war_support)
    }
}
