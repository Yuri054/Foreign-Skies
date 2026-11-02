//! The Foreign Skies simulation in Rust: a port of `scripts/sim` (GDScript).
//!
//! The port goes system by system and every piece is checked against the original: `tools/dump_sim_golden.gd` runs the
//! GDScript code over a grid of inputs and writes what it gives (floats as their exact bits) to
//! `tests/golden/slice.json`, and `tests/golden.rs` makes this crate reproduce it. See `rust/README.md` for what is
//! ported and what is not.

pub mod actions;
pub mod army_mgmt;
pub mod budget;
pub mod clock;
pub mod config;
pub mod capitulation;
pub mod declare;
pub mod diplomacy;
pub mod economy;
pub mod economy_cmds;
pub mod front;
pub mod game;
pub mod group;
pub mod gd;
pub mod map;
pub mod military;
pub mod population;
pub mod navy;
pub mod offensive;
pub mod peace;
pub mod pressure;
pub mod state;
pub mod war;
pub mod tsv;
