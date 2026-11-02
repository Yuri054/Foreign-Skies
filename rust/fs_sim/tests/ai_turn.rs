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
    if !close(gs.tension, bits(&w["tension"])) {
        fails.push(format!("{label}: tension {:e} vs {:e}", gs.tension, bits(&w["tension"])));
    }
}

fn run(index: usize) {
    let data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/ai_turn.json")).unwrap();
    let all: Value = serde_json::from_str(&text).unwrap();
    let run = &all[index];
    let name = s(&run["name"]);
    let mut gs = GameState::load_scenario(&data, name).unwrap();
    gs.pressure_ai = false;
    gs.ai_turn = AiTurn { budget: true, focus: true };
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
