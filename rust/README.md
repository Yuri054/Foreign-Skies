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
| `diplomacy.gd` (part) | `diplomacy.rs`, `state.rs` | `load_scenario` (the treaty web, every pair's opinion and baseline, rivalries), relations, diplomacy points and prestige, `step_day` (mobilization, alarms, call-ups, `mobilization_target`), `step_month` (points income and rank, projects, prestige, grievance, gifts, the drift of opinion), and neighbours (`MapData.neighbors`). |
| `war_support.gd` (part) | `diplomacy.rs` | `monthly_changes` and `step_month`. (A forced white peace needs the peace rules and stops the port with a message.) |
| `military.gd` (part), `capitulation.gd` (part), `munitions.gd` (part), `war.gd`, `cities.gd` | `war.rs`, `state.rs`, `map.rs` | War on the map: `can_enter`, `find_path` (the game's own heap, so ties come out the same), `MoveArmy`, `move_days`, the daily march, supply (`supply_cost`, `home_connected`, `sea_route_home`, the cities' reach), battles (`_fight`: shells burnt, power, works, casualties, morale, routs, retreats, pursuit, the war's tallies, war score and war support from a battle), occupation, supply attrition, reinforcement, `collapse_nations`, and the capitulation check. |
| `peace.gd`, `war_goal.gd` (part), `diplomacy.gd` (part) | `peace.rs` | War score (ground, capital, battles, capitulation), what a province and a demand cost (with the war goal's discount and premium), `check` and `check_terms` (forced peace, cession limits, detached ground), `pick_takeable`, `propose` (an AI answer is passed in), the player's pending offer and `answer`, refusals and the cooldown, `make_peace` (ground handed over with its lost works, `revanche` claims and rivalries, ground still held handed back, armies withdrawn, prestige), indemnities, clauses (a disarmed border, a fleet limit), and the month's fading of scores and paying of indemnities. |
| `diplomacy.gd` (part), `war_goal.gd` (part) | `declare.rs`, `diplomacy.rs` | Declaring war: `casus_belli_options` (scenario and earned claims, a guaranteed or allied nation at war, a dated casus belli), `declare_block` and `declare_gate`, `declare_war` (a war on a neutral, relations, prestige and war support, the casus belli an unprovoked war gives its neighbours and the victim's guarantors, the AI's tally), `start_war` with the allies called, conflicts (`war_groups`), the join decisions (`offer_joins`, the player's pending decisions and `answer_join`, declining with its cost, `violate_border`) and the AI's call-ups (`step_join_calls`; the AI's yes or no is passed in), and `WarGoal.for_declaration`. |
| `pressure.gd` | `pressure.rs`, `config.rs` | Europe's tension (arms race, mobilization, wars, rivalry, blocs, events), the monthly step (events fire by date and condition, roles by what a nation is now, the player's waiting decisions and their answers, every kind of effect, public appeals, rivalries hardening). A war or crisis event stops the port with a message. |
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

A fifth golden file, `diplomacy.json` (made by `tools/dump_diplomacy_golden.gd`), is the treaties, opinions and rivalries
each scenario loads with (18 treaties and 231 opinions in July 1914, 9 and 231 in January 1900), and then a year and a half
of the real `Diplomacy.step_day` and `step_month` on top of the economy with great powers mobilizing, an opinion project,
gifts, a casus belli and a rivalry that lapse, and a nation of negative prestige. War support's monthly changes at war (the
war itself, taxes, men lost, blockade, ground lost, debt) and its step are compared too.

A sixth golden file, `war.json` (made by `tools/dump_war_golden.gd`), is three real campaigns of the game's own code: wars
between neighbours (Germany and France and Belgium; Austria-Hungary, Serbia, Russia and Germany; Italy, Austria-Hungary,
the Ottomans, Greece, Bulgaria and Serbia), armies sent over the borders and deep into the enemy's country with the game's
own `MoveArmy` command, trenches and fortifications on the ground they go for, and `Economy.step_day` with
`Military.step_day` for up to 150 days. Every day's figures for every nation are compared, and every fifth day all the armies
(every division's strength, morale and drill), the wars' books, the ground that changed hands, the occupation under way, and
when each battle last ended; every thirtieth day also what each side could supply in a third of the provinces. The port
matches all of it: 3 campaigns, 333 days of war, 70 provinces changing hands, routs, cut-off armies and attrition. (The
southern campaign ends on day 33 because the game has Bulgaria capitulate on day 34.)

A seventh golden file, `pressure.json` (made by `tools/dump_pressure_golden.gd`), is the real `Pressure` month after month for
years: five runs (July 1914 as France and as Serbia for four years; January 1900 as Germany, Serbia and Belgium for ten),
with 50 or more events fired in each long one, the player's questions answered in a fixed way, public stands taken, and what
tension, opinions, prestige, money, war support and the chronicle did. Direct cases cover what the runs do not reach: a strained
world (an arms race, mobilization and two wars moving tension), 162 role picks in three states of the world, 21 effects at the
extremes, the events that choose by tension, and every event with a condition in 18 different worlds (270 cases).

An eighth golden file, `peace.json` (made by `tools/dump_peace_golden.gd`), is three campaigns of forty days of the game's own war,
with wars declared with no casus belli and with goals of every kind, and then, for each war, what both sides' scores are, what
fifteen kinds of demand would be refused for or cost in both directions, what `pick_takeable` chooses at three budgets, and
peace made on terms chosen by the game's own rules: a forced peace of a nation whose people will not fight on, of one mostly
occupied, of one whose capital is held; ground, indemnities, a disarmed border, a fleet limit and a released ally; the player
answering an offer (and one spoiled by a third nation taking the ground first); a refusal and the proposer's cooldown; and 14
months afterward (indemnities paid, clauses lapsing). Every step's ground, armies, nations, claims, rivalries, clauses,
indemnities and finished wars are compared.

A ninth golden file, `declare.json` (made by `tools/dump_declare_golden.gd`), plays seven campaigns of actions from the July 1914
scenario in the game's own code: the Balkan war started with the allies called (the player as Britain, Italy or France, joining
or not), declarations with each kind of casus belli (a scenario claim, a guarantee, an alliance, a dated or fabricated one, none,
with and without the mobilization the law asks for, on a neutral, the same war twice), a border violation, and the days after,
while the nations that were called mobilize and enter. After every action the conflicts, wars and their goals, pending and called
decisions, opinions, grievance, prestige, war support, casus belli and treaties are compared, and the options and blocks between
fourteen nations. The test passes the AI's yes or no in from what the GDScript decided, since the AI is not ported. The
GDScript has a quirk the port keeps: an unprovoked war adds the victim's guarantors to the aggressor's *cached* neighbour list.

A second golden file, `state.json` (made by `tools/dump_state_golden.gd`), holds what the real game's state is right after it
loads each scenario: all 941 provinces (owner, holder, people, works, deposits and what each makes), the 22 nations
(development, people, province lists, summed output) and the raw-materials constant, for July 1914 and January 1900,
and the sums again with nine provinces held by an enemy. The Rust load reproduces all of it.

The tests cover about 2,400 cases (6,000 days of the calendar, 600 province outputs, 900 growth cases, 331 building
costs, 200 worker shares, 180 population steps and so on). Breaking any of these rules on purpose makes a test fail.

## What is not ported

Most of it, though the heart of it is in. Still missing from the economy: `level_gain` and `building_stats` (what the screens
show). The loader does not start a scenario's wars, and the game's own daily step (`game_state.gd`'s stages) is not wired up:
economy, focus, diplomacy and the army's day are ported separately; `Navy` and `Crisis` are not. In diplomacy: proposing and cancelling
treaties and the crises. In war: fronts, army groups,
offensives and attack lines, recruiting and training, armies at sea and landings, and everything after a capitulation or a lost
capital (the port stops with a message when one would happen). Then `navy.gd` (movement and battles, the blockade),
`peace.gd`, `pressure.gd` and `crisis.gd`, the war and front code, and `save_game.gd`. The AI (`scripts/ai`) is not part of
this port.

The simulation uses no random numbers (only the main menu and the city drawing do), so the port has no Godot generator to
match.

## What comes next

1. Start a scenario's wars from the loader (`starting_wars`, `start_crisis`), and port `Capitulation.capitulate` so a beaten
   nation's capitulation can be carried out.
2. Then `crisis.gd` (the crises that open between nations), the navy, and fronts and offensives.
3. Wire the stages into one daily and monthly step like `game_state.gd`'s, and compare whole days of the real game.
