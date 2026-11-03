//! Fronts against the GDScript: `tests/golden/group.json` is what `tools/dump_front_golden.gd` got out of the real `Front`,
//! `FrontSolver` and `Military.step_fronts`: fronts designated and armies assigned, the AI's armies each sent to hold a province, the
//! player's divisions spread along the line as detachments, lines that follow the war, and a fallback line. The days run in the game's
//! order (economy, navy, army).

mod common;

use common::{bits, close};
use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn s(v: &Value) -> &str {
    v.as_str().unwrap()
}

fn compare(label: &str, gs: &GameState, w: &Value, data: &Data, fails: &mut Vec<String>) {
    let want_fronts = w["fronts"].as_array().unwrap();
    if gs.fronts.len() != want_fronts.len() {
        fails.push(format!("{label}: {} fronts vs {}", gs.fronts.len(), want_fronts.len()));
        return;
    }
    for (f, x) in gs.fronts.iter().zip(want_fronts) {
        let mut slots: Vec<(String, usize)> = f.slots.iter().map(|(k, v)| (k.to_string(), *v)).collect();
        slots.sort();
        let mut want_slots: Vec<(String, usize)> = x[3].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_u64().unwrap() as usize)).collect();
        want_slots.sort();
        let mut retry: Vec<(String, i64)> = f.retry.iter().map(|(k, v)| (k.to_string(), *v)).collect();
        retry.sort();
        let mut want_retry: Vec<(String, i64)> = x[7].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_i64().unwrap())).collect();
        want_retry.sort();
        let mut dep: Vec<u32> = f.deploying.iter().copied().collect();
        dep.sort();
        let mine = serde_json::json!([f.id, f.provinces, f.army_ids, f.order, f.dirty, dep, f.spread, f.cohesion, f.anchors, f.weights_day, f.line_stamp]);
        let want = serde_json::json!([x[0], x[1], x[2], x[4], x[6], x[8], x[9], x[10], x[11], x[12], x[13]]);
        // the days are floats in the game
        if normalize(&mine) != normalize(&want) {
            fails.push(format!("{label}: front {}\n    mine {mine}\n    want {want}", f.id));
        }
        if slots != want_slots {
            fails.push(format!("{label}: slots of front {} {slots:?} vs {want_slots:?}", f.id));
        }
        if retry != want_retry {
            fails.push(format!("{label}: retry of front {} {retry:?} vs {want_retry:?}", f.id));
        }
        let ww = x[5].as_array().unwrap();
        if f.weights.len() != ww.len() || f.weights.iter().zip(ww).any(|(a, b)| !close(*a, bits(b))) {
            fails.push(format!("{label}: weights of front {}", f.id));
        }
    }
    let want_armies = w["armies"].as_array().unwrap();
    if gs.armies.len() != want_armies.len() {
        fails.push(format!("{label}: {} armies vs {}", gs.armies.len(), want_armies.len()));
        return;
    }
    for (a, x) in gs.armies.iter().zip(want_armies) {
        let mine = serde_json::json!([a.id, a.tag, a.name, a.province, a.parent_id, a.front_id, a.pin, a.prepared, a.units.len(), a.path.len(), a.still_days, a.general_id, a.fighting, a.fleet_id]);
        let want = serde_json::json!([x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7], x[8], x[9], x[10], x[11], x[13], x[15]]);
        if mine != want {
            fails.push(format!("{label}: army {}\n    mine {mine}\n    want {want}", a.id));
        }
        if !close(a.men(&data.military), bits(&x[12])) || !close(a.move_days_left, bits(&x[14])) {
            fails.push(format!("{label}: army {} men or move days", a.id));
        }
    }
    if (gs.next_front_id as i64, gs.next_army_id as i64, gs.next_offensive_id as i64) != (w["counters"][0].as_i64().unwrap(), w["counters"][1].as_i64().unwrap(), w["counters"][2].as_i64().unwrap()) {
        fails.push(format!("{label}: counters"));
    }
    let offs: Vec<Value> = gs.offensives.iter().map(|o| serde_json::json!([o.id, o.tag, o.army_id, o.kind, o.phases, o.phase, o.aggressiveness, o.port, o.active, o.launched, o.done])).collect();
    if normalize(&Value::Array(offs.clone())) != normalize(&w["offs"]) {
        fails.push(format!("{label}: plans\n    mine {}\n    want {}", Value::Array(offs), w["offs"]));
    }
    for (a, x) in gs.armies.iter().zip(w["planning"].as_array().unwrap()) {
        if !close(a.planning, bits(x)) {
            fails.push(format!("{label}: planning of army {} {:e} vs {:e}", a.id, a.planning, bits(x)));
        }
    }
    let groups: Vec<Value> = gs.army_groups.iter().map(|g| serde_json::json!([g.id, g.tag, g.name, g.army_ids, g.marshal_id])).collect();
    if Value::Array(groups.clone()) != w["groups"] {
        fails.push(format!("{label}: groups {} vs {}", Value::Array(groups), w["groups"]));
    }
    let lines: Vec<Value> = gs.attack_lines.iter().map(|l| serde_json::json!([l.id, l.tag, l.name, l.group_id, l.enemy, l.front_id, l.active, l.wait])).collect();
    if normalize(&Value::Array(lines.clone())) != normalize(&w["lines"]) {
        fails.push(format!("{label}: attack lines {} vs {}", Value::Array(lines), w["lines"]));
    }
    let gens: Vec<Value> = gs.generals.iter().map(|g| serde_json::json!([g.id, g.army_id, g.group_id])).collect();
    if Value::Array(gens) != w["gens"] {
        fails.push(format!("{label}: generals differ"));
    }
    for (a, x) in gs.armies.iter().zip(w["powers"].as_array().unwrap()) {
        if a.group_id as i64 != x[0].as_i64().unwrap() || !close(a.power(&data.military), bits(&x[1])) {
            fails.push(format!("{label}: group or power of army {} {:e} vs {:e}", a.id, a.power(&data.military), bits(&x[1])));
        }
    }
    if (gs.next_group_id as i64, gs.next_attack_line_id as i64) != (w["gcounters"][0].as_i64().unwrap(), w["gcounters"][1].as_i64().unwrap()) {
        fails.push(format!("{label}: group counters"));
    }
    let fleets: Vec<Value> = gs.fleets.iter().map(|f| serde_json::json!([f.id, f.zone, f.port, f.landing])).collect();
    if Value::Array(fleets) != w["fleets"] {
        fails.push(format!("{label}: fleets differ"));
    }
}

/// Whole numbers the game keeps as floats compare as integers.
fn normalize(v: &Value) -> Value {
    match v {
        Value::Array(a) => Value::Array(a.iter().map(normalize).collect()),
        Value::Number(n) => match n.as_f64() {
            Some(f) if f.fract() == 0.0 => serde_json::json!(f as i64),
            _ => v.clone(),
        },
        other => other.clone(),
    }
}

fn run(index: usize) -> String {
    let data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/group.json")).unwrap();
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
    compare(&format!("{name} start"), &gs, &snaps[0], &data, &mut fails);
    let mut next = 1;
    for (i, act) in camp["log"].as_array().unwrap().iter().enumerate() {
        let label = format!("{name} step {i} ({})", act.to_string().chars().take(90).collect::<String>());
        let ok = |k: usize| act[k].as_bool().unwrap();
        let ids = |v: &Value| -> Vec<u32> { v.as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as u32).collect() };
        let provs = |v: &Value| -> Vec<usize> { v.as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect() };
        let mut compare_now = false;
        match s(&act[0]) {
            "war" => gs.set_war_goal(s(&act[1]), s(&act[2]), "none", Value::Null),
            "front" => {
                let got = gs.designate_front(&data, s(&act[1]), s(&act[2]), &provs(&act[3]), s(&act[4]), s(&act[5]), act[6].as_u64().unwrap() as usize);
                assert_eq!(got.is_some(), ok(7), "{label}");
                assert_eq!(got.unwrap_or(0) as i64, act[8].as_i64().unwrap(), "{label}");
            }
            "assign" => assert_eq!(gs.assign_to_front(s(&act[1]), act[2].as_u64().unwrap() as u32, &ids(&act[3])), ok(4), "{label}"),
            "cohesion" => assert_eq!(gs.set_front_policy(s(&act[1]), act[2].as_u64().unwrap() as u32, "cohesion", s(&act[3])), ok(4), "{label}"),
            "anchors" => assert_eq!(gs.set_front_anchors(s(&act[1]), act[2].as_u64().unwrap() as u32, &provs(&act[3])), ok(4), "{label}"),
            "setline" => assert_eq!(gs.set_front_line(&data, s(&act[1]), act[2].as_u64().unwrap() as u32, &provs(&act[3])), ok(4), "{label}"),
            "forts" => {
                for (i, p) in provs(&act[1]).iter().enumerate() {
                    if i % 2 == 0 {
                        let list = &mut gs.province_buildings[*p];
                        let level = act[2].as_i64().unwrap() as i32;
                        match list.iter_mut().find(|(k, _)| k == "fortification") {
                            Some(slot) => slot.1 = level,
                            None => list.push(("fortification".to_string(), level)),
                        }
                    }
                }
            }
            "group" => {
                let got = gs.create_army_group(&data, s(&act[1]), s(&act[2]), &ids(&act[3]));
                assert_eq!(got.is_some(), ok(4), "{label}");
                assert_eq!(got.unwrap_or(0) as i64, act[5].as_i64().unwrap(), "{label}");
            }
            "free_general" => assert_eq!(gs.assign_general(s(&act[1]), act[2].as_u64().unwrap() as u32, 0), ok(3), "{label}"),
            "marshal" => assert_eq!(gs.set_marshal(&data, s(&act[1]), act[2].as_u64().unwrap() as u32, act[3].as_u64().unwrap() as u32), ok(4), "{label}"),
            "assign_group" => assert_eq!(gs.assign_to_group(&data, s(&act[1]), act[2].as_u64().unwrap() as u32, &ids(&act[3])), ok(4), "{label}"),
            "disband" => assert_eq!(gs.disband_army_group(&data, s(&act[1]), act[2].as_u64().unwrap() as u32), ok(3), "{label}"),
            "alcreate" => {
                let got = gs.create_attack_line(s(&act[1]), act[2].as_u64().unwrap() as u32, s(&act[3]), act[4].as_u64().unwrap() as u32);
                assert_eq!(got.is_some(), ok(5), "{label}");
                assert_eq!(got.unwrap_or(0) as i64, act[6].as_i64().unwrap(), "{label}");
            }
            "alset" => assert_eq!(gs.set_attack_line(&data, s(&act[1]), act[2].as_u64().unwrap() as u32, ok(3)), ok(4), "{label}"),
            "aldelete" => assert_eq!(gs.delete_attack_line(&data, s(&act[1]), act[2].as_u64().unwrap() as u32), ok(3), "{label}"),
            "peace" => {
                let w = gs.war_between(s(&act[1]), s(&act[2])).unwrap();
                gs.end_war(w);
            }
            "stack" => {
                let first = gs.armies.iter().position(|a| a.id == act[2].as_u64().unwrap() as u32).unwrap();
                let tag = s(&act[1]).to_string();
                let mut others: Vec<usize> = gs.armies.iter().enumerate().filter(|(i, a)| a.tag == tag && *i != first && a.parent_id == 0).map(|(i, _)| i).collect();
                others.truncate(act[3].as_u64().unwrap() as usize);
                let mut moved = vec![];
                for &o in &others {
                    moved.extend(std::mem::take(&mut gs.armies[o].units));
                }
                gs.armies[first].units.extend(moved);
                let gone: Vec<u32> = others.iter().map(|&o| gs.armies[o].id).collect();
                gs.armies.retain(|a| !gone.contains(&a.id));
            }
            "plan" => {
                let got = gs.plan_offensive(&data, s(&act[1]), act[2].as_u64().unwrap() as u32, s(&act[3]), &provs(&act[4]), s(&act[5]), act[6].as_u64().unwrap() as usize);
                assert_eq!(got.is_some(), ok(7), "{label}");
                assert_eq!(got.unwrap_or(0) as i64, act[8].as_i64().unwrap(), "{label}");
            }
            "setoff" => {
                let (tag, id, key) = (s(&act[1]), act[2].as_u64().unwrap() as u32, s(&act[3]));
                let v = &act[4];
                let got = gs.set_offensive(tag, id, key, v.as_bool().unwrap_or(false), v.as_str().unwrap_or(""), &v.as_array().map(|a| a.iter().map(|x| x.as_u64().unwrap() as usize).collect::<Vec<_>>()).unwrap_or_default());
                assert_eq!(got, ok(5), "{label}");
            }
            "delfront" => assert_eq!(gs.delete_front(s(&act[1]), act[2].as_u64().unwrap() as u32), ok(3), "{label}"),
            "order" => assert_eq!(gs.order_army_to(&data, s(&act[1]), act[2].as_u64().unwrap() as u32, act[3].as_u64().unwrap() as usize), ok(4), "{label}"),
            "seize" => {
                for p in act[2].as_array().unwrap() {
                    gs.set_controller(p.as_u64().unwrap() as usize, s(&act[1]));
                }
                gs.recompute(&data);
            }
            "stack" => {
                let first = gs.armies.iter().position(|a| a.id == act[2].as_u64().unwrap() as u32).unwrap();
                let tag = s(&act[1]).to_string();
                let mut others: Vec<usize> = gs.armies.iter().enumerate().filter(|(i, a)| a.tag == tag && *i != first && a.parent_id == 0).map(|(i, _)| i).collect();
                others.truncate(act[3].as_u64().unwrap() as usize);
                let mut moved = vec![];
                for &o in &others {
                    moved.extend(std::mem::take(&mut gs.armies[o].units));
                }
                gs.armies[first].units.extend(moved);
                let gone: Vec<u32> = others.iter().map(|&o| gs.armies[o].id).collect();
                gs.armies.retain(|a| !gone.contains(&a.id));
            }
            "wipe" => {
                let id = act[1].as_u64().unwrap() as u32;
                gs.armies.retain(|a| a.id != id);
            }
            "shot" => compare_now = true,
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
                compare_now = ok(1);
            }
            other => panic!("unknown action {other}"),
        }
        if compare_now {
            compare(&label, &gs, &snaps[next], &data, &mut fails);
            next += 1;
            if !fails.is_empty() {
                break;
            }
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(6).cloned().collect::<Vec<_>>().join("\n"));
    assert_eq!(next, snaps.len(), "{name}: snapshots used");
    name
}

#[test]
fn groups_agree_with_the_gdscript() {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/group.json")).unwrap();
    let n = serde_json::from_str::<Value>(&text).unwrap().as_array().unwrap().len();
    for i in 0..n {
        println!("{}: agrees with the GDScript", run(i));
    }
}
