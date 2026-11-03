//! Historical pressure against the GDScript one: `tests/golden/pressure.json` is what `tools/dump_pressure_golden.gd` got out of
//! the real `Pressure` (with the economy and diplomacy month by month): the events that come up over years, the ones the player
//! is asked and how they answer, public stands, and Europe's tension.

use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::collections::HashMap;
use std::path::Path;

fn bits(v: &Value) -> f64 {
    f64::from_bits(v.as_str().unwrap().parse::<i64>().unwrap() as u64)
}

fn close(a: f64, b: f64) -> bool {
    a == b || (a - b).abs() <= 0.0 * a.abs().max(b.abs())
}

fn data() -> Data {
    Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap()
}

fn golden() -> Value {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/pressure.json")).unwrap();
    serde_json::from_str(&text).unwrap()
}

fn compare_map(label: &str, what: &str, mine: &HashMap<String, f64>, want: &Value, fails: &mut Vec<String>) {
    let want = want.as_object().unwrap();
    if mine.len() != want.len() {
        fails.push(format!("{label}: {what} has {} entries vs {}", mine.len(), want.len()));
    }
    for (k, v) in want {
        match mine.get(k) {
            Some(x) if close(*x, bits(v)) => {}
            other => fails.push(format!("{label}: {what}[{k}] {other:?} vs {:e}", bits(v))),
        }
    }
}

fn compare_month(label: &str, gs: &GameState, snap: &Value, fails: &mut Vec<String>) {
    for (k, got) in [("tension", gs.tension), ("impulse", gs.tension_impulse), ("arms_base", gs.tension_arms_base), ("bonus", gs.tension_bonus)] {
        if !close(got, bits(&snap[k])) {
            fails.push(format!("{label}: {k} {got:e} vs {:e}", bits(&snap[k])));
        }
    }
    let fired: HashMap<String, i64> = snap["fired"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_i64().unwrap())).collect();
    if gs.events_fired != fired {
        fails.push(format!("{label}: events fired {:?} vs {fired:?}", gs.events_fired));
    }
    let pending = snap["pending"].as_array().unwrap();
    if gs.pending_events.len() != pending.len() {
        fails.push(format!("{label}: {} events waiting vs {}", gs.pending_events.len(), pending.len()));
    }
    for (d, w) in gs.pending_events.iter().zip(pending) {
        let roles: Vec<(String, String)> = w[4].as_array().unwrap().iter().map(|r| (r[0].as_str().unwrap().to_string(), r[1].as_str().unwrap().to_string())).collect();
        let labels: Vec<String> = w[5].as_array().unwrap().iter().map(|x| x.as_str().unwrap().to_string()).collect();
        let mine: Vec<String> = d.options.iter().map(|o| o["label"].as_str().unwrap().to_string()).collect();
        let ok = d.id as i64 == w[0].as_i64().unwrap() && d.event == w[1].as_str().unwrap() && d.title == w[2].as_str().unwrap() && d.text == w[3].as_str().unwrap()
            && d.roles == roles && mine == labels && d.as_b == w[6].as_bool().unwrap() && d.deferred.len() as i64 == w[7].as_i64().unwrap() && d.date == w[8].as_str().unwrap();
        if !ok {
            fails.push(format!("{label}: waiting event {} {:?} vs {w}", d.id, d.event));
        }
    }
    let chronicle: Vec<(String, String, String)> = snap["chronicle"].as_array().unwrap().iter().map(|c| (c[0].as_str().unwrap().to_string(), c[1].as_str().unwrap().to_string(), c[2].as_str().unwrap().to_string())).collect();
    if gs.chronicle != chronicle {
        fails.push(format!("{label}: chronicle {:?} vs {chronicle:?}", gs.chronicle.first()));
    }
    if gs.tension_history.len() as i64 != snap["history_len"].as_i64().unwrap() || !close(*gs.tension_history.last().unwrap(), bits(&snap["history_last"])) {
        fails.push(format!("{label}: tension history"));
    }
    if gs.next_event_uid as i64 != snap["next_uid"].as_i64().unwrap() {
        fails.push(format!("{label}: next event id"));
    }
    if gs.treaties.len() as i64 != snap["treaties"].as_i64().unwrap() {
        fails.push(format!("{label}: {} treaties vs {}", gs.treaties.len(), snap["treaties"]));
    }
    let ready: HashMap<String, i64> = snap["appeal_ready"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_i64().unwrap())).collect();
    if gs.appeal_ready != ready {
        fails.push(format!("{label}: appeal_ready {:?} vs {ready:?}", gs.appeal_ready));
    }
    for (i, r) in snap["nations"].as_array().unwrap().iter().enumerate() {
        let n = &gs.nations[i];
        for (k, got, want) in [("prestige", n.prestige, &r[0]), ("treasury", n.treasury, &r[1]), ("war_support", n.war_support, &r[2]), ("mobilization", n.mobilization, &r[3]), ("points", n.diplomacy_points, &r[5])] {
            if !close(got, bits(want)) {
                fails.push(format!("{label} {}: {k} {got:e} vs {:e}", n.tag, bits(want)));
            }
        }
        if n.manpower != r[4].as_i64().unwrap() {
            fails.push(format!("{label} {}: manpower {} vs {}", n.tag, n.manpower, r[4]));
        }
    }
    if let Some(rel) = snap.get("relations") {
        compare_map(label, "relations", &gs.relations, rel, fails);
        compare_map(label, "relation_base", &gs.relation_base, &snap["relation_base"], fails);
    }
}

fn run(name: &str) {
    let (data, g) = (data(), golden());
    let w = &g[name];
    let mut gs = GameState::load_scenario(&data, w["scenario"].as_str().unwrap()).unwrap();
    gs.player_tag = w["player"].as_str().unwrap().to_string();
    let mut fails = vec![];
    let start = &w["start"];
    for (k, got) in [("tension", gs.tension), ("impulse", gs.tension_impulse), ("arms_base", gs.tension_arms_base), ("bonus", gs.tension_bonus)] {
        if !close(got, bits(&start[k])) {
            fails.push(format!("{name} start: {k} {got:e} vs {:e}", bits(&start[k])));
        }
    }
    if gs.pressure_ai != start["pressure_ai"].as_bool().unwrap() || gs.pressure_start != start["pressure_start"].as_i64().unwrap() {
        fails.push(format!("{name} start: pressure_ai or start month"));
    }
    compare_map(name, "start relations", &gs.relations, &start["relations"], &mut fails);
    assert!(fails.is_empty(), "{}", fails.join("\n"));

    let answers = w["answers"].as_array().unwrap();
    let appeals = w["appeals"].as_array().unwrap();
    let (mut ai, mut pi) = (0, 0);
    let months = w["months"].as_array().unwrap();
    for (m, snap) in months.iter().enumerate() {
        loop {
            if gs.calendar.advance_day().new_month {
                break;
            }
        }
        gs.step_month(&data);
        gs.diplomacy_step_month(&data);
        gs.pressure_step_month(&data);
        while pi < appeals.len() && appeals[pi][0].as_i64().unwrap() == (m + 1) as i64 {
            let a = &appeals[pi];
            let ok = gs.appeal(&data, a[1].as_str().unwrap(), a[2].as_str().unwrap());
            assert_eq!(ok, a[3].as_bool().unwrap(), "{name} month {}: appeal {a}", m + 1);
            pi += 1;
        }
        while ai < answers.len() && answers[ai][0].as_i64().unwrap() == (m + 1) as i64 {
            let a = &answers[ai];
            let ok = gs.answer_event(&data, a[1].as_u64().unwrap() as u32, a[2].as_u64().unwrap() as usize);
            assert_eq!(ok, a[3].as_bool().unwrap(), "{name} month {}: answer {a}", m + 1);
            ai += 1;
        }
        compare_month(&format!("{name} month {}", m + 1), &gs, snap, &mut fails);
        if !fails.is_empty() {
            break;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));
    println!("{name}: {} months, {} events fired, {} answers, {} appeals agree with the GDScript", months.len(), gs.events_fired.len(), answers.len(), appeals.len());
}

#[test]
fn july_1914_with_france() {
    run("july_fra");
}

#[test]
fn july_1914_with_serbia() {
    run("july_srb");
}

#[test]
fn january_1900_with_germany() {
    run("jan_ger");
}

#[test]
fn january_1900_with_serbia() {
    run("jan_srb");
}

#[test]
fn january_1900_with_belgium() {
    run("jan_bel");
}

use fs_sim::military::{Army, Unit};
use fs_sim::pressure::Roles;

fn roles_of(v: &Value) -> Roles {
    v.as_object().unwrap().iter().map(|(k, x)| (k.clone(), x.as_str().unwrap().to_string())).collect()
}

#[test]
fn tension_under_strain() {
    let (data, g) = (data(), golden());
    let w = &g["strain"];
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    gs.player_tag = "POR".to_string();
    for (tag, v) in w["mobilization"].as_object().unwrap() {
        let i = gs.nation_index[tag.as_str()];
        gs.nations[i].mobilization = v.as_f64().unwrap();
    }
    for tag in ["GER", "FRA", "AUH", "SRB"] {
        let i = gs.nation_index[tag];
        gs.nations[i].war_support = w["war_support"].as_f64().unwrap();
    }
    let tag = w["extra_army_tag"].as_str().unwrap();
    let province = gs.nation(tag).provinces[0];
    let id = gs.next_army_id;
    gs.next_army_id += 1;
    gs.armies.push(Army {
        id,
        tag: tag.to_string(),
        name: "Extra".to_string(),
        province,
        units: (0..w["extra_units"].as_i64().unwrap()).map(|_| Unit::new("infantry", 1.0)).collect(),
        general_skill: 1.0,
        landing_days: 0,
        path: vec![],
        move_days_left: 0.0,
        still_days: 0,
        attacking: false,
        fighting: false,
        supplied: true,
        landed_supply: 0,
        fleet_id: 0,
        general_id: 0,
        front_id: 0,
        parent_id: 0,
        pin: 0,
        prepared: false,
        planning: 0.0,
        group_id: 0,
        marshal: 1.0,
        training: false,
    });
    for p in w["wars"].as_array().unwrap() {
        gs.set_war(p[0].as_str().unwrap(), p[1].as_str().unwrap());
    }
    gs.recompute(&data);
    let mut fails = vec![];
    let mut seen_parts = (false, false, false);
    for (m, snap) in w["months"].as_array().unwrap().iter().enumerate() {
        while !gs.calendar.advance_day().new_month {}
        gs.step_month(&data);
        gs.diplomacy_step_month(&data);
        gs.pressure_step_month(&data);
        let parts = gs.tension_parts(&data);
        seen_parts = (seen_parts.0 || parts.arms > 0.0, seen_parts.1 || parts.mobilization > 0.0, seen_parts.2 || parts.wars > 0.0);
        compare_month(&format!("strain month {}", m + 1), &gs, snap, &mut fails);
        if !fails.is_empty() {
            break;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));
    assert_eq!(seen_parts, (true, true, true), "the arms race, mobilization and the wars should all have moved tension");
    println!("strain: 7 months of tension with an arms race, mobilization and two wars agree");
}

#[test]
fn who_the_events_turn_to() {
    let (data, g) = (data(), golden());
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    let mut state = String::new();
    let mut fails = vec![];
    let mut count = 0;
    for c in g["picks"].as_array().unwrap() {
        let (st, player, sel, want) = (c[0].as_str().unwrap(), c[1].as_str().unwrap(), c[2].as_str().unwrap(), c[3].as_str().unwrap());
        if st != state {
            state = st.to_string();
            gs = GameState::load_scenario(&data, "july_1914").unwrap();
            if st == "tied" {
                for t in ["GBR", "FRA", "GER"] {
                    let i = gs.nation_index[t];
                    gs.nations[i].men_in_units = 900000;
                }
            }
            if st == "troubled" {
                for (t, v) in [("AUH", 30.0), ("OTT", 35.0), ("RUS", 30.0)] {
                    let i = gs.nation_index[t];
                    gs.nations[i].war_support = v;
                }
            }
        }
        gs.player_tag = player.to_string();
        let got = gs.pick_role(&data, sel);
        if got != want {
            fails.push(format!("{st} player {player}: {sel} -> {got:?} vs {want:?}"));
        }
        count += 1;
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));
    println!("picks: {count} roles agree");
}

#[test]
fn effects_at_the_extremes() {
    let (data, g) = (data(), golden());
    let w = &g["direct_effects"];
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    gs.player_tag = "POR".to_string();
    let roles = roles_of(&w["roles"]);
    let mut fails = vec![];
    for (i, step) in w["list"].as_array().unwrap().iter().enumerate() {
        gs.apply_effect(&data, &step["fx"], &roles);
        compare_month(&format!("effect {i} {}", step["fx"]), &gs, &step["after"], &mut fails);
        let (rel, base) = (gs.relations.get("FRA|GER").copied().unwrap_or(0.0), gs.relation_base.get("FRA|GER").copied().unwrap_or(0.0));
        if !close(rel, bits(&step["rel"])) || !close(base, bits(&step["base"])) {
            fails.push(format!("effect {i} {}: relation {rel} base {base} vs {} {}", step["fx"], bits(&step["rel"]), bits(&step["base"])));
        }
        let grievance = gs.grievance.get("GER>FRA").copied().unwrap_or(-1.0);
        if !close(grievance, step["grievance"].as_f64().unwrap()) {
            fails.push(format!("effect {i} {}: grievance {grievance} vs {}", step["fx"], step["grievance"]));
        }
        if !fails.is_empty() {
            break;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));
    println!("effects: {} effects at the extremes agree", w["list"].as_array().unwrap().len());
}

#[test]
fn events_that_choose_by_tension() {
    let (data, g) = (data(), golden());
    let mut fails = vec![];
    let mut done = 0;
    for c in g["choices"].as_array().unwrap() {
        if c["wars"].as_i64().unwrap() > 0 {
            continue; // the game starts a war here, which the port cannot yet
        }
        let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
        gs.player_tag = "POR".to_string();
        gs.tension_impulse = c["impulse"].as_f64().unwrap();
        gs.update_tension(&data);
        gs.post_event_by_id(&data, c["event"].as_str().unwrap(), roles_of(&c["roles"]));
        let label = format!("{} at impulse {}", c["event"], c["impulse"]);
        compare_month(&label, &gs, &c["after"], &mut fails);
        compare_map(&label, "relations", &gs.relations, &c["relations"], &mut fails);
        done += 1;
    }
    assert!(done >= 3, "only {done} cases ran");
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));
    println!("choices: {done} events that choose by tension agree");
}

#[test]
fn event_conditions_in_different_worlds() {
    let (data, g) = (data(), golden());
    let mut fails = vec![];
    let mut count = 0;
    let mut state = String::new();
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    for c in g["conditions"].as_array().unwrap() {
        let (st, id, want) = (c[0].as_str().unwrap(), c[1].as_str().unwrap(), c[2].as_bool().unwrap());
        if st != state {
            state = st.to_string();
            gs = GameState::load_scenario(&data, "july_1914").unwrap();
            gs.player_tag = "POR".to_string();
            for token in st.split('+') {
                match token {
                    "tense" => gs.tension = 70.0,
                    "calm" => gs.tension = 5.0,
                    "notai" => gs.pressure_ai = false,
                    "hostile" | "friendly" => {
                        let great = ["GBR", "FRA", "GER", "RUS", "AUH", "ITA"];
                        for a in great {
                            for b in great {
                                if a < b {
                                    gs.relations.insert(format!("{a}|{b}"), if token == "hostile" { -80.0 } else { 80.0 });
                                }
                            }
                        }
                    }
                    "late" => gs.pressure_start -= 100,
                    "war" => {
                        gs.set_war("GER", "FRA");
                        gs.set_war("AUH", "SRB");
                    }
                    "minor" => gs.player_tag = "SRB".to_string(),
                    "great" => gs.player_tag = "GER".to_string(),
                    _ => {}
                }
            }
        }
        let e = data.pressure.events.iter().find(|e| e["id"].as_str() == Some(id)).unwrap();
        let got = gs.condition_ok(&data, e);
        if got != want {
            fails.push(format!("{st}: {id} may come up: {got} vs {want}"));
        }
        count += 1;
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));
    println!("conditions: {count} (event, world) cases agree");
}
