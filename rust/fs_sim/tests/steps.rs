//! The Rust economy over time against the GDScript one: `tests/golden/steps.json` is what `tools/dump_steps_golden.gd` got
//! out of `Economy.step_day` (thirty times) and `Economy.step_month`, month after month, on a loaded scenario.

use fs_sim::economy::new_job;
use fs_sim::state::{Data, GameState, Nation};
use serde_json::Value;
use std::path::Path;

fn bits(v: &Value) -> f64 {
    f64::from_bits(v.as_str().unwrap().parse::<i64>().unwrap() as u64)
}

fn data() -> Data {
    Data::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap()
}

fn golden() -> Value {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/steps.json")).unwrap();
    serde_json::from_str(&text).unwrap()
}

/// Queues the golden's projects as the dumper did: onto the end of the queue, or the head for `front`, and hulls onto the
/// slips.
fn give_jobs(gs: &mut GameState, jobs: &Value) {
    for j in jobs.as_array().unwrap() {
        let i = gs.nation_index[j["tag"].as_str().unwrap()];
        let job = new_job(j["province"].as_u64().unwrap() as usize, j["type"].as_str().unwrap(), j["days"].as_i64().unwrap() as i32);
        if j.get("ship").is_some() {
            gs.nations[i].shipbuilding.push(job);
        } else if j.get("front").is_some() {
            gs.nations[i].construction.insert(0, job);
        } else {
            gs.nations[i].construction.push(job);
        }
    }
}

fn apply_spec(gs: &mut GameState, spec: &Value) {
    for e in spec.as_array().unwrap() {
        let n = &mut gs.nations[gs.nation_index[e["tag"].as_str().unwrap()]];
        for (k, v) in e.as_object().unwrap() {
            match k.as_str() {
                "tag" => {}
                "mobilization" => n.mobilization = bits(v),
                "treasury" => n.treasury = bits(v),
                "cp" => n.cp = bits(v),
                "blockade" => n.blockade = bits(v),
                "war_support" => n.war_support = bits(v),
                "deaths_month" => n.deaths_month = bits(v),
                "war_dead" => n.war_dead = bits(v),
                "men_exercising" => n.men_exercising = v.as_i64().unwrap(),
                "manpower" => n.manpower = v.as_i64().unwrap(),
                "peacetime_army" => n.peacetime_army = v.as_i64().unwrap(),
                "focus_fx" => {
                    n.focus_income = v.get("income").map(bits).unwrap_or(0.0);
                    n.focus_cp = v.get("cp").map(bits).unwrap_or(0.0);
                }
                other => panic!("the golden spec sets {other}, which the test does not know"),
            }
        }
    }
}

fn compare_month(label: &str, month: usize, gs: &GameState, row: &Value, fails: &mut Vec<String>) {
    for (i, w) in row.as_array().unwrap().iter().enumerate() {
        let n: &Nation = &gs.nations[i];
        let tag = w["tag"].as_str().unwrap();
        assert_eq!(n.tag, tag);
        let st = &w["state"];
        for (k, got) in [
            ("treasury", n.treasury), ("cp", n.cp), ("war_support", n.war_support), ("war_dead", n.war_dead),
            ("deaths_month", n.deaths_month), ("mobilization", n.mobilization), ("naval_budget", n.naval_budget),
        ] {
            if got != bits(&st[k]) {
                fails.push(format!("{label} month {month} {tag}: {k} {got:e} vs {:e}", bits(&st[k])));
            }
        }
        for (k, got) in [
            ("manpower", n.manpower), ("men_in_units", n.men_in_units), ("peacetime_army", n.peacetime_army),
            ("population", n.population),
        ] {
            if got != st[k].as_i64().unwrap() {
                fails.push(format!("{label} month {month} {tag}: {k} {got} vs {}", st[k]));
            }
        }
        let b = &n.budget;
        let wb = &w["budget"];
        for (k, got) in [
            ("base", b.base), ("factories", b.factories), ("ports", b.ports), ("occupied", b.occupied), ("income", b.income),
            ("administration", b.administration), ("army", b.army), ("navy", b.navy), ("buildings", b.buildings),
            ("interest", b.interest), ("expenses", b.expenses), ("net", b.net), ("cp", b.cp),
            ("manpower_pool", b.manpower_pool), ("manpower_max", b.manpower_max),
        ] {
            if got != bits(&wb[k]) {
                fails.push(format!("{label} month {month} {tag}: budget {k} {got:e} vs {:e}", bits(&wb[k])));
            }
        }
        let jobs = w["jobs"].as_array().unwrap();
        if n.construction.len() != jobs.len() {
            fails.push(format!("{label} month {month} {tag}: jobs {} vs {}", n.construction.len(), jobs.len()));
        } else {
            for (j, t) in n.construction.iter().zip(jobs) {
                let ok = j.province as u64 == t[0].as_u64().unwrap()
                    && j.kind == t[1].as_str().unwrap()
                    && j.started as i64 == t[2].as_i64().unwrap()
                    && j.days_total as i64 == t[3].as_i64().unwrap()
                    && j.days_left as i64 == t[4].as_i64().unwrap();
                if !ok {
                    fails.push(format!("{label} month {month} {tag}: job {j:?} vs {t}"));
                }
            }
        }
        let ships = w["ships"].as_array().unwrap();
        if n.shipbuilding.len() != ships.len() {
            fails.push(format!("{label} month {month} {tag}: ships {} vs {}", n.shipbuilding.len(), ships.len()));
        } else {
            for (j, t) in n.shipbuilding.iter().zip(ships) {
                if j.province as u64 != t[0].as_u64().unwrap() || j.kind != t[1].as_str().unwrap() || j.days_left as i64 != t[2].as_i64().unwrap() {
                    fails.push(format!("{label} month {month} {tag}: ship {j:?} vs {t}"));
                }
            }
        }
    }
}

fn compare_end(label: &str, gs: &GameState, end: &Value, fails: &mut Vec<String>) {
    for (i, p) in end["population"].as_array().unwrap().iter().enumerate() {
        let id = i + 1;
        if gs.province_population[id] as i64 != p.as_i64().unwrap() {
            fails.push(format!("{label}: province {id} people {} vs {p}", gs.province_population[id]));
        }
        if gs.province_pop_frac[id] as f64 != bits(&end["frac"][i]) {
            fails.push(format!("{label}: province {id} fraction {} vs {}", gs.province_pop_frac[id], bits(&end["frac"][i])));
        }
        let b: Vec<(String, i64)> = end["buildings"][i].as_array().unwrap().iter().map(|x| (x[0].as_str().unwrap().to_string(), x[1].as_i64().unwrap())).collect();
        let mine: Vec<(String, i64)> = gs.province_buildings[id].iter().map(|(k, l)| (k.clone(), *l as i64)).collect();
        if mine != b {
            fails.push(format!("{label}: province {id} works {mine:?} vs {b:?}"));
        }
    }
}

fn run(label: &str, scenario: &str, setup: impl Fn(&mut GameState, &Data), want: &Value) {
    let data = data();
    let mut gs = GameState::load_scenario(&data, scenario).unwrap();
    setup(&mut gs, &data);
    let mut fails = vec![];
    let months = want["months"].as_array().unwrap();
    for (m, row) in months.iter().enumerate() {
        for _ in 0..30 {
            gs.step_day(&data);
        }
        gs.step_month(&data);
        compare_month(label, m + 1, &gs, row, &mut fails);
        if !fails.is_empty() {
            break; // later months only repeat the first difference
        }
    }
    if fails.is_empty() {
        compare_end(label, &gs, &want["end"], &mut fails);
    }
    assert!(fails.is_empty(), "{label}: {} differences, e.g.\n{}", fails.len(), fails.iter().take(15).cloned().collect::<Vec<_>>().join("\n"));
    println!("{label}: {} months agree with the GDScript", months.len());
}

#[test]
fn peace_with_works_under_construction() {
    let g = golden();
    let w = &g["peace_with_works"];
    run(
        "peace_with_works",
        "july_1914",
        |gs, _| {
            apply_spec(gs, &w["spec"]);
            give_jobs(gs, &w["jobs"]);
        },
        w,
    );
}

#[test]
fn a_year_of_january_1900() {
    let g = golden();
    run("jan_1900", "jan_1900", |_, _| {}, &g["jan_1900"]);
}

#[test]
fn a_war_economy_for_a_year_and_a_half() {
    let g = golden();
    let w = &g["at_war"];
    run(
        "at_war",
        "july_1914",
        |gs, data| {
            apply_spec(gs, &w["spec"]);
            for p in w["wars"].as_array().unwrap() {
                gs.set_war(p[0].as_str().unwrap(), p[1].as_str().unwrap());
            }
            for c in w["controllers"].as_array().unwrap() {
                gs.set_controller(c[0].as_u64().unwrap() as usize, c[1].as_str().unwrap());
            }
            gs.recompute(data);
            give_jobs(gs, &w["jobs"]);
        },
        w,
    );
}
