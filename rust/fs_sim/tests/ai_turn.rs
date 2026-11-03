//! The AI's budget and focus against the GDScript: `tests/golden/ai_turn.json` is what `tools/dump_ai_turn_golden.gd` got out of the real
//! game, its day driven stage by stage with those parts of the AI's turn run where the game runs the AI (the rest of the turn does
//! nothing). Four campaigns, two with wars and a front drawn for each side. The nations' policies, money, works, foci and the month of
//! their last budget are compared every five days.

mod common;

use common::{bits, close};
use fs_sim::ai_turn::AiTurn;
use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn s(v: &Value) -> &str {
    v.as_str().unwrap()
}

fn norm(v: &Value) -> Value {
    match v {
        Value::Number(n) => serde_json::json!(n.as_f64().unwrap()),
        Value::Array(a) => Value::Array(a.iter().map(norm).collect()),
        Value::Object(o) => Value::Object(o.iter().map(|(k, v)| (k.clone(), norm(v))).collect()),
        x => x.clone(),
    }
}

fn compare(label: &str, gs: &GameState, w: &Value, fails: &mut Vec<String>) {
    if gs.calendar.date_string() != s(&w["date"]) {
        fails.push(format!("{label}: date {} vs {}", gs.calendar.date_string(), w["date"]));
        return;
    }
    for (n, x) in gs.nations.iter().zip(w["nations"].as_array().unwrap()) {
        for (k, got, i) in [
            ("treasury", n.treasury, 0), ("tax", n.tax_rate, 1), ("investment", n.investment, 2), ("arms share", n.arms_share, 3),
            ("munitions", n.munitions, 4), ("points", n.diplomacy_points, 5), ("prestige", n.prestige, 6), ("mobilization", n.mobilization, 7),
            ("net", n.budget.net, 8),
        ] {
            if !close(got, bits(&x[i])) {
                fails.push(format!("{label} {}: {k} {got:e} vs {:e}", n.tag, bits(&x[i])));
            }
        }
        let jobs: Vec<Value> = n.construction.iter().map(|j| serde_json::json!([j.province, j.kind, j.days_left])).collect();
        let want_jobs: Vec<Value> = x[9].as_array().unwrap().iter().map(|j| serde_json::json!([j[0], j[1], j[2]])).collect();
        if jobs != want_jobs {
            fails.push(format!("{label} {}: works {jobs:?} vs {want_jobs:?}", n.tag));
        } else {
            for (j, wj) in n.construction.iter().zip(x[9].as_array().unwrap()) {
                if !close(j.points_left, bits(&wj[3])) {
                    fails.push(format!("{label} {}: work points {:e} vs {:e}", n.tag, j.points_left, bits(&wj[3])));
                }
            }
        }
        let focus = n.focus.as_ref().map(|f| f.id.clone()).unwrap_or_default();
        if focus != s(&x[10]) || Value::from(n.focus_done.clone()) != x[11] {
            fails.push(format!("{label} {}: focus {focus:?} done {:?} vs {} {}", n.tag, n.focus_done, x[10], x[11]));
        }
        let stamp = gs.ai_budget_stamp.get(&n.tag).copied().unwrap_or(0);
        if stamp != x[13].as_i64().unwrap() || n.provinces.len() as i64 != x[14].as_i64().unwrap() {
            fails.push(format!("{label} {}: budget month {stamp} vs {}, provinces {} vs {}", n.tag, x[13], n.provinces.len(), x[14]));
        }
    }
    let owners: Vec<&str> = gs.province_owner.iter().skip(1).map(|x| x.as_str()).collect();
    let want: Vec<&str> = w["owners"].as_array().unwrap().iter().map(s).collect();
    if owners != want {
        fails.push(format!("{label}: owners differ"));
    }
    let armies: Vec<Value> = gs.armies.iter().map(|a| serde_json::json!([a.id, a.tag, a.province, a.units.len(), a.path, a.front_id, a.pin, a.parent_id])).collect();
    let want_armies: Vec<Value> = w["armies"].as_array().unwrap().iter().map(|a| serde_json::json!([a[0], a[1], a[2], a[4], a[9], a[6], a[7], a[8]])).collect();
    if armies != want_armies {
        let only_mine: Vec<&Value> = armies.iter().filter(|a| !want_armies.contains(a)).collect();
        let only_want: Vec<&Value> = want_armies.iter().filter(|a| !armies.contains(a)).collect();
        fails.push(format!("{label}: armies differ ({} vs {})\n  only mine {only_mine:?}\n  only want {only_want:?}", armies.len(), want_armies.len()));
    }
    let rec: Vec<Value> = gs.nations.iter().map(|n| Value::Array(n.recruiting.iter().map(|j| serde_json::json!([j.unit_type, j.province, j.days_left])).collect())).collect();
    if norm(&Value::Array(rec)) != norm(&w["recruiting"]) {
        fails.push(format!("{label}: units in training {} vs {}", serde_json::Value::Array(gs.nations.iter().map(|n| Value::Array(n.recruiting.iter().map(|j| serde_json::json!([j.unit_type, j.province, j.days_left])).collect())).collect()), w["recruiting"]));
    }
    let men: Vec<Value> = gs.nations.iter().map(|n| serde_json::json!([n.manpower, n.men_in_units])).collect();
    if norm(&Value::Array(men)) != norm(&w["manpower"]) {
        fails.push(format!("{label}: manpower, men under arms differ"));
    }
    let wars: Vec<Value> = gs.wars.iter().map(|x| serde_json::json!([x.id, x.a, x.b])).collect();
    if Value::Array(wars) != w["wars"] {
        fails.push(format!("{label}: wars differ"));
    }
    let mut amb: Vec<(String, String, i64)> = gs.ai_ambition.iter().map(|(k, v)| (k.clone(), v.0.clone(), v.1)).collect();
    amb.sort();
    let mut want_amb: Vec<(String, String, i64)> = w["ambition"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), s(&v["target"]).to_string(), v["since"].as_i64().unwrap())).collect();
    want_amb.sort();
    let mut wait: Vec<(String, i64)> = gs.ai_ambition_wait.iter().map(|(k, v)| (k.clone(), *v)).collect();
    wait.sort();
    let mut want_wait: Vec<(String, i64)> = w["ambition_wait"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_i64().unwrap())).collect();
    want_wait.sort();
    if amb != want_amb || wait != want_wait {
        fails.push(format!("{label}: ambitions {amb:?} {wait:?} vs {want_amb:?} {want_wait:?}"));
    }
    let fronts: Vec<Value> = gs.fronts.iter().map(|f| serde_json::json!([f.id, f.tag, f.against, f.provinces, f.anchors, f.army_ids])).collect();
    if norm(&Value::Array(fronts.clone())) != norm(&w["fronts"]) {
        fails.push(format!("{label}: fronts\n  mine {}\n  want {}", Value::Array(fronts), w["fronts"]));
    }
    let mut reserve: Vec<(String, u32)> = gs.ai_reserve.iter().map(|(k, v)| (k.clone(), *v)).collect();
    reserve.sort();
    let mut want_reserve: Vec<(String, u32)> = w["reserve"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_u64().unwrap() as u32)).collect();
    want_reserve.sort();
    let mut stamps: Vec<(u32, i64)> = gs.ai_anchor_stamp.iter().map(|(k, v)| (*k, *v)).collect();
    stamps.sort();
    let mut want_stamps: Vec<(u32, i64)> = w["anchor_stamp"].as_object().unwrap().iter().map(|(k, v)| (k.parse().unwrap(), v.as_i64().unwrap())).collect();
    want_stamps.sort();
    if reserve != want_reserve || stamps != want_stamps {
        fails.push(format!("{label}: reserves {reserve:?} stamps {stamps:?} vs {want_reserve:?} {want_stamps:?}"));
    }
    let treaties: Vec<Value> = gs.treaties.iter().map(|t| serde_json::json!([t.id, t.kind, t.a, t.b, t.start_day, t.end_day])).collect();
    if norm(&Value::Array(treaties.clone())) != norm(&w["treaties"]) {
        fails.push(format!("{label}: treaties\n  mine {}\n  want {}", Value::Array(treaties), w["treaties"]));
    }
    let crises: Vec<Value> = gs.crises.iter().map(|c| serde_json::json!([c.id, c.kind, c.a, c.b])).collect();
    let cbs: Vec<Value> = gs.casus_belli.iter().map(|c| serde_json::json!([c.holder, c.target, c.kind])).collect();
    if norm(&Value::Array(crises.clone())) != norm(&w["crises"]) || norm(&Value::Array(cbs.clone())) != norm(&w["cbs"]) {
        fails.push(format!("{label}: crises {} {} vs {} {}", Value::Array(crises), Value::Array(cbs), w["crises"], w["cbs"]));
    }
    if (gs.ai_declarations.0 as i64, gs.ai_declarations.1 as i64) != (w["declarations"][0].as_i64().unwrap(), w["declarations"][1].as_i64().unwrap()) {
        fails.push(format!("{label}: declarations {:?} vs {}", gs.ai_declarations, w["declarations"]));
    }
    for (what, mine, want) in [("relations", &gs.relations, &w["relations"]), ("grievance", &gs.grievance, &w["grievance"])] {
        let want = want.as_object().unwrap();
        if want.iter().any(|(k, v)| mine.get(k).map(|x| !close(*x, bits(v))).unwrap_or(true)) || mine.iter().any(|(k, v)| *v != 0.0 && !want.contains_key(k)) {
            fails.push(format!("{label}: {what} differ"));
        }
    }
    let want_plans: Value = serde_json::from_str(s(&w["plans"])).unwrap();
    if norm(&Value::Array(gs.ai_plans.clone())) != norm(&want_plans) {
        fails.push(format!("{label}: plans {} vs {}", Value::Array(gs.ai_plans.clone()), want_plans));
    }
    if !close(gs.tension, bits(&w["tension"])) {
        fails.push(format!("{label}: tension {:e} vs {:e}", gs.tension, bits(&w["tension"])));
    }
}

fn run(index: usize) {
    let mut data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(std::env::var("AI_GOLDEN").unwrap_or(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/ai_turn.json").to_string())).unwrap();
    let all: Value = serde_json::from_str(&text).unwrap();
    let run = &all[index];
    let name = s(&run["name"]);
    fn merge(dst: &mut Value, src: &Value) {
        for (k, v) in src.as_object().unwrap() {
            if v.is_object() && dst.get(k).map(Value::is_object).unwrap_or(false) {
                merge(&mut dst[k], v);
            } else {
                dst[k] = v.clone();
            }
        }
    }
    for (section, keys) in run["ai_cfg"].as_object().unwrap() {
        merge(&mut data.ai.raw[section], keys);
    }
    data.ai.diplomacy = data.ai.raw["diplomacy"].clone();
    let mut gs = GameState::load_scenario(&data, name).unwrap();
    gs.pressure_ai = run["pressure"].as_bool().unwrap();
    let on = |p: &str| run["parts"].as_array().unwrap().iter().any(|x| x == p);
    gs.ai_turn = AiTurn { budget: on("budget"), focus: on("focus"), forces: on("forces"), ambition: on("ambition"), defence: on("defence"), diplomacy: on("diplomacy") };
    gs.start_scenario_wars(&data);
    gs.player_tag = s(&run["player"]).to_string();
    let purse: Vec<f64> = run["purse"].as_array().unwrap().iter().map(|x| x.as_f64().unwrap()).collect();
    if !purse.is_empty() {
        let mut tags: Vec<String> = gs.nations.iter().map(|n| n.tag.clone()).collect();
        tags.sort();
        for (i, tag) in tags.iter().enumerate() {
            let ni = gs.nation_index[tag];
            gs.nations[ni].treasury *= purse[i % purse.len()];
        }
    }
    for w in run["wars"].as_array().unwrap() {
        gs.start_war(&data, s(&w[0]), s(&w[1]), true);
    }
    for st in run["setup"].as_array().unwrap() {
        let got = gs.designate_front(&data, s(&st[0]), &format!("Front {}", s(&st[1])), &[], s(&st[1]), "line", 0).is_some();
        assert_eq!(got, st[2].as_bool().unwrap(), "front of {} against {}", st[0], st[1]);
    }
    for o in run["orders"].as_array().unwrap() {
        let ok = gs.order_army_to(&data, s(&o[0]), o[1].as_u64().unwrap() as u32, o[2].as_u64().unwrap() as usize);
        assert_eq!(ok, o[3].as_bool().unwrap(), "{name}: order {o}");
    }
    let every = run["every"].as_u64().unwrap() as usize;
    let snaps = run["snaps"].as_array().unwrap();
    let mut fails = vec![];
    compare(&format!("{name}/{} day 0", s(&run["player"])), &gs, &snaps[0], &mut fails);
    for (i, snap) in snaps.iter().enumerate().skip(1) {
        for _ in 0..every {
            gs.advance_day(&data);
        }
        compare(&format!("{name}/{} day {}", s(&run["player"]), i * every), &gs, snap, &mut fails);
        if !fails.is_empty() {
            break;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(8).cloned().collect::<Vec<_>>().join("\n"));
    println!("{name}/{}: {} days agree with the GDScript", s(&run["player"]), (snaps.len() - 1) * every);
}

#[test]
fn debug_run() {
    if let Ok(i) = std::env::var("AI_RUN") {
        run(i.parse().unwrap());
    }
}

#[test]
fn germany_in_july_1914() {
    run(0);
}

#[test]
fn britain_in_january_1900() {
    run(1);
}

#[test]
fn july_1914_at_war() {
    run(2);
}

#[test]
fn january_1900_at_war() {
    run(3);
}

#[test]
fn germany_with_purses_thrown_about() {
    run(4);
}

#[test]
fn britain_with_purses_thrown_about() {
    run(5);
}

#[test]
fn july_1914_at_war_with_purses_thrown_about() {
    run(6);
}

#[test]
fn united_states_for_fifteen_hundred_days() {
    run(7);
}

#[test]
fn portugal_with_all_of_it_in_july_1914() {
    run(8);
}

#[test]
fn britain_with_purses_and_all_of_it() {
    run(9);
}

#[test]
fn united_states_with_all_of_it_in_1900() {
    run(10);
}

#[test]
fn britain_in_1900_with_the_world_in_tension() {
    run(11);
}

#[test]
fn serbia_in_july_1914_with_the_world_in_tension() {
    run(12);
}

#[test]
fn britain_in_july_1914_with_ambitions_loosened() {
    run(13);
}

#[test]
fn united_states_in_1900_with_ambitions_loosened() {
    run(14);
}

#[test]
fn serbia_with_ambitions_loosened_and_the_world_in_tension() {
    run(15);
}

#[test]
fn britain_in_1900_with_ambitions_loosened_and_the_world_in_tension() {
    run(16);
}

#[test]
fn portugal_with_armies_at_the_borders() {
    run(17);
}

#[test]
fn britain_with_three_wars_and_armies_at_the_borders() {
    run(18);
}

#[test]
fn united_states_in_1900_with_armies_at_the_borders() {
    run(19);
}

#[test]
fn britain_in_1900_with_a_stricter_ambition() {
    run(20);
}

#[test]
fn britain_with_ambition_near_its_threshold() {
    run(21);
}

#[test]
fn united_states_with_ambition_near_its_threshold_in_tension() {
    run(22);
}

#[test]
fn france_with_ambition_at_its_threshold() {
    run(23);
}

#[test]
fn defence_with_portugal_looking_on() {
    run(24);
}

#[test]
fn defence_in_four_wars() {
    run(25);
}

#[test]
fn defence_of_serbia() {
    run(26);
}

#[test]
fn defence_in_1900() {
    run(27);
}

#[test]
fn defence_in_four_wars_in_1900() {
    run(28);
}

#[test]
fn diplomacy_in_july_1914_with_the_thresholds_loosened() {
    run(29);
}

#[test]
fn diplomacy_in_1900_with_the_thresholds_loosened() {
    run(30);
}

#[test]
fn diplomacy_in_july_1914_without_tension() {
    run(31);
}

#[test]
fn diplomacy_in_1900_as_the_game_has_it() {
    run(32);
}

#[test]
fn diplomacy_in_july_1914_as_the_game_has_it() {
    run(33);
}

#[test]
fn diplomacy_in_1900_without_the_tension_gate() {
    run(34);
}

#[test]
fn diplomacy_in_1900_with_stricter_thresholds() {
    run(35);
}
