//! The Rust game state against the GDScript one: `tests/golden/state.json` is what `tools/dump_state_golden.gd` read out
//! of the real game right after it loaded each scenario, with enemy-held ground, and under strain. Every number must be
//! the same, bit for bit.

use fs_sim::state::{Data, GameState, Sums};
use serde_json::Value;
use std::path::Path;

fn bits(v: &Value) -> f64 {
    f64::from_bits(v.as_str().unwrap().parse::<i64>().unwrap() as u64)
}

fn data() -> Data {
    Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap()
}

fn golden() -> Value {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/state.json")).unwrap();
    serde_json::from_str(&text).unwrap()
}

/// The levels of each building (a dictionary of floats in the game). The golden's keys are sorted (Godot's
/// `JSON.stringify` sorts them), so both sides are compared sorted.
fn levels(v: &Value) -> Vec<(String, f64)> {
    v.as_object().map(|o| o.iter().map(|(k, x)| (k.clone(), bits(x))).collect()).unwrap_or_default()
}

fn sorted(l: &[(String, f64)]) -> Vec<(String, f64)> {
    let mut l = l.to_vec();
    l.sort_by(|a, b| a.0.cmp(&b.0));
    l
}

/// A nation's summed provinces against the game's.
fn compare_sums(tag: &str, s: &Sums, w: &Value, fails: &mut Vec<String>) {
    for (k, got) in [
        ("base", s.base), ("occupied", s.occupied), ("factories", s.factories), ("ports", s.ports),
        ("upkeep", s.upkeep), ("cp", s.cp), ("pool", s.pool),
    ] {
        if got != bits(&w[k]) {
            fails.push(format!("{tag}: sums.{k} {got:e} vs {:e}", bits(&w[k])));
        }
    }
    if sorted(&s.levels) != levels(&w["levels"]) {
        fails.push(format!("{tag}: sums.levels {:?} vs {:?}", s.levels, levels(&w["levels"])));
    }
}

/// The nation's own figures (men, money, points) and its whole budget, against the game's.
fn compare_state_and_budget(tag: &str, n: &fs_sim::state::Nation, levels_now: &[(String, f64)], w: &Value, fails: &mut Vec<String>) {
    let st = &w["state"];
    for (k, got) in [
        ("naval_budget", n.naval_budget),
        ("naval_overhead", n.naval_overhead),
        ("war_support", n.war_support),
        ("mobilization", n.mobilization),
        ("blockade", n.blockade),
        ("treasury", n.treasury),
        ("cp", n.cp),
    ] {
        if got != bits(&st[k]) {
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
    let wb = &w["budget"];
    for (k, got) in [
        ("base", b.base), ("factories", b.factories), ("ports", b.ports), ("occupied", b.occupied), ("income", b.income),
        ("administration", b.administration), ("army", b.army), ("navy", b.navy), ("buildings", b.buildings),
        ("interest", b.interest), ("expenses", b.expenses), ("net", b.net), ("cp", b.cp),
        ("manpower_pool", b.manpower_pool), ("manpower_max", b.manpower_max),
    ] {
        if got != bits(&wb[k]) {
            fails.push(format!("{tag}: budget.{k} {got:e} vs {:e}", bits(&wb[k])));
        }
    }
    if sorted(levels_now) != levels(&wb["levels"]) {
        fails.push(format!("{tag}: budget.levels"));
    }
    // every key the game puts in the budget is one the port compares
    assert_eq!(wb.as_object().unwrap().len(), 16, "the game's budget has keys the port does not know");
}

fn finish(what: &str, fails: Vec<String>) {
    if !fails.is_empty() {
        panic!("{what}: {} differences, e.g.\n{}", fails.len(), fails.iter().take(15).cloned().collect::<Vec<_>>().join("\n"));
    }
}

fn check_scenario(name: &str) {
    let (data, g) = (data(), golden());
    let want = &g[name];
    let gs = GameState::load_scenario(&data, name).unwrap();
    let mut fails: Vec<String> = vec![];

    // The provinces: who owns and holds them, their people, buildings and base income (a 32-bit float).
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
        if gs.province_base_income[id] as f64 != bits(&p["base_income"]) {
            fails.push(format!("province {id}: base income {} vs {}", gs.province_base_income[id], bits(&p["base_income"])));
        }
    }

    // The nations, in the game's order.
    let nations = want["nations"].as_array().unwrap();
    assert_eq!(nations.len(), gs.nations.len());
    for (i, w) in nations.iter().enumerate() {
        let n = &gs.nations[i];
        let tag = w["tag"].as_str().unwrap();
        assert_eq!(n.tag, tag, "nation order");
        if n.treasury != bits(&w["treasury"]) {
            fails.push(format!("{tag}: treasury"));
        }
        compare_state_and_budget(tag, n, &gs.economy_sums[i].levels, w, &mut fails);
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
        compare_sums(tag, &gs.economy_sums[i], &w["sums"], &mut fails);
    }
    finish(name, fails);
    println!("{name}: {} provinces and {} nations agree with the GDScript", provinces.len(), nations.len());
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
fn occupied_provinces_move_their_income_to_the_holder() {
    let (data, g) = (data(), golden());
    let want = &g["july_1914_occupied"];
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    for c in want["changes"].as_array().unwrap() {
        gs.set_controller(c[0].as_u64().unwrap() as usize, c[1].as_str().unwrap());
    }
    gs.recompute(&data);
    let mut fails = vec![];
    for (i, w) in want["nations"].as_array().unwrap().iter().enumerate() {
        let tag = w["tag"].as_str().unwrap();
        assert_eq!(gs.nations[i].tag, tag);
        compare_sums(tag, &gs.economy_sums[i], &w["sums"], &mut fails);
        compare_state_and_budget(tag, &gs.nations[i], &gs.economy_sums[i].levels, w, &mut fails);
    }
    finish("july_1914 occupied", fails);
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
                "treasury" => n.treasury = bits(v),
                "blockade" => n.blockade = bits(v),
                "war_support" => n.war_support = bits(v),
                "manpower" => n.manpower = v.as_i64().unwrap(),
                "focus_fx" => {
                    n.focus_income = v.get("income").map(bits).unwrap_or(0.0);
                    n.focus_cp = v.get("cp").map(bits).unwrap_or(0.0);
                }
                other => panic!("the golden spec sets {other}, which the test does not know"),
            }
        }
    }
    for w in want["wars"].as_array().unwrap() {
        gs.set_war(w[0].as_str().unwrap(), w[1].as_str().unwrap());
    }
    gs.recompute(&data);
    let mut fails = vec![];
    for (i, w) in want["nations"].as_array().unwrap().iter().enumerate() {
        let tag = w["tag"].as_str().unwrap();
        assert_eq!(gs.nations[i].tag, tag);
        compare_sums(tag, &gs.economy_sums[i], &w["sums"], &mut fails);
        compare_state_and_budget(tag, &gs.nations[i], &gs.economy_sums[i].levels, w, &mut fails);
    }
    finish("july_1914 under strain", fails);
}
