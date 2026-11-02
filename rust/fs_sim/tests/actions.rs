//! The player's diplomacy against the GDScript: `tests/golden/actions.json` is what `tools/dump_actions_golden.gd` got out of the real
//! commands (`BuyPoints`, `ImproveRelations`, `ProposeTreaty`, `Gift`, `CancelTreaty`, `RenameAlliance`) run on the July 1914 scenario,
//! with the real game running by itself for days and months in between (the clock driven, the AI off). After each action or few days
//! the points, prestige, money, treaties (and their names), efforts, opinions and the memory of gifts are compared.

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
        for (k, got, i) in [("points", n.diplomacy_points, 0), ("prestige", n.prestige, 1), ("treasury", n.treasury, 2), ("points price", n.points_price, 3)] {
            if !close(got, bits(&x[i])) {
                fails.push(format!("{label} {}: {k} {got:e} vs {:e}", n.tag, bits(&x[i])));
            }
        }
    }
    let treaties: Vec<Value> = gs.treaties.iter().map(|t| serde_json::json!([t.id, t.kind, t.a, t.b, t.start_day, t.end_day])).collect();
    let want: Vec<Value> = w["treaties"].as_array().unwrap().iter().map(|t| serde_json::json!([t[0], t[1], t[2], t[3], t[4], t[5]])).collect();
    if treaties != want {
        fails.push(format!("{label}: treaties {} vs {}", treaties.len(), want.len()));
    }
    for (t, x) in gs.treaties.iter().zip(w["treaties"].as_array().unwrap()) {
        let terms: Value = serde_json::from_str(s(&x[6])).unwrap();
        let mine = if t.terms.is_null() { serde_json::json!({}) } else { t.terms.clone() };
        let terms = if terms.is_null() { serde_json::json!({}) } else { terms };
        if mine != terms {
            fails.push(format!("{label}: terms of treaty {} {mine} vs {terms}", t.id));
        }
    }
    let projects: Vec<Value> = gs.relation_projects.iter().map(|p| serde_json::json!([p.from, p.to, p.months_left])).collect();
    let want_projects: Vec<Value> = w["projects"].as_array().unwrap().iter().map(|p| serde_json::json!([p[0], p[1], p[2].as_f64().unwrap() as i64])).collect();
    if projects != want_projects {
        fails.push(format!("{label}: efforts {projects:?} vs {want_projects:?}"));
    }
    for (what, mine, want) in [("relations", &gs.relations, &w["relations"]), ("baselines", &gs.relation_base, &w["base"]), ("gifts", &gs.gift_memory, &w["gifts"])] {
        let want = want.as_object().unwrap();
        if mine.len() != want.len() {
            fails.push(format!("{label}: {what} has {} entries vs {}", mine.len(), want.len()));
        }
        for (k, v) in want {
            if mine.get(k).map(|x| !close(*x, bits(v))).unwrap_or(true) {
                fails.push(format!("{label}: {what}[{k}] {:?} vs {:e}", mine.get(k), bits(v)));
            }
        }
    }
    if gs.next_treaty_id as i64 != w["counters"].as_i64().unwrap() {
        fails.push(format!("{label}: next treaty id"));
    }
}

fn run(index: usize) -> String {
    let data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/actions.json")).unwrap();
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
        let mut compare_now = true;
        match s(&act[0]) {
            "war" => gs.set_war_goal(s(&act[1]), s(&act[2]), "none", Value::Null),
            "rel" => gs.set_relation(&data, s(&act[1]), s(&act[2]), act[3].as_f64().unwrap()),
            "gain" => {
                let ni = gs.nation_index[s(&act[1])];
                gs.nations[ni].diplomacy_points = (gs.nations[ni].diplomacy_points + act[2].as_f64().unwrap()).min(200.0);
            }
            "setpoints" => {
                let ni = gs.nation_index[s(&act[1])];
                gs.nations[ni].diplomacy_points = act[2].as_f64().unwrap();
            }
            "rival" => {
                gs.rivalries.insert(s(&act[1]).to_string(), act[2].as_f64().unwrap());
            }
            "treasury" => {
                let ni = gs.nation_index[s(&act[1])];
                gs.nations[ni].treasury = act[2].as_f64().unwrap();
            }
            "prestige" => {
                let ni = gs.nation_index[s(&act[1])];
                gs.nations[ni].prestige = act[2].as_f64().unwrap();
            }
            "buy" => assert_eq!(gs.buy_points(&data, s(&act[1])), ok(2), "{label}"),
            "improve" => assert_eq!(gs.improve_relations(&data, s(&act[1]), s(&act[2])).is_empty(), ok(3), "{label}"),
            "propose" => {
                let p = gs.propose_treaty(&data, s(&act[1]), s(&act[2]), s(&act[3]));
                assert_eq!((p.ok, p.accepted, p.reason.as_str()), (ok(4), ok(5), s(&act[6])), "{label}");
            }
            "gift" => assert_eq!(gs.gift(&data, s(&act[1]), s(&act[2]), act[3].as_f64().unwrap()).is_empty(), ok(4), "{label}"),
            "cancel" => assert_eq!(gs.cancel_treaty(&data, s(&act[1]), act[2].as_u64().unwrap() as u32).is_empty(), ok(3), "{label}"),
            "rename" => assert_eq!(gs.rename_alliance(s(&act[1]), s(&act[2])), ok(3), "{label}"),
            "shot" => {}
            "day" => {
                gs.advance_day(&data);
                compare_now = ok(1);
            }
            other => panic!("unknown action {other}"),
        }
        let compare_now = compare_now && !matches!(s(&act[0]), "war" | "rel" | "gain" | "setpoints" | "rival" | "treasury" | "prestige" | "buy" | "improve" | "propose" | "gift" | "cancel" | "rename");
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
fn diplomacy_actions_agree_with_the_gdscript() {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/actions.json")).unwrap();
    let n = serde_json::from_str::<Value>(&text).unwrap().as_array().unwrap().len();
    for i in 0..n {
        println!("{}: agrees with the GDScript", run(i));
    }
}
