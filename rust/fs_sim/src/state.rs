//! The game state (`scripts/sim/game_state.gd`) as far as it is ported: the provinces' owners, people, works and
//! deposits, the nations, and what the economy works out from them. Armies, fleets, wars, treaties and the rest of the
//! state are not here yet (see `rust/README.md`).

use crate::config::{EconomyConfig, Effects};
use crate::economy::{self, EconNation};
use crate::map::MapData;
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
    /// The share of a province's tax an occupier collects (`data/military.json`, occupation.income_share).
    pub occupation_income_share: f64,
    /// The smallest port level each ship type needs (`data/navy.json`, types.<type>.min_port).
    pub navy_min_port: HashMap<String, i64>,
}

impl Data {
    pub fn load(dir: &Path) -> Result<Data, String> {
        let economy = EconomyConfig::from_json_str(
            &std::fs::read_to_string(dir.join("economy.json")).map_err(|e| format!("economy.json: {e}"))?,
        )?;
        let military: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join("military.json")).map_err(|e| format!("military.json: {e}"))?,
        )
        .map_err(|e| format!("military.json is invalid: {e}"))?;
        let occupation_income_share = military["occupation"]["income_share"].as_f64().ok_or("military.json: occupation.income_share")?;
        let navy: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join("navy.json")).map_err(|e| format!("navy.json: {e}"))?,
        )
        .map_err(|e| format!("navy.json is invalid: {e}"))?;
        let mut navy_min_port = HashMap::new();
        for (t, def) in navy["types"].as_object().ok_or("navy.json: types")? {
            navy_min_port.insert(t.clone(), def["min_port"].as_i64().ok_or("navy.json: min_port")?);
        }
        Ok(Data { dir: dir.to_path_buf(), map: MapData::load(dir)?, economy, occupation_income_share, navy_min_port })
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
    pub provinces: Vec<usize>,
    pub population: i64,
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
            ..Default::default()
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
                provinces: vec![],
                population: 0,
            });
        }
        gs.rebuild_nation_provinces()?;
        gs.materials_k = 0.0;
        gs.give_home_ports(data, &dir)?;
        gs.absorb_works(data);
        gs.recompute(data);
        Ok(gs)
    }

    /// `Navy.deploy_starting` and `Navy._give_home_ports`, the part that touches the economy: a nation that starts with a
    /// navy starts with at least one port (the building, which also brings trade). If it owns none, the biggest naval
    /// base of its fleets gets a level 1 port. (The fleets themselves are not ported yet.)
    pub fn give_home_ports(&mut self, data: &Data, dir: &Path) -> Result<(), String> {
        // Each fleet's tag and port, in the order the fleets are first named in navy.tsv, and the port level each base needs.
        let mut fleets: Vec<(String, usize, String)> = vec![];
        let mut naval_bases: HashMap<usize, i64> = HashMap::new();
        for row in Table::read(&dir.join("navy.tsv"))?.rows() {
            let (tag, province) = (row.get("tag").to_string(), row.int("province") as usize);
            let min_port = *data.navy_min_port.get(row.get("type")).ok_or_else(|| format!("navy.tsv: unknown ship type {}", row.get("type")))?;
            let key = format!("{tag}|{province}|{}", row.get("fleet"));
            if !fleets.iter().any(|(t, p, f)| format!("{t}|{p}|{f}") == key) {
                fleets.push((tag.clone(), province, row.get("fleet").to_string()));
            }
            let slot = naval_bases.entry(province).or_insert(1);
            *slot = (*slot).max(min_port);
        }
        let base = |id: usize| naval_bases.get(&id).copied().unwrap_or(0);
        let mut home: Vec<(String, usize)> = vec![];
        for (tag, port, _) in &fleets {
            match home.iter_mut().find(|(t, _)| t == tag) {
                Some(slot) => {
                    if slot.1 == 0 || base(*port) > base(slot.1) {
                        slot.1 = *port;
                    }
                }
                None => home.push((tag.clone(), *port)),
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
        Ok(())
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
                sums[holder].gdp += o.gdp * data.occupation_income_share;
            }
        }
        self.economy_sums = sums;
        if self.materials_k <= 0.0 {
            self.calibrate_materials(data);
        }
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
