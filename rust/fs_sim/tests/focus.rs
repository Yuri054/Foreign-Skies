//! The national focus against the GDScript one: `tests/golden/focus.json` is what `tools/dump_focus_golden.gd` got out of
//! the real `Focus` and `Economy` over eighteen months of every nation working through its tree, and out of effects applied
//! by hand.

use fs_sim::config::FocusEffects;
use fs_sim::state::{CasusBelli, Data, GameState};
use serde_json::Value;
use std::path::Path;

fn bits(v: &Value) -> f64 {
    f64::from_bits(v.as_str().unwrap().parse::<i64>().unwrap() as u64)
}

fn close(a: f64, b: f64, rel: f64) -> bool {
    a == b || (a - b).abs() <= rel * a.abs().max(b.abs())
}

const REL: f64 = 1e-13;

fn data() -> Data {
    Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap()
}

fn golden() -> Value {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/focus.json")).unwrap();
    serde_json::from_str(&text).unwrap()
}

fn set_relations(gs: &mut GameState, relations: &Value) {
    gs.relations.clear();
    for (k, v) in relations.as_object().unwrap() {
        gs.relations.insert(k.clone(), bits(v));
    }
}

fn compare_snapshot(label: &str, gs: &GameState, snap: &Value, fails: &mut Vec<String>) {
    for (i, w) in snap["nations"].as_array().unwrap().iter().enumerate() {
        let n = &gs.nations[i];
        let tag = w["tag"].as_str().unwrap();
        assert_eq!(n.tag, tag);
        let focus = match &n.focus {
            Some(f) => (f.id.clone(), f.days_left, f.days_total),
            None => (String::new(), 0, 0),
        };
        let want = (w["focus"][0].as_str().unwrap().to_string(), w["focus"][1].as_i64().unwrap(), w["focus"][2].as_i64().unwrap());
        if focus != want {
            fails.push(format!("{label} {tag}: focus {focus:?} vs {want:?}"));
        }
        let done: Vec<&str> = w["done"].as_array().unwrap().iter().map(|x| x.as_str().unwrap()).collect();
        if n.focus_done.iter().map(String::as_str).collect::<Vec<_>>() != done {
            fails.push(format!("{label} {tag}: foci done {:?} vs {done:?}", n.focus_done));
        }
        let mut counts: Vec<(String, i64)> = w["count"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_i64().unwrap())).collect();
        let mut mine = n.focus_count.clone();
        counts.sort();
        mine.sort();
        if mine != counts {
            fails.push(format!("{label} {tag}: counts {mine:?} vs {counts:?}"));
        }
        // the lasting bonuses: a key the game never set is nothing here
        let fx = w["fx"].as_object().unwrap();
        for (k, got) in [
            ("gdp", n.focus_fx.gdp), ("industry", n.focus_fx.industry), ("food", n.focus_fx.food), ("trade", n.focus_fx.trade),
            ("growth", n.focus_fx.growth), ("diplomacy", n.focus_diplomacy), ("construction", n.focus_construction),
        ] {
            let want = fx.get(k).map(bits).unwrap_or(0.0);
            if !close(got, want, REL) {
                fails.push(format!("{label} {tag}: focus_fx.{k} {got:e} vs {want:e}"));
            }
        }
        for k in fx.keys() {
            if !["gdp", "industry", "food", "trade", "growth", "diplomacy", "construction"].contains(&k.as_str()) {
                fails.push(format!("{label} {tag}: the game has a focus bonus {k} the port does not know"));
            }
        }
        for (k, got) in [
            ("treasury", n.treasury), ("war_support", n.war_support), ("prestige", n.prestige), ("points", n.diplomacy_points),
        ] {
            if !close(got, bits(&w[k]), REL) {
                fails.push(format!("{label} {tag}: {k} {got:e} vs {:e}", bits(&w[k])));
            }
        }
        for (k, got) in [("peacetime_army", n.peacetime_army), ("manpower", n.manpower)] {
            if got != w[k].as_i64().unwrap() {
                fails.push(format!("{label} {tag}: {k} {got} vs {}", w[k]));
            }
        }
        if let Some(x) = w.get("development") {
            if !close(n.development, bits(x), REL) || !close(n.budget.net, bits(&w["net"]), REL) {
                fails.push(format!("{label} {tag}: development or net budget"));
            }
        }
    }
    let rel = snap["relations"].as_object().unwrap();
    if gs.relations.len() != rel.len() {
        fails.push(format!("{label}: {} relations vs {}", gs.relations.len(), rel.len()));
    }
    for (k, v) in rel {
        match gs.relations.get(k) {
            Some(got) if close(*got, bits(v), REL) => {}
            other => fails.push(format!("{label}: relation {k} {other:?} vs {:e}", bits(v))),
        }
    }
    let claims: Vec<CasusBelli> = snap["claims"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| CasusBelli {
            holder: c[0].as_str().unwrap().to_string(),
            target: c[1].as_str().unwrap().to_string(),
            kind: c[2].as_str().unwrap().to_string(),
            expires_day: c[3].as_i64().unwrap(),
        })
        .collect();
    if gs.casus_belli != claims {
        fails.push(format!("{label}: claims {:?} vs {claims:?}", gs.casus_belli));
    }
}

fn run(name: &str) {
    let (data, g) = (data(), golden());
    let w = &g[name];
    let mut gs = GameState::load_scenario(&data, name).unwrap();
    set_relations(&mut gs, &w["relations0"]);
    let starts = w["starts"].as_array().unwrap();
    let mut next = 0;
    let mut fails = vec![];
    let mut day = 0;
    for (m, snap) in w["months"].as_array().unwrap().iter().enumerate() {
        for _ in 0..30 {
            // each nation without a focus takes the first one of its tree it may
            while next < starts.len() && starts[next][0].as_i64().unwrap() == day {
                let (tag, id) = (starts[next][1].as_str().unwrap(), starts[next][2].as_str().unwrap());
                assert_eq!(gs.focus_block(&data, tag, id), "", "{name} day {day}: {tag} may not take {id}");
                assert!(gs.focus_start(&data, tag, id));
                next += 1;
            }
            gs.step_day(&data);
            gs.focus_step_day(&data);
            gs.finish_economy_stage(&data);
            gs.calendar.advance_day();
            day += 1;
        }
        gs.step_month(&data);
        compare_snapshot(&format!("{name} month {}", m + 1), &gs, snap, &mut fails);
        if !fails.is_empty() {
            break;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(15).cloned().collect::<Vec<_>>().join("\n"));
    println!("{name}: {} months of every nation working through its focus tree agree with the GDScript ({} foci started)", w["months"].as_array().unwrap().len(), starts.len());
}

#[test]
fn every_nation_works_through_its_focus_tree_in_july_1914() {
    run("july_1914");
}

#[test]
fn every_nation_works_through_its_focus_tree_in_january_1900() {
    run("jan_1900");
}

fn effects_from_json(v: &Value) -> FocusEffects {
    let f = |k: &str| v.get(k).and_then(Value::as_f64);
    FocusEffects {
        gdp: f("gdp"),
        industry: f("industry"),
        food: f("food"),
        trade: f("trade"),
        growth: f("growth"),
        diplomacy: f("diplomacy"),
        construction: f("construction"),
        prestige: f("prestige"),
        points: f("points"),
        treasury: f("treasury"),
        war_support: f("war_support"),
        army_size: f("army_size"),
        relation: v.get("relation").and_then(Value::as_array).map(|a| a.iter().map(|p| (p[0].as_str().unwrap().to_string(), p[1].as_f64().unwrap())).collect()).unwrap_or_default(),
        claim: v.get("claim").and_then(Value::as_array).map(|a| a.iter().map(|x| x.as_str().unwrap().to_string()).collect()).unwrap_or_default(),
    }
}

#[test]
fn effects_applied_by_hand() {
    let (data, g) = (data(), golden());
    let w = &g["direct"];
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    set_relations(&mut gs, &w["relations0"]);
    gs.calendar.days_elapsed = w["days"].as_i64().unwrap() as i32;
    for e in w["effects"].as_array().unwrap() {
        gs.apply_focus_effects(&data, e[0].as_str().unwrap(), &effects_from_json(&e[1]));
    }
    let mut fails = vec![];
    compare_snapshot("direct", &gs, &w["after"], &mut fails);
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(15).cloned().collect::<Vec<_>>().join("\n"));
    println!("direct: effects applied by hand (claims, army growth, relations past their limits, points past the maximum) agree");
}
