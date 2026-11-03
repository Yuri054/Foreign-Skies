//! Helpers the golden-file tests share (the peace snapshot and its comparison).
#![allow(dead_code)]

use fs_sim::peace::Demand;
use fs_sim::state::GameState;
use serde_json::Value;

pub fn bits(v: &Value) -> f64 {
    f64::from_bits(v.as_str().unwrap().parse::<i64>().unwrap() as u64)
}

/// The port's numbers are the game's, bit for bit (the whole suite passes with no tolerance at all).
pub fn close(a: f64, b: f64) -> bool {
    a == b
}

pub fn demands(v: &Value) -> Vec<Demand> {
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

pub fn compare_snapshot(label: &str, gs: &GameState, s: &Value, fails: &mut Vec<String>) {
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


pub fn data_ref() -> &'static fs_sim::state::Data {
    static DATA: std::sync::OnceLock<fs_sim::state::Data> = std::sync::OnceLock::new();
    DATA.get_or_init(|| fs_sim::state::Data::load(&std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")).unwrap())
}
