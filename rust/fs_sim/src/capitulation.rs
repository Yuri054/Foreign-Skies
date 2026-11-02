//! Capitulation (`scripts/sim/capitulation.gd`, the part that acts): a nation whose enemies hold enough of what it is worth lays
//! down its arms, a nation that loses its capital moves it (or capitulates if it cannot), and each enemy dictates its peace.
//!
//! The terms an AI enemy asks (`AIPeace.price_terms`) and whether the beaten nation accepts them (`AIPeace.accepts`) are the AI's
//! decisions, which are not ported: a test supplies them in `GameState::ai_dictation`, and the port stops with a message if
//! they are missing. Recruiting is not ported, so a nation is taken to have nothing in training.

use crate::peace::Demand;
use crate::state::{Data, GameState};

/// `GameState.capital_choice`: the player's capital has fallen and a new one is to be chosen.
#[derive(Debug, Clone, PartialEq)]
pub struct CapitalChoice {
    pub tag: String,
    pub candidates: Vec<usize>,
    pub lost: i64,
}

/// What the AI decided for one war a capitulation ended: `enemy` dictating to `tag` in war `war_id`.
#[derive(Debug, Clone)]
pub struct Dictation {
    pub enemy: String,
    pub tag: String,
    pub war_id: u32,
    pub terms: Vec<Demand>,
    pub accepts: bool,
}

impl GameState {
    /// `Capitulation.capital_candidates`: where a nation could move its capital: the provinces it owns and holds, those with a
    /// city first, each kind most valuable first.
    pub fn capital_candidates(&self, data: &Data, tag: &str) -> Vec<usize> {
        let n = self.nation(tag);
        let mut out: Vec<usize> = n.provinces.iter().copied().filter(|&id| self.province_controller[id] == tag && id as i64 != n.capital).collect();
        let has_city = |id: usize| self.cities.iter().any(|c| c.province == id);
        crate::gd::sort_custom(&mut out, |&a, &b| {
            let (ca, cb) = (has_city(a), has_city(b));
            if ca != cb {
                return ca;
            }
            self.province_value(data, a) > self.province_value(data, b)
        });
        out
    }

    /// `Capitulation.can_relocate`.
    pub fn can_relocate(&self, data: &Data, tag: &str) -> bool {
        1.0 - self.capitulation_progress(data, tag) >= data.diplomacy.capitulation.relocation_share && !self.capital_candidates(data, tag).is_empty()
    }

    /// `Capitulation.step_day`.
    pub fn capitulation_step_day(&mut self, data: &Data) {
        for i in 0..self.nations.len() {
            if self.nations[i].provinces.is_empty() {
                continue;
            }
            let tag = self.nations[i].tag.clone();
            if self.wars_of(&tag).is_empty() {
                // At peace: no longer capitulated; a capital moved in the war goes home if the home is still the nation's.
                self.nations[i].capitulated = false;
                let home = self.home_capital(&tag);
                let owned = self.nations[i].provinces.iter().any(|&p| p as i64 == home);
                if self.relocated(&tag) && owned && self.province_controller[home as usize] == tag {
                    self.move_capital(&tag, home as usize);
                } else if !owned {
                    self.nations[i].home_capital = self.nations[i].capital;
                }
                continue;
            }
            if self.nations[i].capitulated {
                continue;
            }
            // The home capital retaken: the capital goes back.
            let home = self.home_capital(&tag);
            if self.relocated(&tag) && self.province_controller[home as usize] == tag {
                self.move_capital(&tag, home as usize);
            }
            if self.capitulation_progress(data, &tag) >= data.diplomacy.capitulation.capitulate_share {
                self.capitulate(data, &tag);
                continue;
            }
            let cap = self.nations[i].capital;
            if cap > 0 && self.province_controller[cap as usize] != tag && self.at_war(&tag, &self.province_controller[cap as usize].clone()) {
                self.capital_lost(data, &tag);
            }
        }
    }

    /// `Capitulation._capital_lost`: the capital has fallen: move it if the nation can, else capitulate.
    fn capital_lost(&mut self, data: &Data, tag: &str) {
        if self.capital_choice.as_ref().map(|c| c.tag == tag).unwrap_or(false) {
            return; // the player is choosing
        }
        if !self.can_relocate(data, tag) {
            self.capitulate(data, tag);
            return;
        }
        let candidates = self.capital_candidates(data, tag);
        if tag == self.player_tag {
            self.capital_choice = Some(CapitalChoice { tag: tag.to_string(), candidates, lost: self.nation(tag).capital });
            return;
        }
        self.move_capital(tag, candidates[0]);
    }

    /// `Capitulation.move_capital`: moves a nation's capital (keeping the home capital it started the war with).
    pub fn move_capital(&mut self, tag: &str, id: usize) {
        let i = self.nation_index[tag];
        if self.nations[i].home_capital <= 0 {
            self.nations[i].home_capital = self.nations[i].capital;
        }
        self.nations[i].capital = id as i64;
        if self.capital_choice.as_ref().map(|c| c.tag == tag).unwrap_or(false) {
            self.capital_choice = None;
        }
    }

    /// `MoveCapital.execute`: the player's choice of a new capital.
    pub fn choose_capital(&mut self, tag: &str, province: usize) -> bool {
        match &self.capital_choice {
            Some(c) if c.tag == tag && c.candidates.contains(&province) => {}
            _ => return false,
        }
        if self.province_controller[province] != tag {
            return false;
        }
        self.move_capital(tag, province);
        true
    }

    /// `Capitulation.capitulate`: the nation lays down its arms; each AI enemy then dictates its peace.
    pub fn capitulate(&mut self, data: &Data, tag: &str) {
        let i = self.nation_index[tag];
        if self.nations[i].capitulated {
            return;
        }
        self.nations[i].capitulated = true;
        if self.capital_choice.as_ref().map(|c| c.tag == tag).unwrap_or(false) {
            self.capital_choice = None;
        }
        let mut men = 0.0;
        for a in self.armies.iter().filter(|a| a.tag == tag) {
            men += a.men(&data.military);
        }
        self.armies.retain(|a| a.tag != tag);
        self.nations[i].manpower += men.round() as i64;
        self.refresh_men(data);
        let date = self.calendar.date_string();
        for w in self.wars_of(tag) {
            self.wars[w].capitulated.insert(tag.to_string(), date.clone());
        }
        self.dictate(data, tag);
    }

    /// `Capitulation.dictate`: every AI enemy takes what its war score (and the capitulation) pays for; the player, if an enemy,
    /// gets the peace screen to dictate its own.
    fn dictate(&mut self, data: &Data, tag: &str) {
        let wars: Vec<(u32, String)> = self.wars_of(tag).into_iter().map(|w| (self.wars[w].id, self.wars[w].other(tag).to_string())).collect();
        for (war_id, enemy) in wars {
            if enemy == self.player_tag {
                continue; // the peace screen
            }
            let pos = self
                .ai_dictation
                .iter()
                .position(|d| d.enemy == enemy && d.tag == tag && d.war_id == war_id)
                .unwrap_or_else(|| panic!("the AI's terms for {enemy} dictating to {tag} in war {war_id} are needed: the AI is not ported"));
            let d = self.ai_dictation.remove(pos);
            let mut terms = d.terms;
            if !self.check_peace(data, &enemy, tag, "demand", &terms).ok {
                terms = vec![];
            }
            self.propose_peace(data, &enemy, tag, "demand", terms, d.accepts);
        }
    }
}
