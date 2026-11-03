//! Saving and loading: a game saved in the middle and loaded again goes on exactly as the one that was not saved. Two copies of a
//! war-torn game (the AI playing every nation, the player's commands in between) are run on, one of them through a save and a load
//! at every stage, and their states compared in full, every bit.

use ciborium::Value as Cbor;
use fs_sim::ai_turn::AiTurn;
use fs_sim::save;
use fs_sim::state::{Data, GameState};
use std::path::Path;

/// The whole state in a form that does not depend on the order a hash map happens to give its entries.
fn canon(gs: &GameState) -> Cbor {
    let mut raw = vec![];
    ciborium::into_writer(gs, &mut raw).unwrap();
    fn sort(v: Cbor) -> Cbor {
        match v {
            Cbor::Array(a) => Cbor::Array(a.into_iter().map(sort).collect()),
            Cbor::Map(m) => {
                let mut m: Vec<(Cbor, Cbor)> = m.into_iter().map(|(k, v)| (sort(k), sort(v))).collect();
                m.sort_by_key(|(k, _)| {
                    let mut b = vec![];
                    ciborium::into_writer(k, &mut b).unwrap();
                    b
                });
                Cbor::Map(m)
            }
            Cbor::Tag(t, b) => Cbor::Tag(t, Box::new(sort(*b))),
            x => x,
        }
    }
    sort(ciborium::from_reader(raw.as_slice()).unwrap())
}

fn data() -> Data {
    Data::load_with_difficulty(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data"), "normal").unwrap()
}

fn start(data: &Data, scenario: &str) -> GameState {
    let mut gs = GameState::load_scenario(data, scenario).unwrap();
    gs.pressure_ai = true;
    gs.ai_turn = AiTurn::all();
    gs.start_scenario_wars(data);
    gs.player_tag = "SRB".to_string();
    gs
}

/// Where two states first differ, as a path through them.
fn first_diff(a: &Cbor, b: &Cbor, path: &mut Vec<String>) -> Option<String> {
    match (a, b) {
        (Cbor::Array(x), Cbor::Array(y)) => {
            for (i, (p, q)) in x.iter().zip(y).enumerate() {
                path.push(i.to_string());
                if let Some(d) = first_diff(p, q, path) {
                    return Some(d);
                }
                path.pop();
            }
            (x.len() != y.len()).then(|| format!("{}: {} vs {} entries", path.join("."), x.len(), y.len()))
        }
        (Cbor::Map(x), Cbor::Map(y)) => {
            for (i, ((k, p), (_, q))) in x.iter().zip(y).enumerate() {
                path.push(format!("{k:?}@{i}"));
                if let Some(d) = first_diff(p, q, path) {
                    return Some(d);
                }
                path.pop();
            }
            (x.len() != y.len()).then(|| format!("{}: {} vs {} entries", path.join("."), x.len(), y.len()))
        }
        _ => (a != b).then(|| format!("{}: {:?} vs {:?}", path.join("."), a, b)),
    }
}

fn same(label: &str, a: &GameState, b: &GameState) {
    let (x, y) = (canon(a), canon(b));
    if x != y {
        let d = first_diff(&x, &y, &mut vec![]).unwrap_or_default();
        panic!("{label}: the loaded game differs from the one that was kept, first at {}", d.chars().take(600).collect::<String>());
    }
}

#[test]
fn a_loaded_game_goes_on_as_the_kept_one_does() {
    goes_on("july_1914", 8, 90);
}

#[test]
fn the_same_through_twelve_years_of_peace_and_war() {
    goes_on("jan_1900", 16, 120);
}

fn goes_on(scenario: &str, rounds: usize, days: usize) {
    let data = data();
    let mut kept = start(&data, scenario);
    let mut through = start(&data, scenario);
    for round in 0..rounds {
        for _ in 0..days {
            kept.advance_day(&data);
            through.advance_day(&data);
        }
        // The saved copy goes through the bytes, and must read back as it was before it goes on.
        let bytes = save::to_bytes(&through).unwrap();
        let loaded = save::from_bytes(&bytes).unwrap();
        same(&format!("{scenario} round {round}, as loaded"), &through, &loaded);
        through = loaded;
        same(&format!("{scenario} round {round}, after {days} days"), &kept, &through);
    }
    if scenario == "july_1914" {
        assert!(kept.wars.len() + kept.war_history.len() > 0, "the test game should have seen war");
    }
}

#[test]
fn a_save_on_disk_reads_back_and_the_header_can_be_read_alone() {
    let data = data();
    let mut gs = start(&data, "jan_1900");
    for _ in 0..40 {
        gs.advance_day(&data);
    }
    let dir = std::env::temp_dir().join(format!("fs_save_test_{}", std::process::id()));
    let path = dir.join("one.sav");
    save::write(&gs, &path).unwrap();
    assert!(!dir.join("one.sav.tmp").exists());
    let bytes = std::fs::read(&path).unwrap();
    let (head, _) = save::read_header(&bytes).unwrap();
    assert_eq!(head.version, save::VERSION);
    assert_eq!(head.date, gs.calendar.date_string());
    assert_eq!(head.player, "SRB");
    assert_eq!(head.days, 40);
    same("from disk", &gs, &save::read(&path).unwrap());
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn what_is_not_a_save_is_refused() {
    assert!(save::from_bytes(b"").is_err());
    assert!(save::from_bytes(b"\x05\0\0\0hello").is_err());
    let head = serde_json::json!({"magic": "foreign-skies-rust-save", "version": 99, "date": "", "days": 0, "player": "", "scenario": ""}).to_string();
    let mut bytes = (head.len() as u32).to_le_bytes().to_vec();
    bytes.extend_from_slice(head.as_bytes());
    let err = save::from_bytes(&bytes).err().unwrap();
    assert!(err.contains("version 99"), "{err}");
    // A save cut short, or damaged, is not read as a game.
    let data = data();
    let gs = start(&data, "july_1914");
    let good = save::to_bytes(&gs).unwrap();
    assert!(save::from_bytes(&good[..good.len() / 2]).is_err());
    let mut bad = good.clone();
    let last = bad.len() - 1;
    bad[last / 2] ^= 0xff;
    assert!(save::from_bytes(&bad).is_err());
}
