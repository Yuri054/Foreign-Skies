//! Saving and loading the whole simulation (`scripts/sim/save_game.gd`). A save is a header, a JSON text that a save list can read
//! without opening the rest (magic, version, date, days, nation, scenario), then the state as compressed CBOR. CBOR keeps what
//! the game needs kept: whole numbers apart from fractions, maps keyed by numbers or pairs, and every bit of every float (a
//! replay must come out the same). Every field of `GameState` is saved as it stands, the day's caches too, so a loaded game
//! goes on exactly as the one that was saved would have. The data files (`Data`) are not in a save: they are read again.
//!
//! The format is the port's own: it does not read the GDScript game's `.sav` files (Godot's variant bytes).

use crate::state::GameState;
use std::io::{Read, Write};

/// The save format. Bump it when a change to the state cannot be read from an older save, and refuse the old ones.
pub const VERSION: u32 = 1;
pub const MAGIC: &str = "foreign-skies-rust-save";

/// What a save list shows of a save.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Header {
    pub magic: String,
    pub version: u32,
    pub date: String,
    pub days: i64,
    pub player: String,
    pub scenario: String,
}

pub fn header(gs: &GameState) -> Header {
    Header { magic: MAGIC.to_string(), version: VERSION, date: gs.calendar.date_string(), days: gs.calendar.days_elapsed as i64, player: gs.player_tag.clone(), scenario: gs.scenario.clone() }
}

/// The game as bytes: the header's length (4 bytes) and text, the length of the state (8 bytes), the state compressed.
pub fn to_bytes(gs: &GameState) -> Result<Vec<u8>, String> {
    let head = serde_json::to_string(&header(gs)).map_err(|e| e.to_string())?;
    let mut raw = vec![];
    ciborium::into_writer(gs, &mut raw).map_err(|e| format!("Cannot write the save: {e}"))?;
    let mut zip = flate2::write::GzEncoder::new(vec![], flate2::Compression::fast());
    zip.write_all(&raw).map_err(|e| e.to_string())?;
    let packed = zip.finish().map_err(|e| e.to_string())?;
    let mut out = Vec::with_capacity(packed.len() + head.len() + 12);
    out.extend_from_slice(&(head.len() as u32).to_le_bytes());
    out.extend_from_slice(head.as_bytes());
    out.extend_from_slice(&(raw.len() as u64).to_le_bytes());
    out.extend_from_slice(&packed);
    Ok(out)
}

/// The header of a save, or what is wrong with it.
pub fn read_header(bytes: &[u8]) -> Result<(Header, usize), String> {
    let len = bytes.get(..4).ok_or("Not a save.")?;
    let len = u32::from_le_bytes(len.try_into().unwrap()) as usize;
    let text = bytes.get(4..4 + len).ok_or("Not a save.")?;
    let head: Header = serde_json::from_slice(text).map_err(|_| "Not a save.".to_string())?;
    if head.magic != MAGIC {
        return Err("Not a save.".to_string());
    }
    if head.version != VERSION {
        return Err(format!("This save is of version {}; this game reads version {VERSION}.", head.version));
    }
    Ok((head, 4 + len))
}

/// The game a save holds.
pub fn from_bytes(bytes: &[u8]) -> Result<GameState, String> {
    let (_, at) = read_header(bytes)?;
    let size = bytes.get(at..at + 8).ok_or("The save is cut short.")?;
    let size = u64::from_le_bytes(size.try_into().unwrap()) as usize;
    let mut raw = Vec::with_capacity(size);
    flate2::read::GzDecoder::new(&bytes[at + 8..]).read_to_end(&mut raw).map_err(|e| format!("The save is damaged: {e}"))?;
    if raw.len() != size {
        return Err("The save is damaged: it is shorter than it says.".to_string());
    }
    ciborium::from_reader(raw.as_slice()).map_err(|e| format!("The save is damaged: {e}"))
}

/// Writes the game to `path`; the old file stays until the new one is whole.
pub fn write(gs: &GameState, path: &std::path::Path) -> Result<(), String> {
    let bytes = to_bytes(gs)?;
    let tmp = path.with_extension("sav.tmp");
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| format!("Cannot write {}: {e}", path.display()))?;
    }
    std::fs::write(&tmp, bytes).map_err(|e| format!("Cannot write {}: {e}", path.display()))?;
    std::fs::rename(&tmp, path).map_err(|e| format!("Cannot write {}: {e}", path.display()))
}

pub fn read(path: &std::path::Path) -> Result<GameState, String> {
    from_bytes(&std::fs::read(path).map_err(|e| format!("Cannot open {}: {e}", path.display()))?)
}
