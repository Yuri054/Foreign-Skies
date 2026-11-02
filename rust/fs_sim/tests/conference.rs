//! Peace conferences and the AI's peace against the GDScript: `tests/golden/conference.json` is what `tools/dump_conference_golden.gd`
//! got out of the real `Conference` (through `ProposeConference` and `AnswerConference`) and `AIPeace`: ground taken by one side of
//! the July 1914 war, the player proposing a conference with demands small and large, refusals, counter-offers and cooldowns, and the
//! days after, in which the AI makes its own overtures. Nothing is supplied from the GDScript but the AI nations' answers to calls to arms.

mod common;

use common::{bits, close, demands};
use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn s(v: &Value) -> &str {
    v.as_str().unwrap()
}

fn compare(label: &str, gs: &GameState, w: &Value, fails: &mut Vec<String>) {
    let owners: Vec<&str> = gs.province_owner.iter().skip(1).map(String::as_str).collect();
    let want: Vec<&str> = w["owners"].as_array().unwrap().iter().map(s).collect();
    if owners != want {
        fails.push(format!("{label}: owners differ"));
    }
    let ctl: Vec<&str> = gs.province_controller.iter().skip(1).map(String::as_str).collect();
    let want: Vec<&str> = w["controllers"].as_array().unwrap().iter().map(s).collect();
    if ctl != want {
        fails.push(format!("{label}: holders differ"));
    }
    let wars: Vec<Value> = gs.wars.iter().map(|x| serde_json::json!([x.id, x.a, x.b])).collect();
    if Value::Array(wars) != w["wars"] {
        fails.push(format!("{label}: wars {:?} vs {}", gs.wars.iter().map(|x| (&x.a, &x.b)).collect::<Vec<_>>(), w["wars"]));
    }
    if gs.war_history.len() as i64 != w["history"].as_i64().unwrap() || gs.pending_offers.len() as i64 != w["pending"].as_i64().unwrap() || gs.indemnities.len() as i64 != w["indemnities"].as_i64().unwrap() || gs.next_offer_id as i64 != w["offer_id"].as_i64().unwrap() {
        fails.push(format!("{label}: finished wars {} offers {} indemnities {} next offer {}", gs.war_history.len(), gs.pending_offers.len(), gs.indemnities.len(), gs.next_offer_id));
    }
    for (tag, v) in w["prestige"].as_object().unwrap() {
        if !close(gs.nation(tag).prestige, bits(v)) {
            fails.push(format!("{label}: prestige of {tag} {:e} vs {:e}", gs.nation(tag).prestige, bits(v)));
        }
    }
    for (k, v) in w["relations"].as_object().unwrap() {
        if gs.relations.get(k).map(|x| !close(*x, bits(v))).unwrap_or(true) {
            fails.push(format!("{label}: relation {k}"));
        }
    }
    let cd: std::collections::HashMap<String, i64> = w["cooldown"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_f64().unwrap() as i64)).collect();
    if gs.peace_cooldown != cd {
        fails.push(format!("{label}: cooldown {:?} vs {cd:?}", gs.peace_cooldown));
    }
    let counter = match &gs.conference_counter {
        Some(c) => serde_json::json!([c.from, c.enemy, c.entries.iter().map(|e| serde_json::json!([e.tag, e.demands.len()])).collect::<Vec<_>>(), c.day, c.until_day]),
        None => Value::Null,
    };
    let want_counter = if w["counter"].is_null() {
        Value::Null
    } else {
        let c = &w["counter"];
        serde_json::json!([c[0], c[1], c[2].as_array().unwrap().iter().map(|e| serde_json::json!([e[0], serde_json::from_str::<Value>(s(&e[1])).unwrap().as_array().unwrap().len()])).collect::<Vec<_>>(), c[3], c[4]])
    };
    if counter.to_string().replace(".0", "") != want_counter.to_string().replace(".0", "") {
        fails.push(format!("{label}: counter-offer {counter} vs {want_counter}"));
    }
}

fn run(index: usize) -> String {
    let data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/conference.json")).unwrap();
    let all: Value = serde_json::from_str(&text).unwrap();
    let camp = &all[index];
    let name = s(&camp["name"]).to_string();
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    gs.pressure_ai = false;
    // the AI answers calls to arms itself
    gs.start_scenario_wars(&data);
    gs.player_tag = s(&camp["player"]).to_string();
    let snaps = camp["snaps"].as_array().unwrap();
    let mut fails = vec![];
    compare(&format!("{name} start"), &gs, &snaps[0], &mut fails);
    let mut next = 1;
    for (i, act) in camp["log"].as_array().unwrap().iter().enumerate() {
        let label = format!("{name} step {i} ({})", act.to_string().chars().take(90).collect::<String>());
        let mut compare_now = false;
        match s(&act[0]) {
            "war" => gs.start_war(&data, s(&act[1]), s(&act[2]), true),
            "join" => assert_eq!(gs.answer_join(&data, act[1].as_u64().unwrap() as u32, true), act[2].as_bool().unwrap(), "{label}"),
            "seize" => {
                for p in act[2].as_array().unwrap() {
                    gs.set_controller(p.as_u64().unwrap() as usize, s(&act[1]));
                }
                gs.recompute(&data);
            }
            "conf" => {
                let partners: Vec<String> = act[4].as_array().unwrap().iter().map(|x| s(x).to_string()).collect();
                let r = gs.conference_propose(&data, s(&act[1]), s(&act[2]), demands(&act[3]), &partners);
                assert_eq!((r.ok, r.accepted, r.reason.as_str()), (act[5].as_bool().unwrap(), Some(act[6].as_bool().unwrap_or(false)), s(&act[7])), "{label}");
            }
            "answer" => {
                assert_eq!(gs.answer_counter(&data, act[1].as_bool().unwrap()), act[2].as_bool().unwrap(), "{label}");
            }
            "shot" => compare_now = true,
            "day" => {
                gs.advance_day(&data);
                compare_now = act[1].as_bool().unwrap();
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
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(8).cloned().collect::<Vec<_>>().join("\n"));
    assert_eq!(next, snaps.len(), "{name}: snapshots used");
    name
}

#[test]
fn conferences_agree_with_the_gdscript() {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/conference.json")).unwrap();
    let n = serde_json::from_str::<Value>(&text).unwrap().as_array().unwrap().len();
    for i in 0..n {
        println!("{}: agrees with the GDScript", run(i));
    }
}
