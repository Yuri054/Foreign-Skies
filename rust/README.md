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
| `economy.gd` (steps) | `state.rs` | `step_day` (war weariness and starvation, munitions made, hulls and buildings built), `step_month` (treasury, development, wages, the AI's standing army, manpower), the job queue. |
| `focus.gd` | `config.rs`, `state.rs` | The national focus: `tree_of`, `block`, `start`, the daily step, `complete` and `apply_effects` (lasting bonuses, prestige, points, money, war support, army size, relations, claims). |
| `diplomacy.gd` (part) | `state.rs` | Relations (`relation`, `set_relation`, `change_relation`), diplomacy points (`gain`) and prestige, which the focus uses. Treaties, wars and the monthly drift are not ported. |
| `population.gd` | `population.rs`, `state.rs` | The monthly step: growth, famine, occupation and war dead. |
| `economy.gd` (budgets) | `budget.rs`, `state.rs` | `nation_budget` (revenue, costs, food, raw materials, industry, manpower), `materials_of`, soldier wages, `construction_points`, `_budgets`, `calibrate`. |

The budget of every nation is compared key by key (31 figures and the 7 of its raw materials), together with its civil
spending, wage, men and stockpile, in four situations the real game worked out: each scenario as it loads, July 1914 with
nine provinces held by an enemy, and July 1914 under strain (mobilization, debt, blockade, famine, investment, heavy
taxes, a national focus, men on exercise, and two wars).

A third golden file, `steps.json` (made by `tools/dump_steps_golden.gd`), is the real `Economy.step_day` (thirty times) and
`Economy.step_month`, month after month, with nothing else running: 24 months of July 1914 at peace with works and hulls in
the queue, a year of January 1900, and 18 months of July 1914 at war (strain, blockade, famine, enemy-held ground, war
deaths). Every nation's treasury, development, wage, stockpile, weariness, war support, men, people and budget, and the
state of every job, are compared after every month, and the people, fractions and works of every province at the end.
The Rust reproduces all of it bit for bit (the tolerance in the test is 1e-13, and 0 passes too).

A fourth golden file, `focus.json` (made by `tools/dump_focus_golden.gd`), has every nation of July 1914 working through
its focus tree for forty-eight months (464 foci, the repeatable ones included) and of January 1900 for eighteen, with the
real daily and monthly economy running, and effects applied by hand (a claim, army growth, relations and points past their
limits). Each month's focus, foci done, bonuses, treasury, war support, army, prestige, points, relations and claims are
compared. (The starting relations are read from the game: the loader for them is not ported yet.)

A second golden file, `state.json` (made by `tools/dump_state_golden.gd`), holds what the real game's state is right after it
loads each scenario: all 941 provinces (owner, holder, people, works, deposits and what each makes), the 22 nations
(development, people, province lists, summed output) and the raw-materials constant, for July 1914 and January 1900,
and the sums again with nine provinces held by an enemy. The Rust load reproduces all of it.

The tests cover about 2,400 cases (6,000 days of the calendar, 600 province outputs, 900 growth cases, 331 building
costs, 200 worker shares, 180 population steps and so on). Breaking any of these rules on purpose makes a test fail.

## What is not ported

Most of it. Still missing from the economy: `level_gain` and `building_stats` (what the screens show). The loader does not
start a scenario's wars, set up diplomacy (treaties, relations, claims), the AI, pressure or crises, and the game's own
daily step (`game_state.gd`'s stages: economy and focus are ported, then `Navy`, `Military`, `Diplomacy`, `Crisis` and the
AI) is not. Next come `diplomacy.gd`, `military.gd` (movement, supply, battles, fronts), `navy.gd` (movement and battles),
`peace.gd`, `pressure.gd`, `crisis.gd` and the war and front code. They need the map's neighbours and sea zones. The AI
(`scripts/ai`) is not part of this port.

The simulation uses no random numbers (only the main menu and the city drawing do), so the port has no Godot generator to
match.

## What comes next

1. Port `diplomacy.gd`'s setup (`load_scenario`: treaties, relations, claims) and its monthly step, so the relations the
   focus uses are loaded and drift as in the game.
2. Load the map's neighbours (`data/map/adjacencies.tsv`) and port the movement and battle rules of `military.gd`,
   comparing days of the real game with the AI off.
3. Then navy, diplomacy and peace, pressure and crises, comparing whole days of the real game at each step.
