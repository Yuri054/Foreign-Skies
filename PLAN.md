# Foreign Skies: plan

Written 2026-10-25, after the AI was trained and applied (40 generations, +11.3 over the original on 16 fresh seeds).
Work goes straight to `main`, pushed after each step. Each step ends with a headless test printing `FAILURES: 0`,
a full-suite run, and the docs updated.

## Principles

1. No technology tree, tactical battle layer, multiplayer or world map. The Europe frame is a feature.
2. History pushes, it does not script. Crises create pressure and choices, never one fixed outcome.
3. Show and deepen the state that exists before adding new meters.
4. Content lives in `data/`; every new rule gets a headless test.
5. The player must be able to understand why the world moves.

## Done (since the last plan)

Emergent AI (no authored plans, no army-quality bonuses) trained by self-play and applied; instant occupation of
undefended provinces; player-facing front lines; music and audio settings; 3D border readability; camera (edge room, zoom
to the mouse, wheel ignored over menus); diplomacy mouse tip and more tooltips; buildings shown as IC not money.

## Order

| Step | Work | Size | Why now |
|---|---|---|---|
| 1 | War length and peace | S | The trained AI fights the great war for years (about 30 months). Decide whether that is wanted; add a peace term to the fitness or a war-weariness rule, and retrain only if so. |
| 2 | War goals and justification | L | You cannot choose what you fight for today; "justify" only makes a generic claim. Goals shape the war, the peace terms and the AI. Needed by step 3. |
| 3 | June 1914 crisis | L | The July Crisis is the central fantasy, and it fixes the missing Belgian invasion (Britain never joins now). Uses the goals of step 2. |
| 4 | Cabinet briefing and "why" | M | Read-only, cheap; shows each war's goal and why the AI acts; also the best tool for tuning the AI. |
| 5 | Data validator and save version | S | Catches the ordering and indentation mistakes the data has had. |
| 6 | History book | M | The payoff for a game with no score: a readable, exportable history. |
| 7 | Peace conference | M | Allies negotiate together, built on the goals of step 2. |
| 8 | Long game (post-1914 crises, dynamic crises) | XL | Only after 2, 3 and 4 are stable. |
| 9 | Staff tools (supply map, odds preview, delegate to front) | M | Fronts are drawn already; supply and odds are the missing legibility. |
| 10 | Coalition AI and difficulty | L | After the war-length decision and war goals. |

Cut: the home front (food, unrest, revolution), localization, modding and the art pipeline (no release target; PhotoCraft is unspecified).

## Steps in detail

### 1. War length and peace (decided: the great war lasts years)
- No retraining. Check with `tools/war_length.gd` over several seeds that the July 1914 war still ends within about
  five years and no nation is left fighting for ever; if a seed runs away, add a small war-weariness rule rather than
  a fitness term.
- Keep `ai_history_test` bounds meaningful (peaces are made all along).

### 2. War goals and justification
Today: "justify" costs 25 points and 90 days and yields a generic `fabricated_claim`; casus belli otherwise come
only from scenario claims; the peace screen allows any demand the war score pays for, whatever was justified.

- **A goal when you justify.** Goals, built in this order: (a) claim named provinces (a region, a city and its
  hinterland), (b) force a concession (indemnity, disarmament, ending a treaty), (c) liberate or back a nationality
  (Austria-Hungary, the Ottoman Empire, Russia carry these in data). Defending a guarantee or an ally needs no
  justification: it becomes the war's goal automatically. Each has its own cost, time and grievance in
  `data/diplomacy.json`, and a goal can need a precondition (a claim, an alliance, a guarantee).
- **The goal shapes the war.** A war fought for a goal gets its goal at a discount in war score and everything
  else at a premium; a war with no goal stays allowed, keeps today's penalties and pays more for terms. The goal is
  stored on the war and saved.
- **A visible build-up.** Justifying is an open step: the target and its friends see it (a notice and an opinion
  effect), rivals and allies react, and the target can respond (mobilize, ask for a guarantee, appeal).
- **The AI uses goals.** `ai_ambition` picks a goal, `ai_diplomacy` justifies it, offence and peace treat reaching it
  as the aim of the war (`aims_enough`), and a limited goal makes a limited war. Retrain the affected numbers after
  step 1.
- **A "why" line** on every war: the goal and its progress, in the war tooltip and the peace screen (and later the
  briefing).
- Tests: `tests/war_goals_test.gd`, extend `justify_test.gd` and `peace_test.gd`, `ai_diplomacy_test.gd`; a balance
  run and `ai_history_test` afterwards.

### 3. June 1914 crisis
- `data/scenarios/june_1914/` from `july_1914`: start 28 June, no starting wars, tense but at peace.
- A daily hook (`Crisis.step_day`) with deadlines for the dates the monthly events cannot hit (23, 25, 28, 30 July,
  2 August). The monthly event table stays as it is.
- Event chain in `data/events.json` using `requires_event`, `until`, `options`, `ai_option`: Sarajevo, the blank
  cheque, the ultimatum, the Serbian reply, Russian mobilization, British mediation, the Belgian ultimatum. The
  ultimatums and the Belgian violation grant goals and casus belli through the step 2 system.
- A crisis state saved with the game; a panel with phase, days to decision and each power's stance.
- AI options keyed to tension, relations and temperament: the historical path likely, never certain.
- Acceptance: both a war path and a mediation path are reachable from the same start; a mid-crisis save loads.
- Test: `tests/crisis_1914_test.gd`, and `history_test` stays green.

### 4. Cabinet briefing and "why"
- A monthly briefing with the top three issues, each with a one-line reason and a button to the screen.
- Tension breakdown (`Pressure.parts`) with a 24-month sparkline.
- Read-only explanation functions for declarations, joining wars and peace (`AIDiplomacy.explain_*`,
  `AIPeace.explain`), built from the numbers the AI uses, shown in the country panel, join prompt and peace screen.
- No AI behaviour change. Test: `tests/briefing_test.gd`.

### 5. Data validator and save version
- `tools/validate_data.py`: required keys, event `requires_event` integrity, scenario owners and claims, focus trees,
  the trainer's parameter paths. A deliberately broken file is rejected with a clear message.
- A save-format version with a migration test. Python tests for `ai_train.py` (`apply()` on a copy of `ai.json`).

### 6. History book
- A whole-run `history_log` and `territory_log` in the state (the chronicle is a 40-entry ring) plus monthly aggregates.
- `scripts/sim/history.gd` builds sections (timeline, wars with their goals, territory, nations); a window with tabs and
  an export to Markdown and HTML under `user://history/`.
- Budget: the day step grows by under 2 ms, a 20-year save by under 10%. Test: `tests/history_book_test.gd`.

### 7. Peace conference
- Allies in a war group negotiate together, each with its own goal from step 2; counter-offers and a chairman.
  Start with a screen for the player's side only. Tests: extend `peace_test.gd`; a balance run afterwards.

### 8 to 10
Each scoped when reached. Staff tools are a supply map, an order preview with an odds range under fog (never the
hidden strength) and "delegate to a front"; coalition AI starts with shared objectives and no separate peace;
difficulty presets in data.

## Quality gates

- New or changed rule: a headless test. UI feature: a test that drives the scene and checks text and state.
- `godot --headless --path . --import` after adding a `class_name`.
- Save mid-feature, load, verify.
- Performance: a day step under 90 ms, the AI under 25 ms (`SPEED_TESTS=0` on a busy machine).
- Full suite green before each step is called done. AI numbers change only through `tools/ai_train.py apply`, after a
  fresh-seed test.

## Open decisions

None open. Decided: the great war lasts years; step 2 starts with province claims, then concessions, then nationality
(defence of a guarantee or an ally is an automatic goal); git now points at the Foreign-Skies repository.
