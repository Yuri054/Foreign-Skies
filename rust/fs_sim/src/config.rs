//! `data/economy.json`, read into typed fields: only what the ported rules use. The file's order is kept where the
//! order of the rules depends on it (the resources, and the buildings).

use serde_json::Value;

/// Fractional bonuses (a province's buildings and a nation's focus add up to one of these).
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Effects {
    pub gdp: f64,
    pub industry: f64,
    pub food: f64,
    pub trade: f64,
    pub growth: f64,
}

#[derive(Debug, Clone)]
pub struct BuildingDef {
    pub id: String,
    pub effects: Effects,
    pub ic: f64,
    pub ic_growth: f64,
    pub min_days: i32,
    pub max_level: i32,
    pub gold_share: Option<f64>,
    pub size_by_industry: bool,
    /// What a level of works adds to an army's defence, and takes off a shelling and an assault (trench, fortification).
    pub defense: f64,
    pub shell_reduction: f64,
    pub hard_reduction: f64,
    /// Whether the works can be started now (`enabled`) and whether it needs a coastal province (`requires`).
    pub enabled: bool,
    pub needs_coast: bool,
}

#[derive(Debug, Clone)]
pub struct EconomyConfig {
    pub gdp_per_capita: f64,
    pub reference_density: f64,
    pub density_exponent: f64,
    pub density_min: f64,
    pub density_max: f64,
    pub industry_share_min: f64,
    pub industry_share_max: f64,
    pub food_per_km2: f64,
    pub manpower_share: f64,
    pub default_tax_rate: f64,
    pub min_tax_rate: f64,
    pub max_tax_rate: f64,
    pub baseline_growth: f64,
    pub ic_value: f64,
    pub famine_decline: f64,
    pub min_province: f64,
    pub tax_relief_growth_bonus: f64,
    pub tax_strain_growth_penalty: f64,
    pub invest_growth_per_share: f64,
    pub invest_soft_share: f64,
    pub labor_penalty: f64,
    pub labor_floor: f64,
    pub starvation_output: f64,
    pub construction_gold_share: f64,
    pub cost_ref_gdp: f64,
    pub cost_ref_industry: f64,
    pub cost_min_factor: f64,
    pub materials_extraction_base: f64,
    pub materials_min_deposit: f64,
    pub materials_need_per_industry: f64,
    pub materials_import_cap: f64,
    pub materials_import_price: f64,
    pub materials_import_markup: f64,
    pub materials_export_share: f64,
    pub materials_floor: f64,
    pub mobilization_output_penalty: f64,
    pub famine_output_penalty: f64,
    pub blockade_trade_loss: f64,
    pub tax_drag: f64,
    pub civil_share: f64,
    pub start_surplus: f64,
    pub soldier_upkeep: f64,
    pub soldier_upkeep_ref: f64,
    pub wage_min: f64,
    pub wage_max: f64,
    pub reserve_upkeep: f64,
    pub food_import_cost: f64,
    pub food_state_share: f64,
    pub debt_interest: f64,
    pub munitions_default_share: f64,
    pub munitions_output_penalty: f64,
    pub munitions_storage_cost: f64,
    pub munitions_per_gun_power: f64,
    pub munitions_engaged_share: f64,
    pub munitions_idle_share: f64,
    /// What a unit of munitions costs abroad, GBP millions (`munitions.import_price`).
    pub munitions_import_price: f64,
    pub base_ic: f64,
    pub base_ic_gdp_ref: f64,
    pub base_ic_min: f64,
    pub ic_per_industry: f64,
    pub occupation_decline: f64,
    pub death_share: f64,
    pub weariness_max: f64,
    pub weariness_per_100k: f64,
    pub weariness_ease_per_day: f64,
    pub starvation_below: f64,
    pub starvation_support_per_day: f64,
    pub munitions_decay_per_year: f64,
    pub mobilization_rate: f64,
    pub mobilization_peace_max: f64,
    pub standing_share: f64,
    pub army_growth_share: f64,
    pub tax_strain_war_weariness: f64,
    pub tax_strain_support_penalty: f64,
    pub tax_relief_support_bonus: f64,
    /// The deposit tables (coal, iron, timber), in file order.
    pub resource_ids: Vec<String>,
    pub buildings: Vec<BuildingDef>,
}

fn num(v: &Value, path: &[&str]) -> Result<f64, String> {
    let mut cur = v;
    for key in path {
        cur = cur.get(*key).ok_or_else(|| format!("economy.json: missing {}", path.join(".")))?;
    }
    cur.as_f64().ok_or_else(|| format!("economy.json: {} is not a number", path.join(".")))
}

impl EconomyConfig {
    pub fn from_json_str(text: &str) -> Result<EconomyConfig, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("economy.json is invalid: {e}"))?;
        let resource_ids: Vec<String> = v
            .get("resources")
            .and_then(Value::as_object)
            .ok_or("economy.json: missing resources")?
            .keys()
            .filter(|k| !k.starts_with('_'))
            .cloned()
            .collect();
        let mut buildings = Vec::new();
        for (id, def) in v.get("buildings").and_then(Value::as_object).ok_or("economy.json: missing buildings")? {
            if id.starts_with('_') {
                continue;
            }
            let mut effects = Effects::default();
            if let Some(map) = def.get("effects").and_then(Value::as_object) {
                for (k, x) in map {
                    let x = x.as_f64().ok_or("building effect is not a number")?;
                    match k.as_str() {
                        "gdp" => effects.gdp = x,
                        "industry" => effects.industry = x,
                        "food" => effects.food = x,
                        "trade" => effects.trade = x,
                        "growth" => effects.growth = x,
                        other => return Err(format!("economy.json: building {id} has an unknown effect {other}")),
                    }
                }
            }
            buildings.push(BuildingDef {
                id: id.clone(),
                effects,
                ic: num(def, &["ic"])?,
                ic_growth: def.get("ic_growth").and_then(Value::as_f64).unwrap_or(0.0),
                min_days: num(def, &["min_days"])? as i32,
                max_level: num(def, &["max_level"])? as i32,
                gold_share: def.get("gold_share").and_then(Value::as_f64),
                size_by_industry: def.get("size_by").and_then(Value::as_str) == Some("industry"),
                defense: def.get("defense").and_then(Value::as_f64).unwrap_or(0.0),
                shell_reduction: def.get("shell_reduction").and_then(Value::as_f64).unwrap_or(0.0),
                hard_reduction: def.get("hard_reduction").and_then(Value::as_f64).unwrap_or(0.0),
                enabled: def.get("enabled").and_then(Value::as_bool).unwrap_or(true),
                needs_coast: def.get("requires").and_then(Value::as_str) == Some("coastal"),
            });
        }
        Ok(EconomyConfig {
            gdp_per_capita: num(&v, &["gdp_per_capita"])?,
            reference_density: num(&v, &["reference_density"])?,
            density_exponent: num(&v, &["density_exponent"])?,
            density_min: num(&v, &["density_min"])?,
            density_max: num(&v, &["density_max"])?,
            industry_share_min: num(&v, &["industry_share_min"])?,
            industry_share_max: num(&v, &["industry_share_max"])?,
            food_per_km2: num(&v, &["food_per_km2"])?,
            manpower_share: num(&v, &["manpower_share"])?,
            default_tax_rate: num(&v, &["default_tax_rate"])?,
            min_tax_rate: num(&v, &["min_tax_rate"])?,
            max_tax_rate: num(&v, &["max_tax_rate"])?,
            baseline_growth: num(&v, &["baseline_growth"])?,
            ic_value: num(&v, &["ic_value"])?,
            famine_decline: num(&v, &["population", "famine_decline"])?,
            min_province: num(&v, &["population", "min_province"])?,
            tax_relief_growth_bonus: num(&v, &["tax_relief", "growth_bonus"])?,
            tax_strain_growth_penalty: num(&v, &["tax_strain", "growth_penalty"])?,
            invest_growth_per_share: num(&v, &["invest", "growth_per_share"])?,
            invest_soft_share: num(&v, &["invest", "soft_share"])?,
            labor_penalty: num(&v, &["labor", "penalty"])?,
            labor_floor: num(&v, &["labor", "floor"])?,
            starvation_output: num(&v, &["starvation", "output"])?,
            construction_gold_share: v
                .get("construction")
                .and_then(|c| c.get("gold_share"))
                .and_then(Value::as_f64)
                .unwrap_or(0.0),
            cost_ref_gdp: num(&v, &["construction", "cost_ref_gdp"])?,
            cost_ref_industry: num(&v, &["construction", "cost_ref_industry"])?,
            cost_min_factor: num(&v, &["construction", "cost_min_factor"])?,
            materials_extraction_base: num(&v, &["materials", "extraction_base"])?,
            materials_min_deposit: num(&v, &["materials", "min_deposit"])?,
            materials_need_per_industry: num(&v, &["materials", "need_per_industry"])?,
            materials_import_cap: num(&v, &["materials", "import_cap"])?,
            materials_import_price: num(&v, &["materials", "import_price"])?,
            materials_import_markup: num(&v, &["materials", "import_markup"])?,
            materials_export_share: num(&v, &["materials", "export_share"])?,
            materials_floor: num(&v, &["materials", "floor"])?,
            mobilization_output_penalty: num(&v, &["mobilization_output_penalty"])?,
            famine_output_penalty: num(&v, &["famine_output_penalty"])?,
            blockade_trade_loss: num(&v, &["blockade_trade_loss"])?,
            tax_drag: num(&v, &["tax_drag"])?,
            civil_share: num(&v, &["civil_share"])?,
            start_surplus: v.get("start_surplus").and_then(Value::as_f64).unwrap_or(0.0),
            soldier_upkeep: num(&v, &["soldier_upkeep"])?,
            soldier_upkeep_ref: num(&v, &["soldier_upkeep_ref"])?,
            wage_min: num(&v, &["wage_min"])?,
            wage_max: num(&v, &["wage_max"])?,
            reserve_upkeep: num(&v, &["reserve_upkeep"])?,
            food_import_cost: num(&v, &["food_import_cost"])?,
            food_state_share: num(&v, &["food_state_share"])?,
            debt_interest: num(&v, &["debt", "interest"])?,
            munitions_default_share: num(&v, &["munitions", "default_share"])?,
            munitions_output_penalty: num(&v, &["munitions", "output_penalty"])?,
            munitions_storage_cost: num(&v, &["munitions", "storage_cost"])?,
            munitions_per_gun_power: num(&v, &["munitions", "per_gun_power"])?,
            munitions_engaged_share: num(&v, &["munitions", "engaged_share"])?,
            munitions_idle_share: num(&v, &["munitions", "idle_share"])?,
            munitions_import_price: num(&v, &["munitions", "import_price"])?,
            base_ic: num(&v, &["construction", "base_ic"])?,
            base_ic_gdp_ref: num(&v, &["construction", "base_ic_gdp_ref"])?,
            base_ic_min: num(&v, &["construction", "base_ic_min"])?,
            ic_per_industry: num(&v, &["construction", "ic_per_industry"])?,
            occupation_decline: num(&v, &["population", "occupation_decline"])?,
            death_share: num(&v, &["population", "death_share"])?,
            weariness_max: num(&v, &["weariness", "max"])?,
            weariness_per_100k: num(&v, &["weariness", "per_100k"])?,
            weariness_ease_per_day: num(&v, &["weariness", "ease_per_day"])?,
            starvation_below: num(&v, &["starvation", "below"])?,
            starvation_support_per_day: num(&v, &["starvation", "support_per_day"])?,
            munitions_decay_per_year: num(&v, &["munitions", "decay_per_year"])?,
            mobilization_rate: num(&v, &["mobilization_rate"])?,
            mobilization_peace_max: num(&v, &["mobilization", "peace_max"])?,
            standing_share: num(&v, &["standing_share"])?,
            army_growth_share: num(&v, &["army_growth_share"])?,
            tax_strain_war_weariness: num(&v, &["tax_strain", "war_weariness"])?,
            tax_strain_support_penalty: num(&v, &["tax_strain", "support_penalty"])?,
            tax_relief_support_bonus: num(&v, &["tax_relief", "support_bonus"])?,
            resource_ids,
            buildings,
        })
    }

    pub fn building(&self, id: &str) -> Option<&BuildingDef> {
        self.buildings.iter().find(|b| b.id == id)
    }
}


/// One kind of unit (`data/military.json`, unit_types), in file order.
#[derive(Debug, Clone)]
pub struct UnitType {
    pub id: String,
    pub size: i64,
    pub attack: f64,
    pub speed: f64,
    /// Whether the unit burns shells (its "shells" value is above zero).
    pub shells: bool,
    /// Its share of a starting army's men.
    pub share: f64,
    pub cost: f64,
    pub train_days: i64,
}

/// The parts of `data/military.json` the ported rules read.
#[derive(Debug, Clone)]
pub struct MilitaryConfig {
    pub field_share: f64,
    pub unit_types: Vec<UnitType>,
    pub morale_floor_effect: f64,
    pub training_power_max: f64,
    pub training_days_full: f64,
    pub training_cost_share: f64,
    pub landing_power_mult: f64,
    pub landing_days: i64,
    pub front_paths_per_day: i64,
    pub front_enemy_weight: f64,
    pub front_fort_weight: f64,
    pub front_reweigh_days: i64,
    pub front_rigid_hops: i64,
    pub front_balanced_hops: i64,
    pub fallback_extra_levels: i64,
    pub fallback_dig_speed: f64,
    pub landing_supply_days: i64,
    pub marshal_share: f64,
    pub occupation_income_share: f64,
    pub occupation_mop_up_days: i64,
    pub occupation_cavalry_mult: f64,
    /// Each nation's commanders: name and skill, in order.
    pub generals: Vec<(String, Vec<(String, f64)>)>,
    pub terrain: Vec<(String, TerrainDef)>,
    pub combat: CombatConfig,
    pub supply: SupplyConfig,
    pub movement: MovementConfig,
    pub cities: CitiesConfig,
    pub training_loss_dilution: f64,
}

#[derive(Debug, Clone)]
pub struct TerrainDef {
    pub defense: f64,
    pub move_cost: f64,
    pub occupy_days: i64,
}

#[derive(Debug, Clone)]
pub struct CombatConfig {
    pub casualties_per_point: f64,
    pub shell_penalty: f64,
    pub morale_loss_per_casualty: f64,
    pub morale_loss_base: f64,
    pub morale_regain: f64,
    pub rout_morale: f64,
    pub routed_loss: f64,
    pub pursuit: f64,
    pub pursuit_max: f64,
    pub min_strength: f64,
    pub max_entrenchment: i64,
    pub entrench_days_per_level: i64,
    pub entrench_defense_per_level: f64,
}

#[derive(Debug, Clone)]
pub struct SupplyConfig {
    pub range: f64,
    pub railway_hop_cost: f64,
    pub railway_level_gain: f64,
    pub attrition: f64,
    pub attrition_morale: f64,
    pub reinforce_rate: f64,
}

#[derive(Debug, Clone)]
pub struct MovementConfig {
    pub min_days: f64,
    pub railway_speedup: f64,
    pub home_rail: f64,
    pub strait_days: f64,
    pub sea_link_days: f64,
}

#[derive(Debug, Clone)]
pub struct CitiesConfig {
    /// By city rank 1 to 3.
    pub power: [f64; 3],
    pub radius: [i64; 3],
    pub supply_range: f64,
    pub morale: f64,
    pub reinforce: f64,
    pub morale_fighting: f64,
}

impl MilitaryConfig {
    pub fn from_json_str(text: &str) -> Result<MilitaryConfig, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("military.json is invalid: {e}"))?;
        let mut unit_types = vec![];
        for (id, d) in v.get("unit_types").and_then(Value::as_object).ok_or("military.json: unit_types")? {
            unit_types.push(UnitType {
                id: id.clone(),
                size: num(d, &["size"])? as i64,
                attack: num(d, &["attack"])?,
                speed: num(d, &["speed"])?,
                shells: d.get("shells").and_then(Value::as_f64).unwrap_or(0.0) > 0.0,
                share: num(d, &["share"])?,
                cost: num(d, &["cost"])?,
                train_days: num(d, &["train_days"])? as i64,
            });
        }
        let mut generals = vec![];
        for (tag, list) in v.get("generals").and_then(Value::as_object).ok_or("military.json: generals")? {
            let mut l = vec![];
            for g in list.as_array().ok_or("military.json: generals list")? {
                l.push((
                    g[0].as_str().ok_or("general name")?.to_string(),
                    g[1].as_f64().ok_or("general skill")?,
                ));
            }
            generals.push((tag.clone(), l));
        }
        Ok(MilitaryConfig {
            field_share: num(&v, &["field_share"])?,
            unit_types,
            morale_floor_effect: num(&v, &["combat", "morale_floor_effect"])?,
            training_days_full: v.get("training").and_then(|t| t.get("days_full")).and_then(Value::as_f64).unwrap_or(120.0),
            training_power_max: v.get("training").and_then(|t| t.get("power_max")).and_then(Value::as_f64).unwrap_or(0.0),
            training_cost_share: v.get("training").and_then(|t| t.get("cost_share")).and_then(Value::as_f64).unwrap_or(0.0),
            landing_power_mult: num(&v, &["landing", "power_mult"])?,
            landing_days: num(&v, &["landing", "days"])? as i64,
            front_paths_per_day: num(&v, &["front_pathing", "paths_per_day"])? as i64,
            front_enemy_weight: v["fronts"].get("enemy_weight").and_then(Value::as_f64).unwrap_or(0.25),
            front_fort_weight: v["fronts"].get("fort_weight").and_then(Value::as_f64).unwrap_or(0.15),
            front_reweigh_days: v["fronts"].get("reweigh_days").and_then(Value::as_f64).unwrap_or(7.0) as i64,
            front_rigid_hops: v["fronts"].get("rigid_hops").and_then(Value::as_f64).unwrap_or(2.0) as i64,
            front_balanced_hops: v["fronts"].get("balanced_hops").and_then(Value::as_f64).unwrap_or(6.0) as i64,
            fallback_extra_levels: v["fronts"].get("fallback_extra_levels").and_then(Value::as_f64).unwrap_or(2.0) as i64,
            fallback_dig_speed: v["fronts"].get("fallback_dig_speed").and_then(Value::as_f64).unwrap_or(1.5),
            landing_supply_days: num(&v, &["landing", "supply_days"])? as i64,
            marshal_share: num(&v, &["army_group", "marshal_share"])?,
            occupation_income_share: num(&v, &["occupation", "income_share"])?,
            occupation_mop_up_days: num(&v, &["occupation", "mop_up_days"])? as i64,
            occupation_cavalry_mult: num(&v, &["occupation", "cavalry_mult"])?,
            generals,
            terrain: {
                let mut t = vec![];
                for (id, d) in v.get("terrain").and_then(Value::as_object).ok_or("military.json: terrain")? {
                    t.push((id.clone(), TerrainDef { defense: num(d, &["defense"])?, move_cost: num(d, &["move"])?, occupy_days: num(d, &["occupy_days"])? as i64 }));
                }
                t
            },
            combat: CombatConfig {
                casualties_per_point: num(&v, &["combat", "casualties_per_point"])?,
                shell_penalty: num(&v, &["combat", "shell_penalty"])?,
                morale_loss_per_casualty: num(&v, &["combat", "morale_loss_per_casualty"])?,
                morale_loss_base: num(&v, &["combat", "morale_loss_base"])?,
                morale_regain: num(&v, &["combat", "morale_regain"])?,
                rout_morale: num(&v, &["combat", "rout_morale"])?,
                routed_loss: num(&v, &["combat", "routed_loss"])?,
                pursuit: num(&v, &["combat", "pursuit"])?,
                pursuit_max: num(&v, &["combat", "pursuit_max"])?,
                min_strength: num(&v, &["combat", "min_strength"])?,
                max_entrenchment: num(&v, &["combat", "max_entrenchment"])? as i64,
                entrench_days_per_level: num(&v, &["combat", "entrench_days_per_level"])? as i64,
                entrench_defense_per_level: num(&v, &["combat", "entrench_defense_per_level"])?,
            },
            supply: SupplyConfig {
                range: num(&v, &["supply", "range"])?,
                railway_hop_cost: num(&v, &["supply", "railway_hop_cost"])?,
                railway_level_gain: num(&v, &["supply", "railway_level_gain"])?,
                attrition: num(&v, &["supply", "attrition"])?,
                attrition_morale: num(&v, &["supply", "attrition_morale"])?,
                reinforce_rate: num(&v, &["supply", "reinforce_rate"])?,
            },
            movement: MovementConfig {
                min_days: num(&v, &["movement", "min_days"])?,
                railway_speedup: num(&v, &["movement", "railway_speedup"])?,
                home_rail: num(&v, &["movement", "home_rail"])?,
                strait_days: num(&v, &["movement", "strait_days"])?,
                sea_link_days: num(&v, &["movement", "sea_link_days"])?,
            },
            cities: CitiesConfig {
                power: [num(&v, &["cities", "power", "1"])?, num(&v, &["cities", "power", "2"])?, num(&v, &["cities", "power", "3"])?],
                radius: [num(&v, &["cities", "radius", "1"])? as i64, num(&v, &["cities", "radius", "2"])? as i64, num(&v, &["cities", "radius", "3"])? as i64],
                supply_range: num(&v, &["cities", "supply_range"])?,
                morale: num(&v, &["cities", "morale"])?,
                reinforce: num(&v, &["cities", "reinforce"])?,
                morale_fighting: num(&v, &["cities", "morale_fighting"])?,
            },
            training_loss_dilution: v.get("training").and_then(|t| t.get("loss_dilution")).and_then(Value::as_f64).unwrap_or(0.5),
        })
    }

    pub fn unit_type(&self, id: &str) -> &UnitType {
        self.unit_types.iter().find(|t| t.id == id).unwrap_or_else(|| panic!("unknown unit type {id}"))
    }

    pub fn terrain_def(&self, id: &str) -> &TerrainDef {
        self.terrain.iter().find(|(t, _)| t == id).map(|(_, d)| d).unwrap_or_else(|| panic!("unknown terrain {id}"))
    }

    pub fn generals_of(&self, tag: &str) -> &[(String, f64)] {
        self.generals.iter().find(|(t, _)| t == tag).map(|(_, l)| l.as_slice()).unwrap_or(&[])
    }
}

/// `data/navy.json`: the ship types' upkeep and the port level they need, in file order.
#[derive(Debug, Clone)]
pub struct ShipDef {
    pub id: String,
    pub attack: f64,
    pub speed: f64,
    pub range_days: i64,
    pub detection: f64,
    pub upkeep: f64,
    pub cost: f64,
    pub ic: f64,
    pub build_days: i32,
    pub min_port: i64,
    pub capacity: i64,
    pub hull: f64,
    pub exposure: f64,
    pub crew: f64,
}

#[derive(Debug, Clone)]
pub struct NavyCombat {
    pub contact_base: f64,
    pub damage_per_point: f64,
    pub min_strength: f64,
    pub morale_loss_per_damage: f64,
    pub morale_loss_base: f64,
    pub morale_regain: f64,
    pub rout_morale: f64,
    pub submarine_evasion: f64,
    pub submarine_screen: f64,
}

#[derive(Debug, Clone)]
pub struct BlockadeConfig {
    pub min_power: f64,
    pub base_weight: f64,
    pub per_port_level: f64,
    pub second_zone_share: f64,
    pub max: f64,
    pub land_leak: f64,
    pub rise_per_day: f64,
    pub fall_per_day: f64,
    pub recompute_step: f64,
    pub assess_days: i64,
    pub outlets: Vec<String>,
}

/// `data/navy.json`.
#[derive(Debug, Clone)]
pub struct NavyConfig {
    pub types: Vec<ShipDef>,
    pub port_days: f64,
    pub min_hop_days: f64,
    pub combat: NavyCombat,
    pub repair_per_day: f64,
    pub port_morale_regain: f64,
    pub range_attrition: f64,
    pub range_attrition_morale: f64,
    pub range_floor: f64,
    pub blockade: BlockadeConfig,
    pub slots_per_port_level: i64,
    pub shore_per_squadron: f64,
    pub shore_max: f64,
}

impl NavyConfig {
    pub fn from_json_str(text: &str) -> Result<NavyConfig, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("navy.json is invalid: {e}"))?;
        let mut types = vec![];
        for (id, d) in v.get("types").and_then(Value::as_object).ok_or("navy.json: types")? {
            types.push(ShipDef {
                id: id.clone(),
                attack: num(d, &["attack"])?,
                speed: num(d, &["speed"])?,
                range_days: num(d, &["range_days"])? as i64,
                detection: num(d, &["detection"])?,
                upkeep: num(d, &["upkeep"])?,
                cost: num(d, &["cost"])?,
                ic: num(d, &["ic"])?,
                build_days: num(d, &["build_days"])? as i32,
                min_port: num(d, &["min_port"])? as i64,
                capacity: num(d, &["capacity"])? as i64,
                hull: num(d, &["hull"])?,
                exposure: num(d, &["exposure"])?,
                crew: num(d, &["crew"])?,
            });
        }
        let c = |k: &str| num(&v, &["combat", k]);
        let b = |k: &str| num(&v, &["blockade", k]);
        Ok(NavyConfig {
            types,
            port_days: num(&v, &["port_days"])?,
            min_hop_days: num(&v, &["min_hop_days"])?,
            combat: NavyCombat {
                contact_base: c("contact_base")?,
                damage_per_point: c("damage_per_point")?,
                min_strength: c("min_strength")?,
                morale_loss_per_damage: c("morale_loss_per_damage")?,
                morale_loss_base: c("morale_loss_base")?,
                morale_regain: c("morale_regain")?,
                rout_morale: c("rout_morale")?,
                submarine_evasion: c("submarine_evasion")?,
                submarine_screen: c("submarine_screen")?,
            },
            slots_per_port_level: num(&v, &["slots_per_port_level"])? as i64,
            shore_per_squadron: num(&v, &["shore_support", "per_squadron"])?,
            shore_max: num(&v, &["shore_support", "max"])?,
            repair_per_day: num(&v, &["repair_per_day"])?,
            port_morale_regain: num(&v, &["port_morale_regain"])?,
            range_attrition: num(&v, &["range_attrition"])?,
            range_attrition_morale: num(&v, &["range_attrition_morale"])?,
            range_floor: num(&v, &["range_floor"])?,
            blockade: BlockadeConfig {
                min_power: b("min_power")?,
                base_weight: b("base_weight")?,
                per_port_level: b("per_port_level")?,
                second_zone_share: b("second_zone_share")?,
                max: b("max")?,
                land_leak: b("land_leak")?,
                rise_per_day: b("rise_per_day")?,
                fall_per_day: b("fall_per_day")?,
                recompute_step: b("recompute_step")?,
                assess_days: b("assess_days")? as i64,
                outlets: v["blockade"]["outlets"].as_array().ok_or("navy.json: outlets")?.iter().filter_map(|x| x.as_str().map(String::from)).collect(),
            },
        })
    }

    pub fn def(&self, ship: &str) -> &ShipDef {
        self.types.iter().find(|t| t.id == ship).unwrap_or_else(|| panic!("unknown ship type {ship}"))
    }

    pub fn upkeep(&self, ship: &str) -> f64 {
        self.def(ship).upkeep
    }

    pub fn min_port(&self, ship: &str) -> Option<i64> {
        self.types.iter().find(|t| t.id == ship).map(|t| t.min_port)
    }
}

/// `data/diplomacy.json`, war_support: what a government starts with, and the curve of tax and recruits at war.
#[derive(Debug, Clone)]
pub struct WarSupportConfig {
    pub start_default: f64,
    pub start: Vec<(String, f64)>,
    pub economy_curve: [f64; 3],
    /// The lowest mobilization a nation at war may have (`data/diplomacy.json`, crisis.war_floor).
    pub crisis_war_floor: f64,
    pub recovery_per_month: f64,
    pub weariness: f64,
    pub casualty_weight: f64,
    pub blockade_weight: f64,
    pub occupied_weight: f64,
    pub debt_weight: f64,
    pub debt_cap: f64,
    pub white_peace_below: f64,
    pub morale_curve: [f64; 3],
    pub win_bonus: f64,
    pub home_win_bonus: f64,
    pub loss_penalty: f64,
}

impl WarSupportConfig {
    pub fn from_json_str(text: &str) -> Result<WarSupportConfig, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("diplomacy.json is invalid: {e}"))?;
        let ws = v.get("war_support").ok_or("diplomacy.json: war_support")?;
        let start = ws.get("start").and_then(Value::as_object).ok_or("war_support.start")?;
        Ok(WarSupportConfig {
            start_default: start.get("default").and_then(Value::as_f64).ok_or("war_support.start.default")?,
            start: start.iter().filter(|(k, _)| *k != "default").filter_map(|(k, x)| x.as_f64().map(|x| (k.clone(), x))).collect(),
            economy_curve: [
                num(ws, &["economy_mult", "at_0"])?,
                num(ws, &["economy_mult", "at_50"])?,
                num(ws, &["economy_mult", "at_100"])?,
            ],
            crisis_war_floor: num(&v, &["crisis", "war_floor"])?,
            recovery_per_month: num(ws, &["recovery_per_month"])?,
            weariness: num(ws, &["weariness"])?,
            casualty_weight: num(ws, &["casualty_weight"])?,
            blockade_weight: num(ws, &["blockade_weight"])?,
            occupied_weight: num(ws, &["occupied_weight"])?,
            debt_weight: num(ws, &["debt_weight"])?,
            debt_cap: num(ws, &["debt_cap"])?,
            white_peace_below: num(ws, &["white_peace_below"])?,
            morale_curve: [num(ws, &["morale_mult", "at_0"])?, num(ws, &["morale_mult", "at_50"])?, num(ws, &["morale_mult", "at_100"])?],
            win_bonus: num(ws, &["win_bonus"])?,
            home_win_bonus: num(ws, &["home_win_bonus"])?,
            loss_penalty: num(ws, &["loss_penalty"])?,
        })
    }

    /// What a government type starts with.
    pub fn start_value(&self, government: &str) -> f64 {
        self.start.iter().find(|(g, _)| g == government).map(|(_, x)| *x).unwrap_or(self.start_default)
    }

    /// Multiplier on tax and recruitment at war, from the nation's support (`WarSupport._curve`).
    pub fn economy_mult_at(&self, support: f64) -> f64 {
        Self::curve(self.economy_curve, support)
    }

    /// Multiplier on the fighting power of the nation's armies at war.
    pub fn morale_mult_at(&self, support: f64) -> f64 {
        Self::curve(self.morale_curve, support)
    }

    fn curve([a, b, c]: [f64; 3], support: f64) -> f64 {
        if support <= 50.0 {
            crate::gd::lerpf(a, b, support / 50.0)
        } else {
            crate::gd::lerpf(b, c, (support - 50.0) / 50.0)
        }
    }
}


/// One kind of treaty (`data/diplomacy.json`, treaties).
#[derive(Debug, Clone)]
pub struct TreatyKind {
    pub id: String,
    /// Whether it runs one way, from a to b.
    pub directed: bool,
    /// What it adds to the pair's baseline opinion.
    pub relation_bonus: f64,
}

/// The crisis constants (`data/diplomacy.json`, crisis): mobilization and its alarms.
#[derive(Debug, Clone)]
pub struct CrisisConfig {
    pub alarm_level: f64,
    pub alarm_clear_level: f64,
    pub alarm_relations: f64,
    pub alarm_grievance: f64,
    pub match_response: f64,
    pub call_response: f64,
    pub called_level: f64,
    pub war_floor: f64,
    pub war_step_up: f64,
    pub ai_step_up: f64,
    pub ai_step_down: f64,
}

/// The parts of `data/diplomacy.json` the ported rules read besides war support.
#[derive(Debug, Clone)]
pub struct DiplomacyConfig {
    pub relation_min: f64,
    pub relation_max: f64,
    pub relation_neutral: f64,
    pub relation_same_bloc: f64,
    pub relation_opposed_blocs: f64,
    pub relation_drift_per_month: f64,
    pub points_start: f64,
    pub points_max: f64,
    pub income_base: f64,
    pub income_prestige_weight: f64,
    pub income_min: f64,
    pub income_top_output_count: i64,
    pub income_top_output_bonus: f64,
    pub prestige_decay_per_month: f64,
    pub price_decay: f64,
    pub improve_monthly: f64,
    pub improve_base_monthly: f64,
    /// How many years a casus belli lasts (`war.cb_years`).
    pub cb_years: f64,
    pub grievance_decay_per_month: f64,
    pub rivalry_fade_per_year: f64,
    pub gift_memory_decay: f64,
    /// The parts of `data/diplomacy.json` the player's diplomatic actions read, as the file has them: `points`, `actions` and
    /// `war.cancel`.
    pub raw_points: Value,
    pub raw_actions: Value,
    pub raw_cancel: Value,
    pub treaties: Vec<TreatyKind>,
    pub crisis: CrisisConfig,
    pub prestige_battle_win: f64,
    pub score_battle_ratio_min: f64,
    pub score_battle_ratio_max: f64,
    pub score_battle_cap: f64,
    pub score_battle_per_kmen: f64,
    pub capitulation: CapitulationConfig,
    pub peace: PeaceConfig,
    /// What a war with each casus belli does when declared (`war.casus_belli`).
    pub casus_belli: Vec<(String, CbRule)>,
    /// What declining a join decision of each kind costs (`join.decline`).
    pub join_decline: Vec<(String, DeclineCost)>,
    pub neutral_world_relations: f64,
    pub neutral_prestige: f64,
    pub neutral_tension: f64,
    pub min_mobilization: f64,
    pub grievance_on_unprovoked_war: f64,
    pub join_mobilization: f64,
}

#[derive(Debug, Clone, Copy)]
pub struct CbRule {
    pub target_relations: f64,
    pub world_relations: f64,
    pub prestige: f64,
    pub war_support: f64,
}

#[derive(Debug, Clone, Copy)]
pub struct DeclineCost {
    pub ally_relations: f64,
    pub prestige: f64,
    pub end_treaty: bool,
}

/// `data/diplomacy.json`, capitulation: what a province is worth in a war, and how much of it a nation may lose.
#[derive(Debug, Clone)]
pub struct CapitulationConfig {
    pub value_population: f64,
    pub value_city: f64,
    pub value_buildings: Vec<(String, f64)>,
    pub value_minimum: f64,
    pub capital_share: f64,
    pub relocation_share: f64,
    pub relocated_bonus: f64,
    pub capitulate_share: f64,
    /// The war score a capitulation gives the enemy.
    pub score: f64,
}

/// `data/diplomacy.json`, peace and the war goals and the claims left by a peace.
#[derive(Debug, Clone)]
pub struct PeaceConfig {
    pub score_max: f64,
    pub score_occupation_points: f64,
    pub score_decay_per_month: f64,
    pub province_scale: f64,
    pub occupied_discount: f64,
    pub indemnity_points_per_year: f64,
    pub max_share: f64,
    pub max_months: i64,
    pub release_ally: f64,
    pub disarm_border_per_year: f64,
    pub fleet_limit_per_year: f64,
    pub disarm_years_max: i64,
    pub forced_occupied_share: f64,
    pub forced_budget_mult: f64,
    pub great_power_max_share: f64,
    pub refuse_cooldown_days: i64,
    pub peace_per_score: f64,
    pub peace_cap: f64,
    pub peace_loser_share: f64,
    pub surrender_at: f64,
    pub support_floor: f64,
    pub goal_discount: f64,
    pub goal_premium: f64,
    pub goal_none_premium: f64,
    pub revanche_years: f64,
    pub revanche_rivalry: f64,
    pub revanche_rivalry_per_province: f64,
    pub revanche_rivalry_max: f64,
}

impl DiplomacyConfig {
    pub fn from_json_str(text: &str) -> Result<DiplomacyConfig, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("diplomacy.json is invalid: {e}"))?;
        let mut treaties = vec![];
        for (id, d) in v.get("treaties").and_then(Value::as_object).ok_or("diplomacy.json: treaties")? {
            if id.starts_with('_') {
                continue;
            }
            treaties.push(TreatyKind {
                id: id.clone(),
                directed: d.get("directed").and_then(Value::as_bool).ok_or("treaty directed")?,
                relation_bonus: num(d, &["relation_bonus"])?,
            });
        }
        let cr = |k: &str| num(&v, &["crisis", k]);
        Ok(DiplomacyConfig {
            relation_min: num(&v, &["relations", "min"])?,
            relation_max: num(&v, &["relations", "max"])?,
            relation_neutral: num(&v, &["relations", "neutral"])?,
            relation_same_bloc: num(&v, &["relations", "same_bloc"])?,
            relation_opposed_blocs: num(&v, &["relations", "opposed_blocs"])?,
            relation_drift_per_month: num(&v, &["relations", "drift_per_month"])?,
            points_start: num(&v, &["points", "start"])?,
            points_max: num(&v, &["points", "max"])?,
            income_base: num(&v, &["points", "income", "base"])?,
            income_prestige_weight: num(&v, &["points", "income", "prestige_weight"])?,
            income_min: num(&v, &["points", "income", "min"])?,
            income_top_output_count: num(&v, &["points", "income", "top_output_count"])? as i64,
            income_top_output_bonus: num(&v, &["points", "income", "top_output_bonus"])?,
            prestige_decay_per_month: num(&v, &["points", "prestige", "decay_per_month"])?,
            price_decay: num(&v, &["points", "purchase", "price_decay"])?,
            improve_monthly: num(&v, &["points", "improve", "monthly"])?,
            improve_base_monthly: num(&v, &["points", "improve", "base_monthly"])?,
            cb_years: num(&v, &["war", "cb_years"])?,
            grievance_decay_per_month: num(&v, &["war", "provocation", "grievance_decay_per_month"])?,
            rivalry_fade_per_year: num(&v, &["war", "provocation", "rivalry_fade_per_year"])?,
            gift_memory_decay: num(&v, &["actions", "gift_memory_decay"])?,
            raw_points: v["points"].clone(),
            raw_actions: v["actions"].clone(),
            raw_cancel: v["war"]["cancel"].clone(),
            treaties,
            prestige_battle_win: num(&v, &["points", "prestige", "battle_win"])?,
            score_battle_ratio_min: num(&v, &["peace", "score", "battle_ratio_min"])?,
            score_battle_ratio_max: num(&v, &["peace", "score", "battle_ratio_max"])?,
            score_battle_cap: num(&v, &["peace", "score", "battle_cap"])?,
            score_battle_per_kmen: num(&v, &["peace", "score", "battle_per_kmen"])?,
            capitulation: CapitulationConfig {
                value_population: num(&v, &["capitulation", "value", "population"])?,
                value_city: num(&v, &["capitulation", "value", "city"])?,
                value_buildings: v["capitulation"]["value"]["buildings"].as_object().ok_or("capitulation.value.buildings")?.iter().filter_map(|(k, x)| x.as_f64().map(|x| (k.clone(), x))).collect(),
                value_minimum: num(&v, &["capitulation", "value", "minimum"])?,
                capital_share: num(&v, &["capitulation", "capital_share"])?,
                relocation_share: num(&v, &["capitulation", "relocation_share"])?,
                relocated_bonus: num(&v, &["capitulation", "relocated_bonus"])?,
                capitulate_share: num(&v, &["capitulation", "capitulate_share"])?,
                score: num(&v, &["capitulation", "score"])?,
            },
            casus_belli: v["war"]["casus_belli"].as_object().ok_or("war.casus_belli")?.iter().filter(|(k, _)| !k.starts_with('_')).map(|(k, r)| Ok((k.clone(), CbRule {
                target_relations: num(r, &["target_relations"])?,
                world_relations: num(r, &["world_relations"])?,
                prestige: num(r, &["prestige"])?,
                war_support: num(r, &["war_support"])?,
            }))).collect::<Result<Vec<_>, String>>()?,
            join_decline: v["join"]["decline"].as_object().ok_or("join.decline")?.iter().map(|(k, r)| Ok((k.clone(), DeclineCost {
                ally_relations: num(r, &["ally_relations"])?,
                prestige: num(r, &["prestige"])?,
                end_treaty: r.get("end_treaty").and_then(Value::as_bool).unwrap_or(false),
            }))).collect::<Result<Vec<_>, String>>()?,
            neutral_world_relations: num(&v, &["war", "neutral_violation", "world_relations"])?,
            neutral_prestige: num(&v, &["war", "neutral_violation", "prestige"])?,
            neutral_tension: num(&v, &["war", "neutral_violation", "tension"])?,
            min_mobilization: cr("min_mobilization")?,
            grievance_on_unprovoked_war: num(&v, &["war", "provocation", "grievance_on_unprovoked_war"])?,
            join_mobilization: cr("join_mobilization")?,
            peace: PeaceConfig {
                score_max: num(&v, &["peace", "score", "max"])?,
                score_occupation_points: num(&v, &["peace", "score", "occupation_points"])?,
                score_decay_per_month: num(&v, &["peace", "score", "decay_per_month"])?,
                province_scale: num(&v, &["peace", "price", "province_scale"])?,
                occupied_discount: num(&v, &["peace", "price", "occupied_discount"])?,
                indemnity_points_per_year: num(&v, &["peace", "price", "indemnity_points_per_year"])?,
                max_share: num(&v, &["peace", "price", "max_share"])?,
                max_months: num(&v, &["peace", "price", "max_months"])? as i64,
                release_ally: num(&v, &["peace", "price", "release_ally"])?,
                disarm_border_per_year: num(&v, &["peace", "price", "disarm_border_per_year"])?,
                fleet_limit_per_year: num(&v, &["peace", "price", "fleet_limit_per_year"])?,
                disarm_years_max: num(&v, &["peace", "price", "disarm_years_max"])? as i64,
                forced_occupied_share: num(&v, &["peace", "forced", "occupied_share"])?,
                forced_budget_mult: num(&v, &["peace", "forced", "budget_mult"])?,
                great_power_max_share: v["peace"].get("great_power_max_share").and_then(Value::as_f64).unwrap_or(1.0),
                refuse_cooldown_days: num(&v, &["peace", "ai", "refuse_cooldown_days"])? as i64,
                peace_per_score: num(&v, &["points", "prestige", "peace_per_score"])?,
                peace_cap: num(&v, &["points", "prestige", "peace_cap"])?,
                peace_loser_share: num(&v, &["points", "prestige", "peace_loser_share"])?,
                surrender_at: num(&v, &["war_support", "surrender_at"])?,
                support_floor: num(&v, &["war_support", "floor"])?,
                goal_discount: num(&v, &["war", "goals", "discount"])?,
                goal_premium: num(&v, &["war", "goals", "premium"])?,
                goal_none_premium: num(&v, &["war", "goals", "none_premium"])?,
                revanche_years: num(&v, &["revanche", "years"])?,
                revanche_rivalry: num(&v, &["revanche", "rivalry"])?,
                revanche_rivalry_per_province: num(&v, &["revanche", "rivalry_per_province"])?,
                revanche_rivalry_max: num(&v, &["revanche", "rivalry_max"])?,
            },
            crisis: CrisisConfig {
                alarm_level: cr("alarm_level")?,
                alarm_clear_level: cr("alarm_clear_level")?,
                alarm_relations: cr("alarm_relations")?,
                alarm_grievance: cr("alarm_grievance")?,
                match_response: cr("match_response")?,
                call_response: cr("call_response")?,
                called_level: cr("called_level")?,
                war_floor: cr("war_floor")?,
                war_step_up: cr("war_step_up")?,
                ai_step_up: cr("ai_step_up")?,
                ai_step_down: cr("ai_step_down")?,
            },
        })
    }

    pub fn treaty_kind(&self, id: &str) -> &TreatyKind {
        self.treaties.iter().find(|t| t.id == id).unwrap_or_else(|| panic!("unknown treaty kind {id}"))
    }
}

/// What a national focus does (`data/focus.json`, effects). A key the focus does not have is `None`: the game tests for
/// the key, not for a value, so a zero that is written is still a lasting effect.
#[derive(Debug, Clone, Default)]
pub struct FocusEffects {
    pub gdp: Option<f64>,
    pub industry: Option<f64>,
    pub food: Option<f64>,
    pub trade: Option<f64>,
    pub growth: Option<f64>,
    pub diplomacy: Option<f64>,
    pub construction: Option<f64>,
    pub prestige: Option<f64>,
    pub points: Option<f64>,
    pub treasury: Option<f64>,
    pub war_support: Option<f64>,
    pub army_size: Option<f64>,
    pub relation: Vec<(String, f64)>,
    pub claim: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct FocusDef {
    pub id: String,
    pub days: i64,
    pub requires: Vec<String>,
    pub repeatable: bool,
    pub max: i64,
    pub effects: FocusEffects,
}

#[derive(Debug, Clone)]
enum Tree {
    Own(Vec<FocusDef>),
    Template { template: String, extra: Vec<FocusDef> },
}

#[derive(Debug, Clone)]
pub struct FocusConfig {
    templates: Vec<(String, Vec<FocusDef>)>,
    nations: Vec<(String, Tree)>,
}

fn focus_def(v: &Value) -> Result<FocusDef, String> {
    let e = v.get("effects").ok_or("focus without effects")?;
    let f = |k: &str| e.get(k).and_then(Value::as_f64);
    let pairs = |k: &str| -> Result<Vec<(String, f64)>, String> {
        let mut out = vec![];
        if let Some(list) = e.get(k).and_then(Value::as_array) {
            for p in list {
                out.push((p[0].as_str().ok_or("relation tag")?.to_string(), p[1].as_f64().ok_or("relation value")?));
            }
        }
        Ok(out)
    };
    Ok(FocusDef {
        id: v["id"].as_str().ok_or("focus id")?.to_string(),
        days: num(v, &["days"])? as i64,
        requires: v.get("requires").and_then(Value::as_array).map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect()).unwrap_or_default(),
        repeatable: v.get("repeatable").and_then(Value::as_bool).unwrap_or(false),
        max: v.get("max").and_then(Value::as_f64).unwrap_or(1.0) as i64,
        effects: FocusEffects {
            gdp: f("gdp"),
            industry: f("industry"),
            food: f("food"),
            trade: f("trade"),
            growth: f("growth"),
            diplomacy: f("diplomacy"),
            construction: f("construction"),
            prestige: f("prestige"),
            points: f("points"),
            treasury: f("treasury"),
            war_support: f("war_support"),
            army_size: f("army_size"),
            relation: pairs("relation")?,
            claim: e.get("claim").and_then(Value::as_array).map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect()).unwrap_or_default(),
        },
    })
}

fn focus_list(v: &Value) -> Result<Vec<FocusDef>, String> {
    v.as_array().ok_or("focus list")?.iter().map(focus_def).collect()
}

impl FocusConfig {
    pub fn from_json_str(text: &str) -> Result<FocusConfig, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("focus.json is invalid: {e}"))?;
        let mut templates = vec![];
        for (name, list) in v.get("templates").and_then(Value::as_object).ok_or("focus.json: templates")? {
            templates.push((name.clone(), focus_list(list)?));
        }
        let mut nations = vec![];
        for (tag, spec) in v.get("nations").and_then(Value::as_object).ok_or("focus.json: nations")? {
            let tree = if let Some(t) = spec.get("tree") {
                Tree::Own(focus_list(t)?)
            } else {
                Tree::Template {
                    template: spec["template"].as_str().ok_or("focus template")?.to_string(),
                    extra: focus_list(spec.get("extra").unwrap_or(&Value::Array(vec![])))?,
                }
            };
            nations.push((tag.clone(), tree));
        }
        Ok(FocusConfig { templates, nations })
    }

    /// The foci of a nation's tree: its template's, then its own (`Focus.tree_of`).
    pub fn tree_of(&self, tag: &str) -> Vec<&FocusDef> {
        let template_of = |name: &str| self.templates.iter().find(|(t, _)| t == name).map(|(_, l)| l);
        match self.nations.iter().find(|(t, _)| t == tag).map(|(_, t)| t) {
            Some(Tree::Own(list)) => list.iter().collect(),
            Some(Tree::Template { template, extra }) => template_of(template).into_iter().flatten().chain(extra.iter()).collect(),
            None => template_of("minor").into_iter().flatten().collect(),
        }
    }

    pub fn find(&self, tag: &str, id: &str) -> Option<&FocusDef> {
        self.tree_of(tag).into_iter().find(|f| f.id == id)
    }
}


/// `data/events.json`: Europe's tension and the historical events.
#[derive(Debug, Clone)]
pub struct PressureConfig {
    pub base: f64,
    pub arms_weight: f64,
    pub arms_max: f64,
    pub arms_drift: f64,
    pub mobilization_from: f64,
    pub mobilization_weight: f64,
    pub mobilization_max: f64,
    pub war_each: f64,
    pub war_max: f64,
    pub rivalry_weight: f64,
    pub impulse_decay: f64,
    pub impulse_max: f64,
    pub aggression_from: f64,
    pub aggression_gain: f64,
    pub harden_above: f64,
    pub harden_per_month: f64,
    pub bloc_weight: f64,
    pub ai_war_gate: f64,
    pub appeals: Value,
    pub recent_months: i64,
    pub empires: Vec<String>,
    pub empire_support: f64,
    /// The events, as the file gives them (they are read as data: dates, actors, conditions, options and their effects).
    pub events: Vec<Value>,
}

impl PressureConfig {
    pub fn from_json_str(text: &str) -> Result<PressureConfig, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("events.json is invalid: {e}"))?;
        let t = |k: &str| num(&v, &["tension", k]);
        let picks = &v["tension"]["picks"];
        Ok(PressureConfig {
            base: t("base")?,
            arms_weight: t("arms_weight")?,
            arms_max: t("arms_max")?,
            arms_drift: v["tension"].get("arms_drift").and_then(Value::as_f64).unwrap_or(0.0),
            mobilization_from: t("mobilization_from")?,
            mobilization_weight: t("mobilization_weight")?,
            mobilization_max: t("mobilization_max")?,
            war_each: t("war_each")?,
            war_max: t("war_max")?,
            rivalry_weight: t("rivalry_weight")?,
            impulse_decay: t("impulse_decay")?,
            impulse_max: t("impulse_max")?,
            aggression_from: t("aggression_from")?,
            aggression_gain: t("aggression_gain")?,
            harden_above: t("harden_above")?,
            harden_per_month: t("harden_per_month")?,
            bloc_weight: t("bloc_weight")?,
            ai_war_gate: t("ai_war_gate")?,
            appeals: v["tension"]["appeals"].clone(),
            recent_months: picks.get("recent_months").and_then(Value::as_i64).unwrap_or(24),
            empires: picks.get("empires").and_then(Value::as_array).map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect()).unwrap_or_default(),
            empire_support: picks.get("empire_support").and_then(Value::as_f64).unwrap_or(40.0),
            events: v.get("events").and_then(Value::as_array).cloned().ok_or("events.json: events")?,
        })
    }
}
