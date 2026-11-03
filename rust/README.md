# Foreign Skies simulation in Rust (`fs_sim`)

A port of `scripts/sim` (GDScript, about 13,700 lines) to Rust. The game stays in Godot; this crate is the simulation
alone, so it can run without an engine (balance runs, servers, tests) and later be called from the game.

**This is the start of the port, not the whole of it.** It goes system by system, and each piece is checked against the
original before the next one begins.

## How a piece is checked

`tools/dump_sim_golden.gd` runs the real GDScript code over a grid of inputs and writes what it returns to
`fs_sim/tests/golden/slice.json`, with every float as the bits of its 64-bit value, so nothing is lost in the text.
`fs_sim/tests/golden.rs` makes the Rust code reproduce every number. The comparison is exact, except for results that
go through `pow()` in the first golden file, which may differ by a few units in the last place between maths libraries (that test allows 4 ulps). Every other golden file, the whole games included, is compared with no tolerance at all: the numbers are the game's, bit for bit.

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
| `capitulation.gd` (part), `move_capital.gd` | `capitulation.rs` | The daily step (a nation at peace is no longer capitulated; the capital goes home when retaken or moves when lost, the AI's to its dearest city, the player's by `choose_capital`), `capital_candidates`, `can_relocate`, `capitulate` (armies lay down their arms, their men go back to the reserve) and `dictate` (each AI enemy proposes its peace; the AI's terms and its answer are passed in). `gd::sort_custom` is Godot's own unstable sort, so ties come out as in the game. |
| `navy.gd`, `naval_combat.gd`, `blockade.gd`, `fleet.gd`, `ship.gd`, `move_fleet.gd`, `embark_army.gd`, `disembark_army.gd`, `send_overseas.gd`, `raise_ships.gd`, `set_fleet_mission.gd` | `navy.rs`, `map.rs`, `config.rs` | The navy: fleets and ships, `can_dock`, sailing through the sea zones (`zone_days`, `find_path`), the ships finished each day, sea battles (contact by a hash roll, firepower with the destroyer screen, hits by exposure, sinkings, routs and retreats, the battle records), repair and attrition, armies embarked, carried and landed (an assault from the sea, convoys that lose transports drown their men), shore support for the army's fights, who holds each sea zone, and the blockade of a nation's trade (`String.hash` is ported: it is djb2). `Military.neighbors_for` and `sea_route_home` now see the water enemies hold. |
| `game_state.gd` (the day and month stages), `clock.gd` | `game.rs` | `advance_day`: the calendar moves on, then the day's stages in the game's order (economy, focus, navy; the armies; diplomacy; the economy worked out again if anything changed it) and, at a month's end, the month's steps (economy, diplomacy, pressure). |
| `military.gd` (recruiting, drill, generals), `raise_units.gd`, `set_training.gd`, `demobilize_units.gd`, `split_army.gd`, `merge_armies.gd`, `transfer_units.gd`, `assign_general.gd` | `army_mgmt.rs`, `military.rs`, `state.rs` | Units raised and trained (`_train`: they join an idle army in their province or form new levies), armies on exercise (`_drill`), men in service counting recruits and the men on exercise, units sent home, armies split, merged and handed units, the generals' pool and `set_general`, and `release_orphan_generals` (the AI's nations put their best free general in command of their biggest army without one). A nation that collapses or capitulates loses its recruits. |
| `diplomacy.gd` (player actions), `buy_points.gd`, `improve_relations.gd`, `propose_treaty.gd`, `gift.gd`, `cancel_treaty.gd`, `rename_alliance.gd`, `declare_war.gd` | `actions.rs` | What the player does in diplomacy, with the diplomacy points it costs: buying points (the price climbs), efforts to improve relations, treaty proposals (the other nation's opinion against the bar for the kind, prestige pull, rivals, opposed blocs; points refunded in part on a refusal), gifts and their memory, cancelling treaties and the price of it, naming and renaming alliances, and declaring war for points. |
| `economy.gd` (`build_problem`, `mass_candidates`), `construct_building.gd`, `mass_construct_building.gd`, `prioritize_construction.gd`, `set_economy_policy.gd`, `buy_munitions.gd` | `economy_cmds.rs` | What the player does with the economy: works started (and refused for every reason) with the money paid up front, mass orders stopped by a count, an amount of IC or the money, the queue reordered, the policy sliders (tax, mobilization, arms, investment, standing army) and munitions bought abroad. |
| `front.gd`, `front_solver.gd`, `Military.step_fronts`, `designate_front.gd`, `delete_front.gd`, `assign_to_front.gd`, `set_front_anchors.gd`, `set_front_line.gd`, `set_front_policy.gd`, `move_army.gd` | `front.rs`, `war.rs` | Fronts: a border with a nation (read again as the war changes who holds what), a hand-drawn chain or a garrison; armies assigned to them; the AI's armies each sent to hold a province (`_deal_slots`), the player's divisions spread along the line as detachments of their army (`FrontSolver`: sectors, shares by weight, reach by cohesion, pins by hand orders, merging back, promotion when the army is gone), the fallback line that digs in deeper. Offensives are not ported, so none ever controls an army. |
| `offensive.gd`, `offensives.gd`, `plan_offensive.gd`, `set_offensive.gd`, `army.gd` (planning) | `offensive.rs` | Plans of attack: planning built up by stacks standing on their front and spent marching or fighting (and added to their power when they attack), a broad push, a spearhead gathering next to the next enemy province, an invasion gathering in a port and sailing (`SendOverseas`), attacks only at the odds and morale the aggressiveness asks, phases, and the commands (launch, aggressiveness, targets, phases, cancel). A launched spearhead or invasion has the army's stacks in hand, so the front does not spread them. |
| `army_group.gd`, `attack_line.gd`, `attack_lines.gd`, `Military` (groups, `marshal_mult`), `create_army_group.gd`, `disband_army_group.gd`, `assign_to_group.gd`, `set_marshal.gd`, `create_attack_line.gd`, `delete_attack_line.gd`, `set_attack_line.gd` | `group.rs` | Army groups under a marshal from the nation's generals (his skill above 1, by `marshal_share`, multiplies the power of the group's armies and their detachments), pruning, and attack lines (made, switched on and off, dropped with their group, stopped when the war ends). The campaign an active line runs is the AI's (`AIOffense`): a day on which one would run stops the port with a message. |
| `scripts/ai/ai_peace.gd`, `ai_coalition.gd`, `ai.gd` (noise, temperament), `conference.gd`, `propose_conference.gd`, `answer_conference.gd`, `peace.gd` (`surrender_terms`, `_separate_peace`), `war_goal.gd` (`progress`) | `ai_peace.rs`, `conference.rs`, `peace.rs`, `config.rs` | How the AI makes and takes peace: the urge to be out of a war, whether it takes a deal (`accepts`), what it proposes and the price it names (`price_terms`, `indemnity_for`), the monthly overtures, the coalition of a side (partners who make peace together, strained nations, holding to allies), and peace conferences: the package, its acceptance, the chair, counter-offers and the player's answer; a nation that makes peace apart from its side loses the trust of those still fighting. The AI's war plans (`ai_plans`) are not ported, so a nation's war aims are its stated war goal. Capitulation's dictated peace is now worked out here instead of supplied. |
| `scripts/sim/crisis.gd`, `crisis_action.gd`, `press_demand.gd`, `war_goal.gd` (`invalid`, `cost_mult`), `scripts/ai/ai_diplomacy.gd` (join and war weighing: `joins`, `war_check`, `war_option`), `pressure.gd` (`crisis` and `war` effects), `war_support.gd` (`_force_peace`) | `crisis.rs`, `ai_diplomacy.rs`, `pressure.rs`, `diplomacy.rs` | Crises between nations: the monthly weighing of quarrels, the demands (revanche, claim, border, indemnity, disarm, naval), the AI answering after its think time (yield, refuse, mobilize, appeal) and declaring war on a refusal, mediation, backing a side, the questions put to the player, `CrisisAction` and `PressDemand`. The AI now decides calls to arms itself (`ai_would_join`), so a test no longer supplies the answers. A nation whose war support collapses is forced into a white peace. The scenario's `ai_traits` are read. |
| `scripts/ai/ai.gd` (`think`, `due_nations`, `is_ai`), `ai_budget.gd`, `ai_focus.gd`, `game_state.gd` (`in_day_step`), `economy.gd` (`request`) | `ai_turn.rs`, `game.rs`, `state.rs` | The first parts of the AI's own turn: every third day each AI nation thinks (the stagger by tag order), and of what it does the monthly budget (taxes against deficit and debt, state investment, the arms share and munitions bought abroad at war, one building where it earns most, diplomacy points bought in a crisis) and the national focus it takes up. `AiTurn` switches the parts on; by default none runs. The ship-building step of the budget (`AINavy.build`) and the rest of the turn are not ported. Inside the day step a change to the economy now only marks it dirty and is worked out once at the day's end, as the game does (`Economy.request`), which the AI sees. |
| `scripts/ai/ai_forces.gd`, `ai_ambition.gd`, `ai.gd` (`hops_from`, `enemy_power`, `threat`, `value`), `diplomacy.gd` (`mobilization_target`) | `ai_forces.rs`, `ai_ambition.rs`, `diplomacy.rs` | The AI's recruiting: a nation at war with a front to hold raises units behind its most threatened line (the safest province near it), a couple a turn, in the mix of unit types the file wants and within its limits (recruits, treasury floor, deficit cushion, share of income); in peace it rebuilds at its capital and, some time after its last war, sends home the men above its peacetime army. Its ambition: once a quarter a nation at peace scores the land neighbours it could beat, picks the best above the threshold, makes a plan against it (objectives on the border and the capital) and mobilizes for it; it drops the plan when the target stops fitting, after a time or when it goes to war. `AiTurn` has switches for both. |\n| `pressure.gd` | `pressure.rs`, `config.rs` | Europe's tension (arms race, mobilization, wars, rivalry, blocs, events), the monthly step (events fire by date and condition, roles by what a nation is now, the player's waiting decisions and their answers, every kind of effect, public appeals, rivalries hardening). A war or crisis event stops the port with a message. |
| `scripts/ai/ai_defense.gd`, `peace.gd` (fronts marked dirty at a peace) | `ai_defense.rs`, `peace.rs` | The AI at war on the defensive: one border front per enemy it touches (and fronts against nations it no longer fights dropped), the provinces its armies mass on chosen again every few days, the stacks that stand together merged, one army held back as a reserve in the most threatened province, idle armies put on the front with the least cover (waiting a few days at a war's start if they are far from every line), one army moved a turn from the best-covered front to the worst, and home ground the enemy holds retaken when the force that can reach it in step beats the defenders by the odds its temperament wants. `AiTurn.defence` switches it on. An army on a campaign of the AI's offence is left alone there; the offence is not ported, so none is. |
| `scripts/ai/ai_diplomacy.gd` (`step`, `best_war`, `consider_war`, `consider_press`, `choose_goal`, treaties and friends) | `ai_diplo_step.rs` | The AI's diplomacy step: a mobilized or provoked nation weighs the wars it could declare on its neighbours (the weighing of `war_check`) and declares the best; with none, one that has a plan against a neighbour and no casus belli makes a demand of it instead (the goal chosen from its plan's objectives, else the richest border province, else an indemnity); once a month it proposes the treaty worth most to it (alliance, guarantee, pact, passage, weighed against its need of friends) and works on its standing with a neighbour it needs. While the treaties are weighed each nation's power is added up once, as the game does. `AiTurn.diplomacy` switches it on. |
| `scripts/ai/ai_offense.gd`, `attack_lines.gd`, `ai.gd` (`armies_by_province`, `threat` caches) | `ai_offense.rs`, `group.rs`, `ai_forces.rs` | The AI on the attack: a nation runs campaigns (several, against different enemies): it picks the enemy province worth most among those it can take (next to ground it supplies, within the share of its army its aggression allows, with a penalty for ground its allies aim at), gathers the armies in a staging province, advances when their power beats the defenders by the odds its temperament wants, carries on to the next province while the odds hold, and falls back when a battle turns bad. An attack line (an order given to an army group) runs the same campaigns for its group instead of stopping the port. The AI keeps its index of armies by province and its threat figures for the day as the game does: an attack line runs before the armies move, so what the AI weighs later that day is where they stood. `AiTurn.offence` switches it on. |
| `scripts/ai/ai_navy.gd`, `ai_landing.gd`, `ai_budget.gd` (`AINavy.build`), `split_fleet.gd`, `navy.gd` (`nearest_port`, `days_to_all`, `path_days`), `peace.gd` (`_sea_link`) | `ai_navy.rs`, `ai_turn.rs`, `peace.rs` | The AI at sea: a nation at war sorts its fleets by role in port (transports and submarines apart, cruisers and destroyers detached as patrols), gives every warfleet a sea zone (the cordon that would seal an enemy's ports, the waters by its own ports where enemy ships lie, the zone a landing needs an escort in) and sends it there only if its power with what is already sent beats the nation's odds times the enemy's in and around the zone; worn fleets go home to repair; once a month it lays down a squadron if its fleet is smaller than the enemies'. A landing is gathered in a port with its transports, waits until the ships hold the zone and the route, then is sent over the water and disembarks if turned back. Water held by the taker's ships (or a friend's) now joins a province to its land in a peace. `AiTurn.navy` switches it on. |
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
The Rust reproduces all of it bit for bit.

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

A ninth golden file, `declare.json` (made by `tools/dump_declare_golden.gd`), plays twelve campaigns of actions from the July 1914
scenario (one of them the scenario as it ships, whose own war, Austria-Hungary on Serbia, begins as it loads: `start_scenario_wars`) in the game's own code: the Balkan war started with the allies called (the player as Britain, Italy or France, joining
or not), declarations with each kind of casus belli (a scenario claim, a guarantee, an alliance, a dated or fabricated one, none,
with and without the mobilization the law asks for, on a neutral, the same war twice), a border violation, and the days after,
while the nations that were called mobilize and enter. After every action the conflicts, wars and their goals, pending and called
decisions, opinions, grievance, prestige, war support, casus belli and treaties are compared, and the options and blocks between
fourteen nations. The test passes the AI's yes or no in from what the GDScript decided, since the AI is not ported. The
GDScript has a quirk the port keeps: an unprovoked war adds the victim's guarantors to the aggressor's *cached* neighbour list.

A tenth golden file, `capitulation.json` (made by `tools/dump_capitulation_golden.gd`, which runs a copy of `Capitulation` that logs the
peace it dictates), is ten wars in which the enemy takes ground in steps: the capital moving (the AI's and the player's choice,
one overtaken), going home, a nation too weak to move capitulating, one enemy or three dictating, the player as the enemy or
the beaten, and a war ended by hand. After every step the ground, armies, nations, claims, indemnities, finished wars, capitulation
progress, the capital choice and the capitulated sides are compared.

An eleventh golden file, `navy.json` (made by `tools/dump_navy_golden.gd`), is nineteen campaigns run in the game's day order (economy, navy,
army): fleets sent into one zone to fight (a hit-and-run in the North Sea, the Adriatic with three powers, a slugfest with weakened
squadrons that sinks ships), a cordon that blockades Germany, an army marched to a port and sent overseas to land in an assault, an
army put aboard and landed by hand, a convoy meeting the enemy, ships bought and launched, and the orders that must be refused. After
each step every fleet and ship, who holds each zone and its power, the battles, the blockade, the armies, the wars' losses and the
counters are compared.

A twelfth golden file, `game.json` (made by `tools/dump_game_golden.gd`), is the real game running by itself, the clock driven day by day so
that its own stages run in its own order: July 1914 as it ships with its own war and the Great Powers called in (400 days, through the AI's peaces), July
1914 with two more wars begun and armies ordered forward on four fronts (300 days), and January 1900 (400 days). The nations'
money, people, standing, mobilization and blockade, the ground and who holds it, every army, the fleets, the wars, opinions, grievance and
tension are compared every ten days. The AI's turn is off, and the crises are off (`pressure_ai`); the AI's peace overtures run at a month's end whether or not the AI is
switched on (`Peace._ai_overtures`), and are ported.

A thirteenth golden file, `army.json` (made by `tools/dump_army_golden.gd`), is five campaigns of the army's side: units raised and trained (failing
for want of money, men or ground), armies on exercise that stand and that march, units sent home, armies split, merged and handed
units, generals assigned and freed and the AI's best general put in command of its biggest army, and a nation that loses every
province. Every nation's recruits and men, every army's units, generals and marching, and the counters are compared.

A fourteenth golden file, `actions.json` (made by `tools/dump_actions_golden.gd`), runs the real commands (`BuyPoints`, `ImproveRelations`, `ProposeTreaty`, `Gift`,
`CancelTreaty`, `RenameAlliance`) in six campaigns, with the real game running by itself for days and months in between: the price of points
climbing and easing, the limits on efforts, treaties accepted and refused (and refused for points, rivals, blocs and the bar), gifts
with diminishing returns, cancelling every kind of treaty, and alliances named and renamed. Points, prestige, money, treaties and their
names, efforts, opinions and baselines, and the memory of gifts are compared after each step.

A fifteenth golden file, `economy_cmds.json` (made by `tools/dump_economy_cmds_golden.gd`), runs those commands through `GameState.issue` (which works the economy
out again after each) in four campaigns, with the game running by itself for days between: works refused for each reason and finished,
the queue reordered, mass orders, every slider and its limits, and munitions bought under a blockade.

A sixteenth golden file, `front.json` (made by `tools/dump_front_golden.gd`), is thirteen campaigns of fronts run in the game's day order: borders, chains and garrisons for the AI and for the
player, single stacks spread into detachments (rigid, balanced and flexible), hand orders pinning a stack, a line that follows the war, a fallback
line, an army that dies leaving a detachment to take its place, refused designations and redrawn lines. Every front's line, order,
weights, slots and deployment, and every army's detachment, pin, front and march, are compared.

A seventeenth golden file, `offensive.json` (made by `tools/dump_offensive_golden.gd`), is six campaigns of plans of attack on a front, in the game's day order: broad pushes
(careful, balanced and aggressive, phases added, launched and stopped, cancelled), a spearhead at a capital, an invasion from a port, and plans
the game refuses. Plans, planning, fronts, detachments, pins, fleets and marches are compared.

An eighteenth golden file, `group.json` (made by `tools/dump_group_golden.gd`), runs the group and attack-line commands in three campaigns: groups made and refused, marshals set, relieved and
refused (and the power of the armies under them), armies moved between groups, a group whose army dies, and attack lines made, refused, switched on and off and
dropped when the war ends.

A nineteenth golden file, `conference.json` (made by `tools/dump_conference_golden.gd`), plays the real `ProposeConference` and `AnswerConference` in six campaigns on the July 1914 war: demands small and
large, refused with a cooldown, taken whole (a white peace for five nations at once), and a player enemy; the days after, in which the AI makes its own overtures. The whole-game
golden file `game.json` now runs on past the AI's peaces (July 1914: five wars end at once on 4 April 1915, the last on 4 May; the
shipped scenario for 400 days) and compares, every ten days, every nation's urge for peace and what it would propose, and whether it would take
more than three thousand deals of each kind. Value of a province is kept for the day, as the game does (a change in the people later in that
day is not seen until the next); the arms base of tension drifts after a great war.

A twentieth golden file, `crisis.json` (made by `tools/dump_crisis_golden.gd`), is eight campaigns with the world's quarrels switched on (the AI's turn off): the Serbian, French, Italian and Belgian players in July 1914 and the German, Belgian, French and Spanish in January 1900, 600 to 900 days each. The player answers every demand made of them, mediates, backs a side and presses demands of their own; four runs loosen the crisis gate so that 25 to 39 crises finish in each. Every ten days the crises, how they ended, cooldowns, casus belli, chronicle, the questions put to the player (labels, texts, tips, effects), wars, owners, standing, opinions and grievances are compared. Mutating the rules (thresholds, weights, sides, backers, effects) makes it fail; only equivalent changes survive (a `<=` against a `<` on floats, the AI's noise, which is zero without a seed).

A twenty-first golden file, `ai_turn.json` (made by `tools/dump_ai_turn_golden.gd`), drives the real game's day stage by stage, with the ported parts of the AI's turn (the budget without its navy, and the focus) where the game runs the AI, in eight campaigns: July 1914 and January 1900, with and without wars (a front drawn for each side), with every nation's treasury multiplied by a different factor so that debt, surplus and wealth are all met, one for 1,500 days. Every five days the nations' tax, investment, arms share, munitions, points, money, works under way, focus and the month of their last budget are compared. Mutation testing killed 28 of 35 changes; those that live are ties and small nudges to the AI's scores that rarely decide a choice, easing the taxes of a rich nation, the crisis term of the arms share and the points floor, which these worlds hardly reach.

`ai_turn.json` now has 24 campaigns: the budget and focus of before, and the recruiting and ambition added, with armies sent to the enemy's border so that there is a threat to weigh, with the AI's ambition and demobilizing loosened (the same numbers are set on both sides) and set near their real threshold, and with the world's tension on. Compared every five or ten days besides what the budget showed: the armies, the units in training, manpower, men under arms, the wars, who has set its sights on whom and the plans made. Mutation testing of the two new modules: all but the guarantor penalty of the score, a float tie-break, the strength of the cut for distance in the threat, the capital's bonus to a province's worth and the block a crisis puts on demobilizing were caught.

`ai_turn.json` now has 30 campaigns, five of them with the defence: wars begun by the test and by the fronts the AI draws itself, armies ordered to the enemy's border, one to four wars at once, 300 to 700 days. Besides the rest, it compares the fronts (their line, anchors and armies), each army's path, front, pin and the stack it is a detachment of, the reserves and the days the anchors were chosen. Mutation testing of `ai_defense.rs` caught 34 of 43 changes; the rest are checks the game makes twice (a front is not drawn where there is no border), a `>=` against a `>` on a day count, the larger share of need for the main effort of a plan, a tie-break of one millionth, and the corners of retaking (whether the holder is at war, supply, an army already in the province) that these wars hardly reach.

`ai_turn.json.gz` (gzipped: the plain file is over GitHub's size limit; `tools/dump_ai_turn_golden.gd` writes it and the comment at its top says how to pack it) now has 42 campaigns. New with the diplomacy: wars the AI declares itself (justified and not), demands it presses, treaties of every kind it proposes, the thresholds loosened, 1900 without the tension gate. New with the offence: four campaign-heavy wars, army groups with attack lines switched on, and runs with every part of the AI's turn on at once. Compared every five or ten days besides the rest: treaties, opinions, grievances, the crises and casus belli, who holds each province, the campaigns each nation runs and the attack lines. The test reads the file once for all of them.

`ai_game.json.gz` (made by `tools/dump_ai_game_golden.gd`) is the whole game as it ships: a scenario loaded, `ai_enabled` on and the scenario's own `pressure_ai`, the clock driven by the game's own day pipeline, in which the AI's turn runs where the game puts it. The port runs the same days with `AiTurn::all()`. Fifteen games: July 1914 for 900 and for 3,000 days (to 1922) with Serbia, Britain, Germany, Russia, Italy and Austria left to the player in turn (so each time a different nation is left to the AI), and January 1900 for 1,800 and 4,500 days (to 1912) with Germany, the United States, France, Russia and Britain; and four games on the `challenging` and `sandbox` difficulties (`Data::load_with_difficulty`, from `Difficulty.apply`: the preset scales the AI's and the crisis generator's numbers from the files), which differ from the shipped game in July 1914. Compared every 10 to 30 days: the nations, who holds each province, the armies and fleets, the fronts, the wars, treaties, opinions, grievances and crises, the casus belli, and everything the AI keeps (campaigns, landings, plans, stations, reserves, anchors, ambitions).

`player.json.gz` (made by `tools/dump_player_golden.gd`) is six whole games in which the player plays and the AI plays the rest: a rotation of twenty kinds of command (policies, works, recruiting, marches, a declaration of war, treaties, gifts, demands, peace offers, ships and fleets, a focus, crisis answers, demobilizing, cancelling a treaty) made through `GameState.issue` and logged with their arguments and results, and every question put to the player answered (events, calls to arms, peace offers). Four July 1914 games (Britain, Serbia, Germany, Italy; 700 days) and two January 1900 games (France, Russia; 1,200 days); about 2,300 commands, all giving the same result in the port, and the world compared every 10 or 20 days.

A second golden file, `state.json` (made by `tools/dump_state_golden.gd`), holds what the real game's state is right after it
loads each scenario: all 941 provinces (owner, holder, people, works, deposits and what each makes), the 22 nations
(development, people, province lists, summed output) and the raw-materials constant, for July 1914 and January 1900,
and the sums again with nine provinces held by an enemy. The Rust load reproduces all of it.

The tests cover about 2,400 cases (6,000 days of the calendar, 600 province outputs, 900 growth cases, 331 building
costs, 200 worker shares, 180 population steps and so on). Breaking any of these rules on purpose makes a test fail.

## What is not ported

The heart of it is in: the economy, population, focus, diplomacy, war on the map and at sea, peace, pressure events, declaring war and
capitulation and the crises, run together by `advance_day`. Still missing: `level_gain` and `building_stats` (what the screens show), and
`save_game.gd`, `history`, `standings` and the briefing. The AI (`scripts/ai`) is ported whole: its peace and coalition (`ai_peace.rs`), its weighing of a call to arms and of a war (`ai_diplomacy.rs`) and its turn: the budget with the ships, the focus, the recruiting, the ambition, the defence, the diplomacy, the offence, the navy and the landings (`ai_turn.rs`, `ai_forces.rs`, `ai_ambition.rs`, `ai_defense.rs`, `ai_diplo_step.rs`, `ai_offense.rs`, `ai_navy.rs`). `AiTurn::all()` plays it all.

The simulation uses no random numbers (only the main menu and the city drawing do), so the port has no Godot generator to
match.

## What comes next

1. The records the screens read (history, standings, briefing, intel, save games).
2. Save and load (`save_game.gd`) and the commands the player gives that the rules tests did not need. The AI's whole turn is ported and plays in the whole-game test; its numbers are what the game's difficulty setting (`Difficulty`) retunes, which is not ported.
