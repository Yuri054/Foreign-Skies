//! Declaring war and the join decisions against the GDScript: `tests/golden/declare.json` is what
//! `tools/dump_declare_golden.gd` got out of the real `Diplomacy`: twelve campaigns of declarations, scenario wars that call their
//! allies, the player's answers, and days passing while the nations that were called mobilize and enter the war. The actions are
//! replayed here and after each one the conflicts, wars, decisions, opinions, prestige, war support, casus belli and treaties
//! must agree. The AI's own choice to join is not ported: it is supplied from what the GDScript decided.

use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::collections::HashMap;
use std::path::Path;

fn bits(v: &Value) -> f64 {
    f64::from_bits(v.as_str().unwrap().parse::<i64>().unwrap() as u64)
}

fn close(a: f64, b: f64) -> bool {
    a == b || (a - b).abs() <= 1e-13 * a.abs().max(b.abs())
}

fn strs(v: &Value) -> Vec<String> {
    v.as_array().unwrap().iter().map(|x| x.as_str().unwrap().to_string()).collect()
}

fn decision(d: &fs_sim::declare::JoinDecision) -> Value {
    serde_json::json!([d.id, d.tag, d.group, d.side, d.kind, d.ally, d.treaty_id, d.cb, d.conflict, d.enemies, d.since.unwrap_or(-1)])
}

fn note(fails: &mut Vec<String>, label: &str, what: &str, mine: String, want: String) {
    if mine != want {
        fails.push(format!("{label}: {what}\n    mine {mine}\n    want {want}"));
    }
}

fn compare(label: &str, gs: &GameState, data: &Data, snap: &Value, fails: &mut Vec<String>) {
    note(fails, label, "day", gs.calendar.days_elapsed.to_string(), snap["day"].to_string());
    let wars: Vec<Value> = gs.wars.iter().map(|w| serde_json::json!([w.id, w.a, w.b, w.casus_belli, w.war_group, w.start_day])).collect();
    let want_wars: Vec<Value> = snap["wars"].as_array().unwrap().iter().map(|w| serde_json::json!([w[0], w[1], w[2], w[3], w[4], w[5]])).collect();
    note(fails, label, "wars", Value::Array(wars).to_string(), Value::Array(want_wars).to_string());
    for (w, want) in gs.wars.iter().zip(snap["wars"].as_array().unwrap()) {
        let goal: Value = serde_json::from_str(want[6].as_str().unwrap()).unwrap();
        let mine = if w.goal.is_null() { serde_json::json!({}) } else { w.goal.clone() };
        let goal = if goal.is_null() { serde_json::json!({}) } else { goal };
        if mine != goal {
            fails.push(format!("{label}: goal of war {}: {mine} vs {goal}", w.id));
        }
    }
    let groups: Vec<Value> = gs.war_groups.iter().map(|g| serde_json::json!([g.id, g.attacker, g.defender, g.members, g.declined, g.called, g.violation])).collect();
    note(fails, label, "groups", Value::Array(groups).to_string(), snap["groups"].to_string());
    let pending: Vec<Value> = gs.pending_joins.iter().map(decision).collect();
    note(fails, label, "pending decisions", Value::Array(pending).to_string(), snap["pending"].to_string());
    let calls: Vec<Value> = gs.join_calls.iter().map(|(k, d)| serde_json::json!([k, decision(d)])).collect();
    note(fails, label, "called nations", Value::Array(calls).to_string(), snap["calls"].to_string());
    let cbs: Vec<Value> = gs.casus_belli.iter().map(|c| serde_json::json!([c.holder, c.target, c.kind, c.expires_day, if c.goal.is_null() { "null".to_string() } else { c.goal.to_string() }])).collect();
    note(fails, label, "casus belli", Value::Array(cbs).to_string(), snap["cbs"].to_string());
    let treaties: Vec<Value> = gs.treaties.iter().map(|t| serde_json::json!([t.id, t.kind, t.a, t.b, t.end_day])).collect();
    note(fails, label, "treaties", Value::Array(treaties).to_string(), snap["treaties"].to_string());
    let counters = [gs.next_decision_id as i64, gs.next_war_group as i64, gs.next_war_id as i64, gs.ai_declarations.0, gs.ai_declarations.1];
    let want_counters: Vec<i64> = snap["counters"].as_array().unwrap()[..5].iter().map(|x| x.as_i64().unwrap()).collect();
    note(fails, label, "counters", format!("{counters:?}"), format!("{want_counters:?}"));
    if !close(gs.tension_impulse, bits(&snap["counters"][5])) {
        fails.push(format!("{label}: tension impulse {:e} vs {:e}", gs.tension_impulse, bits(&snap["counters"][5])));
    }
    for (n, w) in gs.nations.iter().zip(snap["nations"].as_array().unwrap()) {
        assert_eq!(n.tag, w[0].as_str().unwrap());
        for (k, got, i) in [("mobilization", n.mobilization, 1), ("prestige", n.prestige, 2), ("war_support", n.war_support, 3)] {
            if !close(got, bits(&w[i])) {
                fails.push(format!("{label} {}: {k} {got:e} vs {:e}", n.tag, bits(&w[i])));
            }
        }
    }
    for (what, mine, want) in [("relations", &gs.relations, &snap["relations"]), ("grievance", &gs.grievance, &snap["grievance"])] {
        let want = want.as_object().unwrap();
        let mut keys: Vec<&String> = mine.keys().filter(|k| mine[*k] != 0.0 || want.contains_key(*k)).collect();
        keys.sort();
        for k in want.keys() {
            if !mine.contains_key(k) {
                fails.push(format!("{label}: {what}[{k}] missing"));
            }
        }
        for k in keys {
            match want.get(k) {
                Some(v) if close(mine[k], bits(v)) => {}
                other => fails.push(format!("{label}: {what}[{k}] {:e} vs {:?}", mine[k], other.map(bits))),
            }
        }
    }
    for o in snap["options"].as_array().unwrap() {
        let (a, b) = (o[0].as_str().unwrap(), o[1].as_str().unwrap());
        let opts = gs.casus_belli_options(data, a, b);
        note(fails, label, &format!("options {a}>{b}"), format!("{opts:?}"), format!("{:?}", strs(&o[3])));
        note(fails, label, &format!("block {a}>{b}"), gs.declare_block(data, a, b).to_string(), o[2].as_str().unwrap().to_string());
        let can: Vec<bool> = opts.iter().map(|c| gs.can_declare(data, a, b, c)).collect();
        note(fails, label, &format!("can declare {a}>{b}"), serde_json::json!(can).to_string(), o[4].to_string());
        note(fails, label, &format!("neutral {b}"), gs.is_neutral(data, b).to_string(), o[5].to_string());
    }
}

fn run(index: usize) -> (String, usize) {
    let data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/declare.json")).unwrap();
    let all: Value = serde_json::from_str(&text).unwrap();
    let camp = &all[index];
    let name = camp["name"].as_str().unwrap().to_string();
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    gs.ai_join_answers = camp["answers"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_bool().unwrap())).collect::<HashMap<_, _>>();
    if camp["real"].as_bool().unwrap_or(false) {
        gs.start_scenario_wars(&data);
        assert_eq!(gs.player_tag, camp["player"].as_str().unwrap());
    } else {
        // the golden scenarios have no war of their own, and the player is whoever the campaign names
        gs.starting_wars.clear();
        gs.player_tag = camp["player"].as_str().unwrap().to_string();
    }
    gs.recompute(&data);
    let snaps = camp["snaps"].as_array().unwrap();
    let mut fails = vec![];
    compare(&format!("{name} start"), &gs, &data, &snaps[0], &mut fails);
    let mut next = 1;
    for (i, act) in camp["log"].as_array().unwrap().iter().enumerate() {
        let kind = act[0].as_str().unwrap();
        let label = format!("{name} step {i} ({act})");
        let mut shot = true;
        match kind {
            "start_war" => gs.start_war(&data, act[1].as_str().unwrap(), act[2].as_str().unwrap(), act[3].as_bool().unwrap()),
            "declare" => {
                let ok = gs.declare_war(&data, act[1].as_str().unwrap(), act[2].as_str().unwrap(), act[3].as_str().unwrap(), act[4].as_u64().unwrap() as u32);
                assert_eq!(ok, act[5].as_bool().unwrap(), "{label}: whether the declaration was allowed");
            }
            "mob" => {
                let i = gs.nation_index[act[1].as_str().unwrap()];
                gs.nations[i].mobilization = act[2].as_f64().unwrap();
            }
            "cb" => {
                let goal = act[5].clone();
                gs.casus_belli.push(fs_sim::state::CasusBelli { holder: act[1].as_str().unwrap().to_string(), target: act[2].as_str().unwrap().to_string(), kind: act[3].as_str().unwrap().to_string(), expires_day: act[4].as_i64().unwrap(), goal });
            }
            "violate" => gs.violate_border(&data, act[1].as_str().unwrap(), act[2].as_str().unwrap()),
            "answer" => {
                let ok = gs.answer_join(&data, act[1].as_u64().unwrap() as u32, act[2].as_bool().unwrap());
                assert_eq!(ok, act[3].as_bool().unwrap(), "{label}");
            }
            "day" => {
                gs.step_day(&data);
                gs.diplomacy_step_day(&data);
                gs.calendar.advance_day();
                if gs.economy_dirty {
                    gs.economy_dirty = false;
                    gs.recompute(&data);
                }
                shot = act[1].as_bool().unwrap();
            }
            other => panic!("unknown action {other}"),
        }
        if shot {
            compare(&label, &gs, &data, &snaps[next], &mut fails);
            next += 1;
        }
        if !fails.is_empty() {
            break;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(10).cloned().collect::<Vec<_>>().join("\n"));
    assert_eq!(next, snaps.len());
    (name, snaps.len())
}

#[test]
fn campaigns_agree_with_the_gdscript() {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/declare.json")).unwrap();
    let n = serde_json::from_str::<Value>(&text).unwrap().as_array().unwrap().len();
    for i in 0..n {
        let (name, shots) = run(i);
        println!("{name}: {shots} snapshots agree with the GDScript");
    }
}
