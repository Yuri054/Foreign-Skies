//! The game calendar (`scripts/sim/clock.gd`): the date, and how it moves a day at a time.
//!
//! Real time, pause and speed belong to the front end and are not here; the simulation only needs to be told
//! "a day has passed" (`advance_day`) and to know the date.

pub const MONTH_NAMES: [&str; 12] = [
    "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
    "December",
];

/// What a day's step crossed: a new month and/or a new year began.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct DayTick {
    pub new_month: bool,
    pub new_year: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Calendar {
    pub year: i32,
    pub month: i32,
    pub day: i32,
    /// Days since the scenario started (for durations).
    pub days_elapsed: i32,
}

impl Default for Calendar {
    fn default() -> Self {
        // The same default as the GDScript: the July 1914 scenario's first day.
        Calendar { year: 1914, month: 7, day: 28, days_elapsed: 0 }
    }
}

impl Calendar {
    pub fn start(year: i32, month: i32, day: i32) -> Self {
        Calendar { year, month, day, days_elapsed: 0 }
    }

    pub fn advance_day(&mut self) -> DayTick {
        let mut tick = DayTick { new_month: false, new_year: false };
        self.day += 1;
        self.days_elapsed += 1;
        if self.day > days_in_month(self.year, self.month) {
            self.day = 1;
            self.month += 1;
            tick.new_month = true;
            if self.month > 12 {
                self.month = 1;
                self.year += 1;
                tick.new_year = true;
            }
        }
        tick
    }

    /// "28 July 1914".
    pub fn date_string(&self) -> String {
        format!("{} {} {}", self.day, MONTH_NAMES[(self.month - 1) as usize], self.year)
    }

    /// The date the given number of days from now, e.g. "14 August 1914".
    pub fn date_after(&self, days: i32) -> String {
        let (mut y, mut m, mut d) = (self.year, self.month, self.day + days);
        while d > days_in_month(y, m) {
            d -= days_in_month(y, m);
            m += 1;
            if m > 12 {
                m = 1;
                y += 1;
            }
        }
        format!("{} {} {}", d, MONTH_NAMES[(m - 1) as usize], y)
    }
}

pub fn is_leap_year(y: i32) -> bool {
    y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
}

pub fn days_in_month(y: i32, m: i32) -> i32 {
    match m {
        2 => {
            if is_leap_year(y) {
                29
            } else {
                28
            }
        }
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}
