//! The Rust game state against the GDScript one: `tests/golden/state.json` is what `tools/dump_state_golden.gd` read out
//! of the real game right after it loaded each scenario.

use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn bits(v: &Value) -> f64 {
    f64::from_bits(v.as_str().unwrap().parse::<i64>().unwrap() as u64)
}

fn close(a: f64, b: f64, rel: f64) -> bool {
    a == b || (a - b).abs() <= rel * a.abs().max(b.abs())
}

fn data() -> Data {
    Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap()
}

fn golden() -> Value {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/state.json")).unwrap();
    serde_json::from_str(&text).unwrap()
}

fn check_scenario(name: &str) {
    let (data, g) = (data(), golden());
    let want = &g[name];
    let gs = GameState::load_scenario(&data, name).unwrap();
    let mut fails: Vec<String> = vec![];

    // The provinces: who owns and holds them, their people, works and deposits, and what each makes (32-bit floats).
    let provinces = want["provinces"].as_array().unwrap();
    assert_eq!(provinces.len(), gs.province_owner.len() - 1, "province count");
    for p in provinces {
        let id = p["id"].as_u64().unwrap() as usize;
        if gs.province_owner[id] != p["owner"].as_str().unwrap() {
            fails.push(format!("province {id}: owner {} vs {}", gs.province_owner[id], p["owner"]));
        }
        if gs.province_controller[id] != p["controller"].as_str().unwrap() {
            fails.push(format!("province {id}: controller"));
        }
        if gs.province_population[id] as i64 != p["population"].as_i64().unwrap() {
            fails.push(format!("province {id}: population {} vs {}", gs.province_population[id], p["population"]));
        }
        let b: Vec<(String, i32)> =
            p["buildings"].as_array().unwrap().iter().map(|x| (x[0].as_str().unwrap().to_string(), x[1].as_i64().unwrap() as i32)).collect();
        if gs.province_buildings[id] != b {
            fails.push(format!("province {id}: buildings {:?} vs {:?}", gs.province_buildings[id], b));
        }
        let d: Vec<(String, f64)> = p["deposit"].as_array().unwrap().iter().map(|x| (x[0].as_str().unwrap().to_string(), bits(&x[1]))).collect();
        if gs.province_deposit[id] != d {
            fails.push(format!("province {id}: deposits {:?} vs {:?}", gs.province_deposit[id], d));
        }
        for (k, got) in [("gdp", gs.province_gdp[id]), ("industry", gs.province_industry[id]), ("food", gs.province_food[id]), ("pool", gs.province_pool[id])] {
            let w = bits(&p[k]) as f32;
            // 32-bit values: the same number, or one step apart where a double rounded either way.
            if got != w && (got.to_bits() as i64 - w.to_bits() as i64).abs() > 1 {
                fails.push(format!("province {id}: {k} {got} vs {w}"));
            }
        }
    }

    // The nations, in the game's order.
    let nations = want["nations"].as_array().unwrap();
    assert_eq!(nations.len(), gs.nations.len());
    for (i, w) in nations.iter().enumerate() {
        let n = &gs.nations[i];
        let tag = w["tag"].as_str().unwrap();
        assert_eq!(n.tag, tag, "nation order");
        for (k, got, want) in [
            ("development", n.development, bits(&w["development"])),
            ("agri_yield", n.agri_yield, bits(&w["agri_yield"])),
            ("tax_rate", n.tax_rate, bits(&w["tax_rate"])),
            ("pop_growth", n.pop_growth, bits(&w["pop_growth"])),
            ("treasury", n.treasury, bits(&w["treasury"])),
            ("materials_need_mult", n.materials_need_mult, bits(&w["materials_need_mult"])),
        ] {
            // Development came through pow() and a division: allow rounding in the last places.
            if !close(got, want, 1e-13) {
                fails.push(format!("{tag}: {k} {got:e} vs {want:e}"));
            }
        }
        // The scenario's naval budget is raised by Navy.refresh_upkeep to what the fleets cost to keep (the fleets are not
        // ported yet), so all that holds for now is that the game's figure is never below the scenario's.
        if n.naval_budget > bits(&w["naval_budget"]) * (1.0 + 1e-12) {
            fails.push(format!("{tag}: naval_budget {} is above the game's {}", n.naval_budget, bits(&w["naval_budget"])));
        }
        if n.capital != w["capital"].as_i64().unwrap() || n.peacetime_army != w["peacetime_army"].as_i64().unwrap() {
            fails.push(format!("{tag}: capital or peacetime_army"));
        }
        if n.population != w["population"].as_i64().unwrap() {
            fails.push(format!("{tag}: population {} vs {}", n.population, w["population"]));
        }
        let ids: Vec<usize> = w["provinces"].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect();
        if n.provinces != ids {
            fails.push(format!("{tag}: province list"));
        }
        let s = &gs.economy_sums[i];
        for (k, got) in [("coast", s.coast), ("gdp", s.gdp), ("industry", s.industry), ("food", s.food), ("trade", s.trade), ("pool", s.pool), ("materials", s.materials)] {
            let want = bits(&w["sums"][k]);
            if !close(got, want, 1e-12) {
                fails.push(format!("{tag}: sums.{k} {got:e} vs {want:e}"));
            }
        }
    }
    if !close(gs.materials_k, bits(&want["materials_k"]), 1e-12) {
        fails.push(format!("materials_k {} vs {}", gs.materials_k, bits(&want["materials_k"])));
    }
    if !fails.is_empty() {
        panic!("{name}: {} differences, e.g.\n{}", fails.len(), fails.iter().take(15).cloned().collect::<Vec<_>>().join("\n"));
    }
    println!(
        "{name}: {} provinces, {} nations, materials_k {:.6} agree with the GDScript",
        provinces.len(),
        nations.len(),
        gs.materials_k
    );
}

#[test]
fn july_1914_loads_like_the_game() {
    check_scenario("july_1914");
}

#[test]
fn jan_1900_loads_like_the_game() {
    check_scenario("jan_1900");
}

#[test]
fn occupied_provinces_move_their_output_to_the_holder() {
    let (data, g) = (data(), golden());
    let want = &g["july_1914_occupied"];
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    for c in want["changes"].as_array().unwrap() {
        gs.set_controller(c[0].as_u64().unwrap() as usize, c[1].as_str().unwrap());
    }
    gs.recompute(&data);
    let mut fails = vec![];
    for (i, w) in want["nations"].as_array().unwrap().iter().enumerate() {
        let s = &gs.economy_sums[i];
        let tag = w["tag"].as_str().unwrap();
        assert_eq!(gs.nations[i].tag, tag);
        for (k, got) in [("coast", s.coast), ("gdp", s.gdp), ("industry", s.industry), ("food", s.food), ("trade", s.trade), ("pool", s.pool), ("materials", s.materials)] {
            if !close(got, bits(&w["sums"][k]), 1e-12) {
                fails.push(format!("{tag}: sums.{k} {got:e} vs {:e}", bits(&w["sums"][k])));
            }
        }
    }
    assert!(close(gs.materials_k, bits(&want["materials_k"]), 1e-12));
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(10).cloned().collect::<Vec<_>>().join("\n"));
    println!("july_1914 with {} provinces held by an enemy: nation sums agree", want["changes"].as_array().unwrap().len());
}
