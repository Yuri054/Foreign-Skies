//! Diplomacy against the GDScript one: `tests/golden/diplomacy.json` is what `tools/dump_diplomacy_golden.gd` got out of the
//! real `Diplomacy` (and the economy under it): the treaties, relations and rivalries a scenario loads with, and then a year
//! and a half of mobilization, alarms, call-ups, points, projects, prestige, grievance, gifts and the drift of opinion.

use fs_sim::state::{CasusBelli, Data, GameState, RelationProject};
use serde_json::Value;
use std::collections::HashMap;
use std::path::Path;

fn bits(v: &Value) -> f64 {
    f64::from_bits(v.as_str().unwrap().parse::<i64>().unwrap() as u64)
}

fn close(a: f64, b: f64) -> bool {
    a == b || (a - b).abs() <= 1e-13 * a.abs().max(b.abs())
}

fn data() -> Data {
    Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap()
}

fn golden() -> Value {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/diplomacy.json")).unwrap();
    serde_json::from_str(&text).unwrap()
}

fn compare_map(label: &str, what: &str, mine: &HashMap<String, f64>, want: &Value, fails: &mut Vec<String>) {
    let want = want.as_object().unwrap();
    if mine.len() != want.len() {
        let mut extra: Vec<&String> = mine.keys().filter(|k| !want.contains_key(*k)).collect();
        let mut missing: Vec<&String> = want.keys().filter(|k| !mine.contains_key(k.as_str())).collect();
        extra.sort();
        missing.sort();
        fails.push(format!("{label}: {what} has {} entries vs {} (extra {:?}, missing {:?})", mine.len(), want.len(), extra, missing));
    }
    for (k, v) in want {
        match mine.get(k) {
            Some(x) if close(*x, bits(v)) => {}
            other => fails.push(format!("{label}: {what}[{k}] {other:?} vs {:e}", bits(v))),
        }
    }
}

fn compare_snapshot(label: &str, gs: &GameState, snap: &Value, fails: &mut Vec<String>) {
    for (i, w) in snap["nations"].as_array().unwrap().iter().enumerate() {
        let n = &gs.nations[i];
        let tag = w["tag"].as_str().unwrap();
        assert_eq!(n.tag, tag);
        for (k, got) in [
            ("mobilization", n.mobilization), ("points", n.diplomacy_points), ("prestige", n.prestige),
            ("points_price", n.points_price), ("war_support", n.war_support), ("treasury", n.treasury), ("net", n.budget.net),
        ] {
            if !close(got, bits(&w[k])) {
                fails.push(format!("{label} {tag}: {k} {got:e} vs {:e}", bits(&w[k])));
            }
        }
        for (k, got) in [("manpower", n.manpower), ("men_in_units", n.men_in_units)] {
            if got != w[k].as_i64().unwrap() {
                fails.push(format!("{label} {tag}: {k} {got} vs {}", w[k]));
            }
        }
    }
    compare_map(label, "relations", &gs.relations, &snap["relations"], fails);
    compare_map(label, "relation_base", &gs.relation_base, &snap["relation_base"], fails);
    compare_map(label, "grievance", &gs.grievance, &snap["grievance"], fails);
    compare_map(label, "rivalries", &gs.rivalries, &snap["rivalries"], fails);
    compare_map(label, "gift_memory", &gs.gift_memory, &snap["gifts"], fails);
    let alarms: HashMap<String, i64> = snap["alarms"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_i64().unwrap())).collect();
    if gs.alarms != alarms {
        fails.push(format!("{label}: alarms {:?} vs {alarms:?}", gs.alarms));
    }
    let calls = snap["calls"].as_object().unwrap();
    if gs.mobilization_calls.len() != calls.len() {
        fails.push(format!("{label}: {} call-ups vs {}", gs.mobilization_calls.len(), calls.len()));
    }
    for (k, c) in calls {
        let want = (c[0].as_str().unwrap(), c[1].as_str().unwrap(), c[2].as_str().unwrap(), c[3].as_i64().unwrap());
        match gs.mobilization_calls.get(k) {
            Some(m) if (m.tag.as_str(), m.for_tag.as_str(), m.against.as_str(), m.day) == want => {}
            other => fails.push(format!("{label}: call-up {k} {other:?} vs {want:?}")),
        }
    }
    let projects: Vec<RelationProject> = snap["projects"].as_array().unwrap().iter().map(|p| RelationProject { from: p[0].as_str().unwrap().to_string(), to: p[1].as_str().unwrap().to_string(), months_left: p[2].as_i64().unwrap() }).collect();
    if gs.relation_projects != projects {
        fails.push(format!("{label}: projects {:?} vs {projects:?}", gs.relation_projects));
    }
    let cbs: Vec<CasusBelli> = snap["cbs"].as_array().unwrap().iter().map(|c| CasusBelli { holder: c[0].as_str().unwrap().to_string(), target: c[1].as_str().unwrap().to_string(), kind: c[2].as_str().unwrap().to_string(), expires_day: c[3].as_i64().unwrap() }).collect();
    if gs.casus_belli != cbs {
        fails.push(format!("{label}: casus belli {:?} vs {cbs:?}", gs.casus_belli));
    }
}

fn run(name: &str) {
    let (data, g) = (data(), golden());
    let w = &g[name];
    let mut gs = GameState::load_scenario(&data, name).unwrap();
    let mut fails = vec![];

    // what the scenario loads with
    let start = &w["start"];
    let treaties = start["treaties"].as_array().unwrap();
    if gs.treaties.len() != treaties.len() {
        fails.push(format!("{name}: {} treaties vs {}", gs.treaties.len(), treaties.len()));
    }
    for (t, want) in gs.treaties.iter().zip(treaties) {
        let terms: Value = serde_json::from_str(want[6].as_str().unwrap()).unwrap();
        let ok = t.id as i64 == want[0].as_i64().unwrap() && t.kind == want[1].as_str().unwrap() && t.a == want[2].as_str().unwrap()
            && t.b == want[3].as_str().unwrap() && t.start_day == want[4].as_i64().unwrap() && t.end_day == want[5].as_i64().unwrap()
            && t.terms == terms && t.note == want[7].as_str().unwrap();
        if !ok {
            fails.push(format!("{name}: treaty {t:?} vs {want}"));
        }
    }
    if gs.next_treaty_id as i64 != start["next_treaty_id"].as_i64().unwrap() {
        fails.push(format!("{name}: next treaty id"));
    }
    compare_map(name, "start relations", &gs.relations, &start["relations"], &mut fails);
    compare_map(name, "start relation_base", &gs.relation_base, &start["relation_base"], &mut fails);
    compare_map(name, "start rivalries", &gs.rivalries, &start["rivalries"], &mut fails);
    assert!(fails.is_empty(), "{} differences at the start, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));

    // pressure on the system
    let spec = &w["spec"];
    for (tag, v) in spec["mobilization"].as_object().unwrap() {
        let i = gs.nation_index[tag.as_str()];
        gs.nations[i].mobilization = v.as_f64().unwrap();
    }
    for p in spec["projects"].as_array().unwrap() {
        gs.relation_projects.push(RelationProject { from: p["from"].as_str().unwrap().to_string(), to: p["to"].as_str().unwrap().to_string(), months_left: p["months_left"].as_i64().unwrap() });
    }
    for (k, v) in spec["gifts"].as_object().unwrap() {
        gs.gift_memory.insert(k.clone(), v.as_f64().unwrap());
    }
    for cb in spec["cbs"].as_array().unwrap() {
        gs.casus_belli.push(CasusBelli { holder: cb["holder"].as_str().unwrap().to_string(), target: cb["target"].as_str().unwrap().to_string(), kind: cb["kind"].as_str().unwrap().to_string(), expires_day: cb["expires_day"].as_i64().unwrap() });
    }
    for (k, v) in spec["rivalries"].as_object().unwrap() {
        gs.rivalries.insert(k.clone(), v.as_f64().unwrap());
    }
    for (k, v) in spec["grievance"].as_object().unwrap() {
        gs.grievance.insert(k.clone(), v.as_f64().unwrap());
    }
    for (k, v) in spec["prestige"].as_object().unwrap() {
        let i = gs.nation_index[k.as_str()];
        gs.nations[i].prestige = v.as_f64().unwrap();
    }
    for (k, v) in spec["points_price"].as_object().unwrap() {
        let i = gs.nation_index[k.as_str()];
        gs.nations[i].points_price = v.as_f64().unwrap();
    }
    gs.recompute(&data);

    let months = w["months"].as_array().unwrap();
    for (m, snap) in months.iter().enumerate() {
        for _ in 0..30 {
            gs.step_day(&data);
            gs.diplomacy_step_day(&data);
            gs.calendar.advance_day();
        }
        gs.step_month(&data);
        gs.diplomacy_step_month(&data);
        compare_snapshot(&format!("{name} month {}", m + 1), &gs, snap, &mut fails);
        if !fails.is_empty() {
            break;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(15).cloned().collect::<Vec<_>>().join("\n"));
    println!("{name}: {} treaties and {} opinions loaded, and {} months of diplomacy agree with the GDScript", treaties.len(), gs.relations.len(), months.len());
}

#[test]
fn july_1914_diplomacy() {
    run("july_1914");
}

#[test]
fn january_1900_diplomacy() {
    run("jan_1900");
}

#[test]
fn war_support_at_war() {
    let (data, g) = (data(), golden());
    let w = &g["war_support"];
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    for e in w["spec"].as_array().unwrap() {
        let i = gs.nation_index[e["tag"].as_str().unwrap()];
        let n = &mut gs.nations[i];
        for (k, v) in e.as_object().unwrap() {
            match k.as_str() {
                "tag" => {}
                "mobilization" => n.mobilization = bits(v),
                "tax_rate" => n.tax_rate = bits(v),
                "men_lost_month" => n.men_lost_month = bits(v),
                "war_support" => n.war_support = bits(v),
                "treasury" => n.treasury = bits(v),
                "blockade" => n.blockade = bits(v),
                other => panic!("the golden spec sets {other}"),
            }
        }
    }
    for p in w["wars"].as_array().unwrap() {
        gs.wars.push((p[0].as_str().unwrap().to_string(), p[1].as_str().unwrap().to_string()));
    }
    for c in w["controllers"].as_array().unwrap() {
        gs.set_controller(c[0].as_u64().unwrap() as usize, c[1].as_str().unwrap());
    }
    gs.recompute(&data);
    let mut fails = vec![];
    // what moves each nation's support this month, cause by cause, in the game's order
    for (tag, list) in w["changes"].as_object().unwrap() {
        let got = gs.war_support_changes(&data, tag);
        let want = list.as_array().unwrap();
        if got.len() != want.len() {
            fails.push(format!("{tag}: {} causes vs {}", got.len(), want.len()));
            continue;
        }
        for ((name, v), w) in got.iter().zip(want) {
            if *name != w[0].as_str().unwrap() || !close(*v, bits(&w[1])) {
                fails.push(format!("{tag}: {name} {v:e} vs {} {:e}", w[0], bits(&w[1])));
            }
        }
    }
    gs.war_support_step_month(&data);
    compare_snapshot("war support", &gs, &w["after"], &mut fails);
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(15).cloned().collect::<Vec<_>>().join("\n"));
    println!("war_support: the month's changes and step at war agree with the GDScript");
}
