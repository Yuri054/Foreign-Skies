//! The navy against the GDScript: `tests/golden/navy.json` is what `tools/dump_navy_golden.gd` got out of the real `Navy`,
//! `NavalCombat` and `Blockade`: fleets sailing, meeting and fighting, being repaired and worn down, ships being built, armies
//! carried and landed from the sea, and the grip on the sea that blockades a nation. The days run in the game's order (economy,
//! navy, army); after each action or few days everything that matters is compared.

mod common;

use common::{bits, close};
use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn s(v: &Value) -> &str {
    v.as_str().unwrap()
}

fn eq(fails: &mut Vec<String>, label: &str, what: &str, mine: String, want: String) {
    // the same JSON in another key order is the same
    let same = match (serde_json::from_str::<Value>(&mine), serde_json::from_str::<Value>(&want)) {
        (Ok(a), Ok(b)) => a == b,
        _ => false,
    };
    if mine != want && !same {
        fails.push(format!("{label}: {what}\n    mine {mine}\n    want {want}"));
    }
}

fn compare(label: &str, gs: &GameState, data: &Data, w: &Value, fails: &mut Vec<String>) {
    eq(fails, label, "day", gs.calendar.days_elapsed.to_string(), w["day"].to_string());
    let want_fleets = w["fleets"].as_array().unwrap();
    eq(fails, label, "number of fleets", gs.fleets.len().to_string(), want_fleets.len().to_string());
    let mut floats: Vec<(String, f64, f64)> = vec![];
    for (f, x) in gs.fleets.iter().zip(want_fleets) {
        let mine = serde_json::json!([f.id, f.tag, f.name, f.zone, f.port, f.path, f.dest_port, x[7], f.entering, f.landing, f.mission, f.fighting, f.engaged, f.retreating, f.days_out]);
        let want = serde_json::json!([x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7], x[8], x[9], x[10], x[11], x[12], x[13], x[14]]);
        eq(fails, label, &format!("fleet {}", f.id), mine.to_string(), want.to_string());
        floats.push((format!("fleet {} move days", f.id), f.move_days_left, bits(&x[7])));
        let ships = x[15].as_array().unwrap();
        eq(fails, label, &format!("fleet {} ships", f.id), f.ships.len().to_string(), ships.len().to_string());
        for (sh, y) in f.ships.iter().zip(ships) {
            if sh.kind != s(&y[0]) {
                fails.push(format!("{label}: fleet {} ship {} vs {}", f.id, sh.kind, y[0]));
            }
            floats.push((format!("fleet {} {} strength", f.id, sh.kind), sh.strength, bits(&y[1])));
            floats.push((format!("fleet {} {} morale", f.id, sh.kind), sh.morale, bits(&y[2])));
        }
    }
    let want_control = w["control"].as_array().unwrap();
    eq(fails, label, "zones held", gs.sea_control.len().to_string(), want_control.len().to_string());
    for ((zone, c), x) in gs.sea_control.iter().zip(want_control) {
        eq(fails, label, &format!("zone {zone}"), serde_json::json!([zone, c.holders, c.contested]).to_string(), serde_json::json!([x[0], x[1], x[2]]).to_string());
        for (tag, p) in &c.power {
            floats.push((format!("zone {zone} power of {tag}"), *p, bits(&x[3][tag])));
        }
    }
    for (what, mine, want) in [("battles", &gs.sea_battles.iter().map(|(_, b)| b).collect::<Vec<_>>(), &w["battles"]), ("archive", &gs.sea_battle_archive.iter().collect::<Vec<_>>(), &w["archive"])] {
        let want = want.as_array().unwrap();
        eq(fails, label, &format!("number of {what}"), mine.len().to_string(), want.len().to_string());
        for (b, x) in mine.iter().zip(want) {
            let start: serde_json::Map<String, Value> = b.start_ships.iter().map(|(t, n)| (t.clone(), serde_json::json!(n))).collect();
            let sunk: serde_json::Map<String, Value> = b.sunk.iter().map(|(t, n)| (t.clone(), serde_json::json!(n))).collect();
            let a = serde_json::json!([b.id, b.zone, b.start_day, b.days, b.fleets, start, sunk, b.winner, b.active]);
            let c = serde_json::json!([x[0], x[1], x[2], x[3], x[4], x[5], x[7], x[8], x[9]]);
            eq(fails, label, &format!("{what} {}", b.id), a.to_string(), c.to_string());
            for (t, l) in &b.lost {
                floats.push((format!("{what} {} lost by {t}", b.id), *l, bits(&x[6][t])));
            }
            eq(fails, label, &format!("{what} {} lost tags", b.id), b.lost.len().to_string(), x[6].as_object().unwrap().len().to_string());
        }
    }
    for (n, x) in gs.nations.iter().zip(w["nations"].as_array().unwrap()) {
        eq(fails, label, &format!("{} blockade by", n.tag), format!("{:?}", n.blockade_by), format!("{:?}", x[3].as_array().unwrap().iter().map(|t| s(t).to_string()).collect::<Vec<_>>()));
        eq(fails, label, &format!("{} ships", n.tag), format!("{} {} {}", n.ships_lost, n.shipbuilding.len(), n.manpower), format!("{} {} {}", x[4], x[5], x[10]));
        for (k, got, i) in [("blockade", n.blockade, 0), ("blockade target", n.blockade_target, 1), ("blockade applied", n.blockade_applied, 2), ("treasury", n.treasury, 6), ("net", n.budget.net, 7), ("men lost", n.men_lost_month, 8), ("deaths", n.deaths_month, 9)] {
            floats.push((format!("{} {k}", n.tag), got, bits(&x[i])));
        }
    }
    let want_armies = w["armies"].as_array().unwrap();
    eq(fails, label, "number of armies", gs.armies.len().to_string(), want_armies.len().to_string());
    for (a, x) in gs.armies.iter().zip(want_armies) {
        let mine = serde_json::json!([a.id, a.tag, a.province, a.fleet_id, a.path.len(), a.landing_days, a.landed_supply, a.attacking, a.fighting, a.supplied]);
        let want = serde_json::json!([x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7], x[8], x[9]]);
        eq(fails, label, &format!("army {}", a.id), mine.to_string(), want.to_string());
        floats.push((format!("army {} men", a.id), a.men(&data.military), bits(&x[10])));
    }
    for (wr, x) in gs.wars.iter().zip(w["wars"].as_array().unwrap()) {
        eq(fails, label, &format!("war {}", wr.id), wr.last_fight_day.to_string(), x[2].to_string());
        for (t, l) in &wr.losses {
            floats.push((format!("war {} losses of {t}", wr.id), *l, bits(&x[3][t])));
        }
    }
    eq(fails, label, "counters", format!("{} {} {}", gs.next_fleet_id, gs.next_battle_id, gs.budget_dirty), format!("{} {} {}", w["counters"][0], w["counters"][1], w["counters"][2]));
    for (what, got, want) in floats {
        if !close(got, want) {
            fails.push(format!("{label}: {what} {got:e} vs {want:e}"));
        }
    }
}

fn run(index: usize) -> (String, usize) {
    let data = Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap();
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/navy.json")).unwrap();
    let all: Value = serde_json::from_str(&text).unwrap();
    let camp = &all[index];
    let name = s(&camp["name"]).to_string();
    let mut gs = GameState::load_scenario(&data, "july_1914").unwrap();
    gs.starting_wars.clear();
    gs.player_tag = s(&camp["player"]).to_string();
    gs.recompute(&data);
    let snaps = camp["snaps"].as_array().unwrap();
    let mut fails = vec![];
    compare(&format!("{name} start"), &gs, &data, &snaps[0], &mut fails);
    let mut next = 1;
    for (i, act) in camp["log"].as_array().unwrap().iter().enumerate() {
        let label = format!("{name} step {i} ({})", act.to_string().chars().take(80).collect::<String>());
        let mut shot = true;
        let ok = |k: usize| act[k].as_bool().unwrap();
        let u = |k: usize| act[k].as_u64().unwrap() as usize;
        match s(&act[0]) {
            "war" => gs.set_war_goal(s(&act[1]), s(&act[2]), "none", Value::Null),
            "peace" => {
                let w = gs.war_between(s(&act[1]), s(&act[2])).unwrap();
                gs.end_war(w);
            }
            "move" => assert_eq!(gs.move_fleet(&data, s(&act[1]), u(2) as u32, u(3), u(4)), ok(5), "{label}"),
            "mission" => assert_eq!(gs.set_fleet_mission(s(&act[1]), u(2) as u32, s(&act[3])), ok(4), "{label}"),
            "raise" => assert_eq!(gs.raise_ships(&data, s(&act[1]), u(2), s(&act[3]), u(4)), ok(5), "{label}"),
            "order" => assert_eq!(gs.order_army_to(&data, s(&act[1]), u(2) as u32, u(3)), ok(4), "{label}"),
            "embark" => assert_eq!(gs.embark_army(&data, s(&act[1]), u(2) as u32, u(3) as u32), ok(4), "{label}"),
            "disembark" => assert_eq!(gs.disembark_army(&data, s(&act[1]), u(2) as u32, u(3)), ok(4), "{label}"),
            "send" => {
                let ids: Vec<u32> = act[3].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as u32).collect();
                assert_eq!(gs.send_overseas(&data, s(&act[1]), u(2) as u32, &ids, u(4)), ok(5), "{label}");
            }
            "spawn" => {
                let fi = gs.new_fleet(s(&act[1]), s(&act[3]), u(2));
                for _ in 0..u(5) {
                    let mut sh = fs_sim::state::Ship::new(s(&act[4]));
                    sh.strength = act[6].as_f64().unwrap();
                    gs.fleets[fi].ships.push(sh);
                }
            }
            "control" => {
                gs.set_controller(u(1), s(&act[2]));
                gs.recompute(&data);
            }
            "pin" => {
                let ni = gs.nation_index[s(&act[1])];
                gs.nations[ni].blockade_pinned = act[2].as_f64().unwrap();
            }
            "weaken" => {
                let fi = gs.fleet_index(u(2) as u32).unwrap();
                gs.fleets[fi].ships[u(3)].strength = act[4].as_f64().unwrap();
            }
            "rush" => {
                let ni = gs.nation_index[s(&act[1])];
                for j in &mut gs.nations[ni].shipbuilding {
                    j.points_left = act[2].as_f64().unwrap();
                }
            }
            "shot" => {}
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
                shot = ok(1);
            }
            other => panic!("unknown action {other}"),
        }
        // a "shot" entry follows every action; days carry their own flag
        if matches!(s(&act[0]), "day") && !shot {
            continue;
        }
        if matches!(s(&act[0]), "shot") || (s(&act[0]) == "day" && shot) {
            compare(&label, &gs, &data, &snaps[next], &mut fails);
            next += 1;
            if !fails.is_empty() {
                break;
            }
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(10).cloned().collect::<Vec<_>>().join("\n"));
    assert_eq!(next, snaps.len(), "{name}: snapshots used");
    (name, snaps.len())
}

#[test]
fn the_navy_agrees_with_the_gdscript() {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/navy.json")).unwrap();
    let n = serde_json::from_str::<Value>(&text).unwrap().as_array().unwrap().len();
    for i in 0..n {
        let (name, shots) = run(i);
        println!("{name}: {shots} snapshots agree with the GDScript");
    }
}
