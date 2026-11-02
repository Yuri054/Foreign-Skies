//! The Rust port against the GDScript simulation: `tests/golden/slice.json` is what `tools/dump_sim_golden.gd` got out
//! of the original code. Floats are stored as the decimal text of their 64-bit patterns.

use fs_sim::clock::{days_in_month, Calendar};
use fs_sim::config::{EconomyConfig, Effects};
use fs_sim::economy::{self, EconNation};
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

fn effects(v: &Value) -> Effects {
    let get = |k: &str| v.get(k).map(bits).unwrap_or(0.0);
    Effects { gdp: get("gdp"), industry: get("industry"), food: get("food"), trade: get("trade"), growth: get("growth") }
}

fn buildings(v: &Value) -> Vec<(String, i32)> {
    v.as_array().unwrap().iter().map(|p| (p[0].as_str().unwrap().to_string(), int(&p[1]) as i32)).collect()
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
fn modifiers_match() {
    let (g, cfg) = (golden(), config());
    let mut fails = vec![];
    let rows = g["modifiers"].as_array().unwrap();
    for r in rows {
        let b = buildings(&r["buildings"]);
        let b: Vec<(&str, i32)> = b.iter().map(|(k, l)| (k.as_str(), *l)).collect();
        let got = economy::modifiers(&cfg, &b, &effects(&r["fx"]));
        let o = &r["out"];
        for (k, v) in [("gdp", got.gdp), ("industry", got.industry), ("food", got.food), ("trade", got.trade), ("growth", got.growth)] {
            check(&format!("modifiers {k} {r}"), v, bits(&o[k]), 0, &mut fails);
        }
    }
    finish("modifiers", rows.len(), fails);
}

#[test]
fn province_output_matches() {
    let (g, cfg) = (golden(), config());
    let mut fails = vec![];
    let rows = g["province_output"].as_array().unwrap();
    for r in rows {
        let b = buildings(&r["buildings"]);
        let b: Vec<(&str, i32)> = b.iter().map(|(k, l)| (k.as_str(), *l)).collect();
        let dep: Vec<(&str, f64)> = r["deposit"].as_object().unwrap().iter().map(|(k, v)| (k.as_str(), bits(v))).collect();
        let n = EconNation { development: bits(&r["dev"]), agri_yield: bits(&r["agri"]), focus_fx: effects(&r["fx"]), ..Default::default() };
        let got = economy::province_output(&cfg, int(&r["pop"]), bits(&r["area"]), &n, &b, &dep);
        let o = &r["out"];
        // gdp and what follows from it go through pow(): allow a couple of units in the last place.
        for (k, v) in [("gdp", got.gdp), ("industry", got.industry), ("food", got.food), ("trade", got.trade), ("pool", got.pool), ("materials", got.materials)] {
            check(&format!("province_output {k} pop {} area {}", r["pop"], bits(&r["area"])), v, bits(&o[k]), 4, &mut fails);
        }
    }
    finish("province_output", rows.len(), fails);
}

#[test]
fn growth_matches() {
    let (g, cfg) = (golden(), config());
    let mut fails = vec![];
    let rows = g["growth"].as_array().unwrap();
    for r in rows {
        let gdp = r["gdp"].as_str().unwrap();
        let n = EconNation {
            tax_rate: bits(&r["rate"]),
            investment: bits(&r["invest"]),
            budget_gdp: if gdp.is_empty() { None } else { Some(bits(&r["gdp"])) },
            focus_fx: effects(&r["fx"]),
            ..Default::default()
        };
        let tag = format!("rate {} invest {} gdp {gdp}", bits(&r["rate"]), bits(&r["invest"]));
        check(&format!("strain {tag}"), economy::tax_strain(&cfg, &n), bits(&r["strain"]), 0, &mut fails);
        check(&format!("relief {tag}"), economy::tax_relief(&cfg, &n), bits(&r["relief"]), 0, &mut fails);
        check(&format!("investment_growth {tag}"), economy::investment_growth(&cfg, &n), bits(&r["investment_growth"]), 0, &mut fails);
        check(&format!("growth_rate {tag}"), economy::growth_rate(&cfg, &n), bits(&r["growth_rate"]), 0, &mut fails);
    }
    finish("growth", rows.len(), fails);
}

#[test]
fn worker_share_matches() {
    let (g, cfg) = (golden(), config());
    let mut fails = vec![];
    let rows = g["worker_share"].as_array().unwrap();
    for r in rows {
        let n = EconNation {
            men_in_units: int(&r["men"]),
            population: int(&r["pop"]),
            weariness: bits(&r["weariness"]),
            starving: int(&r["starving"]) == 1,
            ..Default::default()
        };
        check(&format!("worker_share {r}"), economy::worker_share(&cfg, &n), bits(&r["share"]), 0, &mut fails);
    }
    finish("worker_share", rows.len(), fails);
}

#[test]
fn building_costs_match() {
    let (g, cfg) = (golden(), config());
    let mut fails = vec![];
    let rows = g["building_cost"].as_array().unwrap();
    for r in rows {
        let def = cfg.building(r["type"].as_str().unwrap());
        // The picture of the province's output: gdp and industry as the 32-bit floats the game keeps.
        let mut gdp = vec![0.0f32; 8];
        let mut ind = vec![0.0f32; 8];
        let id = if r.get("outside").is_some() { 99 } else { 1 };
        gdp[1] = bits(&r["gdp"]) as f32;
        ind[1] = bits(&r["industry"]) as f32;
        assert_eq!(gdp[1] as f64, bits(&r["gdp"]), "the golden gdp is a 32-bit float");
        let sf = economy::size_factor(&cfg, id, def, &gdp, &ind);
        check(&format!("size_factor {r}"), sf, bits(&r["size_factor"]), 0, &mut fails);
        if r.get("outside").is_some() {
            continue;
        }
        let def = def.unwrap();
        let level = int(&r["level"]) as i32;
        check(&format!("level_cost {r}"), economy::level_cost(def, level, sf), bits(&r["level_cost"]), 2, &mut fails);
        let plan = economy::build_plan(&cfg, def, level, sf);
        check(&format!("plan.ic {r}"), plan.ic, bits(&r["ic"]), 2, &mut fails);
        check(&format!("plan.gold {r}"), plan.gold, bits(&r["gold"]), 2, &mut fails);
        check(&format!("plan.total {r}"), plan.total, bits(&r["total"]), 2, &mut fails);
        assert_eq!(plan.days as i64, int(&r["days"]));
    }
    finish("building_cost", rows.len(), fails);
}

#[test]
fn population_rounding_matches() {
    let (g, cfg) = (golden(), config());
    let mut fails = vec![];
    let mut steps = 0;
    for r in g["population_add"].as_array().unwrap() {
        let mut pop = vec![0i32, int(&r["start"]) as i32];
        let mut frac = vec![0.0f32, 0.0];
        for (i, s) in r["steps"].as_array().unwrap().iter().enumerate() {
            let whole = population::add(&cfg, &mut pop, &mut frac, 1, bits(&s["delta"]));
            check(&format!("start {} step {i} whole", r["start"]), whole, bits(&s["whole"]), 0, &mut fails);
            if pop[1] as i64 != int(&s["pop"]) {
                fails.push(format!("start {} step {i}: population {} vs GDScript {}", r["start"], pop[1], s["pop"]));
            }
            check(&format!("start {} step {i} frac", r["start"]), frac[1] as f64, bits(&s["frac"]), 0, &mut fails);
            steps += 1;
        }
    }
    finish("population_add", steps, fails);
}
