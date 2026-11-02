//! The static map (`scripts/map/map_data.gd`, the part the simulation reads): the provinces with their starting
//! owner, area and coast, and the nations in file order. Neighbours, sea zones and the bitmaps are not loaded yet.

use crate::tsv::Table;
use serde_json::Value;
use std::path::Path;

/// Ground area of one bitmap pixel (`MapData.KM2_PER_PX`).
pub const KM2_PER_PX: f64 = 0.48;

#[derive(Debug, Clone)]
pub struct Province {
    pub id: usize,
    pub name: String,
    /// The owner the map file starts the province with (the live owner is in the game state).
    pub owner: String,
    /// Area in bitmap pixels.
    pub area: i64,
    pub coastal: bool,
}

impl Province {
    pub fn area_km2(&self) -> f64 {
        self.area as f64 * KM2_PER_PX
    }
}

#[derive(Debug, Clone)]
pub struct NationInfo {
    pub tag: String,
    pub name: String,
}

#[derive(Debug, Clone)]
pub struct MapData {
    /// Indexed by province id; element 0 is an unused placeholder, as in the game.
    pub provinces: Vec<Province>,
    /// In the order of `data/nations.json`, which is the order the game goes through its nations.
    pub nations: Vec<NationInfo>,
}

impl MapData {
    pub fn load(data_dir: &Path) -> Result<MapData, String> {
        let mut provinces = vec![Province { id: 0, name: String::new(), owner: String::new(), area: 0, coastal: false }];
        for row in Table::read(&data_dir.join("map/provinces.tsv"))?.rows() {
            let id = row.int("id") as usize;
            while provinces.len() <= id {
                provinces.push(Province { id: provinces.len(), name: String::new(), owner: String::new(), area: 0, coastal: false });
            }
            provinces[id] = Province {
                id,
                name: row.get("name").to_string(),
                owner: row.get("owner").to_string(),
                area: row.int("area"),
                coastal: false,
            };
        }
        for row in Table::read(&data_dir.join("map/coastal.tsv"))?.rows() {
            provinces[row.int("id") as usize].coastal = true;
        }
        let text = std::fs::read_to_string(data_dir.join("nations.json")).map_err(|e| e.to_string())?;
        let v: Value = serde_json::from_str(&text).map_err(|e| format!("nations.json is invalid: {e}"))?;
        let nations = v
            .as_object()
            .ok_or("nations.json is not an object")?
            .iter()
            .map(|(tag, d)| NationInfo { tag: tag.clone(), name: d["name"].as_str().unwrap_or("").to_string() })
            .collect();
        Ok(MapData { provinces, nations })
    }
}
