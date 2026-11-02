//! The game state (`scripts/sim/game_state.gd`) as far as it is ported: the provinces' owners, people, works and
//! deposits, the nations, and what the economy works out from them. Armies, fleets, wars, treaties and the rest of the
//! state are not here yet (see `rust/README.md`).

use crate::budget::{self, Budget};
use crate::clock::Calendar;
use crate::diplomacy::is_equal_approx;
use crate::config::{PressureConfig, DiplomacyConfig, EconomyConfig, Effects, FocusConfig, FocusEffects, MilitaryConfig, NavyConfig, WarSupportConfig};
use crate::economy::{self, EconNation, Job};
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
}

impl Data {
    pub fn load(dir: &Path) -> Result<Data, String> {
        let read = |f: &str| std::fs::read_to_string(dir.join(f)).map_err(|e| format!("{f}: {e}"));
        Ok(Data {
            dir: dir.to_path_buf(),
            map: MapData::load(dir)?,
            economy: EconomyConfig::from_json_str(&read("economy.json")?)?,
            military: MilitaryConfig::from_json_str(&read("military.json")?)?,
            navy: NavyConfig::from_json_str(&read("navy.json")?)?,
            war_support: WarSupportConfig::from_json_str(&read("diplomacy.json")?)?,
            diplomacy: DiplomacyConfig::from_json_str(&read("diplomacy.json")?)?,
            focus: FocusConfig::from_json_str(&read("focus.json")?)?,
            pressure: PressureConfig::from_json_str(&read("events.json")?)?,
            ai: crate::ai_peace::AiConfig::from_json_str(&read("ai.json")?)?,
            crises: serde_json::from_str(&read("crises.json")?).map_err(|e| format!("crises.json is invalid: {e}"))?,
        })
    }
}

#[derive(Debug, Clone)]
pub struct Nation {
    pub tag: String,
    pub display_name: String,
    pub treasury: f64,
    pub capital: i64,
    pub development: f64,
    pub agri_yield: f64,
    pub tax_rate: f64,
    pub pop_growth: f64,
    pub peacetime_army: i64,
    pub naval_budget: f64,
    pub materials_need_mult: f64,
    pub mobilization: f64,
    pub focus_fx: Effects,
    /// What the national focus adds to the construction points a day.
    pub focus_construction: f64,
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
    /// Monthly state investment (GBP millions).
    pub investment: f64,
    pub weariness: f64,
    pub starving: bool,
    /// How much of the nation's trade the blockade cuts, 0 to 1.
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
    pub arms_share: f64,
    /// The munitions stockpile, in IC.
    pub munitions: f64,
    pub munitions_used_last: f64,
    pub civil_mult: f64,
    pub civil_base: f64,
    pub civil_index: f64,
    pub wage: f64,
    /// The part of the naval budget that is not ships: dockyards, bases, sailors ashore.
    pub naval_overhead: f64,
    pub budget: Budget,
    /// Works under construction, and hulls on the slips, in the order they were started.
    pub construction: Vec<Job>,
    pub shipbuilding: Vec<Job>,
    pub recruiting: Vec<crate::military::Recruit>,
    /// The IC the last day's work took.
    pub construction_used: f64,
    /// Men killed this month, and in the war so far.
    pub deaths_month: f64,
    pub war_dead: f64,
    pub munitions_used_month: f64,
}

impl Nation {
    /// What the economy reads of this nation, for the pure rules in `economy`.
    pub fn econ(&self) -> EconNation {
        EconNation {
            development: self.development,
            agri_yield: self.agri_yield,
            focus_fx: self.focus_fx,
            tax_rate: self.tax_rate,
            population: self.population,
            investment: self.investment,
            budget_gdp: Some(self.budget.gdp),
            men_in_units: self.men_in_units,
            weariness: self.weariness,
            starving: self.starving,
        }
    }
}

/// The focus a nation is working on (`Nation.focus`).
#[derive(Debug, Clone, PartialEq)]
pub struct ActiveFocus {
    pub id: String,
    pub days_left: i64,
    pub days_total: i64,
}

/// The record of one war (`War`): who started it and what each side lost and took. (Its log of events and battles, kept
/// for the screens, is not ported.)
#[derive(Debug, Clone)]
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
#[derive(Debug, Clone, PartialEq)]
pub struct Indemnity {
    pub payer: String,
    pub receiver: String,
    pub monthly: f64,
    pub months_left: i64,
}

/// A peace clause (`GameState.restrictions`): `nation`'s armies stay out of `provinces` (or it builds no new warships, when
/// `kind` is "fleet_limit") until `until_day`, unless it is at war with `holder`.
#[derive(Debug, Clone, PartialEq)]
pub struct Restriction {
    pub nation: String,
    pub holder: String,
    pub kind: String,
    pub provinces: Vec<usize>,
    pub until_day: i64,
}

/// A major city (`data/scenarios/<scenario>/cities.tsv`).
#[derive(Debug, Clone)]
pub struct City {
    pub id: i64,
    pub name: String,
    pub province: usize,
    pub pop: i64,
    /// 1 a capital, 2 a great city, 3 a large one.
    pub rank: i64,
}

/// A battle in progress in a province (the part of `Military._engagement`'s record that bears on what happens).
#[derive(Debug, Clone)]
pub struct Engagement {
    pub id: u32,
    pub province: usize,
    pub start_day: i64,
    pub attacker: String,
    /// The men each side had when it joined the battle, in the order the sides joined.
    pub start_men: Vec<(String, f64)>,
    /// What each side has lost in it.
    pub lost: Vec<(String, f64)>,
    pub armies: Vec<u32>,
}

/// One standing agreement between two nations (`Treaty`). Kinds are in `data/diplomacy.json`.
#[derive(Debug, Clone, PartialEq)]
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
#[derive(Debug, Clone, PartialEq)]
pub struct MobilizationCall {
    pub tag: String,
    pub for_tag: String,
    pub against: String,
    pub day: i64,
}

/// An effort to improve relations (`GameState.relation_projects`).
#[derive(Debug, Clone, PartialEq)]
pub struct RelationProject {
    pub from: String,
    pub to: String,
    pub months_left: i64,
}

/// A casus belli earned in play (`GameState.casus_belli`).
#[derive(Debug, Clone, PartialEq)]
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

/// A nation's summed province output (`GameState.economy_sums`).
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Sums {
    pub coast: f64,
    pub gdp: f64,
    pub industry: f64,
    pub food: f64,
    pub trade: f64,
    pub pool: f64,
    pub materials: f64,
}

#[derive(Debug, Clone)]
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
    /// Resource id and potential output (kt a year), in the economy file's resource order.
    pub province_deposit: Vec<Vec<(String, f64)>>,
    pub province_gdp: Vec<f32>,
    pub province_industry: Vec<f32>,
    pub province_food: Vec<f32>,
    pub province_pool: Vec<f32>,
    /// One per nation, in `nations` order.
    pub economy_sums: Vec<Sums>,
    /// Kt of raw materials a year one GBP million of industrial output needs (`Economy.calibrate_materials`).
    pub materials_k: f64,
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
#[derive(Debug, Clone)]
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

#[derive(Debug, Clone, Default)]
pub struct SupplyCache {
    pub stamp: Option<(i64, u64)>,
    pub costs: HashMap<(String, usize), f64>,
}

#[derive(Debug, Clone, Default)]
pub struct HomeCache {
    pub day: i64,
    pub answers: HashMap<(String, usize), bool>,
}


/// One squadron of a fleet (`Ship`): strength is the share of it still afloat and fit to fight, morale is 0 to 1.
#[derive(Debug, Clone, PartialEq)]
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
#[derive(Debug, Clone)]
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
#[derive(Debug, Clone)]
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
}

/// Who holds a sea zone today (`GameState.sea_control`).
#[derive(Debug, Clone, PartialEq)]
pub struct SeaControl {
    pub holders: Vec<String>,
    pub contested: bool,
    pub power: Vec<(String, f64)>,
}

fn refs_b(v: &[(String, i32)]) -> Vec<(&str, i32)> {
    v.iter().map(|(k, l)| (k.as_str(), *l)).collect()
}

fn refs_d(v: &[(String, f64)]) -> Vec<(&str, f64)> {
    v.iter().map(|(k, x)| (k.as_str(), *x)).collect()
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
            province_deposit: vec![vec![]; count],
            province_gdp: vec![0.0; count],
            province_industry: vec![0.0; count],
            province_food: vec![0.0; count],
            province_pool: vec![0.0; count],
            economy_sums: vec![],
            materials_k: 0.0,
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
        for row in Table::read(&dir.join("resources.tsv"))?.rows() {
            let id = row.int("id") as usize;
            for r in &data.economy.resource_ids {
                set_deposit(&mut gs.province_deposit[id], r, row.float(r));
            }
        }
        for id in 1..count {
            gs.province_owner[id] = data.map.provinces[id].owner.clone();
            gs.province_controller[id] = data.map.provinces[id].owner.clone();
        }
        let mut by_name: HashMap<&str, usize> = HashMap::new();
        for id in 1..count {
            by_name.insert(data.map.provinces[id].name.as_str(), id);
        }
        // The works a scenario's big cities already have.
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
                development: f("development", 1.0),
                agri_yield: f("agri_yield", 1.0),
                tax_rate: f("tax_rate", data.economy.default_tax_rate),
                pop_growth: f("pop_growth", 0.01),
                peacetime_army: f("peacetime_army", 0.0) as i64,
                naval_budget: f("naval_budget", 0.0),
                materials_need_mult: f("materials_need_mult", 1.0),
                mobilization: f("mobilization", 0.0),
                focus_fx: Effects::default(),
                focus_construction: 0.0,
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
                investment: 0.0,
                weariness: 0.0,
                starving: false,
                blockade: 0.0,
                blockade_target: 0.0,
                blockade_pinned: -1.0,
                blockade_by: vec![],
                blockade_applied: 0.0,
                ships_lost: 0,
                manpower: f("peacetime_army", 0.0) as i64,
                men_in_units: 0,
                men_exercising: 0,
                arms_share: 0.0,
                munitions: 0.0,
                munitions_used_last: 0.0,
                civil_mult: 1.0,
                civil_base: 0.0,
                civil_index: 1.0,
                wage: 0.0,
                naval_overhead: 0.0,
                budget: Budget::default(),
                construction: vec![],
                shipbuilding: vec![],
                recruiting: vec![],
                construction_used: 0.0,
                deaths_month: 0.0,
                war_dead: 0.0,
                munitions_used_month: 0.0,
            });
        }
        for n in &mut gs.nations {
            n.war_support_base = n.war_support;
        }
        gs.rebuild_nation_provinces()?;
        gs.materials_k = 0.0;
        gs.deploy_starting_armies(data, scenario.get("deployment").unwrap_or(&no_nations))?;
        gs.deploy_starting_fleets(data, &dir)?;
        gs.load_munitions(data, &scenario);
        gs.absorb_works(data);
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

    /// `Munitions.load_scenario`: each nation's arms share and a stockpile of `days` of the general war the scenario sets.
    pub fn load_munitions(&mut self, data: &Data, scenario: &Value) {
        let cfg = &data.economy;
        let share = scenario.get("munitions").and_then(|m| m.get("share")).and_then(Value::as_f64).unwrap_or(cfg.munitions_default_share);
        let days = scenario.get("munitions").and_then(|m| m.get("days")).and_then(Value::as_f64).unwrap_or(0.0);
        for i in 0..self.nations.len() {
            let expected = self.expected_daily(data, i);
            let n = &mut self.nations[i];
            n.arms_share = clampf(share, 0.0, 1.0);
            n.munitions_used_last = 0.0;
            n.munitions = days * expected;
        }
    }

    /// `Munitions.war_need`: what a nation's armies would burn in a day if every one of them were fighting.
    pub fn war_need(&self, data: &Data, tag: &str) -> f64 {
        let mut guns = 0.0;
        for a in self.armies.iter().filter(|a| a.tag == tag) {
            guns += a.power(&data.military) * a.shelling_share(&data.military);
        }
        guns * data.economy.munitions_per_gun_power
    }

    /// `Munitions.expected_daily`: what a nation can expect to burn a day in a war.
    pub fn expected_daily(&self, data: &Data, nation: usize) -> f64 {
        let n = &self.nations[nation];
        maxf(n.munitions_used_last / 30.0, self.war_need(data, &n.tag) * data.economy.munitions_engaged_share)
    }

    /// `WarSupport.economy_mult`: the multiplier on tax and recruitment; 1 in peace.
    pub fn war_economy_mult(&self, data: &Data, tag: &str) -> f64 {
        if !self.is_at_war(tag) {
            return 1.0;
        }
        data.war_support.economy_mult_at(self.nation(tag).war_support)
    }

    /// `Economy._budgets`: every nation's budget, from the last province sums.
    pub fn compute_budgets(&mut self, data: &Data) {
        self.refresh_upkeep(data);
        for i in 0..self.nations.len() {
            let tax_mult = self.war_economy_mult(data, &self.nations[i].tag.clone());
            let raw = self.economy_sums[i];
            let mut n = self.nations[i].clone();
            n.budget = budget::nation_budget(&data.economy, &data.military, self.materials_k, &mut n, &raw, tax_mult);
            self.nations[i] = n;
        }
    }

    /// `Economy.calibrate`: at a scenario's start, the raw-materials constant and each nation's civil spending, so that
    /// its budget starts with a small surplus (`start_surplus` of its revenue) for the nation to spend as it chooses.
    pub fn calibrate(&mut self, data: &Data) {
        self.calibrate_materials(data);
        for n in &mut self.nations {
            n.civil_mult = 1.0;
            n.civil_base = 0.0;
            n.civil_index = 1.0;
            n.wage = 0.0;
        }
        self.compute_budgets(data);
        for n in &mut self.nations {
            let civil = n.budget.civil;
            if civil > 0.0 {
                let surplus = n.budget.revenue * data.economy.start_surplus;
                n.civil_mult = clampf((n.budget.net + civil - surplus) / civil, 0.1, 4.0);
            }
            n.civil_base = 0.0; // worked out again from the calibrated multiplier
        }
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
        self.set_war(a, b);
        if let Some(i) = self.war_between(a, b) {
            self.wars[i].casus_belli = casus_belli.to_string();
            self.wars[i].goal = goal;
        }
    }

    /// `GameState.set_war` (starting one): `a` declares war on `b`. The war's log and the notes it makes for the history
    /// are not kept here.
    pub fn set_war(&mut self, a: &str, b: &str) {
        if a == b || self.at_war(a, b) {
            return;
        }
        let mut w = War::new(self.next_war_id, a, b, self.calendar.days_elapsed as i64);
        self.next_war_id += 1;
        w.war_group = self.next_war_group;
        self.next_war_group += 1;
        self.wars.push(w);
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

    /// `Economy._pressures`: war weariness (the share of the workers lost for every 100,000 men lost, easing in peace) and
    /// starvation (a nation that needs imports and gets under a third of them through the blockade loses output and war
    /// support).
    pub fn pressures(&mut self, data: &Data) {
        let cfg = &data.economy;
        for i in 0..self.nations.len() {
            let tag = self.nations[i].tag.clone();
            let at_war = self.is_at_war(&tag);
            let n = &mut self.nations[i];
            let target = crate::gd::minf(cfg.weariness_max, (n.war_dead + n.deaths_month) / 100000.0 * cfg.weariness_per_100k);
            if !at_war {
                n.weariness = maxf(0.0, n.weariness - cfg.weariness_ease_per_day);
            } else {
                n.weariness = maxf(n.weariness, target);
            }
            let b = &n.budget;
            let mut needs_imports = b.food_need > b.food_production;
            if !needs_imports && b.materials.need > b.materials.own {
                needs_imports = true;
            }
            n.starving = needs_imports && (1.0 - n.blockade) < cfg.starvation_below;
            if n.starving {
                self.change_war_support(&tag, -cfg.starvation_support_per_day);
            }
        }
    }

    /// `Economy.step_day`: refreshes the budgets, puts the day's industry into munitions, hulls and buildings, and
    /// completes the buildings that are done.
    pub fn step_day(&mut self, data: &Data) {
        self.pressures(data);
        if !self.economy_sums.is_empty() {
            self.compute_budgets(data);
        }
        let mut finished = false;
        for ni in 0..self.nations.len() {
            let n = &mut self.nations[ni];
            let pool = n.budget.construction_points;
            // Munitions first, by the arms share; then the queue is served in order, each project taking what it can use
            // of what is left. Hulls on the slips come first, then the buildings.
            let arms = {
                let made = pool * clampf(n.arms_share, 0.0, 1.0);
                n.munitions += made;
                made
            };
            if n.construction.is_empty() && n.shipbuilding.is_empty() {
                n.construction_used = arms;
                continue;
            }
            let mut left = pool - arms;
            for job in &mut n.shipbuilding {
                let give = crate::gd::minf(crate::gd::minf(job.rate, left), job.points_left);
                left -= give;
                job.points_left -= give;
                job.given = give;
                job.days_left = if give > 0.0 && job.points_left > 0.0 {
                    (job.points_left / give - 0.0001).ceil() as i32
                } else if job.points_left <= 0.0 {
                    0
                } else {
                    9999
                };
            }
            for job in &mut n.construction {
                let give = crate::gd::minf(crate::gd::minf(job.rate, left), job.points_left);
                left -= give;
                job.points_left -= give;
                job.given = give;
            }
            n.construction_used = pool - left;
            for i in (0..n.construction.len()).rev() {
                if n.construction[i].points_left <= 0.0001 {
                    let job = n.construction.remove(i);
                    let owned = &mut self.province_buildings[job.province];
                    let level = owned.iter().find(|(k, _)| *k == job.kind).map(|(_, l)| *l).unwrap_or(0);
                    set_building(owned, &job.kind, level + 1);
                    finished = true;
                } else {
                    let job = &mut n.construction[i];
                    let rate_now = if job.given > 0.0 { job.given } else { 0.0 };
                    job.days_left = if rate_now > 0.0 { (job.points_left / rate_now - 0.0001).ceil() as i32 } else { 9999 };
                }
            }
        }
        if finished {
            self.recompute(data);
        }
    }

    /// `Population.step_month`: each province grows by its nation's rate, less what famine, occupation and the war dead
    /// take.
    pub fn population_step_month(&mut self, data: &Data) {
        let cfg = &data.economy;
        for ni in 0..self.nations.len() {
            if self.nations[ni].provinces.is_empty() {
                continue;
            }
            let tag = self.nations[ni].tag.clone();
            let rate = crate::population::growth_rate(cfg, self.nations[ni].pop_growth, self.nations[ni].budget.food_shortage);
            let dead = self.nations[ni].deaths_month * cfg.death_share;
            let before = self.nations[ni].population as f64;
            let provinces = self.nations[ni].provinces.clone();
            for &id in &provinces {
                let pop = self.province_population[id] as f64;
                let mut yearly = rate;
                let holder = &self.province_controller[id];
                if *holder != tag && self.at_war(&tag, holder) {
                    yearly -= cfg.occupation_decline;
                }
                let mut delta = pop * yearly / 12.0;
                if dead > 0.0 && before > 0.0 {
                    delta -= dead * pop / before;
                }
                crate::population::add(cfg, &mut self.province_population, &mut self.province_pop_frac, id, delta);
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

    /// `Economy.step_month`: pays the budget, grows the economy and the people, and refills manpower toward its cap.
    pub fn step_month(&mut self, data: &Data) {
        let cfg = &data.economy;
        self.population_step_month(data);
        // Munitions: the stockpile ages, and this month's use starts again.
        let decay = cfg.munitions_decay_per_year / 12.0;
        for n in &mut self.nations {
            n.munitions *= 1.0 - decay;
            n.munitions_used_last = n.munitions_used_month;
            n.munitions_used_month = 0.0;
        }
        for i in 0..self.nations.len() {
            let (lo, hi) = self.mobilization_range(data, &self.nations[i].tag.clone());
            self.nations[i].mobilization = clampf(self.nations[i].mobilization, lo, hi);
        }
        self.refresh_men(data);
        self.recompute(data);
        for i in 0..self.nations.len() {
            let tag = self.nations[i].tag.clone();
            let b = self.nations[i].budget;
            let growth = economy::growth_rate(cfg, &self.nations[i].econ()) / 12.0;
            {
                let n = &mut self.nations[i];
                n.treasury += b.net / 12.0;
                n.development *= 1.0 + growth;
                n.civil_index *= 1.0 + (cfg.baseline_growth + n.pop_growth) / 12.0;
                n.wage *= 1.0 + cfg.baseline_growth / 12.0;
            }
            // The peacetime army of an AI nation grows with its people and its output while its budget can pay for it, up
            // to the standing cap (the player sets their own).
            if tag != self.player_tag && !self.is_at_war(&tag) && b.net > 0.0 {
                let n = &self.nations[i];
                let grown = (n.peacetime_army as f64 * (1.0 + (growth + n.pop_growth / 12.0) * cfg.army_growth_share)) as i64;
                let cap = self.standing_cap(data, i);
                let n = &mut self.nations[i];
                n.peacetime_army = n.peacetime_army.max(grown.min(cap));
            }
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

    /// `Focus.apply_effects`: lasting effects are summed into the nation's bonuses; one-off ones (prestige, points, money,
    /// war support, army size, relations, claims) happen now.
    pub fn apply_focus_effects(&mut self, data: &Data, tag: &str, fx: &FocusEffects) {
        let i = self.nation_index[tag];
        let mut lasting = false;
        {
            let n = &mut self.nations[i];
            if let Some(x) = fx.gdp {
                n.focus_fx.gdp += x;
                lasting = true;
            }
            if let Some(x) = fx.industry {
                n.focus_fx.industry += x;
                lasting = true;
            }
            if let Some(x) = fx.food {
                n.focus_fx.food += x;
                lasting = true;
            }
            if let Some(x) = fx.trade {
                n.focus_fx.trade += x;
                lasting = true;
            }
            if let Some(x) = fx.growth {
                n.focus_fx.growth += x;
                lasting = true;
            }
            if let Some(x) = fx.diplomacy {
                n.focus_diplomacy += x;
                lasting = true;
            }
            if let Some(x) = fx.construction {
                n.focus_construction += x;
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

    /// `Economy.absorb_works`: a scenario's starting works are already in the figures it was fitted to, so each nation's
    /// development is eased by what they would add on top.
    pub fn absorb_works(&mut self, data: &Data) {
        let cfg = &data.economy;
        for n in 0..self.nations.len() {
            let econ = self.nations[n].econ();
            let (mut base, mut gain) = (0.0, 0.0);
            for &id in &self.nations[n].provinces {
                let area = data.map.provinces[id].area_km2();
                let pop = self.province_population[id] as i64;
                let plain = economy::province_output(cfg, pop, area, &econ, &[], &[]).gdp;
                base += plain;
                if !self.province_buildings[id].is_empty() {
                    let b = refs_b(&self.province_buildings[id]);
                    gain += economy::province_output(cfg, pop, area, &econ, &b, &[]).gdp - plain;
                }
            }
            if base > 0.0 && gain > 0.0 {
                self.nations[n].development /= 1.0 + gain / base;
            }
        }
    }

    /// `Economy.recompute`, the part that works out each province's output and each nation's sums. (The budgets it ends
    /// with are not ported yet.)
    pub fn recompute(&mut self, data: &Data) {
        let cfg = &data.economy;
        let count = self.province_owner.len();
        self.province_gdp.resize(count, 0.0);
        self.province_industry.resize(count, 0.0);
        self.province_food.resize(count, 0.0);
        self.province_pool.resize(count, 0.0);
        let mut sums = vec![Sums::default(); self.nations.len()];
        let econ: Vec<EconNation> = self.nations.iter().map(Nation::econ).collect();
        for id in 1..count {
            let tag = self.nation_index[&self.province_owner[id]];
            let b = refs_b(&self.province_buildings[id]);
            let d = refs_d(&self.province_deposit[id]);
            let o = economy::province_output(
                cfg,
                self.province_population[id] as i64,
                data.map.provinces[id].area_km2(),
                &econ[tag],
                &b,
                &d,
            );
            self.province_gdp[id] = o.gdp as f32;
            self.province_industry[id] = o.industry as f32;
            self.province_food[id] = o.food as f32;
            self.province_pool[id] = o.pool as f32;
            let holder = self.nation_index[&self.province_controller[id]];
            if holder == tag {
                let s = &mut sums[tag];
                s.gdp += o.gdp;
                s.industry += o.industry;
                s.food += o.food;
                s.trade += o.trade;
                s.pool += o.pool;
                s.materials += o.materials;
                if data.map.provinces[id].coastal {
                    s.coast += 1.0;
                }
            } else {
                // Occupied: the owner loses the output and the occupier collects a share of the tax.
                sums[holder].gdp += o.gdp * data.military.occupation_income_share;
            }
        }
        self.economy_sums = sums;
        if self.materials_k <= 0.0 {
            self.calibrate(data);
        }
        self.compute_budgets(data);
    }

    /// `Economy._calibrate_materials`: the kt of raw materials a year one GBP million of industrial output needs, so
    /// that the world just balances (all deposits against all industry).
    pub fn calibrate_materials(&mut self, data: &Data) {
        let cfg = &data.economy;
        let (mut own, mut industry) = (0.0, 0.0);
        for id in 1..self.province_owner.len() {
            let mut sum = 0.0;
            for (_, v) in &self.province_deposit[id] {
                if *v >= cfg.materials_min_deposit {
                    sum += *v;
                }
            }
            own += sum * cfg.materials_extraction_base;
            industry += self.province_industry[id] as f64;
        }
        self.materials_k = if industry > 0.0 { own / industry } else { cfg.materials_need_per_industry };
    }
}

fn set_deposit(list: &mut Vec<(String, f64)>, id: &str, value: f64) {
    match list.iter_mut().find(|(k, _)| k == id) {
        Some(slot) => slot.1 = value,
        None => list.push((id.to_string(), value)),
    }
}

fn set_building(list: &mut Vec<(String, i32)>, id: &str, level: i32) {
    match list.iter_mut().find(|(k, _)| k == id) {
        Some(slot) => slot.1 = level,
        None => list.push((id.to_string(), level)),
    }
}
