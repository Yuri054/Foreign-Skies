//! The navy (`scripts/sim/navy.gd`, `naval_combat.gd`, `blockade.gd`, `fleet.gd`, `ship.gd` and the fleet commands): fleets sail
//! through sea zones, fight when hostile fleets meet, are repaired in port and worn down beyond their range, finish the ships being
//! built, carry armies overseas, and hold the sea: whoever holds a zone against a nation blockades its trade.
//!
//! The rolls of the sea battles are not random (`NavalCombat.roll` is a hash of the zone, the day and the two fleets), so the port
//! has no generator to match. `String.hash()` is the djb2 hash of the text.

use crate::gd::{clampf, lerpf, maxf, minf};
use crate::state::{Data, Fleet, GameState, SeaBattle, SeaControl, Ship};

/// Kilometres a pixel of the map stands for (`Navy.KM_PER_PX`).
const KM_PER_PX: f64 = 0.6928;

/// `String.hash()`: djb2 over the characters, in 32 bits.
pub fn string_hash(s: &str) -> i64 {
    let mut h: u32 = 5381;
    for c in s.chars() {
        h = h.wrapping_mul(33).wrapping_add(c as u32);
    }
    h as i64
}

fn bump(list: &mut Vec<(String, f64)>, tag: &str, by: f64) {
    match list.iter_mut().find(|(t, _)| t == tag) {
        Some(slot) => slot.1 += by,
        None => list.push((tag.to_string(), by)),
    }
}

impl GameState {
    fn nday(&self) -> i64 {
        self.calendar.days_elapsed as i64
    }

    // ---------------------------------------------------------------- ships and fleets

    /// `Ship.power`: the type's attack, scaled by strength and dulled by low morale.
    pub fn ship_power(&self, data: &Data, s: &Ship) -> f64 {
        data.navy.def(&s.kind).attack * s.strength * lerpf(data.military.morale_floor_effect, 1.0, s.morale)
    }

    /// `Fleet.power`.
    pub fn fleet_power(&self, data: &Data, f: &Fleet) -> f64 {
        let mut total = 0.0;
        for s in &f.ships {
            total += self.ship_power(data, s);
        }
        total
    }

    /// `Fleet.morale`: mean morale, weighted by strength.
    pub fn fleet_morale(f: &Fleet) -> f64 {
        let (mut total, mut weight) = (0.0, 0.0);
        for s in &f.ships {
            total += s.morale * s.strength;
            weight += s.strength;
        }
        if weight > 0.0 {
            total / weight
        } else {
            0.0
        }
    }

    /// `Fleet.speed`: km per day of the slowest ship.
    pub fn fleet_speed(&self, data: &Data, f: &Fleet) -> f64 {
        let mut slowest = f64::INFINITY;
        for s in &f.ships {
            slowest = minf(slowest, data.navy.def(&s.kind).speed);
        }
        if slowest < f64::INFINITY {
            slowest
        } else {
            0.0
        }
    }

    /// `Fleet.capacity`: men the fleet's transports can carry.
    pub fn fleet_capacity(&self, data: &Data, f: &Fleet) -> i64 {
        f.ships.iter().map(|s| data.navy.def(&s.kind).capacity).sum()
    }

    pub fn count_of(f: &Fleet, kind: &str) -> usize {
        f.ships.iter().filter(|s| s.kind == kind).count()
    }

    /// `Navy.new_fleet`: a fleet in a port; returns its index.
    pub fn new_fleet(&mut self, tag: &str, name: &str, port: usize) -> usize {
        let f = Fleet::new(self.next_fleet_id, tag, name, port);
        self.next_fleet_id += 1;
        self.fleets.push(f);
        self.fleets.len() - 1
    }

    pub fn fleet_index(&self, id: u32) -> Option<usize> {
        self.fleets.iter().position(|f| f.id == id)
    }

    /// `Navy.fleets_in_port`: indices, by fleet id.
    pub fn fleets_in_port(&self, province: usize) -> Vec<usize> {
        let mut out: Vec<usize> = (0..self.fleets.len()).filter(|&i| self.fleets[i].port == province).collect();
        out.sort_by_key(|&i| self.fleets[i].id);
        out
    }

    /// `Navy.fleets_in_zone`: fleets at sea in a zone, by fleet id.
    pub fn fleets_in_zone(&self, zone: usize) -> Vec<usize> {
        let mut out: Vec<usize> = (0..self.fleets.len()).filter(|&i| self.fleets[i].zone == zone).collect();
        out.sort_by_key(|&i| self.fleets[i].id);
        out
    }

    /// `Navy.can_dock`: whether ships of a nation may lie in a province's port.
    pub fn can_dock(&self, data: &Data, tag: &str, province: usize) -> bool {
        if province < 1 || province >= self.province_owner.len() || self.port_level(province) < 1 {
            return false;
        }
        if data.map.zones_of_port(province).is_empty() {
            return false;
        }
        let (o, c) = (&self.province_owner[province], &self.province_controller[province]);
        if o == tag || c == tag {
            return true;
        }
        if self.at_war(tag, o) || self.at_war(tag, c) {
            return false;
        }
        self.has_passage(data, o, tag) && self.has_passage(data, c, tag)
    }

    // ---------------------------------------------------------------- the water

    /// `Navy.zone_days`: days to sail from one zone to a neighbouring one at a speed in km per day.
    pub fn zone_days(data: &Data, speed: f64, from: usize, to: usize) -> f64 {
        let (a, b) = (data.map.sea_zone_centers[from], data.map.sea_zone_centers[to]);
        let (dx, dy) = (a.0 - b.0, a.1 - b.1);
        let d: f32 = (dx * dx + dy * dy).sqrt();
        let km = d as f64 * KM_PER_PX;
        maxf((km / maxf(speed, 1.0)).ceil(), data.navy.min_hop_days)
    }

    /// `Navy.find_path`: the cheapest route through the zones from any of `from_zones` to any of `to_zones`, as the zones in
    /// order, beginning with the zone it starts in. Empty if there is none.
    pub fn sea_find_path(data: &Data, speed: f64, from_zones: &[usize], to_zones: &[usize]) -> Vec<usize> {
        if from_zones.is_empty() || to_zones.is_empty() {
            return vec![];
        }
        let mut dist: std::collections::HashMap<usize, f64> = std::collections::HashMap::new();
        let mut prev: std::collections::HashMap<usize, usize> = std::collections::HashMap::new();
        let mut open: Vec<usize> = vec![];
        for &z in from_zones {
            dist.insert(z, 0.0);
            open.push(z);
        }
        let mut goal = 0;
        while !open.is_empty() {
            let mut best = 0;
            for i in 0..open.len() {
                if dist[&open[i]] < dist[&open[best]] || (dist[&open[i]] == dist[&open[best]] && open[i] < open[best]) {
                    best = i;
                }
            }
            let z = open.remove(best);
            if to_zones.contains(&z) {
                goal = z;
                break;
            }
            for &n in data.map.sea_neighbors(z) {
                let d = dist[&z] + Self::zone_days(data, speed, z, n);
                if !dist.contains_key(&n) || d < dist[&n] {
                    dist.insert(n, d);
                    prev.insert(n, z);
                    if !open.contains(&n) {
                        open.push(n);
                    }
                }
            }
        }
        if goal == 0 {
            return vec![];
        }
        let mut at = goal;
        let mut path = vec![at];
        while let Some(&p) = prev.get(&at) {
            at = p;
            path.insert(0, at);
        }
        path
    }

    // ---------------------------------------------------------------- the day

    /// `Navy.step_day`. The economy is asked to work out again (as `Economy.request` does inside the day's step) if ships were
    /// finished.
    pub fn navy_step_day(&mut self, data: &Data) {
        let built = self.navy_build(data);
        for i in 0..self.fleets.len() {
            self.sail(data, i);
        }
        self.naval_combat_step_day(data);
        self.settle_embarked(data);
        self.blockade_step_day(data);
        if built {
            self.economy_dirty = true;
        }
    }

    /// `Navy._build`: finishes the ships whose building is over and puts them in the yard's port.
    fn navy_build(&mut self, data: &Data) -> bool {
        let mut finished = false;
        for ni in 0..self.nations.len() {
            let tag = self.nations[ni].tag.clone();
            for i in (0..self.nations[ni].shipbuilding.len()).rev() {
                if self.nations[ni].shipbuilding[i].points_left > 0.0001 {
                    continue;
                }
                let job = self.nations[ni].shipbuilding.remove(i);
                // A yard that has changed hands launches nothing.
                if self.province_controller[job.province] != tag {
                    continue;
                }
                let mut host: Option<usize> = None;
                for f in self.fleets_in_port(job.province) {
                    let fl = &self.fleets[f];
                    if fl.tag == tag && !fl.is_moving() && !fl.fighting && host.map(|h| fl.ships.len() < self.fleets[h].ships.len()).unwrap_or(true) {
                        host = Some(f);
                    }
                }
                let host = match host {
                    Some(h) => h,
                    None => self.new_fleet(&tag, &format!("New squadrons at {}", data.map.provinces[job.province].name), job.province),
                };
                self.fleets[host].ships.push(Ship::new(&job.kind));
                finished = true;
            }
        }
        finished
    }

    /// `Navy._sail`.
    fn sail(&mut self, data: &Data, i: usize) {
        let speed = self.fleet_speed(data, &self.fleets[i]);
        let f = &mut self.fleets[i];
        if !f.path.is_empty() {
            f.move_days_left -= 1.0;
            if f.move_days_left > 0.0 {
                return;
            }
            f.zone = f.path.remove(0);
            f.port = 0;
            if !f.path.is_empty() {
                f.move_days_left = Self::zone_days(data, speed, f.zone, f.path[0]);
            } else if f.dest_port > 0 {
                f.entering = true;
                f.move_days_left = data.navy.port_days;
            } else {
                f.move_days_left = 0.0;
            }
            return;
        }
        if f.entering {
            f.move_days_left -= 1.0;
            if f.move_days_left > 0.0 {
                return;
            }
            f.entering = false;
            f.port = f.dest_port;
            f.dest_port = 0;
            f.zone = 0;
        }
    }

    // ---------------------------------------------------------------- fighting at sea

    /// `NavalCombat.roll`: a deterministic stand-in for a dice roll, 0 to 999.
    pub fn sea_roll(&self, zone: usize, a: u32, b: u32) -> i64 {
        let (lo, hi) = (a.min(b) as i64, a.max(b) as i64);
        let mut h: i64 = (zone as i64).wrapping_mul(73856093) ^ self.nday().wrapping_mul(19349663) ^ lo.wrapping_mul(83492791) ^ hi.wrapping_mul(40503);
        h = (h ^ (h >> 13)).wrapping_mul(1274126177);
        ((h ^ (h >> 16)) & 0x7fffffff) % 1000
    }

    /// `NavalCombat.detection`: mean detection of a fleet's ships, weighted by strength.
    fn detection(data: &Data, f: &Fleet) -> f64 {
        let (mut total, mut weight) = (0.0, 0.0);
        for s in &f.ships {
            total += data.navy.def(&s.kind).detection * s.strength;
            weight += s.strength;
        }
        if weight > 0.0 {
            total / weight
        } else {
            0.0
        }
    }

    /// `NavalCombat.contact`: whether two hostile fleets in one zone find each other today.
    fn contact(&self, data: &Data, a: usize, b: usize) -> bool {
        let (fa, fb) = (&self.fleets[a], &self.fleets[b]);
        if fa.engaged && fb.engaged {
            return true;
        }
        let base = data.navy.combat.contact_base;
        let pa = clampf(base * Self::detection(data, fa), 0.0, 1.0);
        let pb = clampf(base * Self::detection(data, fb), 0.0, 1.0);
        let p = 1.0 - (1.0 - pa) * (1.0 - pb);
        self.sea_roll(fa.zone, fa.id, fb.id) < (p * 1000.0) as i64
    }

    /// `NavalCombat.firepower`: what a fleet brings against another; submarines are blunted by the target's destroyer screen.
    fn firepower(&self, data: &Data, f: &Fleet, target: &Fleet) -> f64 {
        let screen = Self::count_of(target, "destroyer") as f64;
        let sub_mult = 1.0 / (1.0 + data.navy.combat.submarine_screen * screen);
        let mut total = 0.0;
        for s in &f.ships {
            let p = self.ship_power(data, s);
            total += if s.kind == "submarine" { p * sub_mult } else { p };
        }
        total
    }

    /// `NavalCombat.step_day`.
    fn naval_combat_step_day(&mut self, data: &Data) {
        for f in &mut self.fleets {
            f.fighting = false;
        }
        self.sea_fight(data);
        self.fleets.retain(|f| !f.ships.is_empty());
        self.fleet_upkeep(data);
    }

    fn sea_fight(&mut self, data: &Data) {
        // fleets at sea by zone, zones in the order first met
        let mut by_zone: Vec<(usize, Vec<usize>)> = vec![];
        for i in 0..self.fleets.len() {
            let f = &self.fleets[i];
            if f.zone > 0 && f.port == 0 {
                match by_zone.iter_mut().find(|(z, _)| *z == f.zone) {
                    Some(slot) => slot.1.push(i),
                    None => by_zone.push((f.zone, vec![i])),
                }
            }
        }
        let mut routed: Vec<usize> = vec![];
        for (zone, here) in by_zone {
            // foes: fleet -> the fleets it fights, in the order the fleets were first matched
            let mut foes: Vec<(usize, Vec<usize>)> = vec![];
            if here.len() >= 2 {
                for i in 0..here.len() {
                    for j in i + 1..here.len() {
                        let (a, b) = (here[i], here[j]);
                        if self.fleets[a].tag != self.fleets[b].tag && self.at_war(&self.fleets[a].tag, &self.fleets[b].tag) && self.contact(data, a, b) {
                            for (x, y) in [(a, b), (b, a)] {
                                match foes.iter_mut().find(|(k, _)| *k == x) {
                                    Some(slot) => slot.1.push(y),
                                    None => foes.push((x, vec![y])),
                                }
                            }
                        }
                    }
                }
            }
            if foes.is_empty() {
                continue;
            }
            // Everyone's shots are fired before anyone's losses are counted.
            let mut incoming: Vec<(usize, f64)> = foes.iter().map(|(a, _)| (*a, 0.0)).collect();
            for (b, targets) in &foes {
                let share = data.war_support_morale_mult(self, &self.fleets[*b].tag) / targets.len() as f64;
                for a in targets {
                    let shot = self.firepower(data, &self.fleets[*b], &self.fleets[*a]) * share;
                    incoming.iter_mut().find(|(k, _)| k == a).unwrap().1 += shot;
                }
            }
            let battle_at = self.sea_engagement(zone, &foes);
            for (a, targets) in &foes {
                self.fleets[*a].fighting = true;
                self.fleets[*a].engaged = true;
                let mut enemies: Vec<String> = vec![];
                for b in targets {
                    if !enemies.contains(&self.fleets[*b].tag) {
                        enemies.push(self.fleets[*b].tag.clone());
                    }
                }
                let points = incoming.iter().find(|(k, _)| k == a).unwrap().1;
                self.sea_damage(data, *a, points, &enemies, battle_at);
            }
            for (a, targets) in &foes {
                for b in targets {
                    if let Some(w) = self.war_between(&self.fleets[*a].tag, &self.fleets[*b].tag) {
                        self.wars[w].last_fight_day = self.nday();
                    }
                }
            }
            for (a, _) in &foes {
                let f = &self.fleets[*a];
                if !f.ships.is_empty() && Self::fleet_morale(f) < data.navy.combat.rout_morale && !f.retreating {
                    routed.push(*a);
                }
            }
        }
        for f in routed {
            self.sea_retreat(data, f);
        }
        // A fleet that no longer shares its zone with an enemy it can fight is free again, and a battle with no hostile fleets left
        // in the zone is over.
        for f in &mut self.fleets {
            if f.ships.is_empty() {
                continue;
            }
            if !f.fighting {
                f.engaged = false;
            }
        }
        let zones: Vec<usize> = self.sea_battles.iter().map(|(z, _)| *z).collect();
        for zone in zones {
            let here = self.fleets_in_zone(zone);
            let mut hostile = false;
            for &a in &here {
                for &b in &here {
                    hostile = hostile || (self.fleets[a].engaged && self.fleets[b].engaged && self.at_war(&self.fleets[a].tag, &self.fleets[b].tag));
                }
            }
            if !hostile {
                self.finish_sea_engagement(zone);
            }
        }
    }

    /// `NavalCombat._damage`: damages a fleet by `points` of enemy fire.
    fn sea_damage(&mut self, data: &Data, fi: usize, points: f64, enemies: &[String], battle_at: usize) {
        let c = &data.navy.combat;
        let zone = self.fleets[fi].zone;
        let mut asw = false;
        for b in &self.fleets {
            if b.zone == zone && enemies.contains(&b.tag) && Self::count_of(b, "destroyer") > 0 {
                asw = true;
            }
        }
        let mut weights: Vec<f64> = vec![];
        let mut total_weight = 0.0;
        for s in &self.fleets[fi].ships {
            let d = data.navy.def(&s.kind);
            let mut w = d.exposure * s.strength;
            if s.kind == "submarine" && !asw {
                w *= c.submarine_evasion;
            }
            weights.push(w);
            total_weight += w;
        }
        if total_weight <= 0.0 || points <= 0.0 {
            return;
        }
        let (mut lost, mut crew_lost) = (0.0, 0.0);
        let mut sunk: Vec<usize> = vec![];
        for i in 0..self.fleets[fi].ships.len() {
            let s = &mut self.fleets[fi].ships[i];
            let d = data.navy.def(&s.kind);
            let mut hit = points * c.damage_per_point * weights[i] / total_weight / d.hull;
            hit = minf(hit, s.strength);
            s.strength -= hit;
            lost += hit;
            crew_lost += hit * d.crew;
            s.morale = maxf(0.0, s.morale - (hit * c.morale_loss_per_damage + c.morale_loss_base));
            if s.strength < c.min_strength {
                sunk.push(i);
            }
        }
        let tag = self.fleets[fi].tag.clone();
        for &i in sunk.iter().rev() {
            let s = self.fleets[fi].ships.remove(i);
            crew_lost += s.strength * data.navy.def(&s.kind).crew;
            let battle = &mut self.sea_battles[battle_at].1;
            match battle.sunk.iter_mut().find(|(t, _)| *t == tag) {
                Some(slot) => slot.1 += 1,
                None => battle.sunk.push((tag.clone(), 1)),
            }
            let ni = self.nation_index[&tag];
            self.nations[ni].ships_lost += 1;
        }
        let battle = &mut self.sea_battles[battle_at].1;
        match battle.lost.iter_mut().find(|(t, _)| *t == tag) {
            Some(slot) => slot.1 += lost,
            None => battle.lost.push((tag.clone(), lost)),
        }
        self.add_loss(&tag, enemies, crew_lost, "losses");
    }

    /// `NavalCombat._retreat`: a beaten fleet runs for the nearest port its nation may use. With none in reach it fights on.
    fn sea_retreat(&mut self, data: &Data, fi: usize) {
        let tag = self.fleets[fi].tag.clone();
        let mut targets: Vec<usize> = vec![];
        let mut port_of: Vec<(usize, usize)> = vec![];
        for z in 1..data.map.sea_zone_count() {
            for &p in data.map.ports_in_zone(z) {
                if self.can_dock(data, &tag, p) {
                    targets.push(z);
                    if !port_of.iter().any(|(k, _)| *k == z) {
                        port_of.push((z, p));
                    }
                    break;
                }
            }
        }
        let speed = self.fleet_speed(data, &self.fleets[fi]);
        let zone = self.fleets[fi].zone;
        let path = Self::sea_find_path(data, speed, &[zone], &targets);
        if path.is_empty() {
            return;
        }
        let last = *path.last().unwrap();
        let dest = port_of.iter().find(|(k, _)| *k == last).unwrap().1;
        let f = &mut self.fleets[fi];
        f.retreating = true;
        f.path = path[1..].to_vec();
        f.dest_port = dest;
        f.entering = false;
        if f.path.is_empty() {
            f.entering = true;
            f.move_days_left = data.navy.port_days;
        } else {
            f.move_days_left = Self::zone_days(data, speed, f.zone, f.path[0]);
        }
    }

    /// `NavalCombat._engagement`: the battle being fought in a zone, started if it is new. Returns its index in `sea_battles`.
    fn sea_engagement(&mut self, zone: usize, foes: &[(usize, Vec<usize>)]) -> usize {
        let at = match self.sea_battles.iter().position(|(z, _)| *z == zone) {
            Some(i) => i,
            None => {
                let b = SeaBattle {
                    id: self.next_battle_id,
                    zone,
                    start_day: self.nday(),
                    days: 0,
                    fleets: vec![],
                    start_ships: vec![],
                    lost: vec![],
                    sunk: vec![],
                    winner: String::new(),
                    active: true,
                };
                self.next_battle_id += 1;
                self.sea_battles.push((zone, b));
                self.sea_battles.len() - 1
            }
        };
        let today = self.nday();
        self.sea_battles[at].1.days = today - self.sea_battles[at].1.start_day + 1;
        for (f, _) in foes {
            let (id, tag, ships) = (self.fleets[*f].id, self.fleets[*f].tag.clone(), self.fleets[*f].ships.len() as i64);
            let battle = &mut self.sea_battles[at].1;
            if battle.fleets.contains(&id) {
                continue;
            }
            battle.fleets.push(id);
            match battle.start_ships.iter_mut().find(|(t, _)| *t == tag) {
                Some(slot) => slot.1 += ships,
                None => battle.start_ships.push((tag, ships)),
            }
        }
        at
    }

    /// `NavalCombat._finish_engagement`.
    fn finish_sea_engagement(&mut self, zone: usize) {
        let at = self.sea_battles.iter().position(|(z, _)| *z == zone).unwrap();
        let (_, mut battle) = self.sea_battles.remove(at);
        battle.active = false;
        // The winner is the side that lost the smaller share of what it brought.
        let mut best = String::new();
        let mut best_share = f64::INFINITY;
        for (tag, brought) in &battle.start_ships {
            let lost = battle.lost.iter().find(|(t, _)| t == tag).map(|(_, l)| *l).unwrap_or(0.0);
            let share = lost / maxf(*brought as f64, 1.0);
            if share < best_share {
                best_share = share;
                best = tag.clone();
            }
        }
        battle.winner = best;
        self.sea_battle_archive.push(battle);
        for f in &mut self.fleets {
            if f.zone == zone || f.port > 0 {
                f.engaged = false;
            }
            if f.zone == zone && f.retreating && !f.is_moving() {
                f.retreating = false;
            }
        }
    }

    /// `NavalCombat._upkeep`: repair and morale in port; attrition for fleets too long at sea.
    fn fleet_upkeep(&mut self, data: &Data) {
        let c = &data.navy;
        for fi in 0..self.fleets.len() {
            if self.fleets[fi].is_in_port() {
                let port = self.fleets[fi].port;
                self.fleets[fi].days_out = 0;
                self.fleets[fi].retreating = false;
                let level = self.port_level(port);
                let tag = self.fleets[fi].tag.clone();
                let held = self.province_controller[port] == tag || self.can_dock(data, &tag, port);
                let fighting = self.fleets[fi].fighting;
                for s in &mut self.fleets[fi].ships {
                    s.morale = minf(1.0, s.morale + c.port_morale_regain);
                    if held && !fighting {
                        s.strength = minf(1.0, s.strength + c.repair_per_day * level as f64);
                    }
                }
                continue;
            }
            self.fleets[fi].days_out += 1;
            if self.fleets[fi].fighting {
                continue;
            }
            let days_out = self.fleets[fi].days_out;
            for s in &mut self.fleets[fi].ships {
                s.morale = minf(1.0, s.morale + c.combat.morale_regain);
                if days_out > c.def(&s.kind).range_days {
                    s.strength = maxf(c.range_floor, s.strength - c.range_attrition);
                    s.morale = maxf(0.0, s.morale - c.range_attrition_morale);
                }
            }
            if self.fleets[fi].retreating && !self.fleets[fi].is_moving() {
                self.fleets[fi].retreating = false;
            }
        }
    }

    // ---------------------------------------------------------------- carrying armies

    /// `Navy.armies_aboard`: indices of the armies embarked in a fleet, by army id.
    pub fn armies_aboard(&self, fleet_id: u32) -> Vec<usize> {
        let mut out: Vec<usize> = (0..self.armies.len()).filter(|&i| self.armies[i].fleet_id == fleet_id).collect();
        out.sort_by_key(|&i| self.armies[i].id);
        out
    }

    /// `Navy.free_capacity`: men the fleet can still take.
    pub fn free_capacity(&self, data: &Data, f: &Fleet) -> f64 {
        let mut men = 0.0;
        for i in self.armies_aboard(f.id) {
            men += self.armies[i].men(&data.military);
        }
        self.fleet_capacity(data, f) as f64 - men
    }

    /// `Navy.embark_problem`: why an army cannot board a fleet, or "" if it can.
    pub fn embark_problem(&self, data: &Data, tag: &str, army: Option<usize>, fleet: Option<usize>) -> &'static str {
        let (Some(ai), Some(fi)) = (army, fleet) else { return "Invalid order." };
        let (a, f) = (&self.armies[ai], &self.fleets[fi]);
        if a.tag != tag || f.tag != tag {
            return "Invalid order.";
        }
        if a.embarked() {
            return "Already aboard";
        }
        if !f.is_in_port() || f.port != a.province || f.is_moving() {
            return "The fleet must lie in the army's port";
        }
        if a.fighting || a.attacking || !a.path.is_empty() {
            return "The army is busy";
        }
        if a.men(&data.military) > self.free_capacity(data, f) {
            return "Not enough transports";
        }
        ""
    }

    /// `EmbarkArmy.execute`.
    pub fn embark_army(&mut self, data: &Data, tag: &str, army_id: u32, fleet_id: u32) -> bool {
        let ai = self.armies.iter().position(|a| a.id == army_id);
        let fi = self.fleet_index(fleet_id);
        if !self.embark_problem(data, tag, ai, fi).is_empty() {
            return false;
        }
        self.armies[ai.unwrap()].fleet_id = fleet_id;
        self.armies[ai.unwrap()].still_days = 0;
        true
    }

    /// `Navy.land_army`: puts an embarked army ashore in a province. A landing from the sea onto ground the enemy holds or defends
    /// is an assault.
    pub fn land_army(&mut self, data: &Data, ai: usize, province: usize, from_sea: bool) {
        let tag = self.armies[ai].tag.clone();
        let mut assault = false;
        if from_sea {
            let holder = self.province_controller[province].clone();
            assault = holder != tag && (self.at_war(&tag, &holder) || self.at_war(&tag, &self.province_owner[province]));
            for b in &self.armies {
                if b.province == province && !b.embarked() && self.at_war(&tag, &b.tag) {
                    assault = true;
                }
            }
        }
        let mut attacking = false;
        for (bi, b) in self.armies.iter().enumerate() {
            if bi != ai && b.province == province && !b.embarked() && self.at_war(&tag, &b.tag) {
                attacking = true;
            }
        }
        let a = &mut self.armies[ai];
        a.fleet_id = 0;
        a.province = province;
        a.path.clear();
        a.still_days = 0;
        a.landing_days = if assault { data.military.landing_days as i32 } else { 0 };
        a.landed_supply = if from_sea { data.military.landing_supply_days } else { 0 };
        a.attacking = attacking;
    }

    /// `DisembarkArmy.execute`.
    pub fn disembark_army(&mut self, data: &Data, tag: &str, army_id: u32, province: usize) -> bool {
        let Some(ai) = self.armies.iter().position(|a| a.id == army_id) else { return false };
        if self.armies[ai].tag != tag || !self.armies[ai].embarked() {
            return false;
        }
        let Some(fi) = self.fleet_index(self.armies[ai].fleet_id) else { return false };
        if self.fleets[fi].tag != tag || province < 1 || province >= self.province_owner.len() {
            return false;
        }
        if !self.can_enter_pub(data, tag, province) {
            return false;
        }
        if self.fleets[fi].is_in_port() {
            if self.fleets[fi].port != province || self.fleets[fi].is_moving() {
                return false;
            }
            self.land_army(data, ai, province, false);
        } else {
            if self.fleets[fi].is_moving() || !data.map.zones_of_port(province).contains(&self.fleets[fi].zone) {
                return false;
            }
            self.land_army(data, ai, province, true);
        }
        true
    }

    /// `Navy.settle_embarked`: after the day's fighting, armies whose fleet is gone are lost with it, a convoy that lost transports
    /// drowns the men it can no longer carry, and fleets that have reached their landing put their armies ashore.
    pub fn settle_embarked(&mut self, data: &Data) {
        let mut aboard: Vec<(u32, Vec<u32>)> = vec![];
        for a in &self.armies {
            if a.fleet_id > 0 {
                match aboard.iter_mut().find(|(f, _)| *f == a.fleet_id) {
                    Some(slot) => slot.1.push(a.id),
                    None => aboard.push((a.fleet_id, vec![a.id])),
                }
            }
        }
        for (fid, list) in aboard {
            let Some(fi) = self.fleet_index(fid) else {
                for id in &list {
                    self.drown(data, *id, 1.0);
                }
                continue;
            };
            let mut men = 0.0;
            for id in &list {
                let ai = self.armies.iter().position(|a| a.id == *id).unwrap();
                men += self.armies[ai].men(&data.military);
            }
            let capacity = self.fleet_capacity(data, &self.fleets[fi]) as f64;
            if men > capacity {
                let frac = (men - capacity) / men;
                for id in &list {
                    self.drown(data, *id, frac);
                }
            }
            let f = &self.fleets[fi];
            let landing = f.landing;
            if landing > 0 && !f.is_moving() && f.zone > 0 && data.map.zones_of_port(landing).contains(&f.zone) {
                for id in &list {
                    if let Some(ai) = self.armies.iter().position(|a| a.id == *id) {
                        let tag = self.armies[ai].tag.clone();
                        if self.can_enter_pub(data, &tag, landing) {
                            self.land_army(data, ai, landing, true);
                        }
                    }
                }
                if self.armies_aboard(fid).is_empty() {
                    self.fleets[fi].landing = 0;
                }
            }
        }
    }

    /// `Navy._drown`.
    fn drown(&mut self, data: &Data, army_id: u32, frac: f64) {
        let Some(ai) = self.armies.iter().position(|a| a.id == army_id) else { return };
        let cfg = &data.military;
        let before = self.armies[ai].men(cfg);
        if frac >= 1.0 {
            self.armies[ai].units.clear();
        } else {
            for u in &mut self.armies[ai].units {
                u.strength *= 1.0 - frac;
            }
            for i in (0..self.armies[ai].units.len()).rev() {
                if self.armies[ai].units[i].strength < cfg.combat.min_strength {
                    self.armies[ai].units.remove(i);
                }
            }
        }
        let lost = before - self.armies[ai].men(cfg);
        let tag = self.armies[ai].tag.clone();
        self.add_loss(&tag, &[], lost, "losses");
        if self.armies[ai].units.is_empty() {
            self.armies.remove(ai);
        }
    }

    // ---------------------------------------------------------------- the commands

    /// `MoveFleet.execute`: sends a fleet to a sea zone (`port` 0) or into a port.
    pub fn move_fleet(&mut self, data: &Data, tag: &str, fleet_id: u32, zone: usize, port: usize) -> bool {
        let Some(fi) = self.fleet_index(fleet_id) else { return false };
        if self.fleets[fi].tag != tag {
            return false;
        }
        let targets: Vec<usize> = if port > 0 {
            if !self.can_dock(data, tag, port) {
                return false;
            }
            data.map.zones_of_port(port)
        } else if zone >= 1 && zone < data.map.sea_zone_count() {
            vec![zone]
        } else {
            return false;
        };
        // Already there: the order cancels any sailing.
        let f = &self.fleets[fi];
        if (port > 0 && f.port == port) || (port == 0 && f.zone == zone && f.port == 0) {
            let f = &mut self.fleets[fi];
            f.path.clear();
            f.entering = false;
            f.dest_port = 0;
            f.landing = 0;
            return true;
        }
        let speed = self.fleet_speed(data, f);
        let starts: Vec<usize> = if f.is_in_port() { data.map.zones_of_port(f.port) } else { vec![f.zone] };
        let path = Self::sea_find_path(data, speed, &starts, &targets);
        if path.is_empty() {
            return false;
        }
        let mut route = path.clone();
        if !f.is_in_port() && route[0] == f.zone {
            route.remove(0);
        }
        // Keep the progress already made if the fleet is still heading into the same zone.
        let keep_progress = !f.is_in_port() && !f.path.is_empty() && !route.is_empty() && f.path[0] == route[0];
        let f = &mut self.fleets[fi];
        f.retreating = false;
        f.landing = 0;
        f.path = route;
        f.dest_port = port;
        f.entering = false;
        if f.is_in_port() {
            f.move_days_left = data.navy.port_days;
        } else if f.path.is_empty() {
            f.entering = port > 0;
            f.move_days_left = data.navy.port_days;
        } else if !keep_progress {
            f.move_days_left = Self::zone_days(data, speed, f.zone, f.path[0]);
        }
        true
    }

    /// `SendOverseas.problem`.
    pub fn send_overseas_problem(&self, data: &Data, tag: &str, fleet_id: u32, armies: &[u32], destination: usize) -> &'static str {
        let fi = self.fleet_index(fleet_id);
        let Some(fi) = fi else { return "Invalid order." };
        if self.fleets[fi].tag != tag || armies.is_empty() {
            return "Invalid order.";
        }
        if destination < 1 || destination >= self.province_owner.len() || data.map.zones_of_port(destination).is_empty() {
            return "Choose a coastal province.";
        }
        if !self.can_enter_pub(data, tag, destination) {
            return "You may not land there.";
        }
        let mut need = 0.0;
        for id in armies {
            let ai = self.armies.iter().position(|a| a.id == *id);
            let Some(ai) = ai else { return "Invalid order." };
            if self.armies[ai].tag != tag || self.armies[ai].embarked() {
                return "Invalid order.";
            }
            let why = self.embark_problem(data, tag, Some(ai), Some(fi));
            if !why.is_empty() && why != "Not enough transports" {
                return why;
            }
            need += self.armies[ai].men(&data.military);
        }
        if need > self.free_capacity(data, &self.fleets[fi]) {
            return "Not enough transports";
        }
        let speed = self.fleet_speed(data, &self.fleets[fi]);
        if Self::sea_find_path(data, speed, &data.map.zones_of_port(self.fleets[fi].port), &data.map.zones_of_port(destination)).is_empty() {
            return "No sea route";
        }
        ""
    }

    /// `SendOverseas.execute`.
    pub fn send_overseas(&mut self, data: &Data, tag: &str, fleet_id: u32, armies: &[u32], destination: usize) -> bool {
        if !self.send_overseas_problem(data, tag, fleet_id, armies, destination).is_empty() {
            return false;
        }
        let fi = self.fleet_index(fleet_id).unwrap();
        let speed = self.fleet_speed(data, &self.fleets[fi]);
        let path = Self::sea_find_path(data, speed, &data.map.zones_of_port(self.fleets[fi].port), &data.map.zones_of_port(destination));
        if !self.move_fleet(data, tag, fleet_id, *path.last().unwrap(), 0) {
            return false;
        }
        for id in armies {
            let ai = self.armies.iter().position(|a| a.id == *id).unwrap();
            self.armies[ai].fleet_id = fleet_id;
            self.armies[ai].still_days = 0;
        }
        self.fleets[fi].landing = destination;
        true
    }

    /// `Navy.build_problem`: why ships cannot be built now, or "" if they can.
    pub fn ship_build_problem(&self, data: &Data, tag: &str, province: usize, kind: &str, count: usize) -> &'static str {
        if !self.nation_index.contains_key(tag) || !data.navy.types.iter().any(|t| t.id == kind) || count < 1 {
            return "Invalid order.";
        }
        if province < 1 || province >= self.province_owner.len() || self.province_owner[province] != tag {
            return "Not your province";
        }
        if self.province_controller[province] != tag {
            return "Province is occupied";
        }
        if self.fleet_limited(tag) {
            return "A treaty limits your fleet: no new warships";
        }
        if data.map.zones_of_port(province).is_empty() {
            return "Needs a coastal province";
        }
        let level = self.port_level(province);
        if level < 1 {
            return "Needs a port";
        }
        if level < data.navy.def(kind).min_port {
            return "Needs a higher level port";
        }
        let building = self.nation(tag).shipbuilding.iter().filter(|j| j.province == province).count();
        if building as i64 + count as i64 > level * data.navy.slots_per_port_level {
            return "The yard is full";
        }
        if self.nation(tag).treasury < data.navy.def(kind).cost * count as f64 {
            return "Not enough money";
        }
        ""
    }

    /// `RaiseShips.execute`: starts building squadrons in a port the nation owns and holds; the money is paid up front.
    pub fn raise_ships(&mut self, data: &Data, tag: &str, province: usize, kind: &str, count: usize) -> bool {
        if !self.ship_build_problem(data, tag, province, kind, count).is_empty() {
            return false;
        }
        let d = data.navy.def(kind);
        let ni = self.nation_index[tag];
        self.nations[ni].treasury -= d.cost * count as f64;
        for _ in 0..count {
            self.nations[ni].shipbuilding.push(crate::economy::new_job(province, kind, d.ic, d.build_days));
        }
        true
    }

    /// `SetFleetMission.execute`.
    pub fn set_fleet_mission(&mut self, tag: &str, fleet_id: u32, mission: &str) -> bool {
        let Some(fi) = self.fleet_index(fleet_id) else { return false };
        if self.fleets[fi].tag != tag || !["station", "patrol", "blockade", "escort", "raid", "support"].contains(&mission) {
            return false;
        }
        self.fleets[fi].mission = mission.to_string();
        true
    }

    // ---------------------------------------------------------------- the blockade

    /// `Blockade.step_day`.
    pub fn blockade_step_day(&mut self, data: &Data) {
        self.update_sea_control(data);
        let cfg = &data.navy.blockade;
        for ni in 0..self.nations.len() {
            let tag = self.nations[ni].tag.clone();
            let mut target = self.nations[ni].blockade_target;
            if self.nations[ni].blockade_pinned >= 0.0 {
                target = self.nations[ni].blockade_pinned;
                self.nations[ni].blockade = target;
                self.nations[ni].blockade_target = target;
                continue;
            }
            if !self.blockade_has_enemy(&tag) {
                target = 0.0;
                self.nations[ni].blockade_by = vec![];
            } else if (self.nday() + string_hash(&tag)) % cfg.assess_days == 0 {
                let (t, by) = self.assess_blockade(data, &tag);
                target = t;
                self.nations[ni].blockade_by = by;
            }
            let n = &mut self.nations[ni];
            n.blockade_target = target;
            if target > n.blockade {
                n.blockade = minf(target, n.blockade + cfg.rise_per_day);
            } else if target < n.blockade {
                n.blockade = maxf(target, n.blockade - cfg.fall_per_day);
            }
            if (n.blockade - n.blockade_applied).abs() >= cfg.recompute_step || (n.blockade == 0.0 && n.blockade_applied > 0.0) {
                n.blockade_applied = n.blockade;
                self.budget_dirty = true;
            }
        }
    }

    fn blockade_has_enemy(&self, tag: &str) -> bool {
        self.nations.iter().any(|o| o.tag != tag && self.at_war(tag, &o.tag))
    }

    /// `Blockade.update_control`: fills `sea_control`. Only fleets at sea with real firepower count; where hostile nations both
    /// have such ships the zone is contested and nobody holds it.
    pub fn update_sea_control(&mut self, data: &Data) {
        let mut power: Vec<(usize, Vec<(String, f64)>)> = vec![];
        for f in &self.fleets {
            if f.zone == 0 || f.port > 0 {
                continue;
            }
            let p = self.fleet_power(data, f);
            match power.iter_mut().find(|(z, _)| *z == f.zone) {
                Some(slot) => bump(&mut slot.1, &f.tag, p),
                None => power.push((f.zone, vec![(f.tag.clone(), p)])),
            }
        }
        let mut control: Vec<(usize, SeaControl)> = vec![];
        for (zone, by_tag) in power {
            let mut tags: Vec<String> = by_tag.iter().filter(|(_, p)| *p >= data.navy.blockade.min_power).map(|(t, _)| t.clone()).collect();
            if tags.is_empty() {
                continue;
            }
            tags.sort();
            let mut contested = false;
            for a in &tags {
                for b in &tags {
                    if a != b && self.at_war(a, b) {
                        contested = true;
                    }
                }
            }
            control.push((zone, SeaControl { holders: if contested { vec![] } else { tags }, contested, power: by_tag }));
        }
        self.sea_control = control;
    }

    /// `Blockade.holds`: whether a nation (or its friends) holds a zone.
    pub fn holds_sea(&self, tag: &str, zone: usize) -> bool {
        let Some((_, c)) = self.sea_control.iter().find(|(z, _)| *z == zone) else { return false };
        if c.contested {
            return false;
        }
        c.holders.iter().any(|h| h == tag || !self.at_war(h, tag))
    }

    /// `Blockade.blockaders`: the nations whose ships hold a zone against `tag`.
    pub fn blockaders(&self, tag: &str, zone: usize) -> Vec<String> {
        let Some((_, c)) = self.sea_control.iter().find(|(z, _)| *z == zone) else { return vec![] };
        if c.contested {
            return vec![];
        }
        c.holders.iter().filter(|h| self.at_war(h, tag)).cloned().collect()
    }

    /// `Blockade.port_weights`: how much each sea zone matters to a nation's trade, zones in the order first met.
    pub fn port_weights(&self, data: &Data, tag: &str) -> Vec<(usize, f64)> {
        let cfg = &data.navy.blockade;
        let mut out: Vec<(usize, f64)> = vec![];
        let add = |out: &mut Vec<(usize, f64)>, z: usize, w: f64| match out.iter_mut().find(|(k, _)| *k == z) {
            Some(slot) => slot.1 += w,
            None => out.push((z, w)),
        };
        for &id in &self.nation(tag).provinces {
            if self.province_controller[id] != tag {
                continue;
            }
            let zones = data.map.zones_of_port(id);
            if zones.is_empty() {
                continue;
            }
            let port = self.level_of(id, "port") as f64;
            let w = self.province_gdp[id] as f64 * (cfg.base_weight + cfg.per_port_level * port);
            if zones.len() == 1 {
                add(&mut out, zones[0], w);
            } else {
                add(&mut out, zones[0], w * (1.0 - cfg.second_zone_share));
                add(&mut out, zones[1], w * cfg.second_zone_share);
            }
        }
        out
    }

    /// `Blockade.open_border_share`: the share of a nation's land border that does not face an enemy.
    pub fn open_border_share(&self, data: &Data, tag: &str) -> f64 {
        let (mut total, mut open) = (0i64, 0i64);
        for &id in &self.nation(tag).provinces {
            for nb in data.map.neighbors(id) {
                let other = &self.province_owner[nb];
                if other == tag {
                    continue;
                }
                total += 1;
                if !self.at_war(tag, other) {
                    open += 1;
                }
            }
        }
        if total > 0 {
            open as f64 / total as f64
        } else {
            0.0
        }
    }

    /// `Blockade.open_zones`: zones from which a nation's ships can still reach an outlet without crossing a zone an enemy holds.
    fn open_zones(&self, data: &Data, tag: &str) -> std::collections::HashSet<usize> {
        let mut seen = std::collections::HashSet::new();
        let mut todo: Vec<usize> = vec![];
        for z in 1..data.map.sea_zone_count() {
            if data.navy.blockade.outlets.contains(&data.map.sea_zone_names[z]) && self.blockaders(tag, z).is_empty() {
                seen.insert(z);
                todo.push(z);
            }
        }
        while let Some(z) = todo.pop() {
            for &n in data.map.sea_neighbors(z) {
                if !seen.contains(&n) && self.blockaders(tag, n).is_empty() {
                    seen.insert(n);
                    todo.push(n);
                }
            }
        }
        seen
    }

    /// `Blockade.assess`: what the enemy's grip on the sea cuts off: the target blockade and the nations behind it.
    pub fn assess_blockade(&self, data: &Data, tag: &str) -> (f64, Vec<String>) {
        let cfg = &data.navy.blockade;
        let weights = self.port_weights(data, tag);
        let mut total = 0.0;
        for (_, w) in &weights {
            total += w;
        }
        let open = self.open_zones(data, tag);
        let mut cut = 0.0;
        let mut by: Vec<String> = vec![];
        for (z, w) in &weights {
            if open.contains(z) {
                continue;
            }
            cut += w;
        }
        if cut > 0.0 {
            for (z, _) in &self.sea_control {
                for e in self.blockaders(tag, *z) {
                    if !by.contains(&e) {
                        by.push(e);
                    }
                }
            }
        }
        by.sort();
        let share = if total > 0.0 { cut / total } else { 0.0 };
        let cap = cfg.max * (1.0 - cfg.land_leak * self.open_border_share(data, tag));
        (share * cap, by)
    }
}
