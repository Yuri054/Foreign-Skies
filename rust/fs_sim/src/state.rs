//! The game state (`scripts/sim/game_state.gd`) as far as it is ported: the provinces' owners, people, works and
//! deposits, the nations, and what the economy works out from them. Armies, fleets, wars, treaties and the rest of the
//! state are not here yet (see `rust/README.md`).

use crate::budget::{self, Budget};
use crate::config::{EconomyConfig, Effects, MilitaryConfig, NavyConfig, WarSupportConfig};
use crate::economy::{self, EconNation};
use crate::gd::{clampf, maxf};
use crate::map::MapData;
use crate::military::{self, Army};
use crate::tsv::Table;
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Everything the simulation reads from `data/`, loaded once.
#[derive(Debug, Clone)]
pub struct Data {
    pub dir: PathBuf,
    pub map: MapData,
    pub economy: EconomyConfig,
    pub military: MilitaryConfig,
    pub navy: NavyConfig,
    pub war_support: WarSupportConfig,
}

impl Data {
    pub fn load(dir: &Path) -> Result<Data, String> {
        let read = |f: &str| std::fs::read_to_string(dir.join(f)).map_err(|e| format!("{f}: {e}"));
        Ok(Data {
            dir: dir.to_path_buf(),
            map: MapData::load(dir)?,
            economy: EconomyConfig::from_json_str(&read("economy.json")?)?,
            military: MilitaryConfig::from_json_str(&read("military.json")?)?,
            navy: NavyConfig::from_json_str(&read("navy.json")?)?,
            war_support: WarSupportConfig::from_json_str(&read("diplomacy.json")?)?,
        })
    }
}

#[derive(Debug, Clone)]
pub struct Nation {
    pub tag: String,
    pub display_name: String,
    pub treasury: f64,
    pub capital: i64,
    pub development: f64,
    pub agri_yield: f64,
    pub tax_rate: f64,
    pub pop_growth: f64,
    pub peacetime_army: i64,
    pub naval_budget: f64,
    pub materials_need_mult: f64,
    pub mobilization: f64,
    pub focus_fx: Effects,
    /// What the national focus adds to the construction points a day.
    pub focus_construction: f64,
    pub provinces: Vec<usize>,
    pub population: i64,
    pub government: String,
    pub war_support: f64,
    /// Monthly state investment (GBP millions).
    pub investment: f64,
    pub weariness: f64,
    pub starving: bool,
    /// How much of the nation's trade the blockade cuts, 0 to 1.
    pub blockade: f64,
    /// The recruits' pool, and the men in armies (and training).
    pub manpower: i64,
    pub men_in_units: i64,
    pub men_exercising: i64,
    pub arms_share: f64,
    /// The munitions stockpile, in IC.
    pub munitions: f64,
    pub munitions_used_last: f64,
    pub civil_mult: f64,
    pub civil_base: f64,
    pub civil_index: f64,
    pub wage: f64,
    /// The part of the naval budget that is not ships: dockyards, bases, sailors ashore.
    pub naval_overhead: f64,
    pub budget: Budget,
}

impl Nation {
    /// What the economy reads of this nation, for the pure rules in `economy`.
    pub fn econ(&self) -> EconNation {
        EconNation {
            development: self.development,
            agri_yield: self.agri_yield,
            focus_fx: self.focus_fx,
            tax_rate: self.tax_rate,
            population: self.population,
            investment: self.investment,
            budget_gdp: Some(self.budget.gdp),
            men_in_units: self.men_in_units,
            weariness: self.weariness,
            starving: self.starving,
        }
    }
}

/// A nation's summed province output (`GameState.economy_sums`).
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Sums {
    pub coast: f64,
    pub gdp: f64,
    pub industry: f64,
    pub food: f64,
    pub trade: f64,
    pub pool: f64,
    pub materials: f64,
}

#[derive(Debug, Clone)]
pub struct GameState {
    pub scenario: String,
    /// In the order the game goes through its nations (`data/nations.json`).
    pub nations: Vec<Nation>,
    pub nation_index: HashMap<String, usize>,
    /// Indexed by province id; element 0 is unused.
    pub province_owner: Vec<String>,
    pub province_controller: Vec<String>,
    pub province_population: Vec<i32>,
    /// The part of a person each province's growth has not yet added (the game keeps it as a 32-bit float).
    pub province_pop_frac: Vec<f32>,
    /// Building type and level, in the order the works were added.
    pub province_buildings: Vec<Vec<(String, i32)>>,
    /// Resource id and potential output (kt a year), in the economy file's resource order.
    pub province_deposit: Vec<Vec<(String, f64)>>,
    pub province_gdp: Vec<f32>,
    pub province_industry: Vec<f32>,
    pub province_food: Vec<f32>,
    pub province_pool: Vec<f32>,
    /// One per nation, in `nations` order.
    pub economy_sums: Vec<Sums>,
    /// Kt of raw materials a year one GBP million of industrial output needs (`Economy.calibrate_materials`).
    pub materials_k: f64,
    /// The armies, in the order they were raised (their ids rise with it).
    pub armies: Vec<Army>,
    pub next_army_id: u32,
    pub fleets: Vec<Fleet>,
    /// The wars being fought, as pairs of tags. (No war is started by loading yet.)
    pub wars: Vec<(String, String)>,
}

/// A fleet at its base: the ships' types (`Fleet`, `Navy.new_fleet`).
#[derive(Debug, Clone)]
pub struct Fleet {
    pub tag: String,
    pub name: String,
    pub port: usize,
    pub ships: Vec<String>,
}

fn refs_b(v: &[(String, i32)]) -> Vec<(&str, i32)> {
    v.iter().map(|(k, l)| (k.as_str(), *l)).collect()
}

fn refs_d(v: &[(String, f64)]) -> Vec<(&str, f64)> {
    v.iter().map(|(k, x)| (k.as_str(), *x)).collect()
}

impl GameState {
    pub fn nation(&self, tag: &str) -> &Nation {
        &self.nations[self.nation_index[tag]]
    }

    /// `GameState.load_scenario`, as far as the economy is concerned: the provinces and nations are set up, the works a
    /// scenario starts with are absorbed into each nation's development, and the economy is worked out once.
    pub fn load_scenario(data: &Data, name: &str) -> Result<GameState, String> {
        let dir = data.dir.join("scenarios").join(name);
        let scenario: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join("scenario.json")).map_err(|e| format!("scenario.json: {e}"))?,
        )
        .map_err(|e| format!("scenario.json is invalid: {e}"))?;
        let count = data.map.provinces.len();
        let mut gs = GameState {
            scenario: name.to_string(),
            nations: vec![],
            nation_index: HashMap::new(),
            province_owner: vec![String::new(); count],
            province_controller: vec![String::new(); count],
            province_population: vec![0; count],
            province_pop_frac: vec![0.0; count],
            province_buildings: vec![vec![]; count],
            province_deposit: vec![vec![]; count],
            province_gdp: vec![0.0; count],
            province_industry: vec![0.0; count],
            province_food: vec![0.0; count],
            province_pool: vec![0.0; count],
            economy_sums: vec![],
            materials_k: 0.0,
            armies: vec![],
            next_army_id: 1,
            fleets: vec![],
            wars: vec![],
        };
        for row in Table::read(&dir.join("resources.tsv"))?.rows() {
            let id = row.int("id") as usize;
            for r in &data.economy.resource_ids {
                set_deposit(&mut gs.province_deposit[id], r, row.float(r));
            }
        }
        for id in 1..count {
            gs.province_owner[id] = data.map.provinces[id].owner.clone();
            gs.province_controller[id] = data.map.provinces[id].owner.clone();
        }
        let mut by_name: HashMap<&str, usize> = HashMap::new();
        for id in 1..count {
            by_name.insert(data.map.provinces[id].name.as_str(), id);
        }
        // The works a scenario's big cities already have.
        if let Some(works) = scenario.get("buildings").and_then(Value::as_object) {
            for (pname, types) in works {
                let id = *by_name.get(pname.as_str()).ok_or_else(|| format!("scenario building: no province {pname}"))?;
                for (t, level) in types.as_object().ok_or("scenario buildings: not an object")? {
                    set_building(&mut gs.province_buildings[id], t, level.as_f64().unwrap_or(0.0) as i32);
                }
            }
        }
        if let Some(changes) = scenario.get("owner_changes").and_then(Value::as_object) {
            for (pname, tag) in changes {
                let id = *by_name.get(pname.as_str()).ok_or_else(|| format!("owner_changes: no province {pname}"))?;
                let tag = tag.as_str().ok_or("owner_changes: not a tag")?.to_string();
                gs.province_owner[id] = tag.clone();
                gs.province_controller[id] = tag;
            }
        }
        for row in Table::read(&dir.join("provinces.tsv"))?.rows() {
            gs.province_population[row.int("id") as usize] = row.int("population") as i32;
        }
        let no_nations = Value::Object(Default::default());
        let nations_json = scenario.get("nations").unwrap_or(&no_nations);
        for info in &data.map.nations {
            let s = nations_json.get(&info.tag).cloned().unwrap_or(Value::Object(Default::default()));
            let f = |k: &str, d: f64| s.get(k).and_then(Value::as_f64).unwrap_or(d);
            gs.nation_index.insert(info.tag.clone(), gs.nations.len());
            gs.nations.push(Nation {
                tag: info.tag.clone(),
                display_name: info.name.clone(),
                treasury: f("treasury", 0.0),
                capital: f("capital", 0.0) as i64,
                development: f("development", 1.0),
                agri_yield: f("agri_yield", 1.0),
                tax_rate: f("tax_rate", data.economy.default_tax_rate),
                pop_growth: f("pop_growth", 0.01),
                peacetime_army: f("peacetime_army", 0.0) as i64,
                naval_budget: f("naval_budget", 0.0),
                materials_need_mult: f("materials_need_mult", 1.0),
                mobilization: f("mobilization", 0.0),
                focus_fx: Effects::default(),
                focus_construction: 0.0,
                provinces: vec![],
                population: 0,
                government: s.get("government").and_then(Value::as_str).unwrap_or("").to_string(),
                war_support: s
                    .get("war_support")
                    .and_then(Value::as_f64)
                    .unwrap_or_else(|| data.war_support.start_value(s.get("government").and_then(Value::as_str).unwrap_or(""))),
                investment: 0.0,
                weariness: 0.0,
                starving: false,
                blockade: 0.0,
                manpower: f("peacetime_army", 0.0) as i64,
                men_in_units: 0,
                men_exercising: 0,
                arms_share: 0.0,
                munitions: 0.0,
                munitions_used_last: 0.0,
                civil_mult: 1.0,
                civil_base: 0.0,
                civil_index: 1.0,
                wage: 0.0,
                naval_overhead: 0.0,
                budget: Budget::default(),
            });
        }
        gs.rebuild_nation_provinces()?;
        gs.materials_k = 0.0;
        gs.deploy_starting_armies(data, scenario.get("deployment").unwrap_or(&no_nations))?;
        gs.deploy_starting_fleets(data, &dir)?;
        gs.load_munitions(data, &scenario);
        gs.absorb_works(data);
        gs.recompute(data);
        Ok(gs)
    }

    /// `Military.deploy_starting`: each nation's peacetime army, as divisions dealt out among the stacks the scenario
    /// lists, under the commanders its list names; then the men each nation has under arms and its reserve.
    pub fn deploy_starting_armies(&mut self, data: &Data, deployment: &Value) -> Result<(), String> {
        let mil = &data.military;
        self.armies.clear();
        self.next_army_id = 1;
        let names: Vec<String> = data.map.provinces.iter().map(|p| p.name.clone()).collect();
        for ni in 0..self.nations.len() {
            let (tag, peacetime) = (self.nations[ni].tag.clone(), self.nations[ni].peacetime_army);
            if peacetime <= 0 {
                continue;
            }
            let units = military::starting_units(mil, (peacetime as f64 * mil.field_share) as i64);
            let null = Value::Null;
            let stacks = military::stack_plan(deployment.get(&tag).unwrap_or(&null), &tag, &names, &self.province_owner)?;
            let first_id = self.next_army_id;
            self.next_army_id += stacks.len() as u32;
            // Every general in the nation's list joins its pool; the first ones lead the armies.
            let generals = mil.generals_of(&tag);
            let held = military::deal_units(mil, units, &stacks);
            for (i, stack) in stacks.iter().enumerate() {
                if held[i].is_empty() {
                    continue; // an army left with no units is dropped (its id is still used)
                }
                self.armies.push(Army {
                    id: first_id + i as u32,
                    tag: tag.clone(),
                    name: stack.name.clone(),
                    province: stack.province,
                    units: held[i].clone(),
                    general_skill: generals.get(i).map(|g| g.1).unwrap_or(1.0),
                    landing_days: 0,
                });
            }
        }
        self.refresh_men(data);
        for n in &mut self.nations {
            n.manpower = (n.peacetime_army - n.men_in_units).max(0);
        }
        Ok(())
    }

    /// `Military.men_in_service`: men in the field plus recruits in training (none are training at the start).
    pub fn men_in_service(&self, data: &Data, tag: &str) -> i64 {
        let mut total = 0.0;
        for a in self.armies.iter().filter(|a| a.tag == tag) {
            total += a.men(&data.military);
        }
        total.round() as i64
    }

    /// `Military.refresh_men`: the men each nation has under arms.
    pub fn refresh_men(&mut self, data: &Data) {
        for i in 0..self.nations.len() {
            self.nations[i].men_in_units = self.men_in_service(data, &self.nations[i].tag.clone());
            self.nations[i].men_exercising = 0;
        }
    }

    /// `Navy.deploy_starting` (and `_give_home_ports`): the starting fleets from navy.tsv; the port building a nation
    /// that starts with a navy gets if it owns none; each nation's naval overhead (what the scenario's historical naval
    /// budget does not spend on ships); and the naval budget that follows.
    pub fn deploy_starting_fleets(&mut self, data: &Data, dir: &Path) -> Result<(), String> {
        self.fleets.clear();
        let mut naval_bases: HashMap<usize, i64> = HashMap::new();
        for row in Table::read(&dir.join("navy.tsv"))?.rows() {
            let (tag, province) = (row.get("tag").to_string(), row.int("province") as usize);
            let ship = row.get("type");
            let min_port = data.navy.min_port(ship).ok_or_else(|| format!("navy.tsv: unknown ship type {ship}"))?;
            if !self.nation_index.contains_key(&tag) {
                return Err(format!("navy.tsv: unknown nation {tag}"));
            }
            let at = self.fleets.iter().position(|f| f.tag == tag && f.port == province && f.name == row.get("fleet"));
            let at = match at {
                Some(i) => i,
                None => {
                    self.fleets.push(Fleet { tag: tag.clone(), name: row.get("fleet").to_string(), port: province, ships: vec![] });
                    self.fleets.len() - 1
                }
            };
            for _ in 0..row.int("count") {
                self.fleets[at].ships.push(ship.to_string());
            }
            let slot = naval_bases.entry(province).or_insert(1);
            *slot = (*slot).max(min_port);
        }
        // A nation that starts with a navy starts with at least one port: if it owns none, its biggest naval base gets a
        // level 1 port.
        let base = |id: usize| naval_bases.get(&id).copied().unwrap_or(0);
        let mut home: Vec<(String, usize)> = vec![];
        for f in &self.fleets {
            match home.iter_mut().find(|(t, _)| *t == f.tag) {
                Some(slot) => {
                    if slot.1 == 0 || base(f.port) > base(slot.1) {
                        slot.1 = f.port;
                    }
                }
                None => home.push((f.tag.clone(), f.port)),
            }
        }
        for id in 1..self.province_owner.len() {
            if self.province_buildings[id].iter().any(|(k, l)| k == "port" && *l > 0) {
                home.retain(|(t, _)| *t != self.province_owner[id]);
            }
        }
        for (tag, province) in home {
            if self.province_owner[province] == tag {
                set_building(&mut self.province_buildings[province], "port", 1);
            }
        }
        for i in 0..self.nations.len() {
            let upkeep = self.ship_upkeep(data, &self.nations[i].tag);
            self.nations[i].naval_overhead = maxf(0.0, self.nations[i].naval_budget - upkeep);
        }
        self.refresh_upkeep(data);
        Ok(())
    }

    /// `Navy.ship_upkeep`: yearly cost of the ships a nation has afloat.
    pub fn ship_upkeep(&self, data: &Data, tag: &str) -> f64 {
        let mut total = 0.0;
        for f in self.fleets.iter().filter(|f| f.tag == tag) {
            for s in &f.ships {
                total += data.navy.upkeep(s);
            }
        }
        total
    }

    /// `Navy.refresh_upkeep`: every nation's yearly naval cost is the shore establishment plus its ships' upkeep.
    pub fn refresh_upkeep(&mut self, data: &Data) {
        for i in 0..self.nations.len() {
            let mut sum = 0.0;
            for f in self.fleets.iter().filter(|f| f.tag == self.nations[i].tag) {
                for s in &f.ships {
                    sum += data.navy.upkeep(s);
                }
            }
            self.nations[i].naval_budget = self.nations[i].naval_overhead + sum;
        }
    }

    /// `Munitions.load_scenario`: each nation's arms share and a stockpile of `days` of the general war the scenario sets.
    pub fn load_munitions(&mut self, data: &Data, scenario: &Value) {
        let cfg = &data.economy;
        let share = scenario.get("munitions").and_then(|m| m.get("share")).and_then(Value::as_f64).unwrap_or(cfg.munitions_default_share);
        let days = scenario.get("munitions").and_then(|m| m.get("days")).and_then(Value::as_f64).unwrap_or(0.0);
        for i in 0..self.nations.len() {
            let expected = self.expected_daily(data, i);
            let n = &mut self.nations[i];
            n.arms_share = clampf(share, 0.0, 1.0);
            n.munitions_used_last = 0.0;
            n.munitions = days * expected;
        }
    }

    /// `Munitions.war_need`: what a nation's armies would burn in a day if every one of them were fighting.
    pub fn war_need(&self, data: &Data, tag: &str) -> f64 {
        let mut guns = 0.0;
        for a in self.armies.iter().filter(|a| a.tag == tag) {
            guns += a.power(&data.military) * a.shelling_share(&data.military);
        }
        guns * data.economy.munitions_per_gun_power
    }

    /// `Munitions.expected_daily`: what a nation can expect to burn a day in a war.
    pub fn expected_daily(&self, data: &Data, nation: usize) -> f64 {
        let n = &self.nations[nation];
        maxf(n.munitions_used_last / 30.0, self.war_need(data, &n.tag) * data.economy.munitions_engaged_share)
    }

    /// `WarSupport.economy_mult`: the multiplier on tax and recruitment; 1 in peace.
    pub fn war_economy_mult(&self, data: &Data, tag: &str) -> f64 {
        if !self.wars.iter().any(|(a, b)| a == tag || b == tag) {
            return 1.0;
        }
        data.war_support.economy_mult_at(self.nation(tag).war_support)
    }

    /// `Economy._budgets`: every nation's budget, from the last province sums.
    pub fn compute_budgets(&mut self, data: &Data) {
        self.refresh_upkeep(data);
        for i in 0..self.nations.len() {
            let tax_mult = self.war_economy_mult(data, &self.nations[i].tag.clone());
            let raw = self.economy_sums[i];
            let mut n = self.nations[i].clone();
            n.budget = budget::nation_budget(&data.economy, &data.military, self.materials_k, &mut n, &raw, tax_mult);
            self.nations[i] = n;
        }
    }

    /// `Economy.calibrate`: at a scenario's start, the raw-materials constant and each nation's civil spending, so that
    /// its budget starts with a small surplus (`start_surplus` of its revenue) for the nation to spend as it chooses.
    pub fn calibrate(&mut self, data: &Data) {
        self.calibrate_materials(data);
        for n in &mut self.nations {
            n.civil_mult = 1.0;
            n.civil_base = 0.0;
            n.civil_index = 1.0;
            n.wage = 0.0;
        }
        self.compute_budgets(data);
        for n in &mut self.nations {
            let civil = n.budget.civil;
            if civil > 0.0 {
                let surplus = n.budget.revenue * data.economy.start_surplus;
                n.civil_mult = clampf((n.budget.net + civil - surplus) / civil, 0.1, 4.0);
            }
            n.civil_base = 0.0; // worked out again from the calibrated multiplier
        }
    }

    /// `GameState.set_controller`: changes who holds a province (the owner stays). The caller recomputes the economy.
    pub fn set_controller(&mut self, id: usize, tag: &str) {
        self.province_controller[id] = tag.to_string();
    }

    /// `GameState._rebuild_nation_provinces`: each nation's provinces (by id) and people.
    pub fn rebuild_nation_provinces(&mut self) -> Result<(), String> {
        for n in &mut self.nations {
            n.provinces.clear();
            n.population = 0;
        }
        for id in 1..self.province_owner.len() {
            let tag = &self.province_owner[id];
            let idx = *self.nation_index.get(tag).ok_or_else(|| format!("province {id} belongs to unknown nation {tag:?}"))?;
            self.nations[idx].provinces.push(id);
            self.nations[idx].population += self.province_population[id] as i64;
        }
        Ok(())
    }

    /// `Economy.absorb_works`: a scenario's starting works are already in the figures it was fitted to, so each nation's
    /// development is eased by what they would add on top.
    pub fn absorb_works(&mut self, data: &Data) {
        let cfg = &data.economy;
        for n in 0..self.nations.len() {
            let econ = self.nations[n].econ();
            let (mut base, mut gain) = (0.0, 0.0);
            for &id in &self.nations[n].provinces {
                let area = data.map.provinces[id].area_km2();
                let pop = self.province_population[id] as i64;
                let plain = economy::province_output(cfg, pop, area, &econ, &[], &[]).gdp;
                base += plain;
                if !self.province_buildings[id].is_empty() {
                    let b = refs_b(&self.province_buildings[id]);
                    gain += economy::province_output(cfg, pop, area, &econ, &b, &[]).gdp - plain;
                }
            }
            if base > 0.0 && gain > 0.0 {
                self.nations[n].development /= 1.0 + gain / base;
            }
        }
    }

    /// `Economy.recompute`, the part that works out each province's output and each nation's sums. (The budgets it ends
    /// with are not ported yet.)
    pub fn recompute(&mut self, data: &Data) {
        let cfg = &data.economy;
        let count = self.province_owner.len();
        self.province_gdp.resize(count, 0.0);
        self.province_industry.resize(count, 0.0);
        self.province_food.resize(count, 0.0);
        self.province_pool.resize(count, 0.0);
        let mut sums = vec![Sums::default(); self.nations.len()];
        let econ: Vec<EconNation> = self.nations.iter().map(Nation::econ).collect();
        for id in 1..count {
            let tag = self.nation_index[&self.province_owner[id]];
            let b = refs_b(&self.province_buildings[id]);
            let d = refs_d(&self.province_deposit[id]);
            let o = economy::province_output(
                cfg,
                self.province_population[id] as i64,
                data.map.provinces[id].area_km2(),
                &econ[tag],
                &b,
                &d,
            );
            self.province_gdp[id] = o.gdp as f32;
            self.province_industry[id] = o.industry as f32;
            self.province_food[id] = o.food as f32;
            self.province_pool[id] = o.pool as f32;
            let holder = self.nation_index[&self.province_controller[id]];
            if holder == tag {
                let s = &mut sums[tag];
                s.gdp += o.gdp;
                s.industry += o.industry;
                s.food += o.food;
                s.trade += o.trade;
                s.pool += o.pool;
                s.materials += o.materials;
                if data.map.provinces[id].coastal {
                    s.coast += 1.0;
                }
            } else {
                // Occupied: the owner loses the output and the occupier collects a share of the tax.
                sums[holder].gdp += o.gdp * data.military.occupation_income_share;
            }
        }
        self.economy_sums = sums;
        if self.materials_k <= 0.0 {
            self.calibrate(data);
        }
        self.compute_budgets(data);
    }

    /// `Economy._calibrate_materials`: the kt of raw materials a year one GBP million of industrial output needs, so
    /// that the world just balances (all deposits against all industry).
    pub fn calibrate_materials(&mut self, data: &Data) {
        let cfg = &data.economy;
        let (mut own, mut industry) = (0.0, 0.0);
        for id in 1..self.province_owner.len() {
            let mut sum = 0.0;
            for (_, v) in &self.province_deposit[id] {
                if *v >= cfg.materials_min_deposit {
                    sum += *v;
                }
            }
            own += sum * cfg.materials_extraction_base;
            industry += self.province_industry[id] as f64;
        }
        self.materials_k = if industry > 0.0 { own / industry } else { cfg.materials_need_per_industry };
    }
}

fn set_deposit(list: &mut Vec<(String, f64)>, id: &str, value: f64) {
    match list.iter_mut().find(|(k, _)| k == id) {
        Some(slot) => slot.1 = value,
        None => list.push((id.to_string(), value)),
    }
}

fn set_building(list: &mut Vec<(String, i32)>, id: &str, level: i32) {
    match list.iter_mut().find(|(k, _)| k == id) {
        Some(slot) => slot.1 = level,
        None => list.push((id.to_string(), level)),
    }
}
