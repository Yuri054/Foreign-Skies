//! The whole game against the GDScript: `tests/golden/game.json` is what `tools/dump_game_golden.gd` got out of the real game
//! running by itself: a scenario as it ships, its war begun, some armies ordered forward, and then the clock driven day by day
//! through the game's own stages and month steps. `GameState::advance_day` is run the same number of days and the nations, the
//! ground, the armies, fleets, wars, opinions and tension are compared every few days. (The AI and the crises are off.)

mod common;

use common::{bits, close};
use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn s(v: &Value) -> &str {
    v.as_str().unwrap()
}

fn compare(label: &str, gs: &GameState, data: &Data, w: &Value, fails: &mut Vec<String>) {
    if gs.calendar.date_string() != s(&w["date"]) {
        fails.push(format!("{label}: date {} vs {}", gs.calendar.date_string(), w["date"]));
        return;
    }
    for (n, x) in gs.nations.iter().zip(w["nations"].as_array().unwrap()) {
        for (k, got, i) in [
            ("treasury", n.treasury, 0), ("prestige", n.prestige, 1), ("war support", n.war_support, 2), ("mobilization", n.mobilization, 3),
            ("blockade", n.blockade, 7), ("net", n.budget.net, 9), ("points", n.diplomacy_points, 10), ("munitions", n.munitions, 12),
            ("tax", n.tax_rate, 14), ("investment", n.investment, 15),
        ] {
            if !close(got, bits(&x[i])) {
                fails.push(format!("{label} {}: {k} {got:e} vs {:e}", n.tag, bits(&x[i])));
            }
        }
        let ints = (n.population, n.manpower, n.men_in_units, n.capital, n.provinces.len() as i64, n.capitulated);
        let want = (x[4].as_i64().unwrap(), x[5].as_i64().unwrap(), x[6].as_i64().unwrap(), x[8].as_i64().unwrap(), x[11].as_i64().unwrap(), x[13].as_bool().unwrap());
        if ints != want {
            fails.push(format!("{label} {}: people, manpower, men, capital, provinces, capitulated {ints:?} vs {want:?}", n.tag));
        }
    }
    let owners: Vec<&String> = gs.province_owner.iter().skip(1).collect();
    let want_owners: Vec<&str> = w["owners"].as_array().unwrap().iter().map(s).collect();
    if owners.len() != want_owners.len() || owners.iter().zip(&want_owners).any(|(a, b)| a.as_str() != *b) {
        fails.push(format!("{label}: owners differ"));
    }
    let controllers: Vec<&String> = gs.province_controller.iter().skip(1).collect();
    let want_c: Vec<&str> = w["controllers"].as_array().unwrap().iter().map(s).collect();
    if controllers.iter().zip(&want_c).any(|(a, b)| a.as_str() != *b) {
        let at = controllers.iter().zip(&want_c).position(|(a, b)| a.as_str() != *b).unwrap() + 1;
        fails.push(format!("{label}: holders differ, first at province {at}"));
    }
    let pop: i64 = gs.province_population.iter().skip(1).map(|&p| p as i64).sum();
    if pop != w["pop"].as_i64().unwrap() {
        fails.push(format!("{label}: province people {pop} vs {}", w["pop"]));
    }
    let armies: Vec<Value> = gs.armies.iter().map(|a| serde_json::json!([a.id, a.tag, a.province, a.path.len(), a.fighting])).collect();
    let want_armies: Vec<Value> = w["armies"].as_array().unwrap().iter().map(|a| serde_json::json!([a[0], a[1], a[2], a[4], a[5]])).collect();
    if armies != want_armies {
        fails.push(format!("{label}: armies differ ({} vs {})", armies.len(), want_armies.len()));
    } else {
        for (a, x) in gs.armies.iter().zip(w["armies"].as_array().unwrap()) {
            if !close(a.men(&data.military), bits(&x[3])) {
                fails.push(format!("{label}: army {} men {:e} vs {:e}", a.id, a.men(&data.military), bits(&x[3])));
            }
        }
    }
    let fleets: Vec<Value> = gs.fleets.iter().map(|f| serde_json::json!([f.id, f.zone, f.port, f.ships.len()])).collect();
    if Value::Array(fleets) != w["fleets"] {
        fails.push(format!("{label}: fleets differ"));
    }
    let wars: Vec<Value> = gs.wars.iter().map(|x| serde_json::json!([x.id, x.a, x.b, x.war_group])).collect();
    if Value::Array(wars) != w["wars"] {
        fails.push(format!("{label}: wars {:?} vs {}", gs.wars.iter().map(|x| (&x.a, &x.b)).collect::<Vec<_>>(), w["wars"]));
    }
    let hist: Vec<Value> = gs.war_history.iter().map(|x| serde_json::json!([x.id, x.end_day])).collect();
    if Value::Array(hist) != w["history"] {
        fails.push(format!("{label}: finished wars differ"));
    }
    for (what, mine, want) in [("relations", &gs.relations, &w["relations"]), ("grievance", &gs.grievance, &w["grievance"])] {
        let want = want.as_object().unwrap();
        let mut bad = 0;
        for (k, v) in want {
            if mine.get(k).map(|x| !close(*x, bits(v))).unwrap_or(true) {
                bad += 1;
                if bad <= 3 {
                    fails.push(format!("{label}: {what}[{k}] {:?} vs {:e}", mine.get(k), bits(v)));
                }
            }
        }
        if mine.iter().any(|(k, v)| *v != 0.0 && !want.contains_key(k)) {
            fails.push(format!("{label}: {what} has extra entries"));
        }
    }
    if !close(gs.tension, bits(&w["tension"])) {
        fails.push(format!("{label}: tension {:e} vs {:e}", gs.tension, bits(&w["tension"])));
    }
    let counts = (gs.pending_events.len() as i64, gs.treaties.len() as i64, gs.war_groups.len() as i64, gs.join_calls.len() as i64);
    let want = (w["pending"].as_i64().unwrap(), w["treaties"].as_i64().unwrap(), w["groups"].as_i64().unwrap(), w["calls"].as_i64().unwrap());
    if counts != want {
        fails.push(format!("{label}: pending events, treaties, groups, calls {counts:?} vs {want:?}"));
    }
}

fn run(index: usize) {
    let data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/game.json")).unwrap();
    let all: Value = serde_json::from_str(&text).unwrap();
    let run = &all[index];
    let name = s(&run["name"]);
    let mut gs = GameState::load_scenario(&data, name).unwrap();
    gs.pressure_ai = false;
    gs.ai_join_answers = run["answers"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_bool().unwrap())).collect();
    gs.start_scenario_wars(&data);
    if !s(&run["set_player"]).is_empty() {
        gs.player_tag = s(&run["set_player"]).to_string();
    }
    for w in run["extra_wars"].as_array().unwrap() {
        gs.start_war(&data, s(&w[0]), s(&w[1]), true);
    }
    assert_eq!(gs.player_tag, s(&run["player"]));
    for o in run["orders"].as_array().unwrap() {
        let ok = gs.order_army_to(&data, s(&o[0]), o[1].as_u64().unwrap() as u32, o[2].as_u64().unwrap() as usize);
        assert_eq!(ok, o[3].as_bool().unwrap(), "{name}: order {o}");
    }
    let every = run["every"].as_u64().unwrap() as usize;
    let snaps = run["snaps"].as_array().unwrap();
    let mut fails = vec![];
    compare(&format!("{name} day 0"), &gs, &data, &snaps[0], &mut fails);
    for (i, snap) in snaps.iter().enumerate().skip(1) {
        for _ in 0..every {
            gs.advance_day(&data);
        }
        compare(&format!("{name} day {}", i * every), &gs, &data, snap, &mut fails);
        if !fails.is_empty() {
            break;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));
    println!("{name}: {} days agree with the GDScript", (snaps.len() - 1) * every);
}

#[test]
fn july_1914_runs_like_the_game() {
    run(0);
}

#[test]
fn july_1914_with_more_wars_runs_like_the_game() {
    run(1);
}

#[test]
fn january_1900_runs_like_the_game() {
    run(2);
}
