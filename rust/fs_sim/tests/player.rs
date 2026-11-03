//! A player who plays, in a game the AI plays the rest of: `tests/golden/player.json.gz` is what `tools/dump_player_golden.gd` got out of the real
//! game: a rotation of about twenty kinds of command made through `GameState.issue` for the player's nation (policies, works, units, marches, a
//! declaration of war, treaties, gifts, demands, peace offers, ships and fleets, a focus), and every question put to the player answered. The
//! same commands are replayed on the port, day by day, with the AI's whole turn on, and the world is compared every few days.

mod common;

use common::{bits, close};
use fs_sim::ai_peace::demand_of;
use fs_sim::state::{Data, GameState};
use serde_json::Value;
use std::path::Path;

fn s(v: &Value) -> &str {
    v.as_str().unwrap()
}

fn golden() -> &'static Value {
    static GOLDEN: std::sync::OnceLock<Value> = std::sync::OnceLock::new();
    GOLDEN.get_or_init(|| {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/player.json.gz");
        let mut text = String::new();
        std::io::Read::read_to_string(&mut flate2::read::GzDecoder::new(std::fs::File::open(path).unwrap()), &mut text).unwrap();
        serde_json::from_str(&text).unwrap()
    })
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
            ("treasury", n.treasury, 0), ("prestige", n.prestige, 1), ("war support", n.war_support, 2), ("mobilization", n.mobilization, 3), ("points", n.diplomacy_points, 4),
            ("tax", n.tax_rate, 7), ("investment", n.investment, 8), ("arms share", n.arms_share, 9), ("munitions", n.munitions, 10),
        ] {
            if !close(got, bits(&x[i])) {
                fails.push(format!("{label} {}: {k} {got:e} vs {:e}", n.tag, bits(&x[i])));
            }
        }
        let focus = n.focus.as_ref().map(|f| f.id.clone()).unwrap_or_default();
        let ints = (n.provinces.len() as i64, n.capital, n.population, n.manpower, n.men_in_units, focus, n.construction.len() as i64, n.recruiting.len() as i64, n.shipbuilding.len() as i64);
        let want = (x[5].as_i64().unwrap(), x[6].as_i64().unwrap(), x[11].as_i64().unwrap(), x[12].as_i64().unwrap(), x[13].as_i64().unwrap(), s(&x[14]).to_string(), x[15].as_i64().unwrap(), x[16].as_i64().unwrap(), x[17].as_i64().unwrap());
        if ints != want {
            fails.push(format!("{label} {}: provinces, capital, people, manpower, men, focus, works, recruits, ships {ints:?} vs {want:?}", n.tag));
        }
    }
    let owners: Vec<&str> = gs.province_owner.iter().skip(1).map(|x| x.as_str()).collect();
    let want: Vec<&str> = w["owners"].as_array().unwrap().iter().map(s).collect();
    if owners != want {
        fails.push(format!("{label}: owners differ"));
    }
    let controllers: Vec<&str> = gs.province_controller.iter().skip(1).map(|x| x.as_str()).collect();
    let want: Vec<&str> = w["controllers"].as_array().unwrap().iter().map(s).collect();
    if controllers != want {
        fails.push(format!("{label}: holders differ"));
    }
    let armies: Vec<Value> = gs.armies.iter().map(|a| serde_json::json!([a.id, a.tag, a.province, a.units.len(), a.path, a.front_id, a.fleet_id])).collect();
    let want_armies: Vec<Value> = w["armies"].as_array().unwrap().iter().map(|a| serde_json::json!([a[0], a[1], a[2], a[4], a[5], a[6], a[7]])).collect();
    if norm(&Value::Array(armies.clone())) != norm(&Value::Array(want_armies.clone())) {
        let only_mine: Vec<&Value> = armies.iter().filter(|a| !want_armies.contains(a)).collect();
        let only_want: Vec<&Value> = want_armies.iter().filter(|a| !armies.contains(a)).collect();
        fails.push(format!("{label}: armies differ ({} vs {})\n  only mine {only_mine:?}\n  only want {only_want:?}", armies.len(), want_armies.len()));
    } else {
        for (a, x) in gs.armies.iter().zip(w["armies"].as_array().unwrap()) {
            if !close(a.men(&data_of().military), bits(&x[3])) {
                fails.push(format!("{label}: army {} men", a.id));
            }
        }
    }
    let fleets: Vec<Value> = gs.fleets.iter().map(|f| serde_json::json!([f.id, f.tag, f.port, f.zone, f.ships.len(), f.path, f.mission])).collect();
    if norm(&Value::Array(fleets)) != norm(&w["fleets"]) {
        fails.push(format!("{label}: fleets differ"));
    }
    let wars: Vec<Value> = gs.wars.iter().map(|x| serde_json::json!([x.id, x.a, x.b, x.war_group])).collect();
    if Value::Array(wars) != w["wars"] {
        fails.push(format!("{label}: wars differ"));
    }
    let treaties: Vec<Value> = gs.treaties.iter().map(|t| serde_json::json!([t.id, t.kind, t.a, t.b])).collect();
    if norm(&Value::Array(treaties.clone())) != norm(&w["treaties"]) {
        fails.push(format!("{label}: treaties\n  mine {}\n  want {}", Value::Array(treaties), w["treaties"]));
    }
    let want = w["relations"].as_object().unwrap();
    if want.iter().any(|(k, v)| gs.relations.get(k).map(|x| !close(*x, bits(v))).unwrap_or(true)) || gs.relations.iter().any(|(k, v)| *v != 0.0 && !want.contains_key(k)) {
        fails.push(format!("{label}: opinions differ"));
    }
    if !close(gs.tension, bits(&w["tension"])) {
        fails.push(format!("{label}: tension {:e} vs {:e}", gs.tension, bits(&w["tension"])));
    }
    let crises: Vec<Value> = gs.crises.iter().map(|c| serde_json::json!([c.id, c.kind, c.a, c.b])).collect();
    if norm(&Value::Array(crises)) != norm(&w["crises"]) {
        fails.push(format!("{label}: crises differ"));
    }
    compare_books(label, gs, &w["books"], false, fails);
    let pending = [gs.pending_events.len() as i64, gs.pending_joins.len() as i64, gs.pending_offers.len() as i64];
    if pending.iter().map(|x| *x as f64).collect::<Vec<_>>() != w["pending"].as_array().unwrap().iter().map(|x| x.as_f64().unwrap()).collect::<Vec<_>>() || gs.chronicle.len() as i64 != w["chronicle"].as_i64().unwrap() {
        fails.push(format!("{label}: questions waiting {pending:?} vs {}, chronicle {} vs {}", w["pending"], gs.chronicle.len(), w["chronicle"]));
    }
}

fn b(x: f64) -> Value {
    Value::String((x.to_bits() as i64).to_string())
}

fn war_book(w: &fs_sim::state::War) -> Value {
    let log: Vec<Value> = w.log.iter().map(|e| serde_json::json!([e.date, e.kind, e.text, e.province, e.battle])).collect();
    let battles: Vec<Value> = w
        .battles
        .iter()
        .map(|r| {
            let strength: Vec<Value> = r.strength.iter().map(|(t, v)| serde_json::json!([t, b(*v)])).collect();
            let lost: Vec<Value> = r.lost.iter().map(|(t, v)| serde_json::json!([t, b(*v)])).collect();
            serde_json::json!([r.id, r.province, r.name, r.date, r.end_date, r.days, r.attacker, r.winner, strength, lost])
        })
        .collect();
    let peace = match &w.peace {
        Some(p) => serde_json::json!([p.taker, p.giver, p.terms, p.white, b(p.score), p.forced, p.date]),
        None => Value::Null,
    };
    serde_json::json!([w.id, w.start_date, w.end_date, w.end_day, log, battles, peace])
}

/// The books as the dumper writes them: the last few entries (or all of them with `full`).
fn books(gs: &GameState, full: bool) -> Value {
    let last = |n: usize, len: usize| if full { 0 } else { len.saturating_sub(n) };
    let notes: Vec<Value> = gs.history_log[last(3, gs.history_log.len())..].iter().map(|n| serde_json::json!([n.day, n.date, n.year, n.kind, n.text])).collect();
    let territory: Vec<Value> = gs.territory_log[last(3, gs.territory_log.len())..].iter().map(|n| serde_json::json!([n.day, n.date, n.year, n.province, n.old, n.new])).collect();
    let months: Vec<Value> = gs.history_months[last(2, gs.history_months.len())..]
        .iter()
        .map(|m| serde_json::json!([m.day, m.year, m.month, m.wars, m.battles, b(m.casualties), m.provinces, b(m.tension), m.crises, m.top]))
        .collect();
    let standings: Vec<Value> = gs.standings_history[last(2, gs.standings_history.len())..]
        .iter()
        .map(|r| {
            let vals: Vec<Value> = r.values.iter().map(|(t, v)| serde_json::json!([t, v.iter().map(|x| b(*x)).collect::<Vec<_>>()])).collect();
            serde_json::json!([r.day, r.date, vals])
        })
        .collect();
    serde_json::json!({
        "wars": gs.wars.iter().map(war_book).collect::<Vec<_>>(),
        "past": gs.war_history.iter().map(war_book).collect::<Vec<_>>(),
        "ambition": [gs.ambition.id, gs.ambition.tag, gs.ambition.since, gs.ambition.state],
        "sizes": [gs.history_log.len(), gs.territory_log.len(), gs.history_months.len(), gs.standings_history.len()],
        "notes": notes, "territory": territory, "months": months, "standings": standings,
    })
}

fn compare_books(label: &str, gs: &GameState, want: &Value, full: bool, fails: &mut Vec<String>) {
    let mine = books(gs, full);
    for k in ["sizes", "ambition", "notes", "territory", "months", "standings", "wars", "past"] {
        if norm(&mine[k]) != norm(&want[k]) {
            let detail = match (mine[k].as_array(), want[k].as_array()) {
                (Some(a), Some(w)) => {
                    let at = a.iter().zip(w).position(|(x, y)| norm(x) != norm(y)).unwrap_or(a.len().min(w.len()));
                    format!("({} vs {} entries) first at {at}:\n  mine {}\n  want {}", a.len(), w.len(), a.get(at).map(|v| v.to_string()).unwrap_or_default(), w.get(at).map(|v| v.to_string()).unwrap_or_default())
                }
                _ => format!("{} vs {}", mine[k], want[k]),
            };
            fails.push(format!("{label}: the {k} of the books differ {}", detail.chars().take(900).collect::<String>()));
        }
    }
}

fn data_of() -> &'static Data {
    static DATA: std::sync::OnceLock<Data> = std::sync::OnceLock::new();
    DATA.get_or_init(|| Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap())
}

/// One command of the log, made as `GameState.issue` makes it: carried out, and the economy worked out again.
fn command(gs: &mut GameState, data: &Data, me: &str, e: &[Value]) -> bool {
    let a = e[2].as_array().unwrap();
    let u = |i: usize| a[i].as_u64().unwrap() as usize;
    let ok = match s(&e[1]) {
        "policy" => gs.set_economy_policy(data, me, s(&a[0]), bits(&a[1])),
        "build" => gs.construct_building(data, me, u(0), s(&a[1])),
        "raise" => gs.raise_units(data, me, u(0), s(&a[1]), a[2].as_i64().unwrap()),
        "move" => gs.order_army_to(data, me, u(0) as u32, u(1)),
        "declare" => gs.declare_war_for_points(data, me, s(&a[0]), s(&a[1]), 0).is_empty(),
        "treaty" => gs.propose_treaty(data, me, s(&a[0]), s(&a[1])).ok,
        "improve" => gs.improve_relations(data, me, s(&a[0])).is_empty(),
        "points" => gs.buy_points(data, me),
        "munitions" => gs.buy_munitions(data, me, a[0].as_f64().unwrap()),
        "focus" => gs.focus_start(data, me, s(&a[0])),
        "press" => gs.press_demand(data, me, s(&a[0]), s(&a[1]), None).is_empty(),
        "peace" => {
            let demands = a[2].as_array().unwrap().iter().map(|d| demand_of(d).unwrap()).collect();
            gs.propose_peace_ai(data, me, s(&a[0]), s(&a[1]), demands).ok
        }
        "gift" => gs.gift(data, me, s(&a[0]), a[1].as_f64().unwrap()).is_empty(),
        "ships" => gs.raise_ships(data, me, u(0), s(&a[1]), 1),
        "fleet" => gs.move_fleet(data, me, u(0) as u32, u(1), 0),
        "crisis" => gs.crisis_action(data, me, u(0) as u32, s(&a[1])),
        "ambition" => gs.choose_ambition(data, me, s(&a[0])),
        "demobilize" => gs.demobilize_units(data, me, 0, a[1].as_i64().unwrap()),
        "split" => gs.split_fleet(me, u(0) as u32, &[0]).is_some(),
        "merge" => gs.merge_fleets(me, &a[0].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as u32).collect::<Vec<_>>()),
        "cancel" => gs.cancel_treaty(data, me, u(0) as u32).is_empty(),
        "answer_event" => return gs.answer_event(data, u(0) as u32, u(1)),
        "answer_join" => gs.answer_join(data, u(0) as u32, a[1].as_bool().unwrap()),
        "answer_peace" => gs.answer_offer(data, u(0) as u32, a[1].as_bool().unwrap()),
        other => panic!("unknown command {other}"),
    };
    if ok {
        gs.recompute(data);
    }
    ok
}

fn run(index: usize) {
    let data = data_of();
    let run = &golden()[index];
    let name = s(&run["name"]);
    let me = s(&run["player"]).to_string();
    let mut gs = GameState::load_scenario(data, name).unwrap();
    gs.pressure_ai = run["pressure"].as_bool().unwrap();
    gs.ai_turn = fs_sim::ai_turn::AiTurn::all();
    gs.start_scenario_wars(data);
    gs.player_tag = me.clone();
    let (days, every) = (run["days"].as_u64().unwrap() as usize, run["every"].as_u64().unwrap() as usize);
    let snaps = run["snaps"].as_array().unwrap();
    let log = run["log"].as_array().unwrap();
    let mut at = 0;
    let mut fails = vec![];
    compare(&format!("{name}/{me} day 0"), &gs, &snaps[0], &mut fails);
    for d in 0..days {
        while at < log.len() && log[at][0].as_u64().unwrap() as usize == d {
            let e = log[at].as_array().unwrap();
            at += 1;
            let ok = command(&mut gs, data, &me, e);
            if ok != e[3].as_bool().unwrap() {
                fails.push(format!("{name}/{me} day {d}: {} {} gave {ok}", e[1], e[2]));
            }
        }
        if !fails.is_empty() {
            break;
        }
        gs.advance_day(data);
        if d % every == every - 1 {
            compare(&format!("{name}/{me} day {}", d + 1), &gs, &snaps[d / every + 1], &mut fails);
        }
        if !fails.is_empty() {
            break;
        }
    }
    compare_books(&format!("{name}/{me} the end"), &gs, &run["final"], true, &mut fails);
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(8).cloned().collect::<Vec<_>>().join("\n"));
    println!("{name}/{me}: {days} days and {} commands agree with the GDScript", log.len());
}

#[test]
fn britain_plays_july_1914() {
    run(0);
}

#[test]
fn serbia_plays_july_1914() {
    run(1);
}

#[test]
fn germany_plays_july_1914() {
    run(2);
}

#[test]
fn italy_plays_july_1914() {
    run(3);
}

#[test]
fn france_plays_january_1900() {
    run(4);
}

#[test]
fn russia_plays_january_1900() {
    run(5);
}
