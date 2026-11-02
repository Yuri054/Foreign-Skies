//! The peace rules against the GDScript ones: `tests/golden/peace.json` is what `tools/dump_peace_golden.gd` got out of the real
//! `Peace`: wars fought for forty days, what each side's score is and what every kind of demand would cost or be refused for, peace
//! made on terms chosen from the score (ground, indemnities, a disarmed border, a fleet limit, an ally released, a forced peace, the
//! player answering an offer), what each leaves behind, and the months after.

use fs_sim::peace::{Demand, Offer};
use fs_sim::state::{Data, GameState};
use serde_json::Value;
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
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/peace.json")).unwrap();
    serde_json::from_str(&text).unwrap()
}

fn demands(v: &Value) -> Vec<Demand> {
    v.as_array()
        .unwrap()
        .iter()
        .map(|d| match d["kind"].as_str().unwrap() {
            "province" => Demand::Province(d["ids"].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect()),
            "indemnity" => Demand::Indemnity { share: d["share"].as_f64().unwrap(), months: d["months"].as_i64().unwrap() },
            "release_ally" => Demand::ReleaseAlly(d["nation"].as_str().unwrap().to_string()),
            "disarm_border" => Demand::DisarmBorder(d["years"].as_i64().unwrap()),
            "fleet_limit" => Demand::FleetLimit(d["years"].as_i64().unwrap()),
            other => panic!("demand {other}"),
        })
        .collect()
}

fn compare_snapshot(label: &str, gs: &GameState, s: &Value, fails: &mut Vec<String>) {
    let ground: Vec<(usize, String, String)> = (1..gs.province_owner.len())
        .filter(|&i| gs.province_controller[i] != gs.province_owner[i] || !s["ground"].as_array().unwrap().iter().all(|g| g[0].as_u64().unwrap() as usize != i) )
        .map(|i| (i, gs.province_owner[i].clone(), gs.province_controller[i].clone()))
        .collect();
    let want: Vec<(usize, String, String)> = s["ground"].as_array().unwrap().iter().map(|g| (g[0].as_u64().unwrap() as usize, g[1].as_str().unwrap().to_string(), g[2].as_str().unwrap().to_string())).collect();
    // the golden lists provinces whose owner changed or that are held by another nation; compare the same way
    let mine: Vec<(usize, String, String)> = ground.into_iter().filter(|(i, o, c)| o != c || want.iter().any(|w| w.0 == *i)).collect();
    if mine != want {
        fails.push(format!("{label}: ground {mine:?} vs {want:?}"));
    }
    let armies = s["armies"].as_array().unwrap();
    if gs.armies.len() != armies.len() {
        fails.push(format!("{label}: {} armies vs {}", gs.armies.len(), armies.len()));
    } else {
        for (a, w) in gs.armies.iter().zip(armies) {
            let got = (a.id as i64, a.tag.as_str(), a.province as i64, a.path.len() as i64, a.still_days, a.attacking);
            let want = (w[0].as_i64().unwrap(), w[1].as_str().unwrap(), w[2].as_i64().unwrap(), w[3].as_i64().unwrap(), w[4].as_i64().unwrap(), w[5].as_bool().unwrap());
            if got != want {
                fails.push(format!("{label}: army {got:?} vs {want:?}"));
            }
        }
    }
    for (i, w) in s["nations"].as_array().unwrap().iter().enumerate() {
        let n = &gs.nations[i];
        for (k, got, want) in [("prestige", n.prestige, &w[0]), ("treasury", n.treasury, &w[1]), ("war_support", n.war_support, &w[6]), ("net", n.budget.net, &w[9])] {
            if !close(got, bits(want)) {
                fails.push(format!("{label} {}: {k} {got:e} vs {:e}", n.tag, bits(want)));
            }
        }
        let ints = (n.capital, n.home_capital, n.provinces.len() as i64, n.population, n.men_in_units, n.manpower, n.capitulated, n.construction.len() as i64);
        let want = (w[2].as_i64().unwrap(), w[3].as_i64().unwrap(), w[4].as_i64().unwrap(), w[5].as_i64().unwrap(), w[7].as_i64().unwrap(), w[8].as_i64().unwrap(), w[10].as_bool().unwrap(), w[11].as_i64().unwrap());
        if ints != want {
            fails.push(format!("{label} {}: {ints:?} vs {want:?}", n.tag));
        }
    }
    let ind: Vec<(String, String, f64, i64)> = gs.indemnities.iter().map(|i| (i.payer.clone(), i.receiver.clone(), i.monthly, i.months_left)).collect();
    let want_ind: Vec<(String, String, f64, i64)> = s["indemnities"].as_array().unwrap().iter().map(|i| (i[0].as_str().unwrap().to_string(), i[1].as_str().unwrap().to_string(), bits(&i[2]), i[3].as_i64().unwrap())).collect();
    if ind.len() != want_ind.len() || ind.iter().zip(&want_ind).any(|(a, b)| a.0 != b.0 || a.1 != b.1 || !close(a.2, b.2) || a.3 != b.3) {
        fails.push(format!("{label}: indemnities {ind:?} vs {want_ind:?}"));
    }
    let res: Vec<(String, String, String, Vec<usize>, i64)> = gs.restrictions.iter().map(|r| (r.nation.clone(), r.holder.clone(), r.kind.clone(), r.provinces.clone(), r.until_day)).collect();
    let want_res: Vec<(String, String, String, Vec<usize>, i64)> = s["restrictions"].as_array().unwrap().iter().map(|r| (r[0].as_str().unwrap().to_string(), r[1].as_str().unwrap().to_string(), r[2].as_str().unwrap().to_string(), r[3].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect(), r[4].as_i64().unwrap())).collect();
    if res != want_res {
        fails.push(format!("{label}: restrictions {res:?} vs {want_res:?}"));
    }
    let claims = s["claims"].as_array().unwrap();
    if gs.claims.len() != claims.len() {
        fails.push(format!("{label}: {} claims vs {}", gs.claims.len(), claims.len()));
    } else {
        for (c, w) in gs.claims.iter().zip(claims) {
            let ids: Vec<i64> = c["ids"].as_array().unwrap().iter().map(|x| x.as_i64().unwrap()).collect();
            let want_ids: Vec<i64> = w[3].as_array().unwrap().iter().map(|x| x.as_i64().unwrap()).collect();
            let ok = c["holder"] == w[0] && c["against"] == w[1] && c["kind"] == w[2] && ids == want_ids && c["expires_day"].as_i64() == w[4].as_i64() && c["made_day"].as_i64() == w[5].as_i64() && c["war"] == w[6] && c["note"] == w[7];
            if !ok {
                fails.push(format!("{label}: claim {c} vs {w}"));
            }
        }
    }
    let riv = s["rivalries"].as_object().unwrap();
    if gs.rivalries.len() != riv.len() || riv.iter().any(|(k, v)| gs.rivalries.get(k).map(|x| !close(*x, bits(v))).unwrap_or(true)) {
        fails.push(format!("{label}: rivalries {:?}", gs.rivalries));
    }
    if gs.wars.len() as i64 != s["wars"].as_i64().unwrap() || gs.pending_offers.len() as i64 != s["pending"].as_i64().unwrap() || gs.next_offer_id as i64 != s["next_offer"].as_i64().unwrap() || gs.occupation.len() as i64 != s["occupation"].as_i64().unwrap() {
        fails.push(format!("{label}: wars {} pending {} next offer {} occupation {}", gs.wars.len(), gs.pending_offers.len(), gs.next_offer_id, gs.occupation.len()));
    }
    let hist = s["history"].as_array().unwrap();
    if gs.war_history.len() != hist.len() {
        fails.push(format!("{label}: {} finished wars vs {}", gs.war_history.len(), hist.len()));
    } else {
        for (w, h) in gs.war_history.iter().zip(hist) {
            let ok = w.a == h[0].as_str().unwrap() && w.b == h[1].as_str().unwrap() && w.end_day == h[2].as_i64().unwrap()
                && h[3].as_object().unwrap().iter().all(|(t, v)| close(w.losses[t], bits(v)))
                && h[4].as_object().unwrap().iter().all(|(t, v)| close(w.battle_points[t], bits(v)));
            if !ok {
                fails.push(format!("{label}: finished war {} {} {h}", w.a, w.b));
            }
        }
    }
    let cd: std::collections::HashMap<String, i64> = s["cooldown"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_f64().unwrap() as i64)).collect();
    if gs.peace_cooldown != cd {
        fails.push(format!("{label}: cooldown {:?} vs {cd:?}", gs.peace_cooldown));
    }
    for r in s["restricted"].as_array().unwrap() {
        let got = gs.can_enter_pub(&data_ref(), r[0].as_str().unwrap(), r[1].as_u64().unwrap() as usize);
        if got != r[2].as_bool().unwrap() {
            fails.push(format!("{label}: {} may enter {}: {got} vs {}", r[0], r[1], r[2]));
        }
    }
}

fn data_ref() -> &'static Data {
    use std::sync::OnceLock;
    static D: OnceLock<Data> = OnceLock::new();
    D.get_or_init(data)
}

fn run(name: &str) {
    let g = golden();
    let w = &g[name];
    let data = data_ref();
    let mut gs = GameState::load_scenario(data, "july_1914").unwrap();
    gs.player_tag = w["player"].as_str().unwrap().to_string();
    for (i, p) in w["wars"].as_array().unwrap().iter().enumerate() {
        let goal = &w["goals"][i];
        let goal = if goal.as_object().map(|o| o.is_empty()).unwrap_or(false) { Value::Null } else { goal.clone() };
        gs.set_war_goal(p[0].as_str().unwrap(), p[1].as_str().unwrap(), p[2].as_str().unwrap(), goal);
    }
    for wk in w["works"].as_array().unwrap() {
        let (id, kind, level) = (wk[0].as_u64().unwrap() as usize, wk[1].as_str().unwrap(), wk[2].as_i64().unwrap() as i32);
        match gs.province_buildings[id].iter_mut().find(|(k, _)| k == kind) {
            Some(slot) => slot.1 = level,
            None => gs.province_buildings[id].push((kind.to_string(), level)),
        }
    }
    gs.recompute(data);
    for o in w["orders"].as_array().unwrap() {
        let ok = gs.order_army_to(data, o[0].as_str().unwrap(), o[1].as_u64().unwrap() as u32, o[2].as_u64().unwrap() as usize);
        assert_eq!(ok, o[3].as_bool().unwrap());
    }
    for _ in 0..w["days"].as_i64().unwrap() {
        gs.step_day(data);
        gs.military_step_day(data);
        gs.calendar.advance_day();
        gs.finish_economy_stage(data);
    }
    let mut fails = vec![];
    let mut checks = 0;

    // what the score is and what could be asked
    for case in w["cases"].as_array().unwrap() {
        let (taker, giver) = (case["taker"].as_str().unwrap(), case["giver"].as_str().unwrap());
        let (a, b) = (case["war"][0].as_str().unwrap(), case["war"][1].as_str().unwrap());
        let war = gs.war_between(a, b).unwrap();
        for tag in [a, b] {
            let parts = gs.score_parts(data, war, tag);
            let want = &case["scores"][tag];
            for (k, got) in [("occupation", parts.0), ("capital", parts.1), ("battles", parts.2), ("capitulation", parts.3), ("total", parts.4)] {
                if !close(got, bits(&want[k])) {
                    fails.push(format!("{name} {a}-{b}: score {k} of {tag} {got:e} vs {:e}", bits(&want[k])));
                }
            }
        }
        let ordered: Vec<usize> = {
            // the golden's candidates: held ground, then the rest, dearest first (ties as the game's sort leaves them)
            let mut held = vec![];
            let mut unheld = vec![];
            for &id in &gs.nation(giver).provinces {
                if gs.province_controller[id] == taker {
                    held.push(id);
                } else if held.len() + unheld.len() < 40 {
                    unheld.push(id);
                }
            }
            let mut cand: Vec<usize> = held.into_iter().chain(unheld).collect();
            cand.sort_by(|&x, &y| gs.province_price(data, y, taker, giver).partial_cmp(&gs.province_price(data, x, taker, giver)).unwrap());
            cand
        };
        for pk in case["picks"].as_array().unwrap() {
            let budget = pk[0].as_f64().unwrap();
            let price = |id: usize| gs.province_price(data, id, taker, giver);
            let (ids, spent) = gs.pick_takeable(data, taker, giver, &ordered, &price, budget);
            let want: Vec<usize> = pk[1].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect();
            if ids != want || !close(spent, bits(&pk[2])) {
                fails.push(format!("{name}: pick_takeable({taker} from {giver}, budget {budget}) {ids:?} {spent} vs {want:?} {}", bits(&pk[2])));
            }
        }
        for p in case["prices"].as_array().unwrap() {
            let id = p[0].as_u64().unwrap() as usize;
            let got = gs.province_price(data, id, taker, giver);
            if !close(got, bits(&p[1])) {
                fails.push(format!("{name}: price of {id} for {taker} from {giver} {got:e} vs {:e}", bits(&p[1])));
            }
        }
        if gs.is_forced(data, taker, giver) != case["forced"].as_bool().unwrap()
            || !close(gs.occupied_share(data, taker, giver), bits(&case["occupied"]))
            || !close(gs.capital_points(data, taker, giver), bits(&case["capital_points"]))
            || gs.max_cession(data, giver) as i64 != case["max_cession"].as_i64().unwrap()
        {
            fails.push(format!("{name}: forced, occupied share, capital points or max cession of {taker} over {giver}"));
        }
        for (key, want) in case["checks"].as_object().unwrap() {
            let (variant, mode) = key.split_once('|').unwrap();
            let dem = demands(&case["variants"][variant]);
            let (from, to) = if mode == "demand" { (taker, giver) } else { (giver, taker) };
            let c = gs.check_peace(data, from, to, mode, &dem);
            let budget_ok = want["budget"].as_str().unwrap().is_empty() || close(c.budget, bits(&want["budget"]));
            let ok = c.ok == want["ok"].as_bool().unwrap() && c.reason == want["reason"].as_str().unwrap() && close(c.cost, bits(&want["cost"])) && budget_ok
                && c.forced == want["forced"].as_bool().unwrap() && c.taker == want["taker"].as_str().unwrap() && c.giver == want["giver"].as_str().unwrap();
            if !ok {
                fails.push(format!("{name} {taker}>{giver} {key}: ok {} reason {:?} cost {:e} budget {:e} vs {want}", c.ok, c.reason, c.cost, c.budget));
            }
            checks += 1;
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));

    // a month with the wars still on: battle points fade
    gs.peace_step_month(data);
    compare_snapshot(&format!("{name} early month"), &gs, &w["early"], &mut fails);
    for (war, want) in gs.wars.iter().zip(w["early"]["points"].as_array().unwrap()) {
        for (t, v) in want.as_object().unwrap() {
            if !close(war.battle_points[t], bits(v)) {
                fails.push(format!("{name}: battle points of {t} {} vs {:e}", war.battle_points[t], bits(v)));
            }
        }
    }
    assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));

    // peace, war by war
    for (i, plan) in w["plans"].as_array().unwrap().iter().enumerate() {
        let (taker, giver) = (plan["taker"].as_str().unwrap(), plan["giver"].as_str().unwrap());
        if let Some(ws) = plan["pre"].get("war_support") {
            for (t, v) in ws.as_object().unwrap() {
                let ti = gs.nation_index[t.as_str()];
                gs.nations[ti].war_support = v.as_f64().unwrap();
            }
        }
        if let Some(cs) = plan["pre"].get("controllers") {
            for c in cs.as_array().unwrap() {
                gs.set_controller(c[0].as_u64().unwrap() as usize, c[1].as_str().unwrap());
            }
        }
        if let Some(r) = plan["pre"].get("rivalries") {
            for (k, v) in r.as_object().unwrap() {
                gs.rivalries.insert(k.clone(), v.as_f64().unwrap());
            }
        }
        if plan["pre"].get("controllers").is_some() || plan["pre"].get("rivalries").is_some() {
            gs.recompute(data);
        }
        if let Some(tr) = plan["pre"].get("treasury") {
            for (t, v) in tr.as_object().unwrap() {
                let ti = gs.nation_index[t.as_str()];
                gs.nations[ti].treasury = v.as_f64().unwrap();
            }
        }
        if let Some(j) = plan["pre"].get("job") {
            let ti = gs.nation_index[j[0].as_str().unwrap()];
            gs.nations[ti].construction.push(fs_sim::economy::new_job(j[1].as_u64().unwrap() as usize, j[2].as_str().unwrap(), j[3].as_f64().unwrap(), j[4].as_i64().unwrap() as i32));
        }
        if let Some(bp) = plan["pre"].get("battle_points") {
            let war = gs.war_between(taker, giver).unwrap();
            for (t, v) in bp.as_object().unwrap() {
                *gs.wars[war].battle_points.get_mut(t).unwrap() = v.as_f64().unwrap();
            }
        }
        if let Some(parts) = plan["parts"].as_object().filter(|p| !p.is_empty()) {
            let war = gs.war_between(taker, giver).unwrap();
            let got = gs.score_parts(data, war, taker);
            for (k, v) in [("occupation", got.0), ("capital", got.1), ("battles", got.2), ("capitulation", got.3), ("total", got.4)] {
                assert!(close(v, bits(&parts[k])), "{name} plan {i}: score {k} {v:e} vs {:e}", bits(&parts[k]));
            }
        }
        let dem = demands(&plan["demands"]);
        let refusal = &plan["refusal"];
        if refusal.as_object().map(|o| !o.is_empty()).unwrap_or(false) {
            // the offer is refused: the proposer must wait before asking again
            let war = gs.war_between(taker, giver).unwrap();
            let off0 = Offer { id: gs.next_offer_id, war_id: gs.wars[war].id, from: taker.to_string(), to: giver.to_string(), mode: "demand".to_string(), taker: taker.to_string(), giver: giver.to_string(), demands: vec![], cost: 0.0, forced: false, day: gs.calendar.days_elapsed as i64, note: String::new() };
            gs.next_offer_id += 1;
            assert_eq!([off0.id as i64, off0.war_id as i64], [refusal["offer"][0].as_i64().unwrap(), refusal["offer"][1].as_i64().unwrap()]);
            gs.resolve_offer_pub(data, &off0, false);
            assert_eq!(gs.check_peace(data, taker, giver, "demand", &[]).reason, refusal["reason"].as_str().unwrap(), "{name}: blocked while cooling");
            let other = if gs.player_tag != giver { giver } else { taker };
            assert_eq!(gs.check_peace(data, &gs.player_tag.clone(), other, "demand", &[]).reason, refusal["player_reason"].as_str().unwrap(), "{name}: the player is never held back");
            let cd: std::collections::HashMap<String, i64> = refusal["cooldown"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_f64().unwrap() as i64)).collect();
            assert_eq!(gs.peace_cooldown, cd, "{name}: cooldown");
            for _ in 0..31 {
                gs.calendar.advance_day();
            }
        }
        let c = gs.check_peace(data, taker, giver, "demand", &dem);
        assert_eq!(c.ok, plan["ok"].as_bool().unwrap(), "{name} plan {i}: {:?}", c.reason);
        assert!(close(c.cost, bits(&plan["cost"])) && c.forced == plan["forced"].as_bool().unwrap(), "{name} plan {i}: cost or forced");
        if plan["method"] == "player" {
            let r = gs.propose_peace(data, taker, giver, "demand", dem.clone(), false);
            assert!(r.ok && r.accepted.is_none(), "the player is asked");
            let pending: Vec<(u32, String, String, String)> = gs.pending_offers.iter().map(|o| (o.id, o.from.clone(), o.to.clone(), o.mode.clone())).collect();
            let want: Vec<(u32, String, String, String)> = plan["pending"].as_array().unwrap().iter().map(|o| (o[0].as_u64().unwrap() as u32, o[1].as_str().unwrap().to_string(), o[2].as_str().unwrap().to_string(), o[3].as_str().unwrap().to_string())).collect();
            assert_eq!(pending, want, "{name} plan {i}: the offer waiting");
            let id = gs.pending_offers[0].id;
            assert_eq!(gs.check_peace(data, taker, giver, "demand", &dem).reason, plan["pending_reason"].as_str().unwrap(), "{name} plan {i}: a second offer while one waits");
            if plan["spoiled"].as_bool().unwrap() {
                // the ground it asked for is lost to a third nation before the answer
                if let Some(Demand::Province(ids)) = dem.iter().find(|d| matches!(d, Demand::Province(_))) {
                    gs.transfer_province(data, ids[0], "POR");
                }
            }
            assert!(gs.answer_offer(data, id, true));
        } else {
            let war = gs.war_between(taker, giver).unwrap();
            let offer = Offer { id: gs.next_offer_id, war_id: gs.wars[war].id, from: taker.to_string(), to: giver.to_string(), mode: "demand".to_string(), taker: taker.to_string(), giver: giver.to_string(), demands: dem, cost: c.cost, forced: c.forced, day: gs.calendar.days_elapsed as i64, note: String::new() };
            gs.next_offer_id += 1;
            gs.make_peace(data, war, &offer);
        }
        compare_snapshot(&format!("{name} peace {i}"), &gs, &w["after"][i], &mut fails);
        assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));
    }

    // the months after
    for (m, snap) in w["months"].as_array().unwrap().iter().enumerate() {
        for _ in 0..30 {
            gs.calendar.advance_day();
        }
        gs.step_month(data);
        gs.peace_step_month(data);
        compare_snapshot(&format!("{name} month {}", m + 1), &gs, snap, &mut fails);
        assert!(fails.is_empty(), "{} differences, e.g.\n{}", fails.len(), fails.iter().take(12).cloned().collect::<Vec<_>>().join("\n"));
    }
    println!("{name}: {} score checks of demands and {} peaces agree with the GDScript", checks, w["plans"].as_array().unwrap().len());
}

#[test]
fn the_western_peace() {
    run("west");
}

#[test]
fn the_eastern_peaces() {
    run("east");
}

#[test]
fn the_southern_peaces() {
    run("south");
}
