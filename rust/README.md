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
| `map_data.gd` (part) | `map.rs`, `tsv.rs` | The provinces (owner, area, coast) and the nations in file order; the table reader. |
| `game_state.gd` (part) | `state.rs` | `load_scenario` for the economy: owners, people, deposits, the works a scenario starts with, the nations, `set_controller`. |
| `economy.gd` (part) | `state.rs` | `absorb_works`, and `recompute`'s province output and nation sums (also with occupied provinces), and `calibrate_materials`. |
| `navy.gd` (part) | `state.rs` | The starting fleets (`navy.tsv`), `_give_home_ports`, ship upkeep, `refresh_upkeep` and the naval overhead. |
| `unit.gd`, `army.gd`, `military.gd` (part) | `military.rs`, `state.rs` | Divisions, a stack's power and shelling share, `deploy_starting` (the divisions dealt out to the scenario's stacks under their generals), `men_in_service`, `refresh_men`. |
| `munitions.gd` (part) | `state.rs` | `load_scenario` (arms share and stockpile), `war_need`, `expected_daily`. |
| `war_support.gd` (part) | `config.rs`, `state.rs` | What a government starts with, and the tax curve at war (`economy_mult`). |
| `economy.gd` (budgets) | `budget.rs`, `state.rs` | `nation_budget` (revenue, costs, food, raw materials, industry, manpower), `materials_of`, soldier wages, `construction_points`, `_budgets`, `calibrate`. |

The budget of every nation is compared key by key (31 figures and the 7 of its raw materials), together with its civil
spending, wage, men and stockpile, in four situations the real game worked out: each scenario as it loads, July 1914 with
nine provinces held by an enemy, and July 1914 under strain (mobilization, debt, blockade, famine, investment, heavy
taxes, a national focus, men on exercise, and two wars).

A second golden file, `state.json` (made by `tools/dump_state_golden.gd`), holds what the real game's state is right after it
loads each scenario: all 941 provinces (owner, holder, people, works, deposits and what each makes), the 22 nations
(development, people, province lists, summed output) and the raw-materials constant, for July 1914 and January 1900,
and the sums again with nine provinces held by an enemy. The Rust load reproduces all of it.

The tests cover about 2,400 cases (6,000 days of the calendar, 600 province outputs, 900 growth cases, 331 building
costs, 200 worker shares, 180 population steps and so on). Breaking any of these rules on purpose makes a test fail.

## What is not ported

Most of it. Still missing from the economy: the construction queue, `Economy.step_day` and `step_month` (and
`Population.step_month`), `level_gain` and `building_stats`. The loader does not start a scenario's wars, set up
diplomacy, the AI, pressure or crises. After the economy: `game_state.gd`'s day stages, `military.gd` (movement,
supply, battles, fronts), `navy.gd` (movement and battles), `diplomacy.gd`, `peace.gd`, `pressure.gd`, `crisis.gd`,
`focus.gd`, and the war and front code. They need the map's neighbours and sea zones, and Godot's random numbers, which
the port has to match before whole days can be compared. The AI (`scripts/ai`) is not part of this port.

## What comes next

1. Port `Economy.step_day` (construction, munitions, weariness and starvation) and `step_month` (with
   `Population.step_month`), and compare a nation's treasury, output and people after a month and a year of the real game
   with the AI off.
2. Match Godot's `RandomNumberGenerator` (PCG32) so seeded runs can be compared, then port military, navy and
   diplomacy, comparing whole days of the real game at each step.
