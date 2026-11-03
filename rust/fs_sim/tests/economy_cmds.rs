//! The player's economy commands against the GDScript: `tests/golden/economy_cmds.json` is what `tools/dump_economy_cmds_golden.gd` got
//! out of the real commands run through `GameState.issue` (which works the economy out again after each): projects queued and
//! refused (with the reason the panel shows), the queue reordered, mass orders and the policy sliders, with the real game
//! running by itself for days in between. After each step the nations' gold, points, policies, queues and budgets, and the
//! buildings in every province, are compared.

mod common;

use common::{bits, close};
use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn s(v: &Value) -> &str {
    v.as_str().unwrap()
}

fn compare(label: &str, gs: &GameState, w: &Value, fails: &mut Vec<String>) {
    for (n, x) in gs.nations.iter().zip(w["nations"].as_array().unwrap()) {
        for (k, got, i) in [
            ("treasury", n.treasury, 0), ("cp", n.cp, 1), ("mobilization", n.mobilization, 2), ("net", n.budget.net, 4),
            ("income", n.budget.income, 5), ("cp a day", n.budget.cp, 6), ("blockade", n.blockade, 8),
        ] {
            if !close(got, bits(&x[i])) {
                fails.push(format!("{label} {}: {k} {got:e} vs {:e}", n.tag, bits(&x[i])));
            }
        }
        if (n.peacetime_army, n.manpower) != (x[3].as_i64().unwrap(), x[9].as_i64().unwrap()) {
            fails.push(format!("{label} {}: standing army and recruits {} {} vs {} {}", n.tag, n.peacetime_army, n.manpower, x[3], x[9]));
        }
        let jobs = x[7].as_array().unwrap();
        let mine: Vec<Value> = n.construction.iter().map(|j| serde_json::json!([j.province, j.kind, j.started as i64, j.days_total, j.days_left])).collect();
        if mine != *jobs {
            fails.push(format!("{label} {}: projects {mine:?} vs {jobs:?}", n.tag));
        }
    }
    let works: Vec<Value> = (1..gs.province_buildings.len())
        .filter(|&id| !gs.province_buildings[id].is_empty())
        .map(|id| serde_json::json!([id, gs.province_buildings[id].iter().map(|(k, l)| serde_json::json!([k, l])).collect::<Vec<_>>()]))
        .collect();
    if Value::Array(works) != w["works"] {
        fails.push(format!("{label}: the works in the provinces differ"));
    }
}

fn run(index: usize) -> String {
    let data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/economy_cmds.json")).unwrap();
    let all: Value = serde_json::from_str(&text).unwrap();
    let camp = &all[index];
    let name = s(&camp["name"]).to_string();
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    gs.starting_wars.clear();
    gs.pressure_ai = false;
    gs.player_tag = s(&camp["player"]).to_string();
    gs.recompute(&data);
    let snaps = camp["snaps"].as_array().unwrap();
    let mut fails = vec![];
    compare(&format!("{name} start"), &gs, &snaps[0], &mut fails);
    let mut next = 1;
    for (i, act) in camp["log"].as_array().unwrap().iter().enumerate() {
        let label = format!("{name} step {i} ({})", act.to_string().chars().take(90).collect::<String>());
        let ok = |k: usize| act[k].as_bool().unwrap();
        let u = |k: usize| act[k].as_u64().unwrap() as usize;
        let mut compare_now = false;
        match s(&act[0]) {
            "war" => gs.set_war_goal(s(&act[1]), s(&act[2]), "none", Value::Null),
            "treasury" | "blockade" | "pin" | "cp" => {
                let ni = gs.nation_index[s(&act[1])];
                let v = act[2].as_f64().unwrap();
                match s(&act[0]) {
                    "treasury" => gs.nations[ni].treasury = v,
                    "blockade" => gs.nations[ni].blockade = v,
                    "cp" => gs.nations[ni].cp = v,
                    _ => gs.nations[ni].blockade_pinned = v,
                }
            }
            "setlevel" => {
                let list = &mut gs.province_buildings[u(1)];
                match list.iter_mut().find(|(k, _)| k == s(&act[2])) {
                    Some(slot) => slot.1 = act[3].as_i64().unwrap() as i32,
                    None => list.push((s(&act[2]).to_string(), act[3].as_i64().unwrap() as i32)),
                }
            }
            "seize" => {
                gs.set_controller(u(1), s(&act[2]));
                gs.recompute(&data);
            }
            "build" => {
                let got = gs.construct_building(&data, s(&act[1]), u(2), s(&act[3]));
                assert_eq!(got, ok(4), "{label}");
                if got {
                    gs.recompute(&data);
                }
            }
            "prio" => {
                let got = gs.prioritize_construction(s(&act[1]), u(2), s(&act[3]));
                assert_eq!(got, ok(4), "{label}");
                if got {
                    gs.recompute(&data);
                }
            }
            "mass" => {
                let r = gs.mass_construct(&data, s(&act[1]), s(&act[2]), act[3].as_u64().unwrap() as usize, act[4].as_f64().unwrap());
                assert_eq!(r.ok, ok(5), "{label}");
                let built: Vec<usize> = act[6].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect();
                assert_eq!(r.built, built, "{label}");
                assert!(close(r.gold, bits(&act[7])) && close(r.cp, bits(&act[8])), "{label}: gold {} cp {}", r.gold, r.cp);
                assert_eq!(r.stopped_by, s(&act[9]), "{label}");
                if r.ok {
                    gs.recompute(&data);
                }
            }
            "policy" => {
                let got = gs.set_economy_policy(&data, s(&act[1]), s(&act[2]), act[3].as_f64().unwrap());
                assert_eq!(got, ok(4), "{label}");
                if got {
                    gs.recompute(&data);
                }
            }
            "problem" => {
                let got = gs.build_problem(&data, s(&act[1]), u(2), s(&act[3]), true);
                assert_eq!(got, s(&act[4]), "{label}");
            }
            "shot" => compare_now = true,
            "day" => {
                gs.advance_day(&data);
                compare_now = ok(1);
            }
            other => panic!("unknown action {other}"),
        }
        if compare_now {
            compare(&label, &gs, &snaps[next], &mut fails);
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
fn economy_commands_agree_with_the_gdscript() {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/economy_cmds.json")).unwrap();
    let n = serde_json::from_str::<Value>(&text).unwrap().as_array().unwrap().len();
    for i in 0..n {
        println!("{}: agrees with the GDScript", run(i));
    }
}
