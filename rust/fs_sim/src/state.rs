//! The game state (`scripts/sim/game_state.gd`): the provinces' owners, people and buildings, the nations, and what the
//! economy works out from them, with the rest of the state (armies, fleets, wars, treaties and more).
use crate::budget::{self, Budget};
use crate::clock::Calendar;
use crate::diplomacy::is_equal_approx;
use crate::config::{PressureConfig, DiplomacyConfig, EconomyConfig, FocusConfig, FocusEffects, MilitaryConfig, NavyConfig, WarSupportConfig};
use crate::economy::{self, Job};
use crate::gd::{clampf, maxf};
use crate::map::MapData;
use crate::military::{self, Army};
use crate::tsv::Table;
use serde_json::Value;
use std::cell::RefCell;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Everything the simulation reads from `data/`, loaded once.
#[derive(Debug, Clone)]
pub struct Data {
    pub dir: PathBuf,
    pub map: MapData,
    pub economy: EconomyConfig,
    pub military: MilitaryConfig,
    pub navy: NavyConfig,
    pub war_support: WarSupportConfig,
    pub diplomacy: DiplomacyConfig,
    pub focus: FocusConfig,
    pub pressure: PressureConfig,
    pub ai: crate::ai_peace::AiConfig,
    /// `data/crises.json` as the file has it.
    pub crises: serde_json::Value,
    /// `data/ambitions.json` as the file has it.
    pub ambitions: serde_json::Value,
    /// Names the books use (province, casus belli and treaty names).
    pub texts: crate::records::Texts,
}

impl Data {
    /// `Difficulty.apply`: the data for a game of a difficulty (`data/difficulty.json`): the AI's and the crisis generator's numbers as the files
    /// have them, scaled by the preset. An unknown preset counts as `historical`, which changes nothing.
    pub fn load_with_difficulty(dir: &Path, preset: &str) -> Result<Data, String> {
        let mut data = Data::load(dir)?;
        let text = std::fs::read_to_string(dir.join("difficulty.json")).map_err(|e| format!("difficulty.json: {e}"))?;
        let cfg: serde_json::Value = serde_json::from_str(&text).map_err(|e| format!("difficulty.json is invalid: {e}"))?;
        let presets = cfg["presets"].as_object().ok_or("difficulty.json: presets")?;
        let preset = presets.get(preset).unwrap_or_else(|| &presets["historical"]);
        let mut ai = data.ai.raw.clone();
        for e in preset.get("ai").and_then(serde_json::Value::as_array).into_iter().flatten() {
            Self::change(&mut ai, e);
        }
        data.ai = crate::ai_peace::AiConfig::from_json_str(&serde_json::to_string(&ai).unwrap())?;
        for e in preset.get("crisis").and_then(serde_json::Value::as_array).into_iter().flatten() {
            Self::change(&mut data.crises, e);
        }
        Ok(data)
    }

    /// `Difficulty._change`: multiplies the number at an entry's dotted path, or sets the value there.
    fn change(root: &mut serde_json::Value, e: &serde_json::Value) {
        let path = e["path"].as_str().unwrap();
        let keys: Vec<&str> = path.split('.').collect();
        let mut node = root;
        for k in &keys[..keys.len() - 1] {
            node = &mut node[*k];
        }
        let leaf = keys[keys.len() - 1];
        if let Some(v) = e.get("set") {
            node[leaf] = v.clone();
            return;
        }
        // the game reads every number of its files as a float
        node[leaf] = serde_json::json!(node[leaf].as_f64().unwrap() * e["mul"].as_f64().unwrap());
    }

    pub fn load(dir: &Path) -> Result<Data, String> {
        let read = |f: &str| std::fs::read_to_string(dir.join(f)).map_err(|e| format!("{f}: {e}"));
        let map = MapData::load(dir)?;
        let diplomacy_json: serde_json::Value = serde_json::from_str(&read("diplomacy.json")?).map_err(|e| format!("diplomacy.json is invalid: {e}"))?;
        let military_json: serde_json::Value = serde_json::from_str(&read("military.json")?).map_err(|e| format!("military.json is invalid: {e}"))?;
        let label_map = |v: &serde_json::Value| -> std::collections::HashMap<String, String> {
            v.as_object().map(|o| o.iter().filter(|(k, _)| !k.starts_with('_')).filter_map(|(k, d)| d.get("label").and_then(serde_json::Value::as_str).map(|l| (k.clone(), l.to_string()))).collect()).unwrap_or_default()
        };
        let texts = crate::records::Texts {
            province_names: map.provinces.iter().map(|p| p.name.clone()).collect(),
            cb_labels: label_map(&diplomacy_json["war"]["casus_belli"]),
            treaty_labels: label_map(&diplomacy_json["treaties"]),
            sea_zone_names: map.sea_zone_names.clone(),
            ship_names: {
                let navy_json: serde_json::Value = serde_json::from_str(&read("navy.json")?).map_err(|e| format!("navy.json is invalid: {e}"))?;
                navy_json["types"].as_object().map(|o| o.iter().filter_map(|(k, d)| d.get("name").and_then(serde_json::Value::as_str).map(|l| (k.clone(), l.to_string()))).collect()).unwrap_or_default()
            },
            terrain_names: military_json["terrain"].as_object().map(|o| o.iter().filter_map(|(k, d)| d.get("name").and_then(serde_json::Value::as_str).map(|l| (k.clone(), l.to_string()))).collect()).unwrap_or_default(),
        };
        Ok(Data {
            texts,
            dir: dir.to_path_buf(),
            map,
            economy: EconomyConfig::from_json_str(&read("economy.json")?)?,
            military: MilitaryConfig::from_json_str(&read("military.json")?)?,
            navy: NavyConfig::from_json_str(&read("navy.json")?)?,
            war_support: WarSupportConfig::from_json_str(&read("diplomacy.json")?)?,
            diplomacy: DiplomacyConfig::from_json_str(&read("diplomacy.json")?)?,
            focus: FocusConfig::from_json_str(&read("focus.json")?)?,
            pressure: PressureConfig::from_json_str(&read("events.json")?)?,
            ai: crate::ai_peace::AiConfig::from_json_str(&read("ai.json")?)?,
            crises: serde_json::from_str(&read("crises.json")?).map_err(|e| format!("crises.json is invalid: {e}"))?,
            ambitions: serde_json::from_str(&read("ambitions.json")?).map_err(|e| format!("ambitions.json is invalid: {e}"))?,
        })
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Nation {
    pub tag: String,
    pub display_name: String,
    pub treasury: f64,
    pub capital: i64,
    pub peacetime_army: i64,
    pub naval_budget: f64,
    pub mobilization: f64,
    /// Construction points in hand.
    pub cp: f64,
    /// What the national focus adds to base income (a fraction) and to the construction points a day.
    pub focus_income: f64,
    pub focus_cp: f64,
    /// What the national focus adds to the diplomacy points a month.
    pub focus_diplomacy: f64,
    /// The focus being worked on, the foci done, and how many times the repeatable ones were taken.
    pub focus: Option<ActiveFocus>,
    pub focus_done: Vec<String>,
    pub focus_count: Vec<(String, i64)>,
    pub prestige: f64,
    pub diplomacy_points: f64,
    pub points_price: f64,
    pub provinces: Vec<usize>,
    pub population: i64,
    pub government: String,
    pub war_support: f64,
    /// What war support settles at in peace (the scenario's, or its government's).
    pub war_support_base: f64,
    /// Whether the nation has capitulated in a war, and the capital it started the war with when it has moved since.
    pub capitulated: bool,
    pub home_capital: i64,
    /// Men lost in battle so far this month.
    pub men_lost_month: f64,
    /// How much of the nation's port and factory income the blockade cuts, 0 to 1.
    pub blockade: f64,
    pub blockade_target: f64,
    pub blockade_pinned: f64,
    pub blockade_by: Vec<String>,
    pub blockade_applied: f64,
    pub ships_lost: i64,
    /// The recruits' pool, and the men in armies (and training).
    pub manpower: i64,
    pub men_in_units: i64,
    pub men_exercising: i64,
    /// The part of the naval budget that is not ships: dockyards, bases, sailors ashore.
    pub naval_overhead: f64,
    pub budget: Budget,
    /// The construction queue, in order (projects waiting and under way), and hulls on the slips.
    pub construction: Vec<Job>,
    pub shipbuilding: Vec<Job>,
    pub recruiting: Vec<crate::military::Recruit>,
    /// Men killed this month, and in the war so far.
    pub deaths_month: f64,
    pub war_dead: f64,
}

/// The focus a nation is working on (`Nation.focus`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct ActiveFocus {
    pub id: String,
    pub days_left: i64,
    pub days_total: i64,
}

/// The record of one war (`War`): who started it and what each side lost and took. (Its log of events and battles, kept
/// for the screens, is not ported.)
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct War {
    pub id: u32,
    pub a: String,
    pub b: String,
    pub start_day: i64,
    /// The day of the last battle between the two sides (-1: none yet).
    pub last_fight_day: i64,
    /// Men killed or wounded in battle, lost to hunger away from supply, and destroyed because the army had nowhere to go.
    pub losses: HashMap<String, f64>,
    pub attrition: HashMap<String, f64>,
    pub surrendered: HashMap<String, f64>,
    /// War score earned from battles won; it fades monthly.
    pub battle_points: HashMap<String, f64>,
    /// tag -> (provinces, people) that nation took from the other.
    pub captured: HashMap<String, (i64, i64)>,
    /// Why `a` could declare it (a casus belli id, "" if it was set up directly) and what it fights for (a war goal as the
    /// game keeps it: `{kind, ids, demand}`, or null for none).
    pub casus_belli: String,
    pub goal: Value,
    /// The conflict it belongs to: pairwise wars opened together share a group.
    pub war_group: u32,
    /// tag -> date of the side that capitulated in this war.
    pub capitulated: HashMap<String, String>,
    /// The day it ended, or -1.
    pub end_day: i64,
    /// The books of the war (`War.start_date`, `end_date`, `peace`, `log`, `battles`).
    pub start_date: String,
    pub end_date: String,
    pub peace: Option<crate::records::PeaceRecord>,
    pub log: Vec<crate::records::WarLog>,
    pub battles: Vec<crate::records::BattleRecord>,
}

impl War {
    pub fn new(id: u32, a: &str, b: &str, start_day: i64) -> War {
        let both = |x: f64| [(a.to_string(), x), (b.to_string(), x)].into_iter().collect::<HashMap<_, _>>();
        War {
            id,
            a: a.to_string(),
            b: b.to_string(),
            start_day,
            last_fight_day: -1,
            losses: both(0.0),
            attrition: both(0.0),
            surrendered: both(0.0),
            battle_points: both(0.0),
            captured: [(a.to_string(), (0, 0)), (b.to_string(), (0, 0))].into_iter().collect(),
            casus_belli: String::new(),
            goal: Value::Null,
            war_group: 0,
            capitulated: HashMap::new(),
            end_day: -1,
            start_date: String::new(),
            end_date: String::new(),
            peace: None,
            log: vec![],
            battles: vec![],
        }
    }

    pub fn involves(&self, tag: &str) -> bool {
        self.a == tag || self.b == tag
    }

    pub fn other(&self, tag: &str) -> &str {
        if tag == self.a {
            &self.b
        } else {
            &self.a
        }
    }
}

/// A money payment from one nation to another at the end of a war (`GameState.indemnities`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Indemnity {
    pub payer: String,
    pub receiver: String,
    pub monthly: f64,
    pub months_left: i64,
}

/// A peace clause (`GameState.restrictions`): `nation`'s armies stay out of `provinces` (or it builds no new warships, when
/// `kind` is "fleet_limit") until `until_day`, unless it is at war with `holder`.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Restriction {
    pub nation: String,
    pub holder: String,
    pub kind: String,
    pub provinces: Vec<usize>,
    pub until_day: i64,
}

/// A major city (`data/scenarios/<scenario>/cities.tsv`).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct City {
    pub id: i64,
    pub name: String,
    pub province: usize,
    pub pop: i64,
    /// 1 a capital, 2 a great city, 3 a large one.
    pub rank: i64,
}

/// A battle in progress in a province (the part of `Military._engagement`'s record that bears on what happens).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Engagement {
    pub id: u32,
    pub province: usize,
    pub start_day: i64,
    pub start_date: String,
    pub name: String,
    pub attacker: String,
    /// The men each side had when it joined the battle, in the order the sides joined.
    pub start_men: Vec<(String, f64)>,
    /// What each side has lost in it.
    pub lost: Vec<(String, f64)>,
    pub armies: Vec<u32>,
    /// The account of the battle (`Military._engagement`'s dictionary in full): the ground, how it ended, each side, each day, in words.
    pub terrain: String,
    pub end_date: String,
    pub days: i64,
    pub winner: String,
    pub active: bool,
    pub sides: Vec<(String, BattleSide)>,
    pub timeline: Vec<BattleDay>,
    pub events: Vec<String>,
}

/// One side of a land battle.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct BattleSide {
    pub armies: Vec<(u32, String)>,
    pub generals: Vec<String>,
    pub comp_start: Vec<(String, i64)>,
    pub comp_now: Vec<(String, i64)>,
    pub comp_end: Vec<(String, i64)>,
    pub men_now: f64,
    pub men_end: f64,
    pub morale: f64,
    pub defense: f64,
}

/// A day of a land battle: men left, losses, morale and the defender's advantage per nation.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct BattleDay {
    pub day: i64,
    pub date: String,
    pub men: Vec<(String, f64)>,
    pub lost: Vec<(String, f64)>,
    pub morale: Vec<(String, f64)>,
    pub defense: Vec<(String, f64)>,
}

/// One standing agreement between two nations (`Treaty`). Kinds are in `data/diplomacy.json`.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Treaty {
    pub id: u32,
    pub kind: String,
    pub a: String,
    pub b: String,
    pub start_day: i64,
    /// The day the treaty lapses, or -1 if it has no end.
    pub end_day: i64,
    /// Kind-specific clauses: an alliance's `defensive_only` or `entente`.
    pub terms: Value,
    pub note: String,
}

impl Treaty {
    pub fn involves(&self, tag: &str) -> bool {
        self.a == tag || self.b == tag
    }

    /// The other party, or "" if `tag` is not in the treaty.
    pub fn other(&self, tag: &str) -> &str {
        if tag == self.a {
            &self.b
        } else if tag == self.b {
            &self.a
        } else {
            ""
        }
    }

    pub fn active_on(&self, day: i64) -> bool {
        day >= self.start_day && (self.end_day < 0 || day < self.end_day)
    }

    pub fn term(&self, key: &str) -> bool {
        self.terms.get(key).and_then(Value::as_bool).unwrap_or(false)
    }
}

/// An ally called up because a neighbour of theirs was alarmed (`GameState.mobilization_calls`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct MobilizationCall {
    pub tag: String,
    pub for_tag: String,
    pub against: String,
    pub day: i64,
}

/// An effort to improve relations (`GameState.relation_projects`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct RelationProject {
    pub from: String,
    pub to: String,
    pub months_left: i64,
}

/// A casus belli earned in play (`GameState.casus_belli`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct CasusBelli {
    /// The day a demand was refused (a casus belli from a crisis), or -1.
    pub refused_day: i64,
    pub holder: String,
    pub target: String,
    pub kind: String,
    pub expires_day: i64,
    /// The goal a refused demand gives a war (`fabricated_claim`), or null.
    pub goal: Value,
}

/// A nation's summed provinces (`GameState.economy_sums`): base income of those it holds, its share of enemy ground it
/// occupies, factory and port income, building upkeep, construction points a day, the manpower pool, and the levels of
/// each building (in the order first met).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Sums {
    pub base: f64,
    pub occupied: f64,
    pub factories: f64,
    pub ports: f64,
    pub upkeep: f64,
    pub cp: f64,
    pub pool: f64,
    pub levels: Vec<(String, f64)>,
}

impl Sums {
    pub fn level(&self, kind: &str) -> f64 {
        self.levels.iter().find(|(k, _)| k == kind).map(|(_, v)| *v).unwrap_or(0.0)
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct GameState {
    pub scenario: String,
    /// In the order the game goes through its nations (`data/nations.json`).
    pub nations: Vec<Nation>,
    pub nation_index: HashMap<String, usize>,
    /// Indexed by province id; element 0 is unused.
    pub province_owner: Vec<String>,
    pub province_controller: Vec<String>,
    pub province_population: Vec<i32>,
    /// The part of a person each province's growth has not yet added (the game keeps it as a 32-bit float).
    pub province_pop_frac: Vec<f32>,
    /// Building type and level, in the order the works were added.
    pub province_buildings: Vec<Vec<(String, i32)>>,
    /// Each province's base income, gold a month, from its people at the start (the game keeps it as a 32-bit float).
    pub province_base_income: Vec<f32>,
    /// One per nation, in `nations` order.
    pub economy_sums: Vec<Sums>,
    /// The armies, in the order they were raised (their ids rise with it).
    pub armies: Vec<Army>,
    pub next_army_id: u32,
    pub fronts: Vec<crate::front::Front>,
    pub next_front_id: u32,
    pub army_groups: Vec<crate::group::ArmyGroup>,
    pub next_group_id: u32,
    pub attack_lines: Vec<crate::group::AttackLine>,
    pub next_attack_line_id: u32,
    pub offensives: Vec<crate::offensive::Offensive>,
    pub next_offensive_id: u32,
    pub generals: Vec<crate::military::General>,
    pub next_general_id: u32,
    pub fleets: Vec<Fleet>,
    pub next_fleet_id: u32,
    /// Who holds each sea zone, in the order the zones were first met (`GameState.sea_control`).
    pub sea_control: Vec<(usize, SeaControl)>,
    pub sea_battles: Vec<(usize, SeaBattle)>,
    pub sea_battle_archive: Vec<SeaBattle>,
    /// The finished land battles, the oldest dropped past 300 (`GameState.battle_archive`).
    pub battle_archive: Vec<Engagement>,
    /// Set when a nation's blockade moved enough for its budget to be worked out again (`GameState.budget_dirty`).
    pub budget_dirty: bool,
    /// Naval bases (dockyards) from the scenario: province -> level the biggest ship there needs. They count as a port for the
    /// navy, not for the economy.
    pub naval_bases: HashMap<usize, i64>,
    /// The wars being fought, in the order they began. (Loading does not start a scenario's wars yet.)
    pub wars: Vec<War>,
    /// Finished wars, oldest first.
    pub war_history: Vec<War>,
    pub next_war_id: u32,
    pub next_war_group: u32,
    /// Indemnities being paid, and peace clauses keeping a nation's armies out of its border provinces or its yards shut.
    pub indemnities: Vec<Indemnity>,
    pub restrictions: Vec<Restriction>,
    /// Peace offers waiting for the player's answer, oldest first, and the next id.
    pub pending_offers: Vec<crate::peace::Offer>,
    /// The conflicts (`GameState.war_groups`), the join decisions waiting for the player, the AI nations called to join that
    /// are still mobilizing (key "TAG|GROUP"), and the next decision id.
    pub war_groups: Vec<crate::declare::WarGroup>,
    pub pending_joins: Vec<crate::declare::JoinDecision>,
    pub join_calls: Vec<(String, crate::declare::JoinDecision)>,
    pub next_decision_id: u32,
    /// What the AI nations answered when asked to join a conflict (`AIDiplomacy.joins`), keyed "TAG|GROUP": the AI is not part
    /// of this port, so a test supplies the answers.
    pub ai_join_answers: HashMap<String, bool>,
    /// Wars the AI has opened, and how many had no casus belli (`ai_declarations`).
    pub ai_declarations: (i64, i64),
    /// The scenario's own claims (read as data).
    pub scenario_claims: Vec<Value>,
    /// The choice of a new capital waiting for the player (`GameState.capital_choice`).
    pub capital_choice: Option<crate::capitulation::CapitalChoice>,
    /// What the AI's peace rules gave for each war a capitulation ends (`AIPeace.price_terms` and `AIPeace.accepts`), supplied by a test.
    pub ai_dictation: Vec<crate::capitulation::Dictation>,
    /// The scenario's wars that exist from the start, and whether their allies are called at once (see `start_scenario_wars`).
    pub starting_wars: Vec<(String, String)>,
    pub start_crisis: bool,
    pub next_offer_id: u32,
    /// Pair key -> the day until which a refused proposer may not ask again.
    pub peace_cooldown: HashMap<String, i64>,
    /// The nations making peace together at a conference (`Peace.joint_tags`).
    pub joint_tags: Vec<String>,
    /// A counter-offer waiting for the player (`GameState.conference_counter`).
    pub conference_counter: Option<crate::conference::Counter>,
    /// What the nations' temperaments are (`GameState.ai_traits`), the AI's seed (0: nothing varies), and its war plans.
    pub ai_traits: HashMap<String, (f64, f64)>,
    pub ai_seed: i64,
    /// The month each nation's budget was last worked over by the AI (`ai_budget_stamp`).
    pub ai_budget_stamp: HashMap<String, i64>,
    /// The books (see `records.rs`): the history of the run, every change of owner, a row a month, the standings, the player's ambition.
    pub history_log: Vec<crate::records::Note>,
    pub territory_log: Vec<crate::records::Territory>,
    pub history_months: Vec<crate::records::MonthRow>,
    pub history_provinces: i64,
    pub history_battles_total: i64,
    pub history_losses_total: f64,
    pub standings_history: Vec<crate::records::StandingsRow>,
    pub ambition: crate::records::AmbitionState,
    pub texts: crate::records::Texts,
    /// The AI's navy: each nation's fleets and the zone each was sent to (`ai_navy`), the landing being prepared (`ai_landing`) and the day it may
    /// look for another, the ship a nation asks its budget for (`ai_navy_need`), the fleets with armies aboard (`AINavy._carrying`) and what the
    /// AI keeps for the day about the sea.
    pub ai_navy: HashMap<String, HashMap<u32, usize>>,
    pub ai_landing: HashMap<String, crate::ai_navy::Landing>,
    pub ai_landing_wait: HashMap<String, i64>,
    pub ai_navy_need: HashMap<String, String>,
    pub ai_carrying: std::cell::RefCell<std::collections::BTreeSet<u32>>,
    pub ai_navy_caches: std::cell::RefCell<crate::ai_navy::NavyCaches>,
    /// What the AI keeps for the day (`AI._index`, `_threat_cache`, `_worth_cache`): the armies in each province as they stood when the first
    /// question of the day was asked (it is built again only when the number of armies or wars changes), the threat on a province, and a
    /// nation's output. They are forgotten when a province changes hands.
    pub ai_index: std::cell::RefCell<(i64, HashMap<usize, Vec<u32>>)>,
    pub ai_threat_cache: std::cell::RefCell<HashMap<(String, usize), f64>>,
    pub ai_worth_cache: std::cell::RefCell<HashMap<String, (i64, f64)>>,
    /// The campaigns the AI runs: the main one and the others against other enemies, and the day each nation may look for another (`ai_campaign`).
    pub ai_campaign: HashMap<String, crate::ai_offense::Campaign>,
    pub ai_campaign_extra: HashMap<String, Vec<crate::ai_offense::Campaign>>,
    pub ai_campaign_wait: HashMap<String, i64>,
    pub next_campaign_uid: u64,
    /// The month each nation last looked over its treaties (`ai_diplo_stamp`).
    pub ai_diplo_stamp: HashMap<String, i64>,
    /// While a batch of evaluations runs (the monthly treaty search), each nation's power added up once (`AIDiplomacy._powers`).
    pub ai_powers: std::cell::RefCell<Option<HashMap<String, f64>>>,
    /// The day each front's anchors were last chosen, and the army each nation holds in reserve (`ai_anchor_stamp`, `ai_reserve`).
    pub ai_anchor_stamp: HashMap<u32, i64>,
    pub ai_reserve: HashMap<String, u32>,
    /// The target each AI nation has set its sights on and the day it did, and the day before which it sets none (`ai_ambition`).
    pub ai_ambition: HashMap<String, (String, i64)>,
    pub ai_ambition_wait: HashMap<String, i64>,
    /// Which parts of the AI's turn run in `advance_day` (the rest of it is not ported yet).
    pub ai_turn: crate::ai_turn::AiTurn,
    pub crises: Vec<crate::crisis::Crisis>,
    pub crisis_log: Vec<crate::crisis::CrisisEnded>,
    pub crisis_cooldown: HashMap<String, i64>,
    pub next_crisis_id: u32,
    /// The scenario's own `ai_war_gate` (null: the file's).
    pub scenario_war_gate: serde_json::Value,
    pub ai_plans: Vec<serde_json::Value>,
    pub cities: Vec<City>,
    /// What each province's people numbered when the scenario began: the cities grow and shrink with the ratio.
    pub province_pop_base: Vec<i32>,
    /// Province -> (the nation taking it, days it has held it): an army is taking the province.
    pub occupation: HashMap<usize, (String, i64)>,
    /// Battles being fought now, by province, in the order they began.
    pub engagements: Vec<Engagement>,
    pub next_battle_id: u32,
    /// The day a battle in each province last ended.
    pub last_battle_day: HashMap<usize, i64>,
    /// Count the changes of who owns and who holds provinces.
    pub owner_version: u64,
    pub control_version: u64,
    /// Answers the game keeps for the day (`Military`'s supply and home-connection caches), forgotten when a province changes
    /// hands.
    pub supply_cache: RefCell<SupplyCache>,
    pub home_cache: RefCell<HomeCache>,
    /// The cities' reach over the ground (`Military.city_aura`), kept while who owns and holds what is unchanged.
    /// `Diplomacy._neighbor_nations`: the land neighbours of each nation, kept while the owners stay as they were. The lists are
    /// shared, as in the GDScript, where `_earn_unprovoked_aggression` adds to the cached list of the aggressor.
    /// `Peace._value_cache`: the day, each province's value that day and each city province's people (`Peace.province_value`).
    pub value_cache: RefCell<(i64, HashMap<usize, f64>, HashMap<usize, i64>)>,
    pub neighbor_cache: RefCell<Option<(u64, HashMap<String, Vec<String>>)>>,
    pub aura_cache: RefCell<Option<((u64, u64), HashMap<String, HashMap<usize, f64>>)>>,
    /// The nation the player plays ("" for none).
    pub player_tag: String,
    pub calendar: Calendar,
    /// Opinion of each pair of nations, -100 to 100, keyed "A|B" with the tags sorted (`GameState.relations`). The scenario's
    /// starting opinions are set by `Diplomacy.load_scenario`, which is not ported yet, so a test sets them.
    pub relations: HashMap<String, f64>,
    pub casus_belli: Vec<CasusBelli>,
    /// What each pair's opinion settles at (`GameState.relation_base`).
    pub relation_base: HashMap<String, f64>,
    /// The treaties ever signed, ended ones included, and the next id.
    pub treaties: Vec<Treaty>,
    pub next_treaty_id: u32,
    /// The blocs of the scenario: name and members.
    pub blocs: Vec<(String, Vec<String>)>,
    /// How much "A>B" resents B, 0 to 100, and the old rivalries that keep a floor under it.
    pub grievance: HashMap<String, f64>,
    pub rivalries: HashMap<String, f64>,
    /// "A>B": the day A's mobilization alarmed B.
    pub alarms: HashMap<String, i64>,
    /// "ALLY|AGAINST": allies called up because a neighbour of theirs was alarmed.
    pub mobilization_calls: HashMap<String, MobilizationCall>,
    /// Efforts to improve relations under way.
    pub relation_projects: Vec<RelationProject>,
    /// Money recently gifted, "from>to".
    pub gift_memory: HashMap<String, f64>,
    /// Set when something changed the economy in the middle of the day's step; the step recomputes once at its end.
    pub economy_dirty: bool,
    /// True while the daily step runs: what changes the economy then only marks it dirty (`Economy.request`).
    pub in_day_step: bool,
    /// Europe's tension, 0 to 100, the part of it that comes from events, the great powers' men under arms when it began, the
    /// aggression it adds to the AI, and whether it steers the AI (`GameState.tension` and friends; see `Pressure`).
    pub tension: f64,
    pub tension_impulse: f64,
    pub tension_arms_base: f64,
    pub tension_bonus: f64,
    pub pressure_ai: bool,
    /// The month the scenario began (year * 12 + month).
    pub pressure_start: i64,
    /// The events that have come up: id -> month index.
    pub events_fired: HashMap<String, i64>,
    /// Nation tag -> the day before which it may not take another public stand.
    pub appeal_ready: HashMap<String, i64>,
    /// Events waiting for the player's answer, oldest first.
    pub pending_events: Vec<PendingEvent>,
    pub next_event_uid: u32,
    /// What has happened lately, newest first: (date, title, text).
    pub chronicle: Vec<(String, String, String)>,
    pub tension_history: Vec<f64>,
    /// Claims made in play (`GameState.claims`): ground lost at a peace. (Peace is not ported, so none are made.)
    pub claims: Vec<Value>,
}

/// An event waiting for the player (`GameState.pending_events`).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PendingEvent {
    pub id: u32,
    pub event: String,
    pub title: String,
    pub text: String,
    /// Role -> nation tag, in the order the event names them.
    pub roles: Vec<(String, String)>,
    pub options: Vec<Value>,
    /// Effects held until the player answers (a war another nation chose), with the roles they were made under.
    pub deferred: Vec<(Value, Vec<(String, String)>)>,
    pub date: String,
    pub as_b: bool,
}

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct SupplyCache {
    pub stamp: Option<(i64, u64)>,
    pub costs: HashMap<(String, usize), f64>,
}

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct HomeCache {
    pub day: i64,
    pub answers: HashMap<(String, usize), bool>,
}


/// One squadron of a fleet (`Ship`): strength is the share of it still afloat and fit to fight, morale is 0 to 1.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Ship {
    pub kind: String,
    pub strength: f64,
    pub morale: f64,
}

impl Ship {
    pub fn new(kind: &str) -> Ship {
        Ship { kind: kind.to_string(), strength: 1.0, morale: 1.0 }
    }
}

/// A stack of ships under one flag (`Fleet`): in a port (`port` > 0, `zone` 0) or in a sea zone (`zone` > 0, `port` 0).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Fleet {
    pub id: u32,
    pub tag: String,
    pub name: String,
    pub ships: Vec<Ship>,
    pub zone: usize,
    pub port: usize,
    pub path: Vec<usize>,
    pub dest_port: usize,
    pub move_days_left: f64,
    pub entering: bool,
    pub landing: usize,
    pub mission: String,
    pub fighting: bool,
    pub engaged: bool,
    pub retreating: bool,
    pub days_out: i64,
}

impl Fleet {
    pub fn new(id: u32, tag: &str, name: &str, port: usize) -> Fleet {
        Fleet {
            id,
            tag: tag.to_string(),
            name: name.to_string(),
            ships: vec![],
            zone: 0,
            port,
            path: vec![],
            dest_port: 0,
            move_days_left: 0.0,
            entering: false,
            landing: 0,
            mission: "station".to_string(),
            fighting: false,
            engaged: false,
            retreating: false,
            days_out: 0,
        }
    }

    pub fn is_in_port(&self) -> bool {
        self.port > 0
    }

    pub fn is_moving(&self) -> bool {
        !self.path.is_empty() || self.entering
    }
}

/// A battle at sea, kept while it lasts and then filed (`GameState.sea_battles`, `sea_battle_archive`).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SeaBattle {
    pub id: u32,
    pub zone: usize,
    pub start_day: i64,
    pub days: i64,
    pub fleets: Vec<u32>,
    pub start_ships: Vec<(String, i64)>,
    pub lost: Vec<(String, f64)>,
    pub sunk: Vec<(String, i64)>,
    pub winner: String,
    pub active: bool,
    /// The account of the battle: where and when, what happened each day, and in words.
    pub name: String,
    pub start_date: String,
    pub end_date: String,
    pub timeline: Vec<(i64, Vec<(String, f64)>)>,
    pub events: Vec<String>,
}

/// Who holds a sea zone today (`GameState.sea_control`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct SeaControl {
    pub holders: Vec<String>,
    pub contested: bool,
    pub power: Vec<(String, f64)>,
}

impl GameState {
    pub fn nation(&self, tag: &str) -> &Nation {
        &self.nations[self.nation_index[tag]]
    }

    /// `GameState.load_scenario`, as far as the economy is concerned: the provinces and nations are set up, the works a
    /// scenario starts with are absorbed into each nation's development, and the economy is worked out once.
    pub fn load_scenario(data: &Data, name: &str) -> Result<GameState, String> {
        let dir = data.dir.join("scenarios").join(name);
        let scenario: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join("scenario.json")).map_err(|e| format!("scenario.json: {e}"))?,
        )
        .map_err(|e| format!("scenario.json is invalid: {e}"))?;
        let count = data.map.provinces.len();
        let mut gs = GameState {
            scenario: name.to_string(),
            nations: vec![],
            nation_index: HashMap::new(),
            province_owner: vec![String::new(); count],
            province_controller: vec![String::new(); count],
            province_population: vec![0; count],
            province_pop_frac: vec![0.0; count],
            province_buildings: vec![vec![]; count],
            province_base_income: vec![0.0; count],
            economy_sums: vec![],
            armies: vec![],
            next_army_id: 1,
            fronts: vec![],
            next_front_id: 1,
            army_groups: vec![],
            next_group_id: 1,
            attack_lines: vec![],
            next_attack_line_id: 1,
            offensives: vec![],
            next_offensive_id: 1,
            generals: vec![],
            next_general_id: 1,
            fleets: vec![],
            next_fleet_id: 1,
            sea_control: vec![],
            sea_battles: vec![],
            sea_battle_archive: vec![],
            battle_archive: vec![],
            budget_dirty: false,
            naval_bases: HashMap::new(),
            wars: vec![],
            war_history: vec![],
            next_war_group: 1,
            indemnities: vec![],
            restrictions: vec![],
            pending_offers: vec![],
            war_groups: vec![],
            pending_joins: vec![],
            join_calls: vec![],
            next_decision_id: 1,
            ai_join_answers: HashMap::new(),
            ai_declarations: (0, 0),
            starting_wars: scenario.get("starting_wars").and_then(Value::as_array).map(|a| a.iter().map(|p| (p[0].as_str().unwrap().to_string(), p[1].as_str().unwrap().to_string())).collect()).unwrap_or_default(),
            start_crisis: scenario.get("start_crisis").and_then(Value::as_bool).unwrap_or(false),
            capital_choice: None,
            ai_dictation: vec![],
            scenario_claims: scenario.get("claims").and_then(Value::as_array).cloned().unwrap_or_default(),
            next_offer_id: 1,
            peace_cooldown: HashMap::new(),
            joint_tags: vec![],
            conference_counter: None,
            ai_traits: HashMap::new(),
            ai_seed: 0,
            ai_budget_stamp: HashMap::new(),
            history_log: vec![],
            territory_log: vec![],
            history_months: vec![],
            history_provinces: 0,
            history_battles_total: 0,
            history_losses_total: 0.0,
            standings_history: vec![],
            ambition: Default::default(),
            texts: data.texts.clone(),
            ai_navy: HashMap::new(),
            ai_landing: HashMap::new(),
            ai_landing_wait: HashMap::new(),
            ai_navy_need: HashMap::new(),
            ai_carrying: std::cell::RefCell::new(Default::default()),
            ai_navy_caches: std::cell::RefCell::new(crate::ai_navy::NavyCaches { weight_day: -1, ..Default::default() }),
            ai_index: std::cell::RefCell::new((-1, HashMap::new())),
            ai_threat_cache: std::cell::RefCell::new(HashMap::new()),
            ai_worth_cache: std::cell::RefCell::new(HashMap::new()),
            ai_campaign: HashMap::new(),
            ai_campaign_extra: HashMap::new(),
            ai_campaign_wait: HashMap::new(),
            next_campaign_uid: 0,
            ai_diplo_stamp: HashMap::new(),
            ai_powers: std::cell::RefCell::new(None),
            ai_anchor_stamp: HashMap::new(),
            ai_reserve: HashMap::new(),
            ai_ambition: HashMap::new(),
            ai_ambition_wait: HashMap::new(),
            ai_turn: Default::default(),
            crises: vec![],
            crisis_log: vec![],
            crisis_cooldown: HashMap::new(),
            next_crisis_id: 1,
            scenario_war_gate: scenario.get("ai_war_gate").cloned().unwrap_or(Value::Null),
            ai_plans: vec![],
            next_war_id: 1,
            cities: vec![],
            province_pop_base: vec![],
            occupation: HashMap::new(),
            engagements: vec![],
            next_battle_id: 1,
            last_battle_day: HashMap::new(),
            owner_version: 0,
            control_version: 0,
            supply_cache: RefCell::new(SupplyCache::default()),
            home_cache: RefCell::new(HomeCache { day: -1, answers: HashMap::new() }),
            value_cache: RefCell::new((-1, HashMap::new(), HashMap::new())),
            neighbor_cache: RefCell::new(None),
            aura_cache: RefCell::new(None),
            player_tag: scenario.get("default_player").and_then(Value::as_str).unwrap_or("").to_string(),
            calendar: {
                let d = scenario.get("start_date").and_then(Value::as_array).ok_or("scenario: start_date")?;
                Calendar::start(d[0].as_i64().unwrap_or(1900) as i32, d[1].as_i64().unwrap_or(1) as i32, d[2].as_i64().unwrap_or(1) as i32)
            },
            relations: HashMap::new(),
            casus_belli: vec![],
            relation_base: HashMap::new(),
            treaties: vec![],
            next_treaty_id: 1,
            blocs: scenario
                .get("blocs")
                .and_then(Value::as_object)
                .map(|o| o.iter().map(|(k, v)| (k.clone(), v.as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect()).unwrap_or_default())).collect())
                .unwrap_or_default(),
            grievance: HashMap::new(),
            rivalries: HashMap::new(),
            alarms: HashMap::new(),
            mobilization_calls: HashMap::new(),
            relation_projects: vec![],
            gift_memory: HashMap::new(),
            economy_dirty: false,
            in_day_step: false,
            tension: 0.0,
            tension_impulse: 0.0,
            tension_arms_base: 1.0,
            tension_bonus: 0.0,
            pressure_ai: false,
            pressure_start: 0,
            events_fired: HashMap::new(),
            appeal_ready: HashMap::new(),
            pending_events: vec![],
            next_event_uid: 1,
            chronicle: vec![],
            tension_history: vec![],
            claims: vec![],
        };
        for id in 1..count {
            gs.province_owner[id] = data.map.provinces[id].owner.clone();
            gs.province_controller[id] = data.map.provinces[id].owner.clone();
        }
        let mut by_name: HashMap<&str, usize> = HashMap::new();
        for id in 1..count {
            by_name.insert(data.map.provinces[id].name.as_str(), id);
        }
        // The buildings each nation starts with (tools/make_start_economy.py).
        if let Some(works) = scenario.get("buildings").and_then(Value::as_object) {
            for (pname, types) in works {
                let id = *by_name.get(pname.as_str()).ok_or_else(|| format!("scenario building: no province {pname}"))?;
                for (t, level) in types.as_object().ok_or("scenario buildings: not an object")? {
                    set_building(&mut gs.province_buildings[id], t, level.as_f64().unwrap_or(0.0) as i32);
                }
            }
        }
        if let Some(changes) = scenario.get("owner_changes").and_then(Value::as_object) {
            for (pname, tag) in changes {
                let id = *by_name.get(pname.as_str()).ok_or_else(|| format!("owner_changes: no province {pname}"))?;
                let tag = tag.as_str().ok_or("owner_changes: not a tag")?.to_string();
                gs.province_owner[id] = tag.clone();
                gs.province_controller[id] = tag;
            }
        }
        for row in Table::read(&dir.join("provinces.tsv"))?.rows() {
            gs.province_population[row.int("id") as usize] = row.int("population") as i32;
        }
        gs.province_pop_base = gs.province_population.clone();
        if dir.join("cities.tsv").exists() {
            for row in Table::read(&dir.join("cities.tsv"))?.rows() {
                gs.cities.push(City { id: row.int("id"), name: row.get("name").to_string(), province: row.int("province") as usize, pop: row.int("pop"), rank: row.int("rank") });
            }
        }
        let no_nations = Value::Object(Default::default());
        let nations_json = scenario.get("nations").unwrap_or(&no_nations);
        for info in &data.map.nations {
            let s = nations_json.get(&info.tag).cloned().unwrap_or(Value::Object(Default::default()));
            let f = |k: &str, d: f64| s.get(k).and_then(Value::as_f64).unwrap_or(d);
            gs.nation_index.insert(info.tag.clone(), gs.nations.len());
            gs.nations.push(Nation {
                tag: info.tag.clone(),
                display_name: info.name.clone(),
                treasury: f("treasury", 0.0),
                capital: f("capital", 0.0) as i64,
                peacetime_army: f("peacetime_army", 0.0) as i64,
                naval_budget: f("naval_budget", 0.0),
                mobilization: f("mobilization", 0.0),
                cp: 0.0,
                focus_income: 0.0,
                focus_cp: 0.0,
                focus_diplomacy: 0.0,
                focus: None,
                focus_done: vec![],
                focus_count: vec![],
                prestige: f("prestige", 0.0),
                diplomacy_points: f("diplomacy_points", data.diplomacy.points_start),
                points_price: 1.0,
                provinces: vec![],
                population: 0,
                government: s.get("government").and_then(Value::as_str).unwrap_or("").to_string(),
                war_support: s
                    .get("war_support")
                    .and_then(Value::as_f64)
                    .unwrap_or_else(|| data.war_support.start_value(s.get("government").and_then(Value::as_str).unwrap_or(""))),
                war_support_base: 0.0,
                capitulated: false,
                home_capital: 0,
                men_lost_month: 0.0,
                blockade: 0.0,
                blockade_target: 0.0,
                blockade_pinned: -1.0,
                blockade_by: vec![],
                blockade_applied: 0.0,
                ships_lost: 0,
                manpower: f("peacetime_army", 0.0) as i64,
                men_in_units: 0,
                men_exercising: 0,
                naval_overhead: 0.0,
                budget: Budget::default(),
                construction: vec![],
                shipbuilding: vec![],
                recruiting: vec![],
                deaths_month: 0.0,
                war_dead: 0.0,
            });
        }
        for n in &mut gs.nations {
            n.war_support_base = n.war_support;
        }
        gs.rebuild_nation_provinces()?;
        gs.deploy_starting_armies(data, scenario.get("deployment").unwrap_or(&no_nations))?;
        gs.deploy_starting_fleets(data, &dir)?;
        gs.economy_load_scenario(data);
        gs.recompute(data);
        gs.load_diplomacy(data, &scenario)?;
        gs.load_pressure(data, &scenario);
        // `AI.load_scenario`: the scenario's own temperaments, the default filling in what an entry leaves out.
        if let Some(traits) = scenario.get("ai_traits").and_then(Value::as_object) {
            for (tag, entry) in traits {
                assert!(gs.nation_index.contains_key(tag), "ai_traits names an unknown nation: {tag}");
                let (mut a, mut c) = (data.ai.default_aggression, data.ai.default_caution);
                for (k, v) in entry.as_object().unwrap() {
                    let v = v.as_f64().unwrap();
                    assert!((0.0..=1.0).contains(&v), "ai_traits {tag}.{k} must be between 0 and 1");
                    match k.as_str() {
                        "aggression" => a = v,
                        "caution" => c = v,
                        _ => panic!("ai_traits for {tag} has an unknown trait: {k}"),
                    }
                }
                gs.ai_traits.insert(tag.clone(), (a, c));
            }
        }
        // `History.load_scenario`: the books begin here
        gs.history_log.clear();
        gs.territory_log.clear();
        gs.history_months.clear();
        gs.history_provinces = 0;
        gs.history_battles_total = 0;
        gs.history_losses_total = 0.0;
        gs.standings_history.clear();
        gs.standings_record(data);
        Ok(gs)
    }

    /// `Military.deploy_starting`: each nation's peacetime army, as divisions dealt out among the stacks the scenario
    /// lists, under the commanders its list names; then the men each nation has under arms and its reserve.
    pub fn deploy_starting_armies(&mut self, data: &Data, deployment: &Value) -> Result<(), String> {
        let mil = &data.military;
        self.armies.clear();
        self.next_army_id = 1;
        self.generals.clear();
        self.next_general_id = 1;
        self.army_groups.clear();
        self.next_group_id = 1;
        self.attack_lines.clear();
        self.next_attack_line_id = 1;
        let names: Vec<String> = data.map.provinces.iter().map(|p| p.name.clone()).collect();
        for ni in 0..self.nations.len() {
            let (tag, peacetime) = (self.nations[ni].tag.clone(), self.nations[ni].peacetime_army);
            if peacetime <= 0 {
                continue;
            }
            let units = military::starting_units(mil, (peacetime as f64 * mil.field_share) as i64);
            let null = Value::Null;
            let stacks = military::stack_plan(deployment.get(&tag).unwrap_or(&null), &tag, &names, &self.province_owner)?;
            let first_id = self.next_army_id;
            self.next_army_id += stacks.len() as u32;
            // Every general in the nation's list joins its pool; the first ones lead the armies (one whose army is left with no
            // units still has its id: he is freed on the first day).
            let generals = mil.generals_of(&tag);
            for (i, g) in generals.iter().enumerate() {
                let id = self.next_general_id;
                self.next_general_id += 1;
                self.generals.push(crate::military::General { id, tag: tag.clone(), name: g.0.clone(), skill: g.1, army_id: if i < stacks.len() { first_id + i as u32 } else { 0 }, group_id: 0 });
            }
            let held = military::deal_units(mil, units, &stacks);
            for (i, stack) in stacks.iter().enumerate() {
                if held[i].is_empty() {
                    continue; // an army left with no units is dropped (its id is still used)
                }
                self.armies.push(Army {
                    id: first_id + i as u32,
                    tag: tag.clone(),
                    name: stack.name.clone(),
                    province: stack.province,
                    units: held[i].clone(),
                    general_skill: generals.get(i).map(|g| g.1).unwrap_or(1.0),
                    landing_days: 0,
                    path: vec![],
                    move_days_left: 0.0,
                    still_days: 0,
                    attacking: false,
                    fighting: false,
                    supplied: true,
                    landed_supply: 0,
                    fleet_id: 0,
                    general_id: if i < generals.len() { self.generals[self.generals.len() - generals.len() + i].id } else { 0 },
                    front_id: 0,
                    parent_id: 0,
                    pin: 0,
                    prepared: false,
                    planning: 0.0,
                    group_id: 0,
                    marshal: 1.0,
                    training: false,
                });
            }
        }
        self.refresh_men(data);
        for n in &mut self.nations {
            n.manpower = (n.peacetime_army - n.men_in_units).max(0);
        }
        Ok(())
    }

    /// `Military.men_in_service`: men in the field plus recruits in training.
    pub fn men_in_service(&self, data: &Data, tag: &str) -> i64 {
        let mut total = 0.0;
        for a in self.armies.iter().filter(|a| a.tag == tag) {
            total += a.men(&data.military);
        }
        for job in &self.nation(tag).recruiting {
            total += data.military.unit_type(&job.unit_type).size as f64;
        }
        total.round() as i64
    }

    /// `Military.refresh_men`: the men each nation has under arms, and how many of them are on exercise.
    pub fn refresh_men(&mut self, data: &Data) {
        for i in 0..self.nations.len() {
            self.nations[i].men_in_units = self.men_in_service(data, &self.nations[i].tag.clone());
            self.nations[i].men_exercising = 0;
        }
        for i in 0..self.armies.len() {
            if self.root_of(i).map(|r| self.armies[r].training).unwrap_or(false) {
                let men = self.armies[i].men(&data.military).round() as i64;
                let ni = self.nation_index[&self.armies[i].tag];
                self.nations[ni].men_exercising += men;
            }
        }
    }

    /// `Navy.deploy_starting` (and `_give_home_ports`): the starting fleets from navy.tsv; the port building a nation
    /// that starts with a navy gets if it owns none; each nation's naval overhead (what the scenario's historical naval
    /// budget does not spend on ships); and the naval budget that follows.
    pub fn deploy_starting_fleets(&mut self, data: &Data, dir: &Path) -> Result<(), String> {
        self.fleets.clear();
        self.next_fleet_id = 1;
        let mut naval_bases: HashMap<usize, i64> = HashMap::new();
        for row in Table::read(&dir.join("navy.tsv"))?.rows() {
            let (tag, province) = (row.get("tag").to_string(), row.int("province") as usize);
            let ship = row.get("type");
            let min_port = data.navy.min_port(ship).ok_or_else(|| format!("navy.tsv: unknown ship type {ship}"))?;
            if !self.nation_index.contains_key(&tag) {
                return Err(format!("navy.tsv: unknown nation {tag}"));
            }
            let at = self.fleets.iter().position(|f| f.tag == tag && f.port == province && f.name == row.get("fleet"));
            let at = match at {
                Some(i) => i,
                None => {
                    self.new_fleet(&tag, row.get("fleet"), province);
                    self.fleets.len() - 1
                }
            };
            for _ in 0..row.int("count") {
                self.fleets[at].ships.push(Ship::new(ship));
            }
            let slot = naval_bases.entry(province).or_insert(1);
            *slot = (*slot).max(min_port);
        }
        // A nation that starts with a navy starts with at least one port: if it owns none, its biggest naval base gets a
        // level 1 port.
        let base = |id: usize| naval_bases.get(&id).copied().unwrap_or(0);
        let mut home: Vec<(String, usize)> = vec![];
        for f in &self.fleets {
            match home.iter_mut().find(|(t, _)| *t == f.tag) {
                Some(slot) => {
                    if slot.1 == 0 || base(f.port) > base(slot.1) {
                        slot.1 = f.port;
                    }
                }
                None => home.push((f.tag.clone(), f.port)),
            }
        }
        for id in 1..self.province_owner.len() {
            if self.province_buildings[id].iter().any(|(k, l)| k == "port" && *l > 0) {
                home.retain(|(t, _)| *t != self.province_owner[id]);
            }
        }
        for (tag, province) in home {
            if self.province_owner[province] == tag {
                set_building(&mut self.province_buildings[province], "port", 1);
            }
        }
        self.naval_bases = naval_bases;
        for i in 0..self.nations.len() {
            let upkeep = self.ship_upkeep(data, &self.nations[i].tag);
            self.nations[i].naval_overhead = maxf(0.0, self.nations[i].naval_budget - upkeep);
        }
        self.refresh_upkeep(data);
        Ok(())
    }

    /// `Navy.ship_upkeep`: yearly cost of the ships a nation has afloat.
    pub fn ship_upkeep(&self, data: &Data, tag: &str) -> f64 {
        let mut total = 0.0;
        for f in self.fleets.iter().filter(|f| f.tag == tag) {
            for s in &f.ships {
                total += data.navy.upkeep(&s.kind);
            }
        }
        total
    }

    /// `Navy.refresh_upkeep`: every nation's yearly naval cost is the shore establishment plus its ships' upkeep.
    pub fn refresh_upkeep(&mut self, data: &Data) {
        for i in 0..self.nations.len() {
            let mut sum = 0.0;
            for f in self.fleets.iter().filter(|f| f.tag == self.nations[i].tag) {
                for s in &f.ships {
                    sum += data.navy.upkeep(&s.kind);
                }
            }
            self.nations[i].naval_budget = self.nations[i].naval_overhead + sum;
        }
    }

    /// `WarSupport.economy_mult`: the multiplier on tax and recruitment; 1 in peace.
    pub fn war_economy_mult(&self, data: &Data, tag: &str) -> f64 {
        if !self.is_at_war(tag) {
            return 1.0;
        }
        data.war_support.economy_mult_at(self.nation(tag).war_support)
    }

    /// `Economy._budgets`: every nation's budget, from the last province sums, with its units' upkeep.
    pub fn compute_budgets(&mut self, data: &Data) {
        self.refresh_upkeep(data);
        let army = self.army_upkeep(data);
        for i in 0..self.nations.len() {
            let tag = self.nations[i].tag.clone();
            let war_mult = self.war_economy_mult(data, &tag);
            let capital = self.nations[i].capital;
            let capital_held = capital > 0 && (capital as usize) < self.province_controller.len() && self.province_controller[capital as usize] == tag;
            let empty = Sums::default();
            let raw = self.economy_sums.get(i).unwrap_or(&empty);
            let b = budget::nation_budget(&data.economy, &self.nations[i], raw, war_mult, army[i], capital_held);
            self.nations[i].budget = b;
        }
    }

    /// `Economy.army_upkeep`: what each nation's army costs a month, every unit's upkeep, in armies (more for those on
    /// exercise) and in training. One per nation, in `nations` order.
    pub fn army_upkeep(&self, data: &Data) -> Vec<f64> {
        let mil = &data.military;
        let mut out = vec![0.0; self.nations.len()];
        for a in &self.armies {
            let mut sum = 0.0;
            for u in &a.units {
                sum += mil.unit_type(&u.unit_type).upkeep;
            }
            let root = if a.parent_id == 0 { Some(a) } else { self.armies.iter().find(|b| b.id == a.parent_id) };
            if root.is_some_and(|r| r.training) {
                sum *= 1.0 + mil.training_cost_share;
            }
            out[self.nation_index[&a.tag]] += sum;
        }
        for (i, n) in self.nations.iter().enumerate() {
            for job in &n.recruiting {
                out[i] += mil.unit_type(&job.unit_type).upkeep;
            }
        }
        out
    }

    /// `GameState.at_war`: whether two nations are at war with each other.
    pub fn at_war(&self, a: &str, b: &str) -> bool {
        a != b && self.wars.iter().any(|w| (w.a == a && w.b == b) || (w.a == b && w.b == a))
    }

    pub fn is_at_war(&self, tag: &str) -> bool {
        self.wars.iter().any(|w| w.involves(tag))
    }

    /// `GameState.war_between`: the index of the war being fought between two nations.
    pub fn war_between(&self, a: &str, b: &str) -> Option<usize> {
        if a == b {
            return None;
        }
        self.wars.iter().position(|w| (w.a == a && w.b == b) || (w.a == b && w.b == a))
    }

    /// `GameState.wars_of`: the wars a nation is fighting, in the order they began.
    pub fn wars_of(&self, tag: &str) -> Vec<usize> {
        (0..self.wars.len()).filter(|&i| self.wars[i].involves(tag)).collect()
    }

    /// `GameState.set_war` with a casus belli and a war goal (`{kind, ids, demand}`).
    pub fn set_war_goal(&mut self, a: &str, b: &str, casus_belli: &str, goal: Value) {
        self.set_war_ext(a, b, casus_belli, 0, goal);
    }

    /// `GameState.set_war` (starting one): `a` declares war on `b`.
    pub fn set_war(&mut self, a: &str, b: &str) {
        self.set_war_ext(a, b, "", 0, Value::Null);
    }

    /// `GameState.set_war(a, b, true, cb, group, goal)`: `a` starts the war; it joins the conflict `group` (0 starts a new one). The war's log
    /// and the history are told of it.
    pub fn set_war_ext(&mut self, a: &str, b: &str, cb: &str, group: u32, goal: Value) {
        if a == b || self.at_war(a, b) {
            return;
        }
        let mut w = War::new(self.next_war_id, a, b, self.calendar.days_elapsed as i64);
        self.next_war_id += 1;
        w.start_date = self.calendar.date_string();
        w.casus_belli = cb.to_string();
        w.goal = goal;
        if group == 0 {
            w.war_group = self.next_war_group;
            self.next_war_group += 1;
        } else {
            w.war_group = group;
        }
        let because = match self.texts.cb_labels.get(cb) {
            Some(l) => format!(" ({})", l.to_lowercase()),
            None => String::new(),
        };
        let text = format!("{} declares war on {}{}.", self.nation(a).display_name, self.nation(b).display_name, because);
        w.log.push(crate::records::WarLog { date: w.start_date.clone(), kind: "war".to_string(), text: text.clone(), province: 0, battle: 0 });
        self.wars.push(w);
        self.note("war", &text);
    }

    /// `WarSupport.change`: moves a nation's war support, within 0 to 100, ignoring a change too small to see.
    pub fn change_war_support(&mut self, tag: &str, delta: f64) {
        if delta.abs() < 0.00001 {
            return;
        }
        let i = self.nation_index[tag];
        let v = clampf(self.nations[i].war_support + delta, 0.0, 100.0);
        if is_equal_approx(v, self.nations[i].war_support) {
            return;
        }
        self.nations[i].war_support = v;
    }

    /// `Economy.mobilization_range`: the lowest and highest mobilization a nation may have now. The game returns them in a
    /// `Vector2`, whose parts are 32-bit floats, so they are rounded to that here too.
    pub fn mobilization_range(&self, data: &Data, tag: &str) -> (f64, f64) {
        let (lo, hi) = if !self.is_at_war(tag) {
            (0.0, data.economy.mobilization_peace_max)
        } else {
            (data.war_support.crisis_war_floor, 1.0)
        };
        (lo as f32 as f64, hi as f32 as f64)
    }

    /// `Economy.standing_cap`: the most men a nation may keep under arms in peace.
    pub fn standing_cap(&self, data: &Data, nation: usize) -> i64 {
        (self.economy_sums[nation].pool * data.economy.standing_share) as i64
    }

    /// `Economy.load_scenario`: every nation gets at least one civilian factory and one construction sector (in its
    /// capital, or its first province).
    pub fn economy_load_scenario(&mut self, data: &Data) {
        let cfg = &data.economy;
        for i in 0..self.nations.len() {
            let n = &self.nations[i];
            if n.provinces.is_empty() {
                continue;
            }
            let home = if n.capital > 0 && n.provinces.contains(&(n.capital as usize)) { n.capital as usize } else { n.provinces[0] };
            let provinces = n.provinces.clone();
            for (kind, least) in [("civilian_factory", cfg.min_civilian_factories), ("construction_sector", cfg.min_construction_sectors)] {
                let mut have = 0;
                for &id in &provinces {
                    have += building_level(&self.province_buildings[id], kind);
                }
                if have < least {
                    let now = building_level(&self.province_buildings[home], kind);
                    set_building(&mut self.province_buildings[home], kind, now + least - have);
                }
            }
        }
    }

    /// `Economy.province_busy`: whether a province has a project under way (not one waiting in the queue).
    pub fn province_busy(n: &Nation, id: usize) -> bool {
        n.construction.iter().any(|j| j.province == id && j.started)
    }

    /// `Economy.start_queued`: starts the projects waiting in a nation's queue, in order: each whose province is free and
    /// held, paying its gold and CP. The first that cannot be paid for stops the rest.
    pub fn start_queued(&mut self, data: &Data, nation: usize) {
        let tag = self.nations[nation].tag.clone();
        for k in 0..self.nations[nation].construction.len() {
            let job = &self.nations[nation].construction[k];
            if job.started || self.province_controller[job.province] != tag || Self::province_busy(&self.nations[nation], job.province) {
                continue;
            }
            let plan = economy::build_plan(data.economy.building(&job.kind).expect("building"));
            let n = &mut self.nations[nation];
            if n.treasury < plan.gold || n.cp < plan.cp {
                return;
            }
            n.treasury -= plan.gold;
            n.cp -= plan.cp;
            n.construction[k].started = true;
        }
    }

    /// `Economy.step_day`: construction points from the sectors, the projects under way count down (and are finished),
    /// the queue starts what it can, and the hulls on the slips count down.
    pub fn step_day(&mut self, data: &Data) {
        if !self.economy_sums.is_empty() {
            self.compute_budgets(data);
        }
        let mut finished = false;
        for ni in 0..self.nations.len() {
            let tag = self.nations[ni].tag.clone();
            let gain = self.nations[ni].budget.cp;
            self.nations[ni].cp += gain;
            for i in (0..self.nations[ni].construction.len()).rev() {
                let province = self.nations[ni].construction[i].province;
                if self.province_owner[province] != tag {
                    self.nations[ni].construction.remove(i); // ceded: the project is lost
                    continue;
                }
                let job = &mut self.nations[ni].construction[i];
                if !job.started {
                    continue;
                }
                job.days_left -= 1;
                if job.days_left <= 0 {
                    let job = self.nations[ni].construction.remove(i);
                    let owned = &mut self.province_buildings[job.province];
                    let level = building_level(owned, &job.kind);
                    set_building(owned, &job.kind, level + 1);
                    finished = true;
                }
            }
            self.start_queued(data, ni);
            for job in &mut self.nations[ni].shipbuilding {
                job.days_left = (job.days_left - 1).max(0);
            }
        }
        if finished {
            self.recompute(data);
        }
    }

    /// `Population.step_month`: the war dead leave the nation's provinces in proportion to their people (the people no
    /// longer grow).
    pub fn population_step_month(&mut self) {
        if self.province_pop_frac.len() != self.province_population.len() {
            self.province_pop_frac.resize(self.province_population.len(), 0.0);
        }
        for ni in 0..self.nations.len() {
            if self.nations[ni].provinces.is_empty() {
                continue;
            }
            let dead = self.nations[ni].deaths_month;
            let before = self.nations[ni].population as f64;
            let provinces = self.nations[ni].provinces.clone();
            if dead > 0.0 && before > 0.0 {
                for &id in &provinces {
                    let delta = -dead * self.province_population[id] as f64 / before;
                    crate::population::add(&mut self.province_population, &mut self.province_pop_frac, id, delta);
                }
            }
            let n = &mut self.nations[ni];
            n.war_dead += n.deaths_month;
            n.deaths_month = 0.0;
            let mut total = 0i64;
            for &id in &provinces {
                total += self.province_population[id] as i64;
            }
            self.nations[ni].population = total;
        }
    }

    /// `Economy.step_month`: pays the budget and refills manpower toward its cap.
    pub fn step_month(&mut self, data: &Data) {
        let cfg = &data.economy;
        self.population_step_month();
        for i in 0..self.nations.len() {
            let (lo, hi) = self.mobilization_range(data, &self.nations[i].tag.clone());
            self.nations[i].mobilization = clampf(self.nations[i].mobilization, lo, hi);
        }
        self.refresh_men(data);
        self.recompute(data);
        for i in 0..self.nations.len() {
            let tag = self.nations[i].tag.clone();
            let b = self.nations[i].budget;
            self.nations[i].treasury += b.net;
            // The cap covers everyone in service; what is not under arms is the reserve.
            let mult = self.war_economy_mult(data, &tag);
            let n = &mut self.nations[i];
            let cap = (b.manpower_max as i64 - n.men_in_units).max(0);
            if n.manpower < cap {
                n.manpower = cap.min(n.manpower + (b.manpower_pool * cfg.mobilization_rate * mult) as i64);
            } else {
                n.manpower = cap;
            }
        }
        self.recompute(data);
    }

    // ---------------------------------------------------------------- diplomacy (the parts the focus uses)

    /// `Diplomacy.pair_key`: key for an unordered pair of tags, sorted.
    pub fn pair_key(a: &str, b: &str) -> String {
        if a < b {
            format!("{a}|{b}")
        } else {
            format!("{b}|{a}")
        }
    }

    /// `Diplomacy.relation`: how a nation regards another, -100 to 100 (the most with itself).
    pub fn relation(&self, data: &Data, a: &str, b: &str) -> f64 {
        if a == b {
            return data.diplomacy.relation_max;
        }
        self.relations.get(&Self::pair_key(a, b)).copied().unwrap_or(data.diplomacy.relation_neutral)
    }

    pub fn set_relation(&mut self, data: &Data, a: &str, b: &str, value: f64) {
        if a == b {
            return;
        }
        let old = self.relation(data, a, b);
        let v = clampf(value, data.diplomacy.relation_min, data.diplomacy.relation_max);
        if is_equal_approx(old, v) {
            return;
        }
        self.relations.insert(Self::pair_key(a, b), v);
    }

    pub fn change_relation(&mut self, data: &Data, a: &str, b: &str, delta: f64) {
        let now = self.relation(data, a, b);
        self.set_relation(data, a, b, now + delta);
    }

    /// `Diplomacy.gain`: adds diplomacy points (never past the maximum).
    pub fn gain_points(&mut self, data: &Data, tag: &str, amount: f64) {
        if amount > 0.0 {
            let i = self.nation_index[tag];
            let v = clampf(self.nations[i].diplomacy_points + amount, 0.0, data.diplomacy.points_max);
            if !is_equal_approx(v, self.nations[i].diplomacy_points) {
                self.nations[i].diplomacy_points = v;
            }
        }
    }

    /// `Diplomacy.gain_prestige`: prestige earned (or lost).
    pub fn gain_prestige(&mut self, tag: &str, amount: f64) {
        if let Some(&i) = self.nation_index.get(tag) {
            self.nations[i].prestige += amount;
        }
    }

    // ---------------------------------------------------------------- the national focus (`scripts/sim/focus.gd`)

    /// `Focus.block`: why a focus cannot be started now ("" if it can): unknown, done, active, busy or locked.
    pub fn focus_block(&self, data: &Data, tag: &str, id: &str) -> &'static str {
        let (Some(f), Some(&ni)) = (data.focus.find(tag, id), self.nation_index.get(tag)) else {
            return "unknown";
        };
        let n = &self.nations[ni];
        if n.focus_done.iter().any(|d| d == id) {
            return "done";
        }
        if f.repeatable && f.max > 0 && n.focus_count.iter().find(|(k, _)| k == id).map(|(_, c)| *c).unwrap_or(0) >= f.max {
            return "done";
        }
        if n.provinces.is_empty() {
            return "unknown";
        }
        if let Some(active) = &n.focus {
            return if active.id == id { "active" } else { "busy" };
        }
        for req in &f.requires {
            if !n.focus_done.iter().any(|d| d == req) {
                return "locked";
            }
        }
        ""
    }

    /// `Focus.start`: a nation takes up a focus. Returns false if it may not.
    pub fn focus_start(&mut self, data: &Data, tag: &str, id: &str) -> bool {
        if !self.focus_block(data, tag, id).is_empty() {
            return false;
        }
        let days = data.focus.find(tag, id).unwrap().days;
        let i = self.nation_index[tag];
        self.nations[i].focus = Some(ActiveFocus { id: id.to_string(), days_left: days, days_total: days });
        true
    }

    /// `Focus.step_day`: the focus in hand moves a day on and applies its effects when it is done.
    pub fn focus_step_day(&mut self, data: &Data) {
        for i in 0..self.nations.len() {
            let Some(active) = &mut self.nations[i].focus else { continue };
            active.days_left -= 1;
            if active.days_left <= 0 {
                let tag = self.nations[i].tag.clone();
                self.focus_complete(data, &tag);
            }
        }
    }

    pub fn focus_complete(&mut self, data: &Data, tag: &str) {
        let i = self.nation_index[tag];
        let Some(active) = self.nations[i].focus.take() else { return };
        let id = active.id;
        if self.nations[i].focus_done.iter().any(|d| *d == id) {
            return;
        }
        let Some(f) = data.focus.find(tag, &id) else { return };
        if f.repeatable {
            let n = &mut self.nations[i];
            let count = match n.focus_count.iter_mut().find(|(k, _)| *k == id) {
                Some(slot) => {
                    slot.1 += 1;
                    slot.1
                }
                None => {
                    n.focus_count.push((id.clone(), 1));
                    1
                }
            };
            // max 0: it may be taken again for ever.
            if f.max > 0 && count >= f.max {
                n.focus_done.push(id.clone());
            }
        } else {
            self.nations[i].focus_done.push(id.clone());
        }
        let fx = f.effects.clone();
        self.apply_focus_effects(data, tag, &fx);
    }

    /// `Focus.apply_effects`: lasting effects (income, diplomacy, construction points) are summed into the nation's
    /// bonuses; one-off ones (prestige, points, money, civilian factories, war support, army size, relations, claims) happen
    /// now.
    pub fn apply_focus_effects(&mut self, data: &Data, tag: &str, fx: &FocusEffects) {
        let i = self.nation_index[tag];
        let mut lasting = false;
        {
            let n = &mut self.nations[i];
            if let Some(x) = fx.income {
                n.focus_income += x;
                lasting = true;
            }
            if let Some(x) = fx.diplomacy {
                n.focus_diplomacy += x;
                lasting = true;
            }
            if let Some(x) = fx.cp {
                n.focus_cp += x;
                lasting = true;
            }
        }
        if let Some(x) = fx.prestige {
            self.gain_prestige(tag, x);
        }
        if let Some(x) = fx.points {
            self.gain_points(data, tag, x);
        }
        if let Some(x) = fx.treasury {
            self.nations[i].treasury += x;
        }
        if let Some(count) = fx.civilian_factories {
            // Built at once, one each in the nation's best provinces with room (`Focus._grant_factories`).
            for id in self.mass_candidates(data, tag, "civilian_factory").into_iter().take(count.max(0) as usize) {
                let level = building_level(&self.province_buildings[id], "civilian_factory");
                set_building(&mut self.province_buildings[id], "civilian_factory", level + 1);
            }
            lasting = true;
        }
        if let Some(x) = fx.war_support {
            self.change_war_support(tag, x);
        }
        if let Some(x) = fx.army_size {
            let n = &mut self.nations[i];
            let extra = (n.peacetime_army as f64 * x).round() as i64;
            n.peacetime_army += extra;
            n.manpower += extra;
        }
        for (other, delta) in &fx.relation {
            if self.nation_index.contains_key(other) {
                self.change_relation(data, tag, other, *delta);
            }
        }
        for target in &fx.claim {
            if self.nation_index.contains_key(target) {
                self.casus_belli.push(CasusBelli {
                    holder: tag.to_string(),
                    target: target.clone(),
                    kind: "national_claim".to_string(),
                    expires_day: self.calendar.days_elapsed as i64 + (data.diplomacy.cb_years * 365.0) as i64,
                    goal: Value::Null,
                    refused_day: -1,
                });
            }
        }
        if lasting {
            self.economy_dirty = true;
        }
    }

    /// `Economy.request`: the economy has changed: recompute now, or, in the middle of the daily step, once at its end.
    pub fn economy_request(&mut self, data: &Data) {
        if self.in_day_step {
            self.economy_dirty = true;
        } else {
            self.recompute(data);
        }
    }

    /// What the game does at the end of the day's economy stage: if something changed the economy, recompute once.
    pub fn finish_economy_stage(&mut self, data: &Data) {
        if self.economy_dirty {
            self.economy_dirty = false;
            self.recompute(data);
        }
    }

    /// `GameState.set_controller`: changes who holds a province (the owner stays). The caller recomputes the economy.
    pub fn set_controller(&mut self, id: usize, tag: &str) {
        if self.province_controller[id] == tag {
            return;
        }
        self.province_controller[id] = tag.to_string();
        self.control_version += 1;
        self.invalidate_aura();
    }

    /// `Military.invalidate_aura`: forgets what the game keeps for the day about supply and the cities' reach (a province
    /// changed hands, or another game was loaded).
    pub fn invalidate_aura(&self) {
        *self.supply_cache.borrow_mut() = SupplyCache::default();
        *self.home_cache.borrow_mut() = HomeCache { day: -1, answers: HashMap::new() };
        *self.aura_cache.borrow_mut() = None;
        // `AI.invalidate_caches`
        *self.ai_index.borrow_mut() = (-1, HashMap::new());
        self.ai_threat_cache.borrow_mut().clear();
        self.ai_worth_cache.borrow_mut().clear();
    }

    /// `GameState._rebuild_nation_provinces`: each nation's provinces (by id) and people.
    pub fn rebuild_nation_provinces(&mut self) -> Result<(), String> {
        for n in &mut self.nations {
            n.provinces.clear();
            n.population = 0;
        }
        for id in 1..self.province_owner.len() {
            let tag = &self.province_owner[id];
            let idx = *self.nation_index.get(tag).ok_or_else(|| format!("province {id} belongs to unknown nation {tag:?}"))?;
            self.nations[idx].provinces.push(id);
            self.nations[idx].population += self.province_population[id] as i64;
        }
        Ok(())
    }

    /// `Economy.province_income`: what a province earns its owner a month before the nation's modifiers: its base income
    /// and its buildings' income.
    pub fn province_income(&self, data: &Data, id: usize) -> f64 {
        let mut total = if id < self.province_base_income.len() { self.province_base_income[id] as f64 } else { 0.0 };
        for (kind, level) in &self.province_buildings[id] {
            total += data.economy.building(kind).and_then(|b| b.income).unwrap_or(0.0) * *level as f64;
        }
        total
    }

    /// `Economy.recompute`: each province's base income, and every nation's sums and budget.
    pub fn recompute(&mut self, data: &Data) {
        let cfg = &data.economy;
        let count = self.province_owner.len();
        self.province_base_income.resize(count, 0.0);
        for id in 1..count {
            let pop = if id < self.province_pop_base.len() { self.province_pop_base[id] } else { self.province_population[id] };
            self.province_base_income[id] = economy::base_income(cfg, pop as f64) as f32;
        }
        let mut sums = vec![Sums::default(); self.nations.len()];
        for id in 1..count {
            let tag = self.nation_index[&self.province_owner[id]];
            let holder = self.nation_index[&self.province_controller[id]];
            sums[tag].pool += self.province_population[id] as f64 * cfg.manpower_share;
            if holder != tag {
                sums[holder].occupied += self.province_base_income[id] as f64 * cfg.occupied_share;
                continue;
            }
            let s = &mut sums[tag];
            s.base += self.province_base_income[id] as f64;
            for (kind, level) in &self.province_buildings[id] {
                let Some(def) = cfg.building(kind) else { continue };
                let level = *level as f64;
                match s.levels.iter_mut().find(|(k, _)| k == kind) {
                    Some(slot) => slot.1 += level,
                    None => s.levels.push((kind.clone(), level)),
                }
                s.upkeep += def.upkeep * level;
                s.cp += def.cp_per_day * level;
                if kind == "port" {
                    s.ports += def.income.unwrap_or(0.0) * level;
                } else if let Some(income) = def.income {
                    s.factories += income * level;
                }
            }
        }
        self.economy_sums = sums;
        self.compute_budgets(data);
    }
}

/// A building's level in a province's list, or 0.
pub fn building_level(list: &[(String, i32)], id: &str) -> i32 {
    list.iter().find(|(k, _)| k == id).map(|(_, l)| *l).unwrap_or(0)
}

fn set_building(list: &mut Vec<(String, i32)>, id: &str, level: i32) {
    match list.iter_mut().find(|(k, _)| k == id) {
        Some(slot) => slot.1 = level,
        None => list.push((id.to_string(), level)),
    }
}
