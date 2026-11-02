//! War against the GDScript one: `tests/golden/war.json` is what `tools/dump_war_golden.gd` got out of the real game: wars
//! between neighbours, armies sent over the borders, and `Economy.step_day` and `Military.step_day` day after day. Each day's
//! nation figures are compared, and every fifth day the armies, the wars' tallies, the ground that changed hands, the
//! occupation under way and the battles last fought.

use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn bits(v: &Value) -> f64 {
    f64::from_bits(v.as_str().unwrap().parse::<i64>().unwrap() as u64)
}

/// The port matches the game bit for bit here; a hair of margin keeps another machine's maths library from tripping it.
fn close(a: f64, b: f64) -> bool {
    a == b || (a - b).abs() <= 1e-13 * a.abs().max(b.abs())
}

fn data() -> Data {
    Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap()
}

fn golden() -> Value {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/war.json")).unwrap();
    serde_json::from_str(&text).unwrap()
}

fn compare_day(label: &str, gs: &GameState, rows: &Value, fails: &mut Vec<String>) {
    for (i, r) in rows.as_array().unwrap().iter().enumerate() {
        let n = &gs.nations[i];
        let ints = [("men_in_units", n.men_in_units, &r[0]), ("manpower", n.manpower, &r[1])];
        for (k, got, want) in ints {
            if got != want.as_i64().unwrap() {
                fails.push(format!("{label} {}: {k} {got} vs {want}", n.tag));
            }
        }
        let floats = [("deaths_month", n.deaths_month, &r[2]), ("men_lost_month", n.men_lost_month, &r[3]), ("war_support", n.war_support, &r[4]), ("prestige", n.prestige, &r[5]), ("munitions", n.munitions, &r[6])];
        for (k, got, want) in floats {
            if !close(got, bits(want)) {
                fails.push(format!("{label} {}: {k} {got:e} vs {:e}", n.tag, bits(want)));
            }
        }
    }
}

/// What each side could supply, province by province (the reach of the cities and the railways included).
fn compare_supply(label: &str, data: &Data, gs: &GameState, cases: &Value, fails: &mut Vec<String>) {
    for c in cases.as_array().unwrap() {
        let (tag, id) = (c[0].as_str().unwrap(), c[1].as_u64().unwrap() as usize);
        let cost = gs.supply_cost(data, tag, id);
        let want = if c[2].as_str().unwrap() == "inf" { f64::INFINITY } else { bits(&c[2]) };
        if !(cost == want || (cost.is_finite() && want.is_finite() && close(cost, want))) {
            fails.push(format!("{label}: supply of {tag} at {id}: {cost} vs {want}"));
        }
        let aura = gs.city_aura(data, tag, id);
        if !close(aura, bits(&c[3])) {
            fails.push(format!("{label}: city aura of {tag} at {id}: {aura} vs {}", bits(&c[3])));
        }
    }
}

fn compare_checkpoint(label: &str, gs: &GameState, cp: &Value, initial: &[String], fails: &mut Vec<String>) {
    // the armies, in the order the game keeps them
    let want = cp["armies"].as_array().unwrap();
    if gs.armies.len() != want.len() {
        fails.push(format!("{label}: {} armies vs {}", gs.armies.len(), want.len()));
    }
    for (a, w) in gs.armies.iter().zip(want) {
        let path: Vec<usize> = w[3].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect();
        let head = (a.id as i64, a.tag.as_str(), a.province as i64, &a.path, a.still_days, a.attacking, a.fighting, a.supplied, a.landing_days as i64, a.landed_supply);
        let want_head = (w[0].as_i64().unwrap(), w[1].as_str().unwrap(), w[2].as_i64().unwrap(), &path, w[5].as_i64().unwrap(), w[6].as_bool().unwrap(), w[7].as_bool().unwrap(), w[8].as_bool().unwrap(), w[9].as_i64().unwrap(), w[10].as_i64().unwrap());
        if head != want_head || !close(a.move_days_left, bits(&w[4])) {
            fails.push(format!("{label}: army {} ({}) {head:?} move {} vs {want_head:?} move {}", a.id, a.tag, a.move_days_left, bits(&w[4])));
            continue;
        }
        let units = w[11].as_array().unwrap();
        if a.units.len() != units.len() {
            fails.push(format!("{label}: army {} has {} units vs {}", a.id, a.units.len(), units.len()));
            continue;
        }
        for (u, x) in a.units.iter().zip(units) {
            if u.unit_type != x[0].as_str().unwrap() || !close(u.strength, bits(&x[1])) || !close(u.morale, bits(&x[2])) || !close(u.experience, bits(&x[3])) {
                fails.push(format!("{label}: army {} unit {} strength {} morale {} vs {} {} {}", a.id, u.unit_type, u.strength, u.morale, bits(&x[1]), bits(&x[2]), bits(&x[3])));
            }
        }
    }
    // the wars' books
    let wars = cp["wars"].as_array().unwrap();
    if gs.wars.len() != wars.len() {
        fails.push(format!("{label}: {} wars vs {}", gs.wars.len(), wars.len()));
    }
    for (w, x) in gs.wars.iter().zip(wars) {
        if w.a != x["a"].as_str().unwrap() || w.b != x["b"].as_str().unwrap() || w.last_fight_day != x["last_fight_day"].as_i64().unwrap() {
            fails.push(format!("{label}: war {} {} last fight {} vs {}", w.a, w.b, w.last_fight_day, x["last_fight_day"]));
        }
        for (name, map) in [("losses", &w.losses), ("attrition", &w.attrition), ("surrendered", &w.surrendered), ("battle_points", &w.battle_points)] {
            for (t, v) in x[name].as_object().unwrap() {
                if !close(map[t], bits(v)) {
                    fails.push(format!("{label}: war {} {} {name}[{t}] {} vs {}", w.a, w.b, map[t], bits(v)));
                }
            }
        }
        for (t, v) in x["captured"].as_object().unwrap() {
            if w.captured[t] != (v[0].as_i64().unwrap(), v[1].as_i64().unwrap()) {
                fails.push(format!("{label}: war {} {} captured[{t}] {:?} vs {v}", w.a, w.b, w.captured[t]));
            }
        }
    }
    // ground that changed hands
    let changed: Vec<(usize, String)> = (1..gs.province_controller.len()).filter(|&i| gs.province_controller[i] != initial[i]).map(|i| (i, gs.province_controller[i].clone())).collect();
    let want_changed: Vec<(usize, String)> = cp["changed"].as_array().unwrap().iter().map(|c| (c[0].as_u64().unwrap() as usize, c[1].as_str().unwrap().to_string())).collect();
    if changed != want_changed {
        fails.push(format!("{label}: ground held {changed:?} vs {want_changed:?}"));
    }
    // occupation under way, and the day each battle last ended
    let mut occ: Vec<(usize, String, i64)> = gs.occupation.iter().map(|(k, (t, d))| (*k, t.clone(), *d)).collect();
    occ.sort();
    let want_occ: Vec<(usize, String, i64)> = cp["occupation"].as_array().unwrap().iter().map(|o| (o[0].as_u64().unwrap() as usize, o[1].as_str().unwrap().to_string(), o[2].as_i64().unwrap())).collect();
    if occ != want_occ {
        fails.push(format!("{label}: occupation {occ:?} vs {want_occ:?}"));
    }
    let mut lb: Vec<(usize, i64)> = gs.last_battle_day.iter().map(|(k, v)| (*k, *v)).collect();
    lb.sort();
    let want_lb: Vec<(usize, i64)> = cp["last_battle"].as_array().unwrap().iter().map(|o| (o[0].as_u64().unwrap() as usize, o[1].as_i64().unwrap())).collect();
    if lb != want_lb {
        fails.push(format!("{label}: last battles {lb:?} vs {want_lb:?}"));
    }
    if gs.engagements.len() as i64 != cp["engagements"].as_i64().unwrap() {
        fails.push(format!("{label}: {} battles under way vs {}", gs.engagements.len(), cp["engagements"]));
    }
}

fn run(name: &str) {
    let (data, g) = (data(), golden());
    let w = &g[name];
    let mut gs = GameState::load_scenario(&data, name_scenario()).unwrap();
    for p in w["wars"].as_array().unwrap() {
        gs.set_war(p[0].as_str().unwrap(), p[1].as_str().unwrap());
    }
    for wk in w["works"].as_array().unwrap() {
        let (id, kind, level) = (wk[0].as_u64().unwrap() as usize, wk[1].as_str().unwrap(), wk[2].as_i64().unwrap() as i32);
        match gs.province_buildings[id].iter_mut().find(|(k, _)| k == kind) {
            Some(slot) => slot.1 = level,
            None => gs.province_buildings[id].push((kind.to_string(), level)),
        }
    }
    gs.recompute(&data);
    for o in w["orders"].as_array().unwrap() {
        let ok = gs.order_army_to(&data, o[0].as_str().unwrap(), o[1].as_u64().unwrap() as u32, o[2].as_u64().unwrap() as usize);
        assert_eq!(ok, o[3].as_bool().unwrap(), "order {o}");
    }
    let initial = gs.province_controller.clone();
    let checkpoints = w["checkpoints"].as_array().unwrap();
    let days = w["days"].as_array().unwrap();
    let mut fails = vec![];
    let mut cp = 0;
    for (d, rows) in days.iter().enumerate() {
        gs.step_day(&data);
        gs.military_step_day(&data);
        gs.calendar.advance_day();
        gs.finish_economy_stage(&data);
        compare_day(&format!("{name} day {}", d + 1), &gs, rows, &mut fails);
        if (d + 1) % 5 == 0 {
            compare_checkpoint(&format!("{name} day {}", d + 1), &gs, &checkpoints[cp], &initial, &mut fails);
            compare_supply(&format!("{name} day {}", d + 1), &data, &gs, &checkpoints[cp]["supply"], &mut fails);
            cp += 1;
        }
        if !fails.is_empty() {
            break;
        }
        if (d + 1) % 30 == 0 {
            gs.step_month(&data);
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(15).cloned().collect::<Vec<_>>().join("\n"));
    let last = checkpoints.last().unwrap();
    println!("{name}: {} days of war agree with the GDScript ({} provinces changed hands, {} armies at the end)", days.len(), last["changed"].as_array().unwrap().len(), last["armies"].as_array().unwrap().len());
}

fn name_scenario() -> &'static str {
    "july_1914"
}

#[test]
fn the_western_war() {
    run("west");
}

#[test]
fn the_eastern_war() {
    run("east");
}

#[test]
fn the_southern_wars() {
    run("south");
}
