# Foreign Skies simulation in Rust (`fs_sim`)

A port of `scripts/sim` (GDScript, about 13,700 lines) to Rust. The game stays in Godot; this crate is the simulation
alone, so it can run without an engine (balance runs, servers, tests) and later be called from the game.

**This is the start of the port, not the whole of it.** It goes system by system, and each piece is checked against the
original before the next one begins.

## How a piece is checked

`tools/dump_sim_golden.gd` runs the real GDScript code over a grid of inputs and writes what it returns to
`fs_sim/tests/golden/slice.json`, with every float as the bits of its 64-bit value, so nothing is lost in the text.
`fs_sim/tests/golden.rs` makes the Rust code reproduce every number. The comparison is exact, except for results that
go through `pow()`, which may differ by a few units in the last place between maths libraries (the tests allow 4).

```sh
cd rust && cargo test                      # no Godot needed: the golden file is in the repository

# after changing the GDScript rules, make the golden file again (needs Godot 4.7.2):
godot --headless --path . -s res://tools/dump_sim_golden.gd -- rust/fs_sim/tests/golden/slice.json
```

## What is ported

| GDScript | Rust | What |
|---|---|---|
| `clock.gd` | `clock.rs` | The calendar: the date, leap years, a day's step, date strings (not real-time speed or pause). |
| `economy.gd` | `economy.rs` | The pure rules: province output, building and focus modifiers, tax strain and relief, growth, investment, workers, building size factor, cost and plan. |
| `population.gd` | `population.rs` | The rounding that adds people to a province (and the growth rate). |
| `data/economy.json` | `config.rs` | The economy's constants, with the file's order kept. |

The tests cover about 2,400 cases (6,000 days of the calendar, 600 province outputs, 900 growth cases, 331 building
costs, 200 worker shares, 180 population steps and so on). Breaking any of these rules on purpose makes a test fail.

## What is not ported

Most of it. The rest of `economy.gd` (budgets, the daily step, raw materials, food and the construction queue) and
`population.gd`'s monthly step need the whole game state, and so does everything else in `scripts/sim`:
`game_state.gd` (the state and the day's stages), `military.gd`, `navy.gd`, `diplomacy.gd`, `peace.gd`, `pressure.gd`,
`crisis.gd`, `focus.gd`, the war and front code, and so on. They also depend on `MapData` (the provinces, their
neighbours and areas), the scenario files and Godot's random numbers, which the port has to match before whole days can
be compared. The AI (`scripts/ai`) is not part of this port.

## What comes next

1. Load the map and a scenario (`data/map`, `data/scenarios/...`) into a Rust `GameState`.
2. Port `Economy.recompute`, `_budgets` and `step_day`, then compare a nation's treasury and output after a month and a
   year of the real game with the AI off.
3. Match Godot's `RandomNumberGenerator` (PCG32) so seeded runs can be compared, then port military, navy and
   diplomacy, comparing whole days of the real game at each step.
