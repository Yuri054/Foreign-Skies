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

/// The nation's own figures (civil spending, wages, men, stockpile) and its whole budget, against the game's.
fn compare_state_and_budget(tag: &str, n: &fs_sim::state::Nation, w: &Value, fails: &mut Vec<String>) {
    let st = &w["state"];
    for (k, got) in [
        ("civil_mult", n.civil_mult),
        ("civil_base", n.civil_base),
        ("civil_index", n.civil_index),
        ("wage", n.wage),
        ("naval_budget", n.naval_budget),
        ("naval_overhead", n.naval_overhead),
        ("munitions", n.munitions),
        ("arms_share", n.arms_share),
        ("war_support", n.war_support),
        ("mobilization", n.mobilization),
        ("blockade", n.blockade),
        ("treasury", n.treasury),
    ] {
        if !close(got, bits(&st[k]), 1e-12) {
            fails.push(format!("{tag}: state.{k} {got:e} vs {:e}", bits(&st[k])));
        }
    }
    for (k, got) in [
        ("manpower", n.manpower),
        ("men_in_units", n.men_in_units),
        ("men_exercising", n.men_exercising),
        ("peacetime_army", n.peacetime_army),
    ] {
        if got != st[k].as_i64().unwrap() {
            fails.push(format!("{tag}: state.{k} {got} vs {}", st[k]));
        }
    }
    let b = &n.budget;
    let m = &b.materials;
    let wb = &w["budget"];
    for (k, got) in [
        ("gdp", b.gdp), ("industry", b.industry), ("revenue", b.revenue), ("trade", b.trade),
        ("gdp_scale", b.gdp_scale), ("trade_scale", b.trade_scale), ("industry_scale", b.industry_scale),
        ("food_scale", b.food_scale), ("output_scale", b.output_scale), ("revenue_per_gdp", b.revenue_per_gdp),
        ("civil", b.civil), ("army", b.army), ("naval", b.naval), ("food_imports", b.food_imports),
        ("materials_cost", b.materials_cost), ("interest", b.interest), ("munitions_storage", b.munitions_storage),
        ("investment", b.investment), ("tax_relief", b.tax_relief), ("arms_mult", b.arms_mult),
        ("tax_strain", b.tax_strain), ("expenses", b.expenses), ("net", b.net), ("food_production", b.food_production),
        ("food_need", b.food_need), ("food_imported", b.food_imported), ("food_shortage", b.food_shortage),
        ("construction_points", b.construction_points), ("manpower_pool", b.manpower_pool), ("manpower_max", b.manpower_max),
    ] {
        if !close(got, bits(&wb[k]), 1e-12) {
            fails.push(format!("{tag}: budget.{k} {got:e} vs {:e}", bits(&wb[k])));
        }
    }
    for (k, got) in [
        ("own", m.own), ("need", m.need), ("imported", m.imported), ("exported", m.exported),
        ("ratio", m.ratio), ("cost", m.cost), ("income", m.income),
    ] {
        if !close(got, bits(&wb["materials"][k]), 1e-12) {
            fails.push(format!("{tag}: budget.materials.{k} {got:e} vs {:e}", bits(&wb["materials"][k])));
        }
    }
    // every key the game puts in the budget is one the port compares
    assert_eq!(wb.as_object().unwrap().len(), 31, "the game's budget has keys the port does not know");
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
        compare_state_and_budget(tag, n, w, &mut fails);
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
        compare_state_and_budget(tag, &gs.nations[i], w, &mut fails);
    }
    assert!(close(gs.materials_k, bits(&want["materials_k"]), 1e-12));
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(10).cloned().collect::<Vec<_>>().join("\n"));
    println!("july_1914 with {} provinces held by an enemy: nation sums agree", want["changes"].as_array().unwrap().len());
}

#[test]
fn a_strained_economy_works_out_like_the_game() {
    let (data, g) = (data(), golden());
    let want = &g["july_1914_stressed"];
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    for e in want["spec"].as_array().unwrap() {
        let tag = e["tag"].as_str().unwrap();
        let i = gs.nation_index[tag];
        let n = &mut gs.nations[i];
        for (k, v) in e.as_object().unwrap() {
            match k.as_str() {
                "tag" => {}
                "mobilization" => n.mobilization = bits(v),
                "tax_rate" => n.tax_rate = bits(v),
                "arms_share" => n.arms_share = bits(v),
                "investment" => n.investment = bits(v),
                "treasury" => n.treasury = bits(v),
                "blockade" => n.blockade = bits(v),
                "weariness" => n.weariness = bits(v),
                "war_support" => n.war_support = bits(v),
                "munitions" => n.munitions = bits(v),
                "materials_need_mult" => n.materials_need_mult = bits(v),
                "starving" => n.starving = v.as_bool().unwrap(),
                "men_exercising" => n.men_exercising = v.as_i64().unwrap(),
                "manpower" => n.manpower = v.as_i64().unwrap(),
                "focus_fx" => {
                    n.focus_fx = effects(v);
                    n.focus_construction = v.get("construction").map(bits).unwrap_or(0.0);
                }
                other => panic!("the golden spec sets {other}, which the test does not know"),
            }
        }
    }
    for w in want["wars"].as_array().unwrap() {
        gs.wars.push((w[0].as_str().unwrap().to_string(), w[1].as_str().unwrap().to_string()));
    }
    gs.recompute(&data);
    let mut fails = vec![];
    for (i, w) in want["nations"].as_array().unwrap().iter().enumerate() {
        let tag = w["tag"].as_str().unwrap();
        assert_eq!(gs.nations[i].tag, tag);
        let s = &gs.economy_sums[i];
        for (k, got) in [("coast", s.coast), ("gdp", s.gdp), ("industry", s.industry), ("food", s.food), ("trade", s.trade), ("pool", s.pool), ("materials", s.materials)] {
            if !close(got, bits(&w["sums"][k]), 1e-12) {
                fails.push(format!("{tag}: sums.{k} {got:e} vs {:e}", bits(&w["sums"][k])));
            }
        }
        compare_state_and_budget(tag, &gs.nations[i], w, &mut fails);
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));
    println!("july_1914 under strain (mobilization, debt, blockade, famine, investment, two wars): {} nations agree", want["nations"].as_array().unwrap().len());
}

fn effects(v: &Value) -> fs_sim::config::Effects {
    let get = |k: &str| v.get(k).map(bits).unwrap_or(0.0);
    fs_sim::config::Effects { gdp: get("gdp"), industry: get("industry"), food: get("food"), trade: get("trade"), growth: get("growth") }
}
