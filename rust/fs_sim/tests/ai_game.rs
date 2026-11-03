//! The whole game, with the AI playing, against the GDScript: `tests/golden/ai_game.json.gz` is what `tools/dump_ai_game_golden.gd` got out of the
//! real game: a scenario loaded, the AI switched on, the clock driven day by day through the game's own stages. The same days are run on the
//! port with the AI's whole turn on, and the nations, the ground, the armies and fleets, the fronts, the wars and treaties, the AI's campaigns,
//! landings and plans are compared every ten days.

mod common;

use common::{bits, close};
use fs_sim::ai_turn::AiTurn;
use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn s(v: &Value) -> &str {
    v.as_str().unwrap()
}

fn norm(v: &Value) -> Value {
    match v {
        Value::Number(n) => serde_json::json!(n.as_f64().unwrap()),
        Value::Array(a) => Value::Array(a.iter().map(norm).collect()),
        Value::Object(o) => Value::Object(o.iter().map(|(k, v)| (k.clone(), norm(v))).collect()),
        x => x.clone(),
    }
}

fn compare(label: &str, gs: &GameState, w: &Value, fails: &mut Vec<String>) {
    if gs.calendar.date_string() != s(&w["date"]) {
        fails.push(format!("{label}: date {} vs {}", gs.calendar.date_string(), w["date"]));
        return;
    }
    for (n, x) in gs.nations.iter().zip(w["nations"].as_array().unwrap()) {
        for (k, got, i) in [
            ("treasury", n.treasury, 0), ("cp", n.cp, 1), ("income", n.budget.income, 2), ("cp a day", n.budget.cp, 3),
            ("naval budget", n.naval_budget, 4), ("points", n.diplomacy_points, 5), ("prestige", n.prestige, 6), ("mobilization", n.mobilization, 7),
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
                if j.started as i64 != wj[3].as_i64().unwrap() {
                    fails.push(format!("{label} {}: project {} {} started {} vs {}", n.tag, j.province, j.kind, j.started, wj[3]));
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
    let armies: Vec<Value> = gs.armies.iter().map(|a| serde_json::json!([a.id, a.tag, a.province, a.units.len(), a.path, a.front_id, a.pin, a.parent_id, a.fleet_id])).collect();
    let want_armies: Vec<Value> = w["armies"].as_array().unwrap().iter().map(|a| serde_json::json!([a[0], a[1], a[2], a[4], a[9], a[6], a[7], a[8], a[11]])).collect();
    if armies != want_armies {
        let only_mine: Vec<&Value> = armies.iter().filter(|a| !want_armies.contains(a)).collect();
        let only_want: Vec<&Value> = want_armies.iter().filter(|a| !armies.contains(a)).collect();
        fails.push(format!("{label}: armies differ ({} vs {})\n  only mine {only_mine:?}\n  only want {only_want:?}", armies.len(), want_armies.len()));
    }
    let rec: Vec<Value> = gs.nations.iter().map(|n| Value::Array(n.recruiting.iter().map(|j| serde_json::json!([j.unit_type, j.province, j.days_left])).collect())).collect();
    if norm(&Value::Array(rec)) != norm(&w["recruiting"]) {
        fails.push(format!("{label}: units in training {} vs {}", serde_json::Value::Array(gs.nations.iter().map(|n| Value::Array(n.recruiting.iter().map(|j| serde_json::json!([j.unit_type, j.province, j.days_left])).collect())).collect()), w["recruiting"]));
    }
    let men: Vec<Value> = gs.nations.iter().map(|n| serde_json::json!([n.manpower, n.men_in_units])).collect();
    if norm(&Value::Array(men)) != norm(&w["manpower"]) {
        fails.push(format!("{label}: manpower, men under arms differ"));
    }
    let wars: Vec<Value> = gs.wars.iter().map(|x| serde_json::json!([x.id, x.a, x.b])).collect();
    if Value::Array(wars) != w["wars"] {
        fails.push(format!("{label}: wars differ"));
    }
    let mut amb: Vec<(String, String, i64)> = gs.ai_ambition.iter().map(|(k, v)| (k.clone(), v.0.clone(), v.1)).collect();
    amb.sort();
    let mut want_amb: Vec<(String, String, i64)> = w["ambition"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), s(&v["target"]).to_string(), v["since"].as_i64().unwrap())).collect();
    want_amb.sort();
    let mut wait: Vec<(String, i64)> = gs.ai_ambition_wait.iter().map(|(k, v)| (k.clone(), *v)).collect();
    wait.sort();
    let mut want_wait: Vec<(String, i64)> = w["ambition_wait"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_i64().unwrap())).collect();
    want_wait.sort();
    if amb != want_amb || wait != want_wait {
        fails.push(format!("{label}: ambitions {amb:?} {wait:?} vs {want_amb:?} {want_wait:?}"));
    }
    let fronts: Vec<Value> = gs.fronts.iter().map(|f| serde_json::json!([f.id, f.tag, f.against, f.provinces, f.anchors, f.army_ids])).collect();
    if norm(&Value::Array(fronts.clone())) != norm(&w["fronts"]) {
        fails.push(format!("{label}: fronts\n  mine {}\n  want {}", Value::Array(fronts), w["fronts"]));
    }
    let mut reserve: Vec<(String, u32)> = gs.ai_reserve.iter().map(|(k, v)| (k.clone(), *v)).collect();
    reserve.sort();
    let mut want_reserve: Vec<(String, u32)> = w["reserve"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_u64().unwrap() as u32)).collect();
    want_reserve.sort();
    let mut stamps: Vec<(u32, i64)> = gs.ai_anchor_stamp.iter().map(|(k, v)| (*k, *v)).collect();
    stamps.sort();
    let mut want_stamps: Vec<(u32, i64)> = w["anchor_stamp"].as_object().unwrap().iter().map(|(k, v)| (k.parse().unwrap(), v.as_i64().unwrap())).collect();
    want_stamps.sort();
    if reserve != want_reserve || stamps != want_stamps {
        fails.push(format!("{label}: reserves {reserve:?} stamps {stamps:?} vs {want_reserve:?} {want_stamps:?}"));
    }
    let treaties: Vec<Value> = gs.treaties.iter().map(|t| serde_json::json!([t.id, t.kind, t.a, t.b, t.start_day, t.end_day])).collect();
    if norm(&Value::Array(treaties.clone())) != norm(&w["treaties"]) {
        fails.push(format!("{label}: treaties\n  mine {}\n  want {}", Value::Array(treaties), w["treaties"]));
    }
    let crises: Vec<Value> = gs.crises.iter().map(|c| serde_json::json!([c.id, c.kind, c.a, c.b])).collect();
    let cbs: Vec<Value> = gs.casus_belli.iter().map(|c| serde_json::json!([c.holder, c.target, c.kind])).collect();
    if norm(&Value::Array(crises.clone())) != norm(&w["crises"]) || norm(&Value::Array(cbs.clone())) != norm(&w["cbs"]) {
        fails.push(format!("{label}: crises {} {} vs {} {}", Value::Array(crises), Value::Array(cbs), w["crises"], w["cbs"]));
    }
    if (gs.ai_declarations.0 as i64, gs.ai_declarations.1 as i64) != (w["declarations"][0].as_i64().unwrap(), w["declarations"][1].as_i64().unwrap()) {
        fails.push(format!("{label}: declarations {:?} vs {}", gs.ai_declarations, w["declarations"]));
    }
    for (what, mine, want) in [("relations", &gs.relations, &w["relations"]), ("grievance", &gs.grievance, &w["grievance"])] {
        let want = want.as_object().unwrap();
        if want.iter().any(|(k, v)| mine.get(k).map(|x| !close(*x, bits(v))).unwrap_or(true)) || mine.iter().any(|(k, v)| *v != 0.0 && !want.contains_key(k)) {
            fails.push(format!("{label}: {what} differ"));
        }
    }
    let controllers: Vec<&str> = gs.province_controller.iter().skip(1).map(|x| x.as_str()).collect();
    let want_controllers: Vec<&str> = w["controllers"].as_array().unwrap().iter().map(s).collect();
    if controllers != want_controllers {
        fails.push(format!("{label}: holders differ"));
    }
    let camp = |c: &fs_sim::ai_offense::Campaign| serde_json::json!([c.enemy, c.target, c.staging, c.armies, if c.advancing { "advance" } else { "gather" }, c.started]);
    let mut camps: Vec<Value> = vec![];
    let mut tags: Vec<&String> = gs.ai_campaign.keys().collect();
    tags.sort();
    for t in &tags {
        let c = &gs.ai_campaign[*t];
        camps.push(serde_json::json!([t, "main", c.enemy, c.target, c.staging, c.armies, if c.advancing { "advance" } else { "gather" }, c.started]));
    }
    let mut extra_tags: Vec<&String> = gs.ai_campaign_extra.keys().collect();
    extra_tags.sort();
    for t in extra_tags {
        for c in &gs.ai_campaign_extra[t] {
            camps.push(serde_json::json!([t, "extra", c.enemy, c.target, c.staging, c.armies, if c.advancing { "advance" } else { "gather" }, c.started]));
        }
    }
    let mut want_camps: Vec<Value> = w["campaigns"].as_array().unwrap().clone();
    let key = |v: &Value| format!("{}{}{}", v[0], v[1], v[2]);
    camps.sort_by_key(|v| key(v));
    want_camps.sort_by_key(|v| key(v));
    if norm(&Value::Array(camps.clone())) != norm(&Value::Array(want_camps.clone())) {
        fails.push(format!("{label}: campaigns\n  mine {}\n  want {}", Value::Array(camps), Value::Array(want_camps)));
    }
    let mut wait: Vec<(String, i64)> = gs.ai_campaign_wait.iter().map(|(k, v)| (k.clone(), *v)).collect();
    wait.sort();
    let mut want_wait: Vec<(String, i64)> = w["campaign_wait"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_i64().unwrap())).collect();
    want_wait.sort();
    if wait != want_wait {
        fails.push(format!("{label}: campaign waits {wait:?} vs {want_wait:?}"));
    }
    let lines: Vec<Value> = gs.attack_lines.iter().map(|l| serde_json::json!([l.id, l.active, l.wait, match &l.campaign { Some(c) => serde_json::json!([c.enemy, c.target, c.staging, c.armies, if c.advancing { "advance" } else { "gather" }, c.started, c.done]), None => serde_json::json!([]) }])).collect();
    if norm(&Value::Array(lines.clone())) != norm(&w["lines"]) {
        fails.push(format!("{label}: attack lines\n  mine {}\n  want {}", Value::Array(lines), w["lines"]));
    }
    let _ = camp;
    let fleets: Vec<Value> = gs.fleets.iter().map(|f| serde_json::json!([f.id, f.tag, f.name, f.port, f.zone, f.ships.iter().map(|s| serde_json::json!([s.kind, s.strength, s.morale])).collect::<Vec<_>>(), f.path, f.dest_port, f.mission, f.landing, f.days_out, f.entering, f.fighting, f.retreating])).collect();
    let want_fleets: Vec<Value> = w["fleets_ai"].as_array().unwrap().iter().map(|f| {
        let ships: Vec<Value> = f[5].as_array().unwrap().iter().map(|s| serde_json::json!([s[0], bits(&s[1]), bits(&s[2])])).collect();
        serde_json::json!([f[0], f[1], f[2], f[3], f[4], ships, f[6], f[7], f[8], f[9], f[10], f[11], f[12], f[13]])
    }).collect();
    if norm(&Value::Array(fleets.clone())) != norm(&Value::Array(want_fleets.clone())) {
        let at = fleets.iter().zip(&want_fleets).position(|(a, b)| norm(a) != norm(b));
        fails.push(format!("{label}: fleets differ ({} vs {}), first at {at:?}\n  mine {:?}\n  want {:?}", fleets.len(), want_fleets.len(), at.map(|i| &fleets[i]), at.map(|i| &want_fleets[i])));
    }
    let mut mem: Vec<(String, Vec<(u32, usize)>)> = gs.ai_navy.iter().map(|(k, v)| { let mut e: Vec<(u32, usize)> = v.iter().map(|(a, b)| (*a, *b)).collect(); e.sort(); (k.clone(), e) }).filter(|x| !x.1.is_empty()).collect();
    mem.sort();
    let mut want_mem: Vec<(String, Vec<(u32, usize)>)> = w["navy_mem"].as_object().unwrap().iter().map(|(k, v)| { let mut e: Vec<(u32, usize)> = v.as_object().unwrap().iter().map(|(a, b)| (a.parse().unwrap(), b.as_u64().unwrap() as usize)).collect(); e.sort(); (k.clone(), e) }).filter(|x| !x.1.is_empty()).collect();
    want_mem.sort();
    if mem != want_mem {
        fails.push(format!("{label}: fleets' stations {mem:?} vs {want_mem:?}"));
    }
    let mut lands: Vec<Value> = gs.ai_landing.iter().map(|(k, l)| serde_json::json!([k, l.enemy, l.target, l.port, l.fleet, l.armies, l.phase, l.started, l.zone])).collect();
    lands.sort_by_key(|v| v[0].to_string());
    let mut want_lands: Vec<Value> = w["landings"].as_object().unwrap().iter().map(|(k, l)| serde_json::json!([k, l[0], l[1], l[2], l[3], l[4], l[5], l[6], l[7]])).collect();
    want_lands.sort_by_key(|v| v[0].to_string());
    let mut lwait: Vec<(String, i64)> = gs.ai_landing_wait.iter().map(|(k, v)| (k.clone(), *v)).collect();
    lwait.sort();
    let mut want_lwait: Vec<(String, i64)> = w["landing_wait"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_i64().unwrap())).collect();
    want_lwait.sort();
    let mut need: Vec<(String, String)> = gs.ai_navy_need.iter().map(|(k, v)| (k.clone(), v.clone())).collect();
    need.sort();
    let mut want_need: Vec<(String, String)> = w["navy_need"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), s(v).to_string())).collect();
    want_need.sort();
    if norm(&Value::Array(lands.clone())) != norm(&Value::Array(want_lands.clone())) || lwait != want_lwait || need != want_need {
        fails.push(format!("{label}: landings {} {lwait:?} {need:?} vs {} {want_lwait:?} {want_need:?}", Value::Array(lands), Value::Array(want_lands)));
    }
    let yards: Vec<Value> = gs.nations.iter().map(|n| Value::Array(n.shipbuilding.iter().map(|j| serde_json::json!([j.kind, j.province, j.days_left])).collect())).collect();
    if norm(&Value::Array(yards.clone())) != norm(&w["yards"]) {
        fails.push(format!("{label}: ships on the slips {} vs {}", Value::Array(yards), w["yards"]));
    }
    let want_plans: Value = serde_json::from_str(s(&w["plans"])).unwrap();
    if norm(&Value::Array(gs.ai_plans.clone())) != norm(&want_plans) {
        fails.push(format!("{label}: plans {} vs {}", Value::Array(gs.ai_plans.clone()), want_plans));
    }
    if !close(gs.tension, bits(&w["tension"])) {
        fails.push(format!("{label}: tension {:e} vs {:e}", gs.tension, bits(&w["tension"])));
    }
}

/// The golden file, read once for all the tests.
fn golden() -> &'static Value {
    static GOLDEN: std::sync::OnceLock<Value> = std::sync::OnceLock::new();
    GOLDEN.get_or_init(|| {
        let path = std::env::var("AI_GOLDEN").unwrap_or(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/ai_game.json.gz").to_string());
        let text = if path.ends_with(".gz") {
            let mut text = String::new();
            std::io::Read::read_to_string(&mut flate2::read::GzDecoder::new(std::fs::File::open(&path).unwrap()), &mut text).unwrap();
            text
        } else {
            std::fs::read_to_string(&path).unwrap()
        };
        serde_json::from_str(&text).unwrap()
    })
}

fn run(index: usize) {
    let all = golden();
    let run = &all[index];
    let name = s(&run["name"]);
    let mut data = Data::load_with_difficulty(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data"), s(&run["difficulty"])).unwrap();
    fn merge(dst: &mut Value, src: &Value) {
        for (k, v) in src.as_object().unwrap() {
            if v.is_object() && dst.get(k).map(Value::is_object).unwrap_or(false) {
                merge(&mut dst[k], v);
            } else {
                dst[k] = v.clone();
            }
        }
    }
    for (section, keys) in run["ai_cfg"].as_object().unwrap() {
        merge(&mut data.ai.raw[section], keys);
    }
    data.ai.diplomacy = data.ai.raw["diplomacy"].clone();
    let mut gs = GameState::load_scenario(&data, name).unwrap();
    gs.pressure_ai = run["pressure"].as_bool().unwrap();
    gs.ai_turn = AiTurn::all();
    gs.start_scenario_wars(&data);
    gs.player_tag = s(&run["player"]).to_string();
    for w in run["wars"].as_array().unwrap() {
        gs.start_war(&data, s(&w[0]), s(&w[1]), true);
    }
    for st in run["setup"].as_array().unwrap() {
        let got = gs.designate_front(&data, s(&st[0]), &format!("Front {}", s(&st[1])), &[], s(&st[1]), "line", 0).is_some();
        assert_eq!(got, st[2].as_bool().unwrap(), "front of {} against {}", st[0], st[1]);
    }
    for o in run["orders"].as_array().unwrap() {
        let ok = gs.order_army_to(&data, s(&o[0]), o[1].as_u64().unwrap() as u32, o[2].as_u64().unwrap() as usize);
        assert_eq!(ok, o[3].as_bool().unwrap(), "{name}: order {o}");
    }
    for g in run["groups"].as_array().unwrap() {
        let ids: Vec<u32> = g[2].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as u32).collect();
        let gid = gs.create_army_group(&data, s(&g[0]), s(&g[1]), &ids);
        assert_eq!(gid.is_some(), g[3].as_bool().unwrap(), "{name}: group {g}");
        let lid = gs.create_attack_line(s(&g[0]), gid.unwrap_or(0), s(&g[9]), g[8].as_u64().unwrap() as u32);
        assert_eq!(lid.is_some(), g[5].as_bool().unwrap(), "{name}: line {g}");
        let set = gs.set_attack_line(&data, s(&g[0]), lid.unwrap_or(0), true);
        assert_eq!(set, g[7].as_bool().unwrap(), "{name}: switching the line on {g}");
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
        // Saved and loaded at every snapshot: the game goes on from the loaded copy.
        gs = fs_sim::save::from_bytes(&fs_sim::save::to_bytes(&gs).unwrap()).unwrap();
        if !fails.is_empty() {
            break;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(8).cloned().collect::<Vec<_>>().join("\n"));
    println!("{name}/{}: {} days agree with the GDScript", s(&run["player"]), (snaps.len() - 1) * every);
}

#[test]
fn serbia_in_july_1914() {
    run(0);
}

#[test]
fn britain_in_july_1914() {
    run(1);
}

#[test]
fn germany_in_january_1900() {
    run(2);
}

#[test]
fn the_united_states_in_january_1900() {
    run(3);
}

#[test]
fn germany_in_july_1914_to_1922() {
    run(4);
}

#[test]
fn russia_in_july_1914_to_1922() {
    run(5);
}

#[test]
fn italy_in_july_1914_to_1922() {
    run(6);
}

#[test]
fn austria_in_july_1914_to_1922() {
    run(7);
}

#[test]
fn france_in_january_1900_to_1912() {
    run(8);
}

#[test]
fn russia_in_january_1900_to_1912() {
    run(9);
}

#[test]
fn britain_in_january_1900_to_1912() {
    run(10);
}

#[test]
fn britain_in_july_1914_challenging() {
    run(11);
}

#[test]
fn germany_in_july_1914_sandbox() {
    run(12);
}

#[test]
fn france_in_january_1900_challenging() {
    run(13);
}

#[test]
fn russia_in_january_1900_sandbox() {
    run(14);
}
