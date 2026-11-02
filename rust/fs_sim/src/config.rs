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
    /// Whether the unit burns shells (its "shells" value is above zero).
    pub shells: bool,
    /// Its share of a starting army's men.
    pub share: f64,
}

/// The parts of `data/military.json` the ported rules read.
#[derive(Debug, Clone)]
pub struct MilitaryConfig {
    pub field_share: f64,
    pub unit_types: Vec<UnitType>,
    pub morale_floor_effect: f64,
    pub training_power_max: f64,
    pub training_cost_share: f64,
    pub landing_power_mult: f64,
    pub marshal_share: f64,
    pub occupation_income_share: f64,
    /// Each nation's commanders: name and skill, in order.
    pub generals: Vec<(String, Vec<(String, f64)>)>,
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
                shells: d.get("shells").and_then(Value::as_f64).unwrap_or(0.0) > 0.0,
                share: num(d, &["share"])?,
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
            training_power_max: v.get("training").and_then(|t| t.get("power_max")).and_then(Value::as_f64).unwrap_or(0.0),
            training_cost_share: v.get("training").and_then(|t| t.get("cost_share")).and_then(Value::as_f64).unwrap_or(0.0),
            landing_power_mult: num(&v, &["landing", "power_mult"])?,
            marshal_share: num(&v, &["army_group", "marshal_share"])?,
            occupation_income_share: num(&v, &["occupation", "income_share"])?,
            generals,
        })
    }

    pub fn unit_type(&self, id: &str) -> &UnitType {
        self.unit_types.iter().find(|t| t.id == id).unwrap_or_else(|| panic!("unknown unit type {id}"))
    }

    pub fn generals_of(&self, tag: &str) -> &[(String, f64)] {
        self.generals.iter().find(|(t, _)| t == tag).map(|(_, l)| l.as_slice()).unwrap_or(&[])
    }
}

/// `data/navy.json`: the ship types' upkeep and the port level they need, in file order.
#[derive(Debug, Clone)]
pub struct NavyConfig {
    pub types: Vec<(String, f64, i64)>,
}

impl NavyConfig {
    pub fn from_json_str(text: &str) -> Result<NavyConfig, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("navy.json is invalid: {e}"))?;
        let mut types = vec![];
        for (id, d) in v.get("types").and_then(Value::as_object).ok_or("navy.json: types")? {
            types.push((id.clone(), num(d, &["upkeep"])?, num(d, &["min_port"])? as i64));
        }
        Ok(NavyConfig { types })
    }

    pub fn upkeep(&self, ship: &str) -> f64 {
        self.types.iter().find(|(t, _, _)| t == ship).map(|(_, u, _)| *u).unwrap_or_else(|| panic!("unknown ship type {ship}"))
    }

    pub fn min_port(&self, ship: &str) -> Option<i64> {
        self.types.iter().find(|(t, _, _)| t == ship).map(|(_, _, m)| *m)
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
        })
    }

    /// What a government type starts with.
    pub fn start_value(&self, government: &str) -> f64 {
        self.start.iter().find(|(g, _)| g == government).map(|(_, x)| *x).unwrap_or(self.start_default)
    }

    /// Multiplier on tax and recruitment at war, from the nation's support (`WarSupport._curve`).
    pub fn economy_mult_at(&self, support: f64) -> f64 {
        let [a, b, c] = self.economy_curve;
        if support <= 50.0 {
            crate::gd::lerpf(a, b, support / 50.0)
        } else {
            crate::gd::lerpf(b, c, (support - 50.0) / 50.0)
        }
    }
}


/// The parts of `data/diplomacy.json` the ported rules read besides war support.
#[derive(Debug, Clone)]
pub struct DiplomacyConfig {
    pub relation_min: f64,
    pub relation_max: f64,
    pub relation_neutral: f64,
    pub points_start: f64,
    pub points_max: f64,
    /// How many years a casus belli lasts (`war.cb_years`).
    pub cb_years: f64,
}

impl DiplomacyConfig {
    pub fn from_json_str(text: &str) -> Result<DiplomacyConfig, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("diplomacy.json is invalid: {e}"))?;
        Ok(DiplomacyConfig {
            relation_min: num(&v, &["relations", "min"])?,
            relation_max: num(&v, &["relations", "max"])?,
            relation_neutral: num(&v, &["relations", "neutral"])?,
            points_start: num(&v, &["points", "start"])?,
            points_max: num(&v, &["points", "max"])?,
            cb_years: num(&v, &["war", "cb_years"])?,
        })
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
