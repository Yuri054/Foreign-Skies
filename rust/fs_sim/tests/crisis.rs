//! The crises against the GDScript: `tests/golden/crisis.json` is what `tools/dump_crisis_golden.gd` got out of the real game
//! running with the world's quarrels on and the AI's turn off, and a player answering the demands made of them, mediating, backing
//! a side and pressing demands of their own. The same actions are replayed on the port day by day, and the crises, how they ended,
//! the casus belli, the chronicle, the questions put to the player and the nations' standing are compared.

mod common;

use common::{bits, close};
use fs_sim::crisis::demand_json;
use fs_sim::state::{Data, GameState};
use serde_json::{json, Value};
use std::path::Path;

fn s(v: &Value) -> &str {
    v.as_str().unwrap()
}

/// Every number as a float, so that 12 and 12.0 are the same.
fn norm(v: &Value) -> Value {
    match v {
        Value::Number(n) => json!(n.as_f64().unwrap()),
        Value::Array(a) => Value::Array(a.iter().map(norm).collect()),
        Value::Object(o) => Value::Object(o.iter().map(|(k, v)| (k.clone(), norm(v))).collect()),
        x => x.clone(),
    }
}

fn parsed(v: &Value) -> Value {
    norm(&serde_json::from_str::<Value>(s(v)).unwrap())
}

fn compare(label: &str, gs: &GameState, w: &Value, fails: &mut Vec<String>) {
    if gs.calendar.date_string() != s(&w["date"]) {
        fails.push(format!("{label}: date {} vs {}", gs.calendar.date_string(), w["date"]));
        return;
    }
    let crises: Vec<Value> = gs
        .crises
        .iter()
        .map(|c| {
            json!([c.id, c.kind, c.a, c.b, c.start_day, c.think_day, c.deadline_day, c.backers_a, c.backers_b, c.title, c.text, c.mediators_tried, norm(&demand_json(&c.demand)), norm(&c.goal)])
        })
        .collect();
    let want: Vec<Value> = w["crises"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| {
            let c = c.as_array().unwrap();
            norm(&json!([c[0], c[1], c[2], c[3], c[6], c[7], c[8], c[9], c[10], c[11], c[12], c[13], parsed(&c[4]), parsed(&c[5])]))
        })
        .collect();
    let crises: Vec<Value> = crises.iter().map(norm).collect();
    if crises != want {
        fails.push(format!("{label}: crises\n  mine {}\n  want {}", Value::Array(crises), Value::Array(want)));
        return;
    }
    let ended: Vec<Value> = gs.crisis_log.iter().map(|e| json!([e.id, e.kind, e.a, e.b, e.start, e.end_day, e.outcome, e.title, e.end_date, if e.goal.is_null() { json!({}) } else { norm(&e.goal) }])).collect();
    if norm(&Value::Array(ended.clone())) != norm(&w["ended"]) {
        fails.push(format!("{label}: finished crises {} vs {}", Value::Array(ended), w["ended"]));
        return;
    }
    let mut cool: Vec<(String, i64)> = gs.crisis_cooldown.iter().map(|(k, v)| (k.clone(), *v)).collect();
    cool.sort();
    let mut want_cool: Vec<(String, i64)> = w["cooldown"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_i64().unwrap())).collect();
    want_cool.sort();
    if cool != want_cool || gs.next_crisis_id as i64 != w["next_id"].as_i64().unwrap() {
        fails.push(format!("{label}: cooldowns {cool:?} next {} vs {want_cool:?} {}", gs.next_crisis_id, w["next_id"]));
    }
    let cb: Vec<Value> = gs.casus_belli.iter().map(|c| json!([c.holder, c.target, c.kind, c.expires_day, c.refused_day, if c.goal.is_null() { json!({}) } else { norm(&c.goal) }])).collect();
    let want_cb: Vec<Value> = w["casus_belli"].as_array().unwrap().iter().map(|c| norm(&json!([c[0], c[1], c[2], c[3], c[4], parsed(&c[5])]))).collect();
    if cb.iter().map(norm).collect::<Vec<_>>() != want_cb {
        fails.push(format!("{label}: casus belli {} vs {}", Value::Array(cb), Value::Array(want_cb)));
    }
    let chron: Vec<Value> = gs.chronicle.iter().take(8).map(|(d, t, x)| json!([d, t, x])).collect();
    if Value::Array(chron.clone()) != w["chronicle"] || gs.chronicle.len() as i64 != w["chronicle_size"].as_i64().unwrap() {
        fails.push(format!("{label}: chronicle\n  mine {}\n  want {}", Value::Array(chron), w["chronicle"]));
    }
    let pend: Vec<Value> = gs
        .pending_events
        .iter()
        .map(|p| json!([p.id, p.event, p.title, p.text, p.options.iter().map(|o| json!([o["label"], o["text"].as_str().unwrap_or(""), o["tip"].as_str().unwrap_or(""), o.get("effects").cloned().unwrap_or(json!([]))])).collect::<Vec<_>>()]))
        .collect();
    if norm(&Value::Array(pend.clone())) != norm(&w["pending"]) || gs.next_event_uid as i64 != w["uid"].as_i64().unwrap() {
        fails.push(format!("{label}: questions\n  mine {}\n  want {}", Value::Array(pend), w["pending"]));
    }
    let wars: Vec<Value> = gs.wars.iter().map(|x| json!([x.id, x.a, x.b, x.war_group])).collect();
    if Value::Array(wars) != w["wars"] {
        fails.push(format!("{label}: wars differ"));
    }
    let owners: Vec<&str> = gs.province_owner.iter().skip(1).map(|x| x.as_str()).collect();
    let want_owners: Vec<&str> = w["owners"].as_array().unwrap().iter().map(s).collect();
    if owners != want_owners {
        fails.push(format!("{label}: owners differ"));
    }
    for (n, x) in gs.nations.iter().zip(w["nations"].as_array().unwrap()) {
        for (k, got, i) in [("treasury", n.treasury, 0), ("prestige", n.prestige, 1), ("war support", n.war_support, 2), ("mobilization", n.mobilization, 3), ("points", n.diplomacy_points, 4)] {
            if !close(got, bits(&x[i])) {
                fails.push(format!("{label} {}: {k} {got:e} vs {:e}", n.tag, bits(&x[i])));
            }
        }
    }
    if !close(gs.tension, bits(&w["tension"])) {
        fails.push(format!("{label}: tension {:e} vs {:e}", gs.tension, bits(&w["tension"])));
    }
    for (what, mine, want) in [("relations", &gs.relations, &w["relations"]), ("grievance", &gs.grievance, &w["grievance"])] {
        let want = want.as_object().unwrap();
        if want.iter().any(|(k, v)| mine.get(k).map(|x| !close(*x, bits(v))).unwrap_or(true)) || mine.iter().any(|(k, v)| *v != 0.0 && !want.contains_key(k)) {
            fails.push(format!("{label}: {what} differ"));
        }
    }
    let ind: Vec<(String, String, i64)> = gs.indemnities.iter().map(|i| (i.payer.clone(), i.receiver.clone(), i.months_left)).collect();
    let want_ind: Vec<(String, String, i64)> = w["indemnities"].as_array().unwrap().iter().map(|i| (s(&i[0]).to_string(), s(&i[1]).to_string(), i[3].as_f64().unwrap() as i64)).collect();
    if ind != want_ind || gs.restrictions.len() != w["restrictions"].as_array().unwrap().len() || gs.treaties.len() as i64 != w["treaties"].as_i64().unwrap() {
        fails.push(format!("{label}: indemnities {ind:?} vs {want_ind:?}, restrictions {} vs {}, treaties {} vs {}", gs.restrictions.len(), w["restrictions"], gs.treaties.len(), w["treaties"]));
    }
}

fn run(index: usize) {
    let mut data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/crisis.json")).unwrap();
    let all: Value = serde_json::from_str(&text).unwrap();
    let run = &all[index];
    let name = s(&run["name"]);
    for (k, v) in run["gate"].as_object().unwrap() {
        data.crises["gate"][k] = v.clone();
    }
    let mut gs = GameState::load_scenario(&data, name).unwrap();
    gs.pressure_ai = true;
    gs.start_scenario_wars(&data);
    gs.player_tag = s(&run["player"]).to_string();
    let me = gs.player_tag.clone();
    let (days, every) = (run["days"].as_u64().unwrap() as usize, run["every"].as_u64().unwrap() as usize);
    let snaps = run["snaps"].as_array().unwrap();
    let log = run["log"].as_array().unwrap();
    let mut at = 0;
    let mut fails = vec![];
    compare(&format!("{name}/{me} day 0"), &gs, &snaps[0], &mut fails);
    let mut opened = 0;
    for d in 0..days {
        while at < log.len() && log[at][0].as_u64().unwrap() as usize == d {
            let e = log[at].as_array().unwrap();
            at += 1;
            let want = e.last().unwrap().as_bool();
            let (kind, ok) = match s(&e[1]) {
                "answer" => ("answer", gs.answer_event(&data, e[2].as_u64().unwrap() as u32, e[3].as_u64().unwrap() as usize)),
                "crisis" => ("crisis", gs.crisis_action(&data, &me, e[2].as_u64().unwrap() as u32, s(&e[3]))),
                _ => ("press", gs.press_demand(&data, &me, s(&e[2]), s(&e[3]), None).is_empty()),
            };
            let want = if kind == "press" { e[4].as_bool() } else { want };
            if Some(ok) != want {
                fails.push(format!("{name}/{me} day {d}: {e:?} gave {ok}"));
            }
            opened += 1;
        }
        gs.advance_day(&data);
        if d % every == every - 1 {
            compare(&format!("{name}/{me} day {}", d + 1), &gs, &snaps[d / every + 1], &mut fails);
        }
        if !fails.is_empty() {
            break;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(6).cloned().collect::<Vec<_>>().join("\n"));
    println!("{name}/{me}: {days} days agree with the GDScript ({opened} actions, {} crises finished)", gs.crisis_log.len());
}

#[test]
fn serbia_in_july_1914() {
    run(0);
}

#[test]
fn france_in_july_1914() {
    run(1);
}

#[test]
fn germany_in_january_1900() {
    run(2);
}

#[test]
fn belgium_in_january_1900() {
    run(3);
}

#[test]
fn italy_in_july_1914_with_the_gate_loosened() {
    run(4);
}

#[test]
fn belgium_in_july_1914_with_the_gate_loosened() {
    run(5);
}

#[test]
fn france_in_january_1900_with_the_gate_loosened() {
    run(6);
}

#[test]
fn spain_in_january_1900_with_the_gate_loosened() {
    run(7);
}
