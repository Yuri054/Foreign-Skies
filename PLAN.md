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

| Step | Work | Status |
|---|---|---|
| 1 | War length and peace | done: the great war lasts 26 to 46 months across seeds |
| 2 | War goals and justification | done (v0.3.0) |
| 3 | Cabinet briefing and "why" | done (v0.4.0) |
| 4 | Data validator and save version | done (v0.4.2) |
| 5 | Dynamic crises for 1900 | done (v0.5.0) |
| 6 | History book | done (v0.5.1) |
| 7 | Peace conference | done (v0.5.2) |
| 8 | Staff tools (supply map, order preview, delegation) | done (v0.5.3) |
| 9 | Coalition AI and difficulty | done (v0.5.4) |

Every step of the plan is built. What would come next, in no order: retrain the AI under the war goals, crises and coalitions
(its numbers were trained before them), a battle "staff report" and an advisor line on event options (left out of step 3),
a player-initiated crisis (today only the AI opens them), and a release pass (art, a manual, a trailer).

Cut: the June 1914 crisis scenario (the game stays focused on 1900; July 1914 remains as a start), the home front (food, unrest, revolution), localization, modding and the art pipeline (no release target; PhotoCraft is unspecified).

## Steps in detail

### 1. War length and peace (decided: the great war lasts years; done)
- Result, July 1914 over six AI seeds: the great war lasts 26 to 36 months (ending between October 1916 and August 1917, 18 to 23 declarations, up to 10 wars at once); two seeds see a second round of wars later (13 and 29 months, 1919-1920); none is still fighting after six years. No change needed.
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

### 5. Dynamic crises for 1900
- The authored calendar (66 events) ends around Sarajevo; a player who keeps the peace, or runs a long game, runs out
  of pressure. A generator on the monthly path (no daily hook, no new scenario): when tension, grievance, claims and
  rivalry between two powers cross thresholds, a crisis opens with demands, a deadline and options to defuse
  (mediation, concession, mobilization, a guarantee) or to escalate (justify a war goal from step 2).
- Data-driven in `data/crises.json`; a crisis is saved with the game and shown in the news and the briefing (step 3).
- Test: a 1900 AI-only run of 20 years has crises after 1914, none stalls, each can be defused; balance run and
  `ai_history_test` after.

### 6. History book
- A whole-run `history_log` and `territory_log` in the state (the chronicle is a 40-entry ring) plus monthly aggregates.
- `scripts/sim/history.gd` builds sections (timeline, wars with their goals, territory, nations); a window with tabs and
  an export to Markdown and HTML under `user://history/`.
- Budget: the day step grows by under 2 ms, a 20-year save by under 10%. Test: `tests/history_book_test.gd`.

### 7. Peace conference
- Allies in a war group negotiate together, each with its own goal from step 2; counter-offers and a chairman.
  Start with a screen for the player's side only. Tests: extend `peace_test.gd`; a balance run afterwards.

### 8 and 9
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
