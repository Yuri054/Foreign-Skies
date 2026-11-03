//! The Rust port against the GDScript simulation: `tests/golden/slice.json` is what `tools/dump_sim_golden.gd` got out
//! of the original code. Floats are stored as the decimal text of their 64-bit patterns.

use fs_sim::clock::{days_in_month, Calendar};
use fs_sim::config::EconomyConfig;
use fs_sim::economy;
use fs_sim::population;
use serde_json::Value;

fn golden() -> Value {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/slice.json"))
        .expect("tests/golden/slice.json (made by tools/dump_sim_golden.gd)");
    serde_json::from_str(&text).unwrap()
}

fn config() -> EconomyConfig {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../../data/economy.json")).unwrap();
    EconomyConfig::from_json_str(&text).unwrap()
}

fn bits(v: &Value) -> f64 {
    f64::from_bits(v.as_str().unwrap().parse::<i64>().unwrap() as u64)
}

fn int(v: &Value) -> i64 {
    v.as_i64().unwrap()
}

/// Same number: the same bits, or (for results of `pow`, which different maths libraries round differently) at most
/// `ulps` representable numbers apart.
fn same(a: f64, b: f64, ulps: i64) -> bool {
    if a == b || (a.is_nan() && b.is_nan()) {
        return true;
    }
    if a.signum() != b.signum() {
        return false;
    }
    (a.to_bits() as i64 - b.to_bits() as i64).abs() <= ulps
}

fn check(what: &str, got: f64, want: f64, ulps: i64, fails: &mut Vec<String>) {
    if !same(got, want, ulps) {
        fails.push(format!("{what}: got {got:e} ({:#x}), GDScript {want:e} ({:#x})", got.to_bits(), want.to_bits()));
    }
}

fn finish(name: &str, cases: usize, fails: Vec<String>) {
    if !fails.is_empty() {
        let shown: Vec<_> = fails.iter().take(15).cloned().collect();
        panic!("{name}: {} differences in {cases} cases, e.g.\n{}", fails.len(), shown.join("\n"));
    }
    println!("{name}: {cases} cases agree with the GDScript");
}

#[test]
fn clock_days_in_month() {
    let g = golden();
    let rows = g["clock_days_in_month"].as_array().unwrap();
    for r in rows {
        assert_eq!(days_in_month(int(&r[0]) as i32, int(&r[1]) as i32) as i64, int(&r[2]), "{r}");
    }
    println!("clock_days_in_month: {} cases agree", rows.len());
}

#[test]
fn clock_runs_day_by_day() {
    let g = golden();
    let mut days = 0;
    for run in g["clock_run"]["runs"].as_array().unwrap() {
        let s = &run["start"];
        let mut c = Calendar::start(int(&s[0]) as i32, int(&s[1]) as i32, int(&s[2]) as i32);
        for (i, row) in run["days"].as_array().unwrap().iter().enumerate() {
            let tick = c.advance_day();
            let got = [
                c.year as i64,
                c.month as i64,
                c.day as i64,
                c.days_elapsed as i64,
                tick.new_month as i64,
                tick.new_year as i64,
            ];
            let want: Vec<i64> = row.as_array().unwrap().iter().map(int).collect();
            assert_eq!(got.to_vec(), want, "start {s}, day {i}");
            days += 1;
        }
    }
    println!("clock_run: {days} days agree");
}

#[test]
fn clock_date_strings() {
    let g = golden();
    let rows = g["clock_date_after"].as_array().unwrap();
    for r in rows {
        let c = Calendar { year: int(&r[0]) as i32, month: int(&r[1]) as i32, day: int(&r[2]) as i32, days_elapsed: 0 };
        let offset = int(&r[3]) as i32;
        let got = if offset < 0 { c.date_string() } else { c.date_after(offset) };
        assert_eq!(got, r[4].as_str().unwrap(), "{r}");
    }
    println!("clock_date_after: {} cases agree", rows.len());
}

#[test]
fn base_income_matches() {
    let (g, cfg) = (golden(), config());
    let mut fails = vec![];
    let rows = g["base_income"].as_array().unwrap();
    for r in rows {
        let pop = bits(&r["pop"]);
        check(&format!("base income of {pop}"), economy::base_income(&cfg, pop), bits(&r["income"]), 0, &mut fails);
    }
    finish("base_income", rows.len(), fails);
}

#[test]
fn build_plans_match() {
    let (g, cfg) = (golden(), config());
    let mut fails = vec![];
    let rows = g["build_plan"].as_array().unwrap();
    assert_eq!(rows.len(), cfg.buildings.len(), "every building type, in file order");
    for (r, def) in rows.iter().zip(&cfg.buildings) {
        assert_eq!(r["type"].as_str().unwrap(), def.id);
        let plan = economy::build_plan(def);
        check(&format!("{} gold", def.id), plan.gold, bits(&r["gold"]), 0, &mut fails);
        check(&format!("{} cp", def.id), plan.cp, bits(&r["cp"]), 0, &mut fails);
        if plan.days as i64 != int(&r["days"]) {
            fails.push(format!("{} days: {} vs {}", def.id, plan.days, r["days"]));
        }
    }
    finish("build_plan", rows.len(), fails);
}

#[test]
fn budgets_match() {
    let (g, cfg) = (golden(), config());
    let data = fs_sim::state::Data::load(std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../../data"))).unwrap();
    let mut gs = fs_sim::state::GameState::load_scenario(&data, "july_1914").unwrap();
    let mut fails = vec![];
    let rows = g["budget"].as_array().unwrap();
    for (k, r) in rows.iter().enumerate() {
        let f = |v: &Value, key: &str| v.get(key).map(bits).unwrap_or(0.0);
        let raw = fs_sim::state::Sums {
            base: f(&r["raw"], "base"),
            occupied: f(&r["raw"], "occupied"),
            factories: f(&r["raw"], "factories"),
            ports: f(&r["raw"], "ports"),
            upkeep: f(&r["raw"], "upkeep"),
            cp: f(&r["raw"], "cp"),
            pool: f(&r["raw"], "pool"),
            levels: vec![],
        };
        let n = &mut gs.nations[0];
        n.mobilization = bits(&r["mobilization"]);
        n.blockade = bits(&r["blockade"]);
        n.treasury = bits(&r["treasury"]);
        n.peacetime_army = int(&r["peacetime_army"]);
        n.naval_budget = bits(&r["naval_budget"]);
        n.focus_income = f(&r["fx"], "income");
        n.focus_cp = f(&r["fx"], "cp");
        let held = int(&r["capital"]) == 1;
        let b = fs_sim::budget::nation_budget(&cfg, n, &raw, bits(&r["war_mult"]), bits(&r["army"]), held);
        let o = &r["out"];
        for (name, got) in [
            ("base", b.base), ("factories", b.factories), ("ports", b.ports), ("occupied", b.occupied), ("income", b.income),
            ("administration", b.administration), ("army", b.army), ("navy", b.navy), ("buildings", b.buildings),
            ("interest", b.interest), ("expenses", b.expenses), ("net", b.net), ("cp", b.cp),
            ("manpower_pool", b.manpower_pool), ("manpower_max", b.manpower_max),
        ] {
            check(&format!("case {k} {name}"), got, bits(&o[name]), 0, &mut fails);
        }
    }
    finish("budget", rows.len(), fails);
}

#[test]
fn population_rounding_matches() {
    let g = golden();
    let mut fails = vec![];
    let mut steps = 0;
    for r in g["population_add"].as_array().unwrap() {
        let mut pop = vec![0i32, int(&r["start"]) as i32];
        let mut frac = vec![0.0f32, 0.0];
        for (i, s) in r["steps"].as_array().unwrap().iter().enumerate() {
            population::add(&mut pop, &mut frac, 1, bits(&s["delta"]));
            if pop[1] as i64 != int(&s["pop"]) {
                fails.push(format!("start {} step {i}: population {} vs GDScript {}", r["start"], pop[1], s["pop"]));
            }
            check(&format!("start {} step {i} frac", r["start"]), frac[1] as f64, bits(&s["frac"]), 0, &mut fails);
            steps += 1;
        }
    }
    finish("population_add", steps, fails);
}
