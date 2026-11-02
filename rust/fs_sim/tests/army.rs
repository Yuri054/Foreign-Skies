//! Raising, training and handling armies against the GDScript: `tests/golden/army.json` is what `tools/dump_army_golden.gd` got out of
//! the real game: units raised and trained, armies on exercise, units sent home, armies split, merged and handed units, generals
//! assigned and freed (the AI's nations keep their best free general in command of their biggest army without one), and a nation that
//! loses all its land. The days run in the game's order; after each action or few days everything is compared.

mod common;

use common::{bits, close};
use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn s(v: &Value) -> &str {
    v.as_str().unwrap()
}

fn compare(label: &str, gs: &GameState, data: &Data, w: &Value, fails: &mut Vec<String>) {
    let mut floats: Vec<(String, f64, f64)> = vec![];
    for (n, x) in gs.nations.iter().zip(w["nations"].as_array().unwrap()) {
        let rec: Vec<Value> = n.recruiting.iter().map(|r| serde_json::json!([r.unit_type, r.province, r.days_left])).collect();
        let mine = serde_json::json!([n.manpower, n.men_in_units, n.men_exercising, rec]);
        // the days left are a float in the game
        let want_rec: Vec<Value> = x[4].as_array().unwrap().iter().map(|r| serde_json::json!([r[0], r[1], r[2].as_f64().unwrap() as i64])).collect();
        let want = serde_json::json!([x[1], x[2], x[3], want_rec]);
        if mine != want {
            fails.push(format!("{label} {}: manpower, men, exercising, recruits {mine} vs {want}", n.tag));
        }
        floats.push((format!("{} treasury", n.tag), n.treasury, bits(&x[0])));
        floats.push((format!("{} net", n.tag), n.budget.net, bits(&x[5])));
    }
    let want_armies = w["armies"].as_array().unwrap();
    if gs.armies.len() != want_armies.len() {
        fails.push(format!("{label}: {} armies vs {}", gs.armies.len(), want_armies.len()));
    } else {
        for (a, x) in gs.armies.iter().zip(want_armies) {
            let mine = serde_json::json!([a.id, a.tag, a.name, a.province, a.general_id, a.units.len(), a.path.len(), a.still_days, a.training, a.attacking]);
            let want = serde_json::json!([x[0], x[1], x[2], x[3], x[4], x[6].as_array().unwrap().len(), x[7], x[8], x[9], x[10]]);
            if mine != want {
                fails.push(format!("{label}: army {} {mine} vs {want}", a.id));
                continue;
            }
            floats.push((format!("army {} general skill", a.id), a.general_skill, bits(&x[5])));
            for (u, y) in a.units.iter().zip(x[6].as_array().unwrap()) {
                if u.unit_type != s(&y[0]) {
                    fails.push(format!("{label}: army {} unit {} vs {}", a.id, u.unit_type, y[0]));
                }
                floats.push((format!("army {} unit strength", a.id), u.strength, bits(&y[1])));
                floats.push((format!("army {} unit morale", a.id), u.morale, bits(&y[2])));
                floats.push((format!("army {} unit experience", a.id), u.experience, bits(&y[3])));
            }
        }
    }
    let gens: Vec<Value> = gs.generals.iter().map(|g| serde_json::json!([g.id, g.tag, g.army_id])).collect();
    let want_gens: Vec<Value> = w["generals"].as_array().unwrap().iter().map(|g| serde_json::json!([g[0], g[1], g[2]])).collect();
    if gens != want_gens {
        fails.push(format!("{label}: generals {gens:?} vs {want_gens:?}"));
    }
    for (g, x) in gs.generals.iter().zip(w["generals"].as_array().unwrap()) {
        floats.push((format!("general {} skill", g.id), g.skill, bits(&x[3])));
    }
    if (gs.next_army_id as i64, gs.next_general_id as i64) != (w["counters"][0].as_i64().unwrap(), w["counters"][1].as_i64().unwrap()) {
        fails.push(format!("{label}: counters {} {} vs {}", gs.next_army_id, gs.next_general_id, w["counters"]));
    }
    let _ = data;
    for (what, got, want) in floats {
        if !close(got, want) {
            fails.push(format!("{label}: {what} {got:e} vs {want:e}"));
        }
    }
}

fn run(index: usize) -> String {
    let data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/army.json")).unwrap();
    let all: Value = serde_json::from_str(&text).unwrap();
    let camp = &all[index];
    let name = s(&camp["name"]).to_string();
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    gs.starting_wars.clear();
    gs.player_tag = s(&camp["player"]).to_string();
    gs.recompute(&data);
    let snaps = camp["snaps"].as_array().unwrap();
    let mut fails = vec![];
    compare(&format!("{name} start"), &gs, &data, &snaps[0], &mut fails);
    let mut next = 1;
    for (i, act) in camp["log"].as_array().unwrap().iter().enumerate() {
        let label = format!("{name} step {i} ({})", act.to_string().chars().take(90).collect::<String>());
        let mut shot = true;
        let ids = |v: &Value| -> Vec<u32> { v.as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as u32).collect() };
        let idx = |v: &Value| -> Vec<usize> { v.as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect() };
        let ok = |k: usize| act[k].as_bool().unwrap();
        let u = |k: usize| act[k].as_u64().unwrap() as u32;
        match s(&act[0]) {
            "war" => gs.set_war_goal(s(&act[1]), s(&act[2]), "none", Value::Null),
            "raise" => {
                let province = act[2].as_i64().unwrap();
                let got = if province < 1 { gs.raise_units(&data, s(&act[1]), 0, s(&act[3]), act[4].as_i64().unwrap()) } else { gs.raise_units(&data, s(&act[1]), province as usize, s(&act[3]), act[4].as_i64().unwrap()) };
                assert_eq!(got, ok(5), "{label}");
            }
            "train" => assert_eq!(gs.set_training(&data, s(&act[1]), &ids(&act[2]), ok(3)), ok(4), "{label}"),
            "demob" => assert_eq!(gs.demobilize_units(&data, s(&act[1]), u(2), act[3].as_i64().unwrap()), ok(4), "{label}"),
            "split" => {
                let got = gs.split_army(s(&act[1]), u(2), &idx(&act[3]));
                assert_eq!(got.is_some(), ok(4), "{label}");
                assert_eq!(got.unwrap_or(0), u(5), "{label}");
            }
            "order" => assert_eq!(gs.order_army_to(&data, s(&act[1]), u(2), u(3) as usize), ok(4), "{label}"),
            "merge" => assert_eq!(gs.merge_armies(s(&act[1]), &ids(&act[2])), ok(3), "{label}"),
            "transfer" => assert_eq!(gs.transfer_units(&data, s(&act[1]), u(2), &idx(&act[3]), u(4)), ok(5), "{label}"),
            "assign" => assert_eq!(gs.assign_general(s(&act[1]), u(2), u(3)), ok(4), "{label}"),
            "wipe" => gs.armies.retain(|a| a.id != u(2)),
            "seize_all" => {
                for id in act[3].as_array().unwrap() {
                    gs.set_controller(id.as_u64().unwrap() as usize, s(&act[2]));
                }
                gs.recompute(&data);
            }
            "shot" => {}
            "day" => {
                gs.step_day(&data);
                gs.navy_step_day(&data);
                gs.military_step_day(&data);
                if gs.economy_dirty {
                    gs.economy_dirty = false;
                    gs.budget_dirty = false;
                    gs.recompute(&data);
                } else if gs.budget_dirty {
                    gs.budget_dirty = false;
                    gs.compute_budgets(&data);
                }
                gs.calendar.advance_day();
                shot = ok(1);
            }
            other => panic!("unknown action {other}"),
        }
        let compare_now = match s(&act[0]) {
            "day" => shot,
            "shot" => true,
            _ => false,
        };
        if compare_now {
            compare(&label, &gs, &data, &snaps[next], &mut fails);
            next += 1;
            if !fails.is_empty() {
                break;
            }
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(10).cloned().collect::<Vec<_>>().join("\n"));
    assert_eq!(next, snaps.len(), "{name}: snapshots used");
    name
}

#[test]
fn armies_agree_with_the_gdscript() {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/army.json")).unwrap();
    let n = serde_json::from_str::<Value>(&text).unwrap().as_array().unwrap().len();
    for i in 0..n {
        println!("{}: agrees with the GDScript", run(i));
    }
}
