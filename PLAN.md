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
| 2 | June 1914 crisis | L | The July Crisis is the central fantasy, and it fixes the missing Belgian invasion (Britain never joins now). |
| 3 | Cabinet briefing and "why" | M | Read-only, cheap; also the best tool for tuning the AI. |
| 4 | Data validator and save version | S | Catches the ordering and indentation mistakes the data has had. |
| 5 | History book | M | The payoff for a game with no score: a readable, exportable history. |
| 6 | War aims and peace conference | L | Gives wars a purpose; touches `war.gd`, `peace.gd`, `ai_peace.gd` and needs a balance run. |
| 7 | Long game (post-1914 crises, dynamic crises) | XL | Only after 2, 3 and 6 are stable. |
| 8 | Home front (rationing and strikes only) | L | Blockade should be able to break a nation, but start small. |
| 9 | Staff tools (supply map, odds preview, delegate to front) | M | Fronts are drawn already; supply and odds are the missing legibility. |
| 10 | Coalition AI and difficulty | L | After the war-length decision and war aims. |

Cut for now: localization, modding, and the art pipeline (no release target; PhotoCraft is unspecified).

## Steps in detail

### 1. War length and peace
- Measure: `tools/war_length.gd` on July 1914 over several seeds, before and after.
- Decide with the user: years-long great war (historical) or months. If months: add to the fitness a penalty on the
  war's length (or a war-weariness rule that raises peace urge with time), then retrain from the current state.
- Test: `ai_history_test` bounds on peaces and fighting at day 520, kept meaningful.

### 2. June 1914 crisis
- `data/scenarios/june_1914/` from `july_1914`: start 28 June, no starting wars, tense but at peace.
- A daily hook (`Crisis.step_day`) with deadlines for the dates the monthly events cannot hit (23, 25, 28, 30 July,
  2 August). The monthly event table stays as it is.
- Event chain in `data/events.json` using `requires_event`, `until`, `options`, `ai_option`: Sarajevo, the blank
  cheque, the ultimatum, the Serbian reply, Russian mobilization, British mediation, the Belgian ultimatum.
- A crisis state saved with the game; a panel with phase, days to decision and each power's stance.
- AI options keyed to tension, relations and temperament: the historical path likely, never certain.
- Acceptance: both a war path and a mediation path are reachable from the same start; a mid-crisis save loads.
- Test: `tests/crisis_1914_test.gd`, and `history_test` stays green.

### 3. Cabinet briefing and "why"
- A monthly briefing with the top three issues, each with a one-line reason and a button to the screen.
- Tension breakdown (`Pressure.parts`) with a 24-month sparkline.
- Read-only explanation functions for declarations, joining wars and peace (`AIDiplomacy.explain_*`,
  `AIPeace.explain`), built from the numbers the AI uses, shown in the country panel, join prompt and peace screen.
- No AI behaviour change. Test: `tests/briefing_test.gd`.

### 4. Data validator and save version
- `tools/validate_data.py`: required keys, event `requires_event` integrity, scenario owners and claims, focus trees,
  the trainer's parameter paths. A deliberately broken file is rejected with a clear message.
- A save-format version with a migration test. Python tests for `ai_train.py` (`apply()` on a copy of `ai.json`).

### 5. History book
- A whole-run `history_log` and `territory_log` in the state (the chronicle is a 40-entry ring) plus monthly aggregates.
- `scripts/sim/history.gd` builds sections (timeline, wars, territory, nations); a window with tabs and an export to
  Markdown and HTML under `user://history/`.
- Budget: the day step grows by under 2 ms, a 20-year save by under 10%. Test: `tests/history_book_test.gd`.

### 6. War aims and peace conference
- Per-nation aims on a war (limited, status quo, total; provinces, indemnity, disarmament), a War Aims panel, effects on
  war support and on what a nation will accept. Start with the player's side only for the conference.
- Tests: `war_aims_test.gd`, extend `peace_test.gd`; a balance run afterwards.

### 7 to 10
As in the earlier plan, in this order, each scoped when reached. Home front starts with food and strikes only; staff
tools are a supply map, an order preview with an odds range under fog (never the hidden strength) and "delegate to a
front"; coalition AI starts with shared objectives and no separate peace.

## Quality gates

- New or changed rule: a headless test. UI feature: a test that drives the scene and checks text and state.
- `godot --headless --path . --import` after adding a `class_name`.
- Save mid-feature, load, verify.
- Performance: a day step under 90 ms, the AI under 25 ms (`SPEED_TESTS=0` on a busy machine).
- Full suite green before each step is called done. AI numbers change only through `tools/ai_train.py apply`, after a
  fresh-seed test.

## Open decisions

1. Years-long great war, or shorter? (step 1)
2. Start with step 2 (the crisis) straight after step 1, or the briefing first?
3. Any content guideline for revolutions and civilian suffering before the home front?
4. Step 6 of the earlier plan (point git at the Foreign-Skies repository) still needs that repository added to this
   session's sources.
