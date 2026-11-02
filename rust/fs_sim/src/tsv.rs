//! Tab-separated tables with a header row (`MapData.read_table`).

use std::path::Path;

pub struct Table {
    header: Vec<String>,
    rows: Vec<Vec<String>>,
}

pub struct Row<'a> {
    table: &'a Table,
    cells: &'a [String],
}

impl Table {
    pub fn read(path: &Path) -> Result<Table, String> {
        let text = std::fs::read_to_string(path).map_err(|e| format!("cannot open {}: {e}", path.display()))?;
        let mut lines = text.split('\n');
        let header: Vec<String> = lines.next().unwrap_or("").trim_end_matches('\r').split('\t').map(str::to_string).collect();
        let rows = lines
            .map(|l| l.trim_end_matches('\r'))
            .filter(|l| !l.is_empty())
            .map(|l| l.split('\t').map(str::to_string).collect())
            .collect();
        Ok(Table { header, rows })
    }

    pub fn rows(&self) -> impl Iterator<Item = Row<'_>> {
        self.rows.iter().map(move |cells| Row { table: self, cells })
    }
}

impl<'a> Row<'a> {
    /// The cell under a column, "" if the row is short (as the GDScript reader gives).
    pub fn get(&self, column: &str) -> &'a str {
        match self.table.header.iter().position(|h| h == column) {
            Some(i) => self.cells.get(i).map(String::as_str).unwrap_or(""),
            None => "",
        }
    }

    pub fn int(&self, column: &str) -> i64 {
        to_int(self.get(column))
    }

    pub fn float(&self, column: &str) -> f64 {
        to_float(self.get(column))
    }
}

/// GDScript's `int("...")` on a string: the leading integer, 0 if there is none.
pub fn to_int(s: &str) -> i64 {
    let s = s.trim();
    let end = s
        .char_indices()
        .find(|(i, c)| !(c.is_ascii_digit() || (*i == 0 && (*c == '-' || *c == '+'))))
        .map(|(i, _)| i)
        .unwrap_or(s.len());
    s[..end].parse().unwrap_or(0)
}

/// GDScript's `float("...")` on a string.
pub fn to_float(s: &str) -> f64 {
    s.trim().parse().unwrap_or(0.0)
}
