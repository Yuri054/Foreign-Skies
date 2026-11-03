//! The game's own step (`GameState._on_day_ticked`, `_on_month_ticked` and `Clock.advance_day`): the calendar moves on, then the
//! day's stages run in order (economy, focus and navy; the armies; diplomacy; the economy worked out again if anything changed it),
//! and at a month's end the month's steps. Not part of it: the AI (`AI.step_day`), and the records the game keeps for its screens (history, standings).

use crate::state::{Data, GameState};

impl GameState {
    /// One day of the game: what the clock's tick does.
    pub fn advance_day(&mut self, data: &Data) {
        let tick = self.calendar.advance_day();
        // the stages of the day
        self.in_day_step = true;
        self.step_day(data);
        self.focus_step_day(data);
        self.navy_step_day(data);
        self.military_step_day(data);
        self.diplomacy_step_day(data);
        self.crisis_step_day(data);
        self.ai_step_day(data);
        self.finish_economy_stage_full(data);
        if tick.new_month {
            self.step_month(data);
            self.diplomacy_step_month(data);
            self.pressure_step_month(data);
            self.crisis_step_month(data);
            self.standings_record(data);
            self.ambition_step_month(data);
            self.history_step_month(data);
        }
    }

    /// The day's last stage: the economy worked out again if something changed it, or just the budgets if only the blockade moved.
    fn finish_economy_stage_full(&mut self, data: &Data) {
        self.in_day_step = false;
        if self.economy_dirty {
            self.economy_dirty = false;
            self.budget_dirty = false;
            self.recompute(data);
        } else if self.budget_dirty {
            self.budget_dirty = false;
            if !self.economy_sums.is_empty() {
                self.compute_budgets(data);
            }
        }
    }
}
