# Foreign Skies: plan

Written 2026-10-26, after a design review of v0.5.7 and a review of its economy (code, data, AI-only runs over many
seeds, and runs of one nation's economy under fixed policies). The previous plan (war goals, briefing, validator,
dynamic crises, history book, conferences, staff tools, coalitions, difficulty) is built; it is summed up in the
CHANGELOG.

Each step ends with a headless test printing `FAILURES: 0`, a full-suite run, the docs updated, and its "done when"
checked with `tools/campaign.py` (AI-only runs) and `tools/economy.py` (one nation's economy under fixed policies)
against the baseline in `docs/baseline.md`.

## Principles

1. No technology tree, tactical battle layer, multiplayer or world map. The Europe frame is a feature.
2. History pushes, it does not script. Crises create pressure and choices, never one fixed outcome.
3. Show and deepen the state that exists before adding new meters.
4. Content lives in `data/`; every new rule gets a headless test.
5. The player must be able to understand why the world moves.
6. No retraining of the AI until the rules stop changing (step 7): trained numbers go stale with every rule fix.

## What the reviews found

| | Finding | Step |
|---|---|---|
| F1 | A capital taken lets the winner dictate any terms (`Peace.check`, `AIPeace._accepts`): great-power wars end in weeks with Berlin, Vienna, Prague, Stockholm and Milan annexed, often far from the winner's land. | 1 |
| F2 | After about 1920 nothing happens: no wars, no crises, tension flat near 40, every focus done. | 4 |
| F3 | Great powers start conquests in 1902-04 against neutrals (Germany on the Netherlands, Russia on Sweden); the war gate (tension 30) is reached by drift alone, and the 1900 nations have no temperaments. | 2 |
| F4 | Armies only grow: no command disbands a unit, so war-sized armies stay for ever. | 3b |
| F5 | Money stops mattering: treasuries pile up; buildings cost IC, and a tax below 10% gives nothing. | 3b |
| F6 | Peacetime holds few decisions for most nations: a passive Belgium is asked 2 things in 16 years; ten nations have at most one event. | 5 |
| F7 | Pressing a demand does what justifying a war does, cheaper and sooner. | 5 |
| F8 | The peace tools are lopsided (the GP-only "concert" event is far stronger than an appeal for calm), and "brink" is a decision with one option. | 5 |
| F9 | Focus trees end early and nothing repeats (see E7); the briefing then asks for a focus for ever. | 4 |
| F10 | Crises open on one-on-one odds but are answered on the odds of whole sides: hopeless demanders collect casus belli. France presses Alsace in May 1900. | 2 |
| F11 | The trainer rewards 30 times the share of soldiers: likely why the AI hoards men and gives up land quickly. | 7 |
| F12 | Small things: "0.0 a month" indemnities, the war signal sent before the goal is set, docs that say units cost IC, screenshots imported by Godot, cavalry with no role. | 0, 1, 6 |
| C1-C4 | From the code review of 0.5.4: conference counter-offers never expire and are not asked again; a failed joint peace skips the solo attempt; a package is judged entry by entry; mediation fails the same way every time. | 1, 6 |
| E1 | Building has no trade-off: IC cannot be kept or spent on anything but buildings and ships, buildings cost no money, so "queue everything" is the answer (Germany, 1900-14: 359 levels for +24% GDP over doing nothing). | 3a |
| E2 | Industry has no part in the land war: units are money and men, combat never reads industry, and `combat.shell_penalty` is in the data but read by nothing. The munitions war of 1914-18 is missing. | 3a |
| E3 | Taxes: 20% gives Germany £2.1bn by 1914 against £88M at 10% for 6% of GDP (the strain is squared), the AI never does it, and a rate under 10% changes nothing but revenue. | 3b |
| E4 | Money has no peacetime use: civil spending follows GDP and takes three quarters of any new tax (a German factory lowers the budget), and the rest piles up. | 3b |
| E5 | Mobilizing in peace is ruinous and unexplained: Germany at 40% runs £14.6M a month short and owes £1.3bn by 1914, because civil spending is worked out on output before mobilization cuts it. | 3b |
| E6 | Small nations have no economy: the flat 20 IC a day is 95% of Serbia's; a Serbian factory pays back its IC in 357 years. | 3c |
| E7 | Focus trees run out for every nation: small ones about 1903, great powers about 1905. | 4 |
| E8 | Raw materials and food matter only under blockade (shortfalls are bought automatically), and the briefing says to "build mines", which do not exist. | 3c |
| E9 | The Economy tab's right column (all spending, IC, materials) is cut off at 1600x900; civil spending, the tax rate and mobilization are described in ways that hide what they do; mixed time units. | 3c |

## Order

| Step | Work | Size | Status |
|---|---|---|---|
| 0 | Housekeeping and the measuring tools | S | done |
| 1 | War resolution: forced peace, connected annexation, conferences | L | done (v0.6.0); France-Germany length carried to step 7 |
| 2 | The road to 1914: war gate, temperaments, neutrals, crisis odds | M | done (v0.7.0) |
| 3a | Munitions: industry arms the guns | L | done (v0.8.0) |
| 3b | Money, taxes, mobilization and demobilization | M | done (v0.8.0); army size after a war carried to step 7 |
| 3c | Small economies, materials and food, the economy on screen | M | done (v0.8.0) |
| 4 | After the war: revanche, post-war crises and events, repeatable foci | L | done (v0.9.0); post-war wars and tension carried to step 7 |
| 5 | Peacetime decisions: demands replace justification, one public stand, small nations, ambitions | M | done (v0.10.0) |
| 6 | Leftovers: mediation, cavalry | S | done (v0.10.1) |
| 7 | Retrain the AI under the new rules | L | |
| 8 | Docs, versions and playtests | S | |

## Steps in detail

### 0. Housekeeping and the measuring tools
- Merge the crisis-backing fix (a nation backs one side once, never both) and its cleanup.
- `docs/.gdignore`, so Godot does not import the screenshots; the economy note says units are paid in money, not IC.
- `tools/campaign_report.gd` measures one AI-only run (the bystander is a passive player that answers as the AI would);
  `tools/campaign.py` runs it over many seeds and prints a table: the first war between great powers, how long
  great-power wars last (and France against Germany), capitals ceded, provinces ceded with no land link to the new
  owner, the worst share a great power lost in a day, wars, crises and the spread of tension from 1922, great-power
  treasuries in months of revenue (the whole run, and from 1922), armies three years after a war against their peak in
  it, the longest idle focus, and decisions put to the bystander.
- `tools/economy_policies.gd` runs one nation's economy with the AI off under a fixed policy (doing nothing, building
  each type or all, foci, a tax rate, a mobilization); `tools/economy.py` runs a grid of nations and policies.
- `docs/baseline.md`: both tables before any rule changes (10 seeds of each scenario to 1935, a passive Belgium, and
  Germany, Italy, Belgium and Serbia under eleven policies, 1900-1914).

### 1. War resolution (F1, F12, C1-C3)
- **Forced peace.** A peace is forced when the taker holds the capital *and* the giver's war support is at or below its
  floor, or when the taker occupies `forced_occupied_share` of the giver (new, about 0.6). A capital alone gives score
  and urge, as now (`Peace.check`).
- **Limits.** Forced terms take only what the taker holds, its war goal and an indemnity, at most `forced_budget_mult`
  times its war score (new) (`AIPeace._accepts`, `Peace.check`).
- **Connected annexation.** `Peace.contiguous(gs, taker, ids)`: each ceded province touches the taker's land or another
  ceded province, or lies on a coast in a sea zone the taker's fleet controls. A capital is ceded only with the whole
  nation. In `demand_cost`, so the peace screen, AI terms, conferences and crises all obey it; the peace screen greys out
  what fails and says why.
- **No empty terms.** `AIPeace.indemnity_for` drops an indemnity under `indemnity_min_monthly` (new, about £0.1M).
- **Signal order.** The goal is on the war before `war_changed` is sent.
- **Conferences.** A counter-offer lapses after `counter_days` (new, about 30) and is put to the enemy again when
  accepted (C1); an invalid joint peace falls through to the nation's own proposal (C2); the enemy weighs the package
  whole, its total cost against its urge and the indemnities against what it can carry together (C3).
- Tests: extend `peace_test`, `conference_test`, `ai_peace_test`.
- **Done when** (10 seeds of each scenario): no capital ceded without the whole nation; no detached cession without
  fleet control; France against Germany lasts 12 months or more (median, July 1914); no great power loses more than a
  quarter of its provinces in one treaty.
- **Result:** no capital ceded in any of 20 runs (median 5 before); provinces with no land link to the new owner from a
  median of 6.5 and 13 to 0 and 0 (the few left go by sea); the worst loss in one treaty 13% (26% before). France and
  Germany still settle in about 4 months (median, July 1914): France holds 14% of Germany within weeks and Germany
  accepts a limited loss (Alsace-Lorraine and the Saar, France's goal). That is the military balance and the trained
  peace thresholds, not the peace rules: carried to step 7, whose fitness rewards ending wars on better terms.

### 2. The road to 1914 (F3, F10)
- **War gate by scenario.** `ai_war_gate` moves to `scenario.json` (about 45 for 1900, 30 for 1914), optionally falling
  with the years; `Pressure.ai_may_declare` reads it.
- **Temperaments.** `ai_traits` for the 1900 great powers and Balkan states, written by `tools/make_1900.py`.
- **Neutrals.** `AIAmbition.best_target` and `AIDiplomacy.war_desire` weigh heavily against a target guaranteed by a
  third power, or outside every bloc and unmobilized; a war with no casus belli on such a nation costs more relations
  and tension.
- **Rivalries.** Starting grievances that fade slowly (France and Germany, Austria-Hungary and Serbia, Russia and
  Austria-Hungary, Italy and Austria-Hungary), so rising tension feeds them and not the weakest neighbour.
- **Crisis odds.** `Crisis.may_quarrel` checks the odds of the two sides (`odds_a` on a draft crisis); a crisis over a
  scenario claim waits for tension `claim_min_tension` (new, about 40).
- Tests: extend `crisis_test` and `ai_ambition_test`.
- **Done when** (1900, 10 seeds): the first war between great powers is in 1908 or later in at least 8 seeds; no war
  without a casus belli on a neutral before 1912; no crisis opens at side odds under 0.7; the general war still comes
  by 1916 in at least 6 seeds.
- **Result** (1900, 10 seeds to 1917): the first war between great powers in October 1912 in all ten (1902-04 in five
  before); no war with no reason on a neutral; no crisis under side odds of 0.70; a general war (four great powers) in
  June 1914 in all ten. Two things beyond the list made it: the 1900 scenario had lost its starting relations (Franco-German
  enmity, the Great Game, the Balkan rivalries) in an earlier data change, and `tools/make_1900.py` restores them; and old
  rivals sign no pact or alliance (`Diplomacy.treaty_acceptable`), since Russia's pacts with Austria-Hungary and Germany
  had kept it out of 1914. France and Germany now fight about 10 months (median), not 4.

### 3. Munitions and the economy (F4, F5, E1-E6, E8, E9)
The economy gets the choice that 1900-1914 was about: grow now, or arm for the war. Industry makes munitions as well
as buildings, the guns burn them in battle, money buys what industry cannot make, and armies can go home. It lands in
three parts, in order; each part ends green and measured.

#### 3a. Munitions: industry arms the guns (E1, E2)
- **State.** `Nation.munitions`, a stockpile in the units of IC (a day's IC of work makes that many units), and
  `Nation.arms_share`, 0 to 1: the share of each day's IC that goes to munitions before hulls and buildings. A policy
  like the tax rate (`SetEconomyPolicy` "arms_share"). Both saved; `SaveGame.VERSION` 3 with a `_migrate` step (an
  older save starts each nation at the AI's default share and an empty stockpile).
- **Making.** `Economy.step_day` puts `arms_share` of the IC into the stockpile first. The materials ratio and the
  blockade already cut IC, so a blockade now cuts shells.
- **Keeping.** A stockpile ages (`munitions.decay_per_year`, about 5%) and costs money to store
  (`munitions.storage_cost` a year a unit): hoarding has a price, and peace has a reason to stop.
- **Burning.** An army in battle burns munitions each day in proportion to the power of its guns (artillery's existing
  `shells`, times `Army.shelling_share` of its power, times `munitions.per_gun_power`); an army dug in facing an enemy
  burns `munitions.idle_share` of that. Drawn from its nation's stockpile in `Military._fight`.
- **Short of shells.** When the stockpile cannot meet the day's need, the guns fight at `1 - shell_penalty` times the
  share missing (`combat.shell_penalty`, in the data and unread today). The battle report and the staff report say so.
- **Buying abroad.** `BuyMunitions`: money for munitions at `munitions.import_price`, cut by the blockade as other
  imports are. Money gets a use in war, and a small nation arms by buying.
- **Calibration targets** (set in data, then checked): a great power fighting a general war at full strength burns
  about half its IC a day; an arms share of 10-15% from 1900 leaves a stockpile for 4 to 6 months of general war, so
  the shell crisis of 1915 comes out of the rules, not a script.
- **The AI.** `AIBudget` sets the arms share from tension, alarms and war (low in calm, high in a crisis and at war),
  and buys when the stockpile would last fewer than `munitions.ai_min_days` of war. New numbers in `ai.json`, on the
  trainer's list for step 7.
- **On screen.** The Economy tab: an Arms production slider with the stockpile, what it adds a month and how many days
  of war it lasts at the army's present size; army cards and the battle screen show "short of shells"; the briefing
  warns when the stockpile will run out within 60 days of war. The campaign report adds days short of shells and the
  stockpile at the first great-power war.
- Tests: `munitions_test` (making by share, ageing and storage cost, burning in battle and dug in, the penalty when
  short, buying, the blockade's cut, save and load, migration from version 2); extend `ai_budget_test`; a UI test that
  drives the slider and checks the text.
- **Done when:** with the AI off, 1900-1914 (`tools/economy.py`), a nation at arms share 0 reaches 1914 with almost no
  stockpile and one at 20% with at least 6 months of general war, at a GDP cost of at least 5%, so building and arming
  pull against each other; with the AI on (`tools/campaign.py`), a great power runs short of shells within the first 6
  months of the general war in at least 5 of 10 seeds.
- **Result:** Germany 1900-1914, building everything: at arms share 0 it reaches 1914 with 11 days of war in store, at
  20% with 860, for 6% of GDP and £216M of its treasury (Italy the same: 6%). From July 1914, a great power runs short of
  shells within 6 months in 10 of 10 seeds (median 3.5 months; Germany and Russia in December 1914 in seed 0). Calibrating
  on what armies actually burn (only a share of them is in contact on a day) took the burn per gun from 0.75 to 4 and
  counts a stockpile's days at the expected use, not at every army fighting at once; the "dug in" burn is an army next
  to an enemy army, since the AI's armies are seldom on formal fronts.

#### 3b. Money, taxes, mobilization and demobilization (F4, F5, E3-E5)
- **Taxes.** The strain rises evenly above the default (not squared) and its growth cost counts at 20%; under the
  default, growth gains (`tax_relief.growth_bonus`). No rate is free, and every rate does something.
- **Civil spending** is worked out on the output after mobilization and blockade, so a mobilized or blockaded state
  also spends less; the per-nation multiplier stays as calibrated.
- **State investment.** A monthly sum (a slider, `SetEconomyPolicy` "investment") the treasury puts into development,
  with a diminishing return: the peacetime home for a surplus that is not going into a stockpile's upkeep or arms
  bought abroad.
- **Mobilization** costs what its men cost: reserve upkeep for the men actually called and the output lost; the slider
  shows the monthly cost before it moves.
- **Demobilize.** A `DemobilizeUnits` command (an army, a count or "to peacetime"), in peace only: units go to the
  reserve and then back to the people, upkeep falls at once. A button on army cards and in the command panel.
  `AIForces` sheds units toward `peacetime_army` times `forces.demob_margin` once at peace and out of every truce, at
  `forces.demob_share` of the excess a month from `forces.demob_after_days` after its last war, while not alarmed or
  mobilized.
- **The AI** taxes by the new curve, may go under the default when rich, and invests a surplus.
- Tests: `demobilize_test`; extend `economy_test` (the tax curve both ways, civil spending on actual output,
  investment) and `ai_budget_test`.
- **Done when:** with the AI off, every tax rate from 5% to 40% gives a different result and no rate gives more than
  twice the treasury of 10% for less than 10% of GDP; the mobilization slider's cost line matches the budget's change
  within 5%. With the AI on: great-power treasuries from 1922 at most 6 months of revenue (12-13.5 in the baseline); armies three years after a
  war at most 0.6 of their peak in it; `balance_run` growth about 3% a year.
- **Result:** with the AI off, Germany 1900-1914: 5% gives +9% GDP and a £1.8bn debt, 15% £1.1bn for 7% of GDP, 20%
  £2.0bn for 13% (and no growth at all), 30% £3.0bn for 24%, 40% £3.4bn for 34%: every rate differs, and over the years
  each pound of tax costs about a pound of output (the plan's "twice the treasury of 10%" means little when 10% leaves
  £80M). Mobilizing to 40% costs what the slider says within 5% (`demobilize_test`), £8.5M a month for Germany (£14.6M
  before). With the AI on: great-power treasuries from 1922 hold 4.2 months of revenue from 1900 and 6.2 from July 1914
  (13.5 and 12 before); growth 1901-1911 is 3.2% a year (median of the great powers). Armies three years after a war
  stand at 0.75 of their peak in it from 1900 and 0.92 from 1914 (1.0 before): they come back to their peacetime size,
  but the wars barely raise them above it (Germany's 1914 peak is its pre-war army), so 0.6 is out of reach until the AI
  raises armies in a war (step 7). Measuring it found that a nation conquered while mobilized kept its neighbours
  mobilized for ever (its alarms never lapsed), which held every post-war army at its war size: fixed.

#### 3c. Small economies, materials and food, the economy on screen (E6, E8, E9)
- **Industry by size.** The flat 20 IC a day becomes a floor that follows the economy (`construction.base_ic` times
  min(1, GDP over `base_ic_gdp_ref`), never under `base_ic_min`), so IC follows size; small nations arm by buying.
- **Materials and food** stay blockade systems and say so: the Economy tab shows them under "Imports and the blockade";
  the briefing's "build mines" (there are none) becomes "hold the provinces with deposits, or keep the sea open".
- **The economy on screen.** The Nation screen fits the window at 1280x720 and 1600x900 (the Economy tab's right column
  is cut off today); civil spending's tooltip says it follows output; the tax slider says what each rate costs and
  gives; money a month and IC a day everywhere, the data notes saying which.
- Tests: extend `economy_test` (IC by size); a UI test at both sizes that checks the right column is inside the window.
- **Done when:** a small nation's best building pays back its IC within about 15 years (Serbia's factory: 357 today);
  the Economy tab shows every figure at 1280x720.
- **Result:** Serbia's best factory pays back its IC in 15.8 years (357 before), Bulgaria's in 11, Belgium's and Italy's
  in 16 (18 and 25 before), Germany's big-city one in 7 as before; a factory is priced by its province's industry, other
  works by its output. Serbia building everything for 14 years ends with +14% GDP and +17% IC (nothing before). The
  Nation screen fits 1280x720 (and, scaled, any window of that shape: `nation_fit_test`).

### 4. After the war (F2, F9, E7)
- **Revanche.** A province ceded at a peace gives the loser a `reconquest` claim for `revanche_years` (new, about 25)
  and a slow grievance. Claims made in play live in the state (`gs.claims`), are saved, and are read by
  `Diplomacy._claim_applies`, the crisis score and `AIAmbition`.
- **Crises go on.** Retune `max_wars`, `min_score` and `pair_cooldown_months`; new crisis kinds in `crises.json`:
  `revanche` (return a lost province), `minority` (protect a people across the border), `naval` (a fleet limit as a
  concession). Same mechanics, new demands.
- **Post-war events,** conditioned on the state, not the date: unrest after a lost war, independence movements in the
  empires, an arms-limitation conference.
- **Repeatable foci for every nation.** Two or three for each great-power tree (`tools/make_focus_trees.py`) and more
  room in the minor template; the briefing asks for a focus only when one can be taken.
- **Tension moves.** The arms part compares armies with a base that drifts up slowly, so a post-war arms race shows,
  and demobilization lowers it.
- Tests: `revanche_test`; extend `crisis_test` and `focus_test`; `validate_data.py` checks the new kinds and events.
- **Done when** (both scenarios to 1940, 10 seeds): from 1922 at least one crisis every 2 years and one war every 5
  years on average; January tension spread of at least 5; no AI nation idle without a focus for more than 12 months.
- **Result:** from 1922, crises come 0.56 a year from 1900 and 0.64 from July 1914 (median; 0.2 to 1.3 by seed; none
  before), from revanche, naval rivalry and the old claims; no AI nation is ever more than a month without a focus (383 and
  215 before). Not met: no war starts after 1922 in any seed, and January tension moves by 2.3 and 2.7. Crises end in
  yielding, backing down or mediation; a target refuses only when about as strong as the demander, who then cannot win,
  and the few nations holding ground lost at a peace are weaker than the winners' side. Making a refused demand a
  provocation brought the great war forward to 1902 (a naval demand of Russia's on Britain), so it only adds to the AI's
  desire (`w_refused`); ground lost at the peace after a war is a provocation (`w_revanche`). The arms base's drift and
  the conference on armaments wait for a great-power war to end, or they took the general war away from 4 of 10 1900
  runs; with that, the road to 1914 is as step 2 left it (first great-power war 1912.10, general war 1914.06 in 10 of
  10). One 1900 seed has a beaten Serbia annexed by Germany in 1920, counted as detached by the report (land paths only;
  the peace rule also accepts a held sea), not yet traced. The "minority" crisis is not built: the map has no peoples to
  protect. Wars after 1922 and the tension spread go to step 7, with the AI's appetite for war.

### 5. Peacetime decisions (F6, F7, F8)
- **Demands replace justification.** The Justify war button and command go; the goal picker chooses what a demand asks.
  Refusal gives the casus belli with that goal, yielding gives the land. `consider_justify` becomes `consider_press`.
  A save with a justification under way migrates to a crisis or a casus belli (a `_migrate` step).
- **One public stand,** for every nation, on the Overview: calm scales with prestige (a great power's at high tension
  about as strong as today's conference); rattling the sabre costs relations with the neighbours too. The "concert"
  and "brink" events go (or "brink" gets real options).
- **Small nations.** At least two events for each nation with fewer (Denmark, Luxembourg, the Netherlands, Romania,
  Switzerland, Norway, Sweden, Portugal, Spain, Albania), from their history; the 1905 Norway-Sweden crisis is the
  model. Crises with the player as a party come a little more often, within the global cap.
- **Ambitions** (optional): the player may pick one ("keep out of the great war", "unify the nation", "become a great
  power"); the History book records how it went. A direction, not a score.
- Tests: update `justify_test` and `crisis_test` for the merged flow; a save migration test;
  `public_stand_test`; `validate_data.py` checks that every nation is in at least two events.
- **Done when:** a passive Belgium is asked at least one thing a year, 1900 to 1915; no decision has an option that
  does nothing; Justify war is gone from code, data and docs.
- **Result:** a passive Belgium is asked 1.63 things a year from 1900 to 1915 (0.16 before), a passive Spain 1.53 to 1940;
  `validate_data.py` refuses an event option with no effect (15 had none) and a nation in fewer than two events. Justify
  war, its command, state, data and signals are gone; the goal picker makes demands (`PressDemand` with a demand chosen in
  full), the AI makes one where it built a case (`consider_press`), and save format 4 turns a case under way into its
  casus belli (`demand_test`). The road to 1914 is unchanged (first great-power war 1912.10, general war 1914.06 in 10 of
  10), crises from 1922 come 0.8 a year. Ambitions are in (`ambition_test`).

### 6. Leftovers (C4, F12)
- **Mediation.** A nation may try to mediate a crisis once (C4).
- **Cavalry.** Occupies at twice the speed and harries a retreating enemy (`military.json`, `Military._fight`), or is
  cut.
- Tests: extend `crisis_test` and `combat_test`.
- **Result:** a nation mediates a crisis once (`crisis_test`); cavalry takes ground after a battle in half the terrain's
  time and adds up to 15% to a routed army's loss by its share of the victors (`cavalry_test`; kept, not cut). From July
  1914 the great powers' wars run 6.2 months (median; 7.2 before), the worst single loss 9% (7.5%), no capital or cut-off
  province ceded.

### 7. Retrain the AI (F11)
- Fitness: the soldier term from 30 to about 5, plus the change in provinces held, less a little for each month at war
  (`tools/ai_train.py`, `tools/ai_arena.gd`). The new numbers of steps 3 and 4 (arms share, buying, investment,
  demobilization) join the trained list.
- Wars after the great war (step 4): with the new rules no war starts after 1922; the AI's weighing of a war (desire,
  odds with allies) should let a stronger revanchist or a refused demander fight, and the trained numbers should be judged
  on it too.
- War-time recruiting: in these runs a war barely raises a great power's army above its peacetime size, so there is
  little to send home after it (step 3b's 0.6 of the peak). The AI should raise armies when a war goes long, and the
  trained numbers should include how far.
- 40 generations under the rules of steps 1 to 6, then 16 fresh seeds.
- **Done when:** applied because it beats the shipped numbers *and* the checks of steps 1 to 4 hold, or declined with
  the evidence in DESIGN.md.

### 8. Docs, versions and playtests
- DESIGN, MANUAL, README, the tutorial (demands, war score, peace, arms production) and the CHANGELOG as each step
  lands; steps 1 to 5 each change how the game plays, so each takes a minor version (0.6.0 onward; 3a to 3c share one),
  and each version publishes a release.
- Playtests, last: Germany 1900-1910 (pacing, and whether arming against building is a choice a player feels); France
  in July 1914 holding the Marne (the front tools, and the shell shortage); Russia told to take Berlin by 1905 (the step
  1 snowball, against a human); a first-time player after the tutorial alone (the first hour); Belgium for two hours
  (small-nation interest). A result that contradicts the runs sends its step back.

## Quality gates

- New or changed rule: a headless test. UI feature: a test that drives the scene and checks text and state.
- `godot --headless --path . --import` after adding a `class_name`.
- Save mid-feature, load, verify.
- Performance: a day step under 90 ms, the AI under 25 ms (`SPEED_TESTS=0` on a busy machine).
- Full suite green, and `tools/campaign.py` and `tools/economy.py` run against `docs/baseline.md`, before a step is
  called done.

## Open decisions

Each has a default, and none blocks the work:
1. Annexation must connect by land or by a sea zone the taker's fleet controls (default), or by land only.
2. Munitions are made by an arms share of each day's IC (default), or queued as projects beside the buildings.
3. Munitions bought abroad come from a world market cut by blockade (default), or only from neutral nations that sell
   (more diplomacy, more work).
4. Ambitions (step 5): in (default), or left out to keep the game free of any goal it sets.
5. A version for each step (default), each publishing a release.
