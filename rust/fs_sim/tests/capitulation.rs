//! Capitulation against the GDScript: `tests/golden/capitulation.json` is what `tools/dump_capitulation_golden.gd` got out of
//! the real `Capitulation`: wars in which the enemy takes ground in steps, with the capital moving (the AI's to its best city,
//! the player's by choice), going home again, the nation laying down its arms, and the peace each AI enemy dictates. The terms the
//! AI asked and its answers come from the dump, since the AI is not ported.

mod common;

use common::{bits, close, compare_snapshot, demands};
use fs_sim::capitulation::Dictation;
use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn run(index: usize, supplied: bool) -> String {
    let data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/capitulation.json")).unwrap();
    let all: Value = serde_json::from_str(&text).unwrap();
    let camp = &all[index];
    let name = camp["name"].as_str().unwrap().to_string();
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    gs.starting_wars.clear();
    gs.player_tag = camp["player"].as_str().unwrap().to_string();
    gs.recompute(&data);
    let snaps = camp["snaps"].as_array().unwrap();
    let mut fails = vec![];
    compare_extra(&format!("{name} start"), &gs, &data, &snaps[0], &mut fails);
    for (i, act) in camp["log"].as_array().unwrap().iter().enumerate() {
        let label = format!("{name} step {i} ({})", act.to_string().chars().take(80).collect::<String>());
        match act[0].as_str().unwrap() {
            "war" => gs.set_war_goal(act[1].as_str().unwrap(), act[2].as_str().unwrap(), "none", Value::Null),
            "occupy" => {
                for id in act[3].as_array().unwrap() {
                    gs.set_controller(id.as_u64().unwrap() as usize, act[2].as_str().unwrap());
                }
            }
            "control" => gs.set_controller(act[1].as_u64().unwrap() as usize, act[2].as_str().unwrap()),
            "end_war" => {
                let w = gs.war_between(act[1].as_str().unwrap(), act[2].as_str().unwrap()).unwrap();
                gs.end_war(w);
            }
            "choose" => {
                let ok = gs.choose_capital(act[1].as_str().unwrap(), act[2].as_u64().map(|x| x as usize).unwrap_or(usize::MAX));
                assert_eq!(ok, act[3].as_bool().unwrap(), "{label}");
            }
            "step" => {
                gs.ai_dictation = if !supplied { vec![] } else { act[1]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|d| Dictation {
                        enemy: d["enemy"].as_str().unwrap().to_string(),
                        tag: d["tag"].as_str().unwrap().to_string(),
                        war_id: d["war_id"].as_u64().unwrap() as u32,
                        terms: demands(&d["terms"]),
                        accepts: d["accepted"].as_bool().unwrap_or(false),
                    })
                    .collect() };
                gs.capitulation_step_day(&data);
                assert!(gs.ai_dictation.is_empty(), "{label}: the AI's terms were not all used");
            }
            "days" => {
                for _ in 0..act[1].as_i64().unwrap() {
                    gs.calendar.advance_day();
                }
            }
            other => panic!("unknown action {other}"),
        }
        compare_extra(&label, &gs, &data, &snaps[i + 1], &mut fails);
        if !fails.is_empty() {
            break;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(10).cloned().collect::<Vec<_>>().join("\n"));
    name
}

fn compare_extra(label: &str, gs: &GameState, data: &Data, snap: &Value, fails: &mut Vec<String>) {
    compare_snapshot(label, gs, snap, fails);
    for (tag, v) in snap["progress"].as_object().unwrap() {
        let got = gs.capitulation_progress(data, tag);
        if !close(got, bits(v)) {
            fails.push(format!("{label}: capitulation progress of {tag} {got:e} vs {:e}", bits(v)));
        }
    }
    let choice = match &gs.capital_choice {
        Some(c) => serde_json::json!([c.tag, c.candidates, c.lost]),
        None => serde_json::json!(["", [], 0]),
    };
    if choice != snap["choice"] {
        fails.push(format!("{label}: capital choice {choice} vs {}", snap["choice"]));
    }
    let mut caps: Vec<Value> = gs.wars.iter().chain(gs.war_history.iter()).map(|w| {
        let mut who: Vec<&String> = w.capitulated.keys().collect();
        who.sort();
        serde_json::json!([w.id, who])
    }).collect();
    let mut want: Vec<Value> = snap["war_caps"].as_array().unwrap().clone();
    for c in caps.iter_mut().chain(want.iter_mut()) {
        if let Some(a) = c[1].as_array_mut() {
            a.sort_by_key(|x| x.as_str().unwrap().to_string());
        }
    }
    if caps != want {
        fails.push(format!("{label}: capitulations {caps:?} vs {want:?}"));
    }
}

#[test]
fn capitulations_agree_with_the_gdscript() {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/capitulation.json")).unwrap();
    let n = serde_json::from_str::<Value>(&text).unwrap().as_array().unwrap().len();
    for i in 0..n {
        println!("{}: agrees with the GDScript", run(i, true));
    }
}

/// The same wars with no terms supplied: the port's own `AIPeace` asks for them and answers.
#[test]
fn capitulations_with_the_ai_ported_agree_with_the_gdscript() {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/capitulation.json")).unwrap();
    let n = serde_json::from_str::<Value>(&text).unwrap().as_array().unwrap().len();
    for i in 0..n {
        println!("{}: agrees with the GDScript", run(i, false));
    }
}
