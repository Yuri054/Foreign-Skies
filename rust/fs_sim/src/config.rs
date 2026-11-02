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
            resource_ids,
            buildings,
        })
    }

    pub fn building(&self, id: &str) -> Option<&BuildingDef> {
        self.buildings.iter().find(|b| b.id == id)
    }
}
