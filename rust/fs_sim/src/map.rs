//! The static map (`scripts/map/map_data.gd`, the part the simulation reads): the provinces with their starting
//! owner, area and coast, and the nations in file order. Neighbours, sea zones and the bitmaps are not loaded yet.

use crate::tsv::Table;
use serde_json::Value;
use std::collections::HashMap;
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
    /// The province's centre on the map, in 32-bit floats as the game keeps it (`Vector2`).
    pub center: (f32, f32),
    pub terrain: String,
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
    /// Provinces next to each province, by id, in the order the borders are listed (land borders and sea crossings).
    pub adjacency: Vec<Vec<usize>>,
    /// The kind of each crossing that is not a land border, by (lower id, higher id): "strait" or "sea".
    pub sea_links: HashMap<(usize, usize), String>,
    /// The sea zones each port province opens on (`MapData.zones_of_port`): the first, and a second (0 if none).
    pub port_zones: HashMap<usize, (usize, usize)>,
    /// The sea zones each sea zone touches, in the order the file lists them.
    pub sea_adjacency: HashMap<usize, Vec<usize>>,
    /// The port provinces on each sea zone, in the order `ports.tsv` lists them.
    pub ports_of_zone: HashMap<usize, Vec<usize>>,
}

impl MapData {
    /// `MapData.zones_of_port`: the zones a coastal province opens on (empty if it has no port).
    pub fn zones_of_port(&self, province: usize) -> Vec<usize> {
        match self.port_zones.get(&province) {
            Some(&(z1, z2)) => [z1, z2].into_iter().filter(|&z| z > 0).collect(),
            None => vec![],
        }
    }

    /// `Military.neighbors`: land provinces (and strait crossings) one step away; open-sea links need a navy.
    pub fn neighbors(&self, id: usize) -> impl Iterator<Item = usize> + '_ {
        self.adjacency[id].iter().copied().filter(move |&n| self.sea_links.get(&(id.min(n), id.max(n))).map(String::as_str) != Some("sea"))
    }

    pub fn load(data_dir: &Path) -> Result<MapData, String> {
        let mut provinces = vec![Province { id: 0, name: String::new(), owner: String::new(), area: 0, coastal: false, center: (0.0, 0.0), terrain: "plains".to_string() }];
        for row in Table::read(&data_dir.join("map/provinces.tsv"))?.rows() {
            let id = row.int("id") as usize;
            while provinces.len() <= id {
                provinces.push(Province { id: provinces.len(), name: String::new(), owner: String::new(), area: 0, coastal: false, center: (0.0, 0.0), terrain: "plains".to_string() });
            }
            provinces[id] = Province {
                id,
                name: row.get("name").to_string(),
                owner: row.get("owner").to_string(),
                area: row.int("area"),
                coastal: false,
                center: (row.int("cx") as f32, row.int("cy") as f32),
                terrain: "plains".to_string(),
            };
        }
        for row in Table::read(&data_dir.join("map/coastal.tsv"))?.rows() {
            provinces[row.int("id") as usize].coastal = true;
        }
        for row in Table::read(&data_dir.join("map/terrain.tsv"))?.rows() {
            provinces[row.int("id") as usize].terrain = row.get("terrain").to_string();
        }
        let text = std::fs::read_to_string(data_dir.join("nations.json")).map_err(|e| e.to_string())?;
        let v: Value = serde_json::from_str(&text).map_err(|e| format!("nations.json is invalid: {e}"))?;
        let nations = v
            .as_object()
            .ok_or("nations.json is not an object")?
            .iter()
            .map(|(tag, d)| NationInfo { tag: tag.clone(), name: d["name"].as_str().unwrap_or("").to_string() })
            .collect();
        let mut adjacency: Vec<Vec<usize>> = vec![vec![]; provinces.len()];
        let mut sea_links = HashMap::new();
        for row in Table::read(&data_dir.join("map/adjacencies.tsv"))?.rows() {
            let (a, b) = (row.int("id_a") as usize, row.int("id_b") as usize);
            for (x, y) in [(a, b), (b, a)] {
                if !adjacency[x].contains(&y) {
                    adjacency[x].push(y);
                }
            }
            if row.get("kind") != "land" {
                sea_links.insert((a.min(b), a.max(b)), row.get("kind").to_string());
            }
        }
        let mut port_zones = HashMap::new();
        let mut ports_of_zone: HashMap<usize, Vec<usize>> = HashMap::new();
        for row in Table::read(&data_dir.join("map/ports.tsv"))?.rows() {
            let id = row.int("id") as usize;
            port_zones.insert(id, (row.int("zone") as usize, row.int("zone2") as usize));
            for z in [row.int("zone") as usize, row.int("zone2") as usize] {
                if z > 0 {
                    ports_of_zone.entry(z).or_default().push(id);
                }
            }
        }
        let mut sea_adjacency: HashMap<usize, Vec<usize>> = HashMap::new();
        for row in Table::read(&data_dir.join("map/sea_adjacency.tsv"))?.rows() {
            let (a, b) = (row.int("id_a") as usize, row.int("id_b") as usize);
            sea_adjacency.entry(a).or_default().push(b);
            sea_adjacency.entry(b).or_default().push(a);
        }
        Ok(MapData { provinces, nations, adjacency, sea_links, port_zones, sea_adjacency, ports_of_zone })
    }
}
