//! The books the game keeps about itself, which nothing in the rules reads: the history of the run (`history.gd`: what happened, every change
//! of owner, a row of figures a month), the standings of the nations month by month (`standings.gd`), the player's ambition (`ambition.gd`) and the
//! log of each war (`war.gd`). They are written by the rules as they happen, and the port keeps them exactly as the game does so that the
//! game's screens can be driven from it.

use crate::gd::{is_equal_approx, sort_custom};
use crate::pressure::GREAT;
use crate::state::{Data, GameState};
use serde_json::Value;
use std::collections::HashMap;

pub const LOG_MAX: usize = 4000;
pub const TERRITORY_MAX: usize = 3000;
pub const MONTHS_MAX: usize = 1200;
pub const WAR_LOG_MAX: usize = 400;
pub const WAR_BATTLES_MAX: usize = 300;
pub const STANDINGS_MAX: usize = 240;

/// A note in the history of the run (`GameState.history_log`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Note {
    pub day: i64,
    pub date: String,
    pub year: i32,
    pub kind: String,
    pub text: String,
}

/// A change of owner (`GameState.territory_log`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Territory {
    pub day: i64,
    pub date: String,
    pub year: i32,
    pub province: usize,
    pub old: String,
    pub new: String,
}

/// One row of figures for a month (`GameState.history_months`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct MonthRow {
    pub day: i64,
    pub year: i32,
    pub month: i32,
    pub wars: usize,
    pub battles: i64,
    pub casualties: f64,
    pub provinces: i64,
    pub tension: f64,
    pub crises: usize,
    pub top: Vec<String>,
}

/// An entry in the log of a war (`War.log`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct WarLog {
    pub date: String,
    pub kind: String,
    pub text: String,
    pub province: usize,
    pub battle: u32,
}

/// A finished battle as a war keeps it (`War.battles`): the sides' strengths and losses are in the order the sides joined.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct BattleRecord {
    pub id: u32,
    pub province: usize,
    pub name: String,
    pub date: String,
    pub end_date: String,
    pub days: i64,
    pub attacker: String,
    pub winner: String,
    pub strength: Vec<(String, f64)>,
    pub lost: Vec<(String, f64)>,
}

/// How a war ended by an accepted peace (`War.peace`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct PeaceRecord {
    pub taker: String,
    pub giver: String,
    pub terms: Vec<String>,
    pub white: bool,
    pub score: f64,
    pub forced: bool,
    pub date: String,
}

/// The figures of one month for every nation that holds land (`GameState.standings_history`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct StandingsRow {
    pub day: i64,
    pub date: String,
    /// tag -> the metrics in the order of `METRICS`.
    pub values: Vec<(String, Vec<f64>)>,
}

/// The player's ambition (`GameState.ambition`); `id` is empty for none.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct AmbitionState {
    pub id: String,
    pub tag: String,
    pub since: i32,
    pub state: String,
}

/// The rankable figures of `Standings.METRICS`, in order.
pub const METRICS: [&str; 11] = ["population", "income", "factories", "treasury", "army", "navy", "manpower", "provinces", "diplomacy_points", "prestige", "war_support"];

/// Names the texts of the books use, copied from the data when a game is loaded.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct Texts {
    pub province_names: Vec<String>,
    pub cb_labels: HashMap<String, String>,
    pub treaty_labels: HashMap<String, String>,
    pub terrain_names: HashMap<String, String>,
    pub ship_names: HashMap<String, String>,
    pub sea_zone_names: Vec<String>,
}

pub fn ordinal(n: i64) -> String {
    let tail = n % 100;
    if (11..=13).contains(&tail) {
        return format!("{n}th");
    }
    match n % 10 {
        1 => format!("{n}st"),
        2 => format!("{n}nd"),
        3 => format!("{n}rd"),
        _ => format!("{n}th"),
    }
}

impl GameState {
    // ---------------------------------------------------------------- history

    /// `History.note`: writes down something that happened now.
    pub fn note(&mut self, kind: &str, text: &str) {
        self.history_log.push(Note { day: self.calendar.days_elapsed as i64, date: self.calendar.date_string(), year: self.calendar.year, kind: kind.to_string(), text: text.to_string() });
        if self.history_log.len() > LOG_MAX {
            self.history_log.remove(0);
        }
    }

    /// `History.refine_last`: replaces the text of the latest note of a kind.
    pub fn refine_last(&mut self, kind: &str, text: &str) {
        if let Some(n) = self.history_log.iter_mut().rev().find(|n| n.kind == kind) {
            n.text = text.to_string();
        }
    }

    /// `History.record_territory`.
    pub fn record_territory(&mut self, province: usize, old: &str, new: &str) {
        self.territory_log.push(Territory { day: self.calendar.days_elapsed as i64, date: self.calendar.date_string(), year: self.calendar.year, province, old: old.to_string(), new: new.to_string() });
        self.history_provinces += 1;
        if self.territory_log.len() > TERRITORY_MAX {
            self.territory_log.remove(0);
        }
    }

    /// `War.add_log`.
    pub fn war_log(&mut self, war: usize, date: &str, kind: &str, text: &str, province: usize, battle: u32) {
        let w = &mut self.wars[war];
        w.log.push(WarLog { date: date.to_string(), kind: kind.to_string(), text: text.to_string(), province, battle });
        if w.log.len() > WAR_LOG_MAX {
            w.log.remove(0);
        }
    }

    /// `War.add_log` with today's date and no province or battle.
    pub fn war_log_now(&mut self, war: usize, kind: &str, text: &str) {
        let date = self.calendar.date_string();
        self.war_log(war, &date, kind, text, 0, 0);
    }

    /// `History.step_month`: one row of figures for the month just ended.
    pub fn history_step_month(&mut self, data: &Data) {
        let mut losses = 0.0;
        let mut battles = 0i64;
        for w in &self.wars {
            battles += w.battles.len() as i64;
            for t in [&w.a, &w.b] {
                losses += w.losses.get(t).copied().unwrap_or(0.0);
            }
        }
        let today = self.calendar.days_elapsed as i64;
        for w in &self.war_history {
            if today - w.end_day < 62 {
                battles += w.battles.len() as i64;
                for t in [&w.a, &w.b] {
                    losses += w.losses.get(t).copied().unwrap_or(0.0);
                }
            }
        }
        let row = MonthRow {
            day: today,
            year: self.calendar.year,
            month: self.calendar.month,
            wars: self.wars.len(),
            battles: (battles - self.history_battles_total).max(0),
            casualties: crate::gd::maxf(0.0, losses - self.history_losses_total),
            provinces: self.history_provinces,
            tension: self.tension,
            crises: self.crises.len(),
            top: self.standings_ranking(data, "income").into_iter().take(3).map(|r| r.0).collect(),
        };
        self.history_battles_total = battles;
        self.history_losses_total = losses;
        self.history_provinces = 0;
        self.history_months.push(row);
        if self.history_months.len() > MONTHS_MAX {
            self.history_months.remove(0);
        }
    }

    // ---------------------------------------------------------------- standings

    /// `Standings.value`: one figure for one nation.
    pub fn standings_value(&self, data: &Data, tag: &str, id: &str) -> f64 {
        let n = self.nation(tag);
        let b = &n.budget;
        match id {
            "population" => n.population as f64,
            "income" => b.income,
            "factories" => self.economy_sums.get(self.nation_index[tag]).map(|s| s.level("civilian_factory")).unwrap_or(0.0),
            "treasury" => n.treasury,
            "army" => self.men_in_service(data, tag) as f64,
            "navy" => self.fleets_of(tag).iter().map(|&i| self.fleets[i].ships.len()).sum::<usize>() as f64,
            "manpower" => b.manpower_pool,
            "provinces" => n.provinces.len() as f64,
            "diplomacy_points" => n.diplomacy_points,
            "prestige" => n.prestige,
            "war_support" => n.war_support,
            _ => 0.0,
        }
    }

    /// `Standings.ranking`: the nations that hold land, best first, as (tag, value). Ties keep tag order.
    pub fn standings_ranking(&self, data: &Data, id: &str) -> Vec<(String, f64)> {
        let mut out: Vec<(String, f64)> = self.nations.iter().filter(|n| !n.provinces.is_empty()).map(|n| (n.tag.clone(), self.standings_value(data, &n.tag, id))).collect();
        sort_custom(&mut out, |a, b| if !is_equal_approx(a.1, b.1) { a.1 > b.1 } else { a.0 < b.0 });
        out
    }

    /// `Standings.record`: writes down every figure for every nation: at the start and each month.
    pub fn standings_record(&mut self, data: &Data) {
        let mut values = vec![];
        for n in &self.nations {
            if n.provinces.is_empty() {
                continue;
            }
            values.push((n.tag.clone(), METRICS.iter().map(|m| self.standings_value(data, &n.tag, m)).collect()));
        }
        self.standings_history.push(StandingsRow { day: self.calendar.days_elapsed as i64, date: self.calendar.date_string(), values });
        while self.standings_history.len() > STANDINGS_MAX {
            self.standings_history.remove(0);
        }
    }

    /// `Standings.year_report`: the player's year in a line ("" without a player or a year of records).
    pub fn standings_year_report(&self) -> String {
        let me = &self.player_tag;
        let h = &self.standings_history;
        if !self.nation_index.contains_key(me) || h.len() < 13 {
            return String::new();
        }
        let income = METRICS.iter().position(|m| *m == "income").unwrap();
        let (then, now) = (&h[h.len() - 13].values, &h[h.len() - 1].values);
        let find = |rows: &Vec<(String, Vec<f64>)>, t: &str| rows.iter().find(|r| r.0 == t).map(|r| r.1[income]);
        let (Some(t_me), Some(n_me)) = (find(then, me), find(now, me)) else { return String::new() };
        if t_me <= 0.0 {
            return String::new();
        }
        let growth = n_me / t_me - 1.0;
        let rank_in = |rows: &Vec<(String, Vec<f64>)>, mine: f64, me: &str| 1 + rows.iter().filter(|r| r.0 != me && r.1[income] > mine).count() as i64;
        let (rank_then, rank_now) = (rank_in(then, t_me, me), rank_in(now, n_me, me));
        let (mut passed, mut lost): (Vec<String>, Vec<String>) = (vec![], vec![]);
        for (tag, row) in now {
            let Some(t_other) = find(then, tag) else { continue };
            if tag == me || !self.nation_index.contains_key(tag) {
                continue;
            }
            let was_ahead = t_other > t_me;
            let is_ahead = row[income] > n_me;
            let name = self.nation(tag).display_name.clone();
            if was_ahead && !is_ahead {
                passed.push(name);
            } else if is_ahead && !was_ahead {
                lost.push(name);
            }
        }
        let mut line = format!("The year {}: income {:+.1}%, {} largest economy", self.calendar.year - 1, growth * 100.0, ordinal(rank_now));
        if rank_now != rank_then {
            line += &format!(" ({} last year)", ordinal(rank_then));
        }
        if !passed.is_empty() {
            line += &format!("; passed {}", passed.join(", "));
        }
        if !lost.is_empty() {
            line += &format!("; passed by {}", lost.join(", "));
        }
        line + "."
    }

    // ---------------------------------------------------------------- the player's ambition

    fn claimed_by(&self, data: &Data, tag: &str) -> Vec<usize> {
        let mut out: Vec<usize> = vec![];
        for claim in &self.scenario_claims {
            if claim.get("holder").and_then(Value::as_str) == Some(tag) {
                for id in self.claim_provinces(data, claim) {
                    if !out.contains(&id) {
                        out.push(id);
                    }
                }
            }
        }
        out
    }

    /// `Ambition.offered`: the ambitions open to `tag`, in the order of the data.
    pub fn ambitions_offered(&self, data: &Data, tag: &str) -> Vec<String> {
        let mut out = vec![];
        if !self.nation_index.contains_key(tag) {
            return out;
        }
        for (id, def) in data.ambitions["ambitions"].as_object().unwrap() {
            match def.get("for").and_then(Value::as_str).unwrap_or("all") {
                "minor" if GREAT.contains(&tag) => continue,
                "claims" if self.claimed_by(data, tag).is_empty() => continue,
                _ => {}
            }
            out.push(id.clone());
        }
        out
    }

    fn ambition_label(data: &Data, id: &str) -> String {
        data.ambitions["ambitions"].get(id).and_then(|d| d.get("label")).and_then(Value::as_str).unwrap_or(id).to_string()
    }

    /// `Ambition.choose`: the player takes up an ambition (or "" to give it up).
    pub fn choose_ambition(&mut self, data: &Data, tag: &str, id: &str) -> bool {
        if tag != self.player_tag || (!id.is_empty() && !self.ambitions_offered(data, tag).iter().any(|x| x == id)) {
            return false;
        }
        let old = self.ambition.id.clone();
        if old == id {
            return false;
        }
        let name = self.nation(tag).display_name.clone();
        if !old.is_empty() {
            self.note("ambition", &format!("{name} gives up its ambition: {}.", Self::ambition_label(data, &old).to_lowercase()));
        }
        self.ambition = if id.is_empty() { AmbitionState::default() } else { AmbitionState { id: id.to_string(), tag: tag.to_string(), since: self.calendar.year, state: String::new() } };
        if !id.is_empty() {
            self.note("ambition", &format!("{name} sets itself an ambition: {}.", Self::ambition_label(data, id).to_lowercase()));
            self.ambition.state = self.ambition_status(data).0;
        }
        true
    }

    /// `Ambition.status`: how the ambition stands: (state: "on course", "achieved", "lost" or "" for none, text).
    pub fn ambition_status(&self, data: &Data) -> (String, String) {
        let a = &self.ambition;
        if a.id.is_empty() || !self.nation_index.contains_key(&a.tag) {
            return (String::new(), String::new());
        }
        let tag = a.tag.as_str();
        let years = self.calendar.year - a.since;
        match a.id.as_str() {
            "keep_out" => {
                for w in &self.wars {
                    if (w.a == tag && GREAT.contains(&w.b.as_str())) || (w.b == tag && GREAT.contains(&w.a.as_str())) {
                        let foe = if w.a == tag { &w.b } else { &w.a };
                        return ("lost".to_string(), format!("We are at war with {}.", self.nation(foe).display_name));
                    }
                }
                if a.state == "lost" {
                    return ("lost".to_string(), "We were drawn into a great power's war.".to_string());
                }
                ("on course".to_string(), format!("Kept out of the powers' wars for {years} years."))
            }
            "unify" => {
                let ids = self.claimed_by(data, tag);
                let held = ids.iter().filter(|&&i| self.province_owner[i] == tag).count();
                if held == ids.len() && !ids.is_empty() {
                    return ("achieved".to_string(), "Every claimed province is ours.".to_string());
                }
                ("on course".to_string(), format!("{} of {} claimed provinces are ours.", held, ids.len()))
            }
            "great_power" => {
                let n = self.nation(tag);
                let mut rank = 1;
                for o in &self.nations {
                    if o.tag != tag && !o.provinces.is_empty() && o.budget.income > n.budget.income {
                        rank += 1;
                    }
                }
                let need = data.ambitions["ambitions"]["great_power"].get("rank").and_then(Value::as_i64).unwrap_or(6);
                if rank <= need {
                    return ("achieved".to_string(), format!("Our output ranks {rank} in Europe."));
                }
                ("on course".to_string(), format!("Our output ranks {rank} in Europe; the powers are the first {need}."))
            }
            _ => (String::new(), String::new()),
        }
    }

    /// `Ambition.step_month`: a change in how the ambition stands goes into the history. A lost "keep out" stays lost.
    pub fn ambition_step_month(&mut self, data: &Data) {
        if self.ambition.id.is_empty() {
            return;
        }
        let (state, text) = self.ambition_status(data);
        if state != self.ambition.state {
            let who = if self.nation_index.contains_key(&self.ambition.tag) { self.nation(&self.ambition.tag).display_name.clone() } else { self.ambition.tag.clone() };
            let label = Self::ambition_label(data, &self.ambition.id).to_lowercase();
            match state.as_str() {
                "achieved" => self.note("ambition", &format!("{who} achieves its ambition ({label}): {text}")),
                "lost" => self.note("ambition", &format!("{who}'s ambition fails ({label}): {text}")),
                "on course" => self.note("ambition", &format!("{who}'s ambition ({label}) is in doubt again: {text}")),
                _ => {}
            }
            self.ambition.state = state;
        }
    }
}
