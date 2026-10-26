# Foreign Skies: plan

Written 2026-10-26, after a design review of v0.5.7 (code, data and AI-only runs over many seeds). The previous plan
(war goals, briefing, validator, dynamic crises, history book, conferences, staff tools, coalitions, difficulty) is
built; it is summed up in the CHANGELOG.

Each step ends with a headless test printing `FAILURES: 0`, a full-suite run, the docs updated, and its "done when"
checked with `tools/campaign.py` against the baseline in `docs/baseline.md`.

## Principles

1. No technology tree, tactical battle layer, multiplayer or world map. The Europe frame is a feature.
2. History pushes, it does not script. Crises create pressure and choices, never one fixed outcome.
3. Show and deepen the state that exists before adding new meters.
4. Content lives in `data/`; every new rule gets a headless test.
5. The player must be able to understand why the world moves.
6. No retraining of the AI until the rules stop changing (step 7): trained numbers go stale with every rule fix.

## What the review found

| | Finding | Step |
|---|---|---|
| F1 | A capital taken lets the winner dictate any terms (`Peace.check`, `AIPeace._accepts`): great-power wars end in weeks with Berlin, Vienna, Prague, Stockholm and Milan annexed, often far from the winner's land. | 1 |
| F2 | After about 1920 nothing happens: no wars, no crises, tension flat near 40, every focus done. | 4 |
| F3 | Great powers start conquests in 1902-04 against neutrals (Germany on the Netherlands, Russia on Sweden); the war gate (tension 30) is reached by drift alone, and the 1900 nations have no temperaments. | 2 |
| F4 | Armies only grow: no command disbands a unit, so war-sized armies stay for ever. | 3 |
| F5 | Money stops mattering: great-power treasuries reach 30 months of revenue; buildings cost IC, and a tax below 10% gives nothing. | 3 |
| F6 | Peacetime holds few decisions for most nations: a passive Belgium is asked 2 things in 16 years; ten nations have at most one event. | 5 |
| F7 | Pressing a demand does what justifying a war does, cheaper and sooner. | 5 |
| F8 | The peace tools are lopsided (the GP-only "concert" event is far stronger than an appeal for calm), and "brink" is a decision with one option. | 5 |
| F9 | The great powers' focus trees end by about 1905 and nothing repeats; the briefing then asks for a focus for ever. | 4 |
| F10 | Crises open on one-on-one odds but are answered on the odds of whole sides: hopeless demanders collect casus belli. France presses Alsace in May 1900. | 2 |
| F11 | The trainer rewards 30 times the share of soldiers: likely why the AI hoards men and gives up land quickly. | 7 |
| F12 | Small things: "0.0 a month" indemnities, the war signal sent before the goal is set, docs that say units cost IC, screenshots imported by Godot, cavalry with no role. | 0, 1, 6 |
| C1-C4 | From the code review of 0.5.4: conference counter-offers never expire and are not asked again; a failed joint peace skips the solo attempt; a package is judged entry by entry; mediation fails the same way every time. | 1, 6 |

## Order

| Step | Work | Size | Status |
|---|---|---|---|
| 0 | Housekeeping and the campaign report | S | in progress |
| 1 | War resolution: forced peace, connected annexation, conferences | L | |
| 2 | The road to 1914: war gate, temperaments, neutrals, crisis odds | M | |
| 3 | Demobilization and money | L | |
| 4 | After the war: revanche, post-war crises and events, repeatable foci | L | |
| 5 | Peacetime decisions: demands replace justification, one public stand, small nations, ambitions | M | |
| 6 | Leftovers: mediation, cavalry | S | |
| 7 | Retrain the AI under the new rules | L | |
| 8 | Docs, versions and playtests | S | |

## Steps in detail

### 0. Housekeeping and the campaign report
- Merge the crisis-backing fix (a nation backs one side once, never both) and its cleanup.
- `docs/.gdignore`, so Godot does not import the screenshots; the economy note says units are paid in money, not IC.
- `tools/campaign_report.gd` measures one AI-only run (the bystander is a passive player that answers as the AI would);
  `tools/campaign.py` runs it over many seeds and prints a table. Measured: the first war between great powers, how long
  great-power wars last (and France against Germany), capitals ceded, provinces ceded with no land link to the new owner,
  the worst share a great power lost in a day, wars and crises a year from 1919 and the spread of tension, great-power
  treasuries in months of revenue, armies against `peacetime_army` three years after a war, the longest idle focus, and
  decisions put to the bystander.
- `docs/baseline.md`: the table for 10 seeds of each scenario to 1935, and a passive Belgium, before any rule changes.

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

### 3. Demobilization and money (F4, F5)
- **Demobilize.** A `DemobilizeUnits` command (an army, a count or "to peacetime"), in peace only: units go to the
  reserve and then back to the people, upkeep falls at once. A button on army cards and in the command panel.
- **The AI demobilizes.** `AIForces` sheds units toward `peacetime_army` times `forces.demob_margin` once at peace and
  out of every truce, at `forces.demob_per_month`, never below what its alarms need.
- **Low taxes.** Under the default rate, growth gains (`tax_relief.growth_bonus`) and war support settles a little
  higher: the mirror of the strain above it.
- **Money buys industry.** A `BuyIC` command: money for IC a day, at a price that rises with use and eases each month,
  as diplomacy points are bought.
- **The AI spends.** `AIBudget` may tax under the default when rich, and buys IC when the treasury is far over
  `rich_months`.
- Tests: `demobilize_test`; extend `economy_test` and `ai_budget_test`.
- **Done when:** great-power armies are at most 1.3 times `peacetime_army` three years after their last peace; the
  median great-power treasury at peace is at most 12 months of revenue; `balance_run` growth stays about 3% a year.

### 4. After the war (F2, F9)
- **Revanche.** A province ceded at a peace gives the loser a `reconquest` claim for `revanche_years` (new, about 25)
  and a slow grievance. Claims made in play live in the state (`gs.claims`), are saved, and are read by
  `Diplomacy._claim_applies`, the crisis score and `AIAmbition`.
- **Crises go on.** Retune `max_wars`, `min_score` and `pair_cooldown_months`; new crisis kinds in `crises.json`:
  `revanche` (return a lost province), `minority` (protect a people across the border), `naval` (a fleet limit as a
  concession). Same mechanics, new demands.
- **Post-war events,** conditioned on the state, not the date: unrest after a lost war, independence movements in the
  empires, an arms-limitation conference.
- **Repeatable foci.** Two or three for every great-power tree (`tools/make_focus_trees.py`); the briefing asks for a
  focus only when one can be taken.
- **Tension moves.** The arms part compares armies with a base that drifts up slowly, so a post-war arms race shows,
  and demobilization lowers it.
- Tests: `revanche_test`; extend `crisis_test` and `focus_test`; `validate_data.py` checks the new kinds and events.
- **Done when** (both scenarios to 1940, 10 seeds): from 1919 at least one crisis every 2 years and one war every 5
  years on average; January tension spread of at least 5 (about 0.5 today); no AI nation idle without a focus for more
  than 12 months.

### 5. Peacetime decisions (F6, F7, F8)
- **Demands replace justification.** The Justify war button and command go; the goal picker chooses what a demand asks.
  Refusal gives the casus belli with that goal, yielding gives the land. `consider_justify` becomes `consider_press`.
  A save with a justification under way migrates to a crisis or a casus belli (`SaveGame.VERSION` 3, a `_migrate`
  step).
- **One public stand,** for every nation, on the Overview: calm scales with prestige (a great power's at high tension
  about as strong as today's conference); rattling the sabre costs relations with the neighbours too. The "concert"
  and "brink" events go (or "brink" gets real options).
- **Small nations.** At least two events for each nation with fewer (Denmark, Luxembourg, the Netherlands, Romania,
  Switzerland, Norway, Sweden, Portugal, Spain, Albania), from their history; the 1905 Norway-Sweden crisis is the
  model. Crises with the player as a party come a little more often, within the global cap.
- **Ambitions** (optional): the player may pick one ("keep out of the great war", "unify the nation", "become a great
  power"); the History book records how it went. A direction, not a score.
- Tests: update `justify_test` and `crisis_test` for the merged flow; a version 2 save migration test;
  `public_stand_test`; `validate_data.py` checks that every nation is in at least two events.
- **Done when:** a passive Belgium is asked at least one thing a year, 1900 to 1915; no decision has an option that
  does nothing; Justify war is gone from code, data and docs.

### 6. Leftovers (C4, F12)
- **Mediation.** A nation may try to mediate a crisis once (C4).
- **Cavalry.** Occupies at twice the speed and harries a retreating enemy (`military.json`, `Military._fight`), or is
  cut.
- Tests: extend `crisis_test` and `combat_test`.

### 7. Retrain the AI (F11)
- Fitness: the soldier term from 30 to about 5, plus the change in provinces held, less a little for each month at war
  (`tools/ai_train.py`, `tools/ai_arena.gd`).
- 40 generations under the rules of steps 1 to 6, then 16 fresh seeds.
- **Done when:** applied because it beats the shipped numbers *and* the campaign checks of steps 1 to 4 hold, or
  declined with the evidence in DESIGN.md.

### 8. Docs, versions and playtests
- DESIGN, MANUAL, README, the tutorial (demands, war score, peace) and the CHANGELOG as each step lands; steps 1 to 5
  each change how the game plays, so each takes a minor version (0.6.0 to 0.9.0), and each version publishes a release.
- Playtests, last: Germany 1900-1910 (pacing and pauses); France in July 1914 holding the Marne (the front tools);
  Russia told to take Berlin by 1905 (the step 1 snowball, against a human); a first-time player after the tutorial
  alone (the first hour); Belgium for two hours (small-nation interest). A result that contradicts the runs sends its
  step back.

## Quality gates

- New or changed rule: a headless test. UI feature: a test that drives the scene and checks text and state.
- `godot --headless --path . --import` after adding a `class_name`.
- Save mid-feature, load, verify.
- Performance: a day step under 90 ms, the AI under 25 ms (`SPEED_TESTS=0` on a busy machine).
- Full suite green, and `tools/campaign.py` run against `docs/baseline.md`, before a step is called done.

## Open decisions

Each has a default, and none blocks the work:
1. Annexation must connect by land or by a sea zone the taker's fleet controls (default), or by land only.
2. Money's new uses: a tax below 10% helps growth *and* money buys IC (default), or one of them.
3. Ambitions (step 5): in (default), or left out to keep the game free of any goal it sets.
4. A version for each step (default), each publishing a release.
