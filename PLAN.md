# Plan: finishing the unfinished work

Written 19 October 2026, on `main`. Sizes are rough: **S** is under a day, **M** a few days, **L** about a week or more of focused work. Each item says what "done" means so it can be checked. `DESIGN.md` stays the record of what exists; this file is the order to do the rest in.

## How the work is grouped

| Milestone | Theme | Why here |
|---|---|---|
| M1 | Stabilise: tests, speed, build checks | Everything after it is safer and faster to check |
| M2 | Interface polish | Small, visible, low risk |
| M3 | Finish the economic rework | Closes phase 15 |
| M4 | Phase 13: Diplomacy | Gives the AI and focus system hooks to use |
| M5 | Phase 14: World content (map, focus, late-game AI) | The big one; needs M3 and M4 |
| M6 | 3D map, second stage | Optional, independent, can slot in anywhere |

M1 comes first. M2 and M6 can be done at any gap. M3 before M4 before M5 is a real order: M5's focus effects use the economy and diplomacy hooks.

---

## M1. Stabilise

**1.1 Make `window` and `ui_input` pass (S).** They fail only because headless Godot gives no real pointer. Rewrite them the way the click checks in `tools/click_card.gd` and `tools/click_map.gd` work: a windowed run under a virtual display, events sent through the window's stretch transform. Add `--windowed` to `tools/run_tests.py` that wraps those tests in `xvfb-run`.
*Done:* the suite has no known-bad tests on a clean machine.

**1.2 Cut the daily cost (M).** About 89 ms a day in a two-year AI run against a 90 ms limit; the full province recompute is about 33 ms and runs about once a day. Make it incremental: keep per-province output, mark only the provinces a change touches (an owner or controller change, a completed building, a population step) and re-sum the nations that own them. Keep the flows solve at every third day. Re-measure with `tools/` timing runs before and after.
*Done:* the AI two-year run is under 60 ms a day here, `ai_history` and `navy_history` pass with margin, and a test proves the incremental totals equal a full recompute after random changes.

**1.3 Pin the engine version and add a build check (S).** The project file says Godot 4.7; every run in this work used 4.6. Decide the target, record it in the README, and add a GitHub Actions workflow that imports the project and runs the suite headless on it.
*Done:* a green check on every push to `main`.
Target: Godot 4.7.2.

**1.3b Repository housekeeping (S).** The repository was renamed to Foreign-Skies but the local remote still uses the old URL; move it, and note in the README how to run the tests and the soak tools (`tools/soak.gd`, `tools/ui_soak.gd`).

## M2. Interface polish

**2.1 Province card (S).** Let long names wrap or shrink instead of clipping next to the More button. Test: a name of 25 or more characters shows in full.

**2.2 Diplomacy window, right half (S–M).** The list is tidy; the treaties, war and proposals side is still dense. Group it into "Treaties", "Actions" and "War" cards, show why a button is off in one line under it (the existing `BLOCKS` text), and show costs in a single column.
*Done:* every disabled action says why without a tooltip.

**2.3 City labels and army counters (S).** Counters hide some city names. Offset a city's label away from a counter at its province, or draw a short leader line, and let city names show over counters when zoomed in. Test with the screenshot tool at three zooms.

**2.4 Command panel closed state (S).** The closed panel still shows a small button. Decide whether to keep it, fold it into the top bar, or show it only when armies are selected.
Decided: keep the small button, nothing else.

**2.5 Flags in the remaining places (S).** Nation picker lists, peace screen, join prompt, battle screens and the event feed use plain names. Add the flag where a nation is named in a list.

## M3. Finish the economic rework

**3.1 Calibrate against the new model (M).** Britain, Serbia and Montenegro had `development` raised by hand to keep 1914 revenue. Re-run `tools/calibrate_nations.gd` for every nation with the daily flows, the export-income removal and the trade floor, and set `development`, `agri_yield` and `intensity` so that revenue, food and resource balances match their targets without hand nudges.
*Done:* `economy_test` passes with the original development values restored or replaced by calibrated ones, and no nation starts short of a resource.

**3.2 Shells and battle length (M).** Shell use is a guess (0.15 a day per artillery brigade). Script three standard wars (Germany against France, Austria-Hungary against Serbia, Russia against Germany) and measure shell stock, production and the share of days with no shells. Tune `shells` per brigade, the shell line's output and the nitrate costs so a major power runs short in a long offensive but not in peace.
*Done:* a test asserts those three properties on the standard wars.

**3.3 AI that understands the new economy (M).** The AI production planner and budget code were written for money costs. Teach them shells and nitrates (build Haber-Bosch plants when nitrates are short, split lines by the shell deficit), IC-based construction priorities, and trench and fortification building behind fronts (already partly done through `front_works_bonus`).
*Done:* a two-year AI run shows no nation stuck at zero shells in peace, and every power with a nitrate shortage builds a plant.

**3.4 Naval build on IC (M, reopens a decision).** Ships still use the old money build system. Move shipbuilding to IC and materials, with the dockyard building (already defined, hidden) setting yard capacity.
Decided: yes, now. *Done:* hulls draw IC from the construction pool, gold cost removed, AI throttles on the pool (see DESIGN.md). The dockyard building stays hidden: port level still sets yard capacity.

**3.5 Interface and tutorial (S).** Economy Overview shows the weariness, labor and starvation lines in a clear block, the Production tab explains each line's limit, and the tutorial's economy steps match.

## M4. Phase 13: Diplomacy

Order matters: justifications first, since the AI uses them.

**4.1 War justifications (M).** A justification takes points and time before a declaration; declaring without one costs prestige, relations and war support. Add the command, the casus belli list, the cost table in `data/diplomacy.json`, and the AI's use of it (the unjustified-war limit already exists in `ai.json`).
*Done:* tests for cost, delay, the penalties for skipping it, and an AI run where wars mostly follow justifications. *Built* (tests/justify_test.gd); the AI-run share is still to be measured with the soak tool.

**4.2 Gifts (S).** Raise the price, scale it by the receiver's size and add diminishing returns.

**4.3 Points and prestige (M).** Rebalance income and costs. Give prestige uses beyond point income: justification cost, peace terms, alliance pull.

**4.4 Named alliances (S–M).** A new alliance gets a generated bloc name from its members, or one the player types, and the interface tells it from the historic blocs (Entente, Central Powers).
*Done (built, tests/alliance_names_test.gd):* the Diplomacy and Rankings windows show bloc names; saves keep them. M4 as a whole is built; peace-terms use of prestige was left out (point income and treaty pull/justification discount cover its uses).

Numbers are mine to propose, kept in data files.

## M5. Phase 14: World content

**5.1 Norway and Sweden on the map (L).** Extend the bitmap with a Scandinavia slice using `tools/extend_map.py` (the Natural Earth admin-1 data is reachable from GitHub; Wikimedia is not). Then rebuild adjacencies, coast, terrain, population and resources; add the nations, scenario data, deployments and navies; extend the AI's data; add their cities and flags; recalibrate.
*Done:* both nations play (their economy balances, they field armies, the AI runs them) and every map-wide test passes with 22 nations. Check performance again after the extra provinces.

**5.2 National focus system (L).** A generic focus engine (a focus has a cost in time, requirements, effects) using the economy and diplomacy hooks from M3 and M4; hand-built trees for the major powers and a smaller one for each minor nation so Albania, Serbia and the rest can grow (development, claims, alliances). Interface: a Focus window with the tree and the current focus. Save and load the progress.
*Done:* every nation has at least a short tree; the AI picks and finishes foci; a test per effect type.

**5.3 The late-game AI (L).** After the opening war the AI does almost nothing. With the focus system in place, give it goals (claims, growth, rebuilding armies after a war, new alliances) and a way to want things. Scripted events stay a thin layer of flavour.
*Done:* a five-year AI run (with the soak tool) shows continued wars and treaties after year two, no stalls, and no invariant violations.

## M6. 3D map, second stage (optional)

**6.1 Turning the map (M).** Yaw, with panning following the view direction.

**6.2 Relief (L).** Needs an elevation source; I have not found one reachable from here yet (check GitHub-hosted DEM tiles or derive pseudo-relief from the terrain types). Displace the plane, light it, and make picking work on the relief.
Decided: yes, real relief.

**6.3 3D unit markers (M).** Replace the flat banners in 3D mode with small drawn models or billboards.

---

## Review loop used at every step

1. Add or update the test for the change first.
2. Run the whole suite, and for anything that touches play or the interface run `tools/soak.gd` and `tools/ui_soak.gd` as well.
3. For visible changes, take screenshots with the tools in `tools/` and check them.
4. Commit to `main` with a message that says what changed and why; update `DESIGN.md` for anything a later reader needs.

## Decisions (made 19 October 2026)

1. **Godot 4.7.2** is the target (1.3). Tests and tools run on it from now on.
2. **Real terrain relief in 3D is wanted** (6.2). It goes ahead; the data source is the first job there.
3. Everything else is left to me. My calls: the closed command panel keeps only a small "Command (C)" button and shows nothing else (2.4); ships move to IC and materials in M3 (3.4); war-justification and prestige numbers are mine to propose and tune (4.1, 4.3), written into `data/diplomacy.json` so they are easy to change.

## Suggested order

M1 → M2 → M3 → M4 → M5, with M6 fitted wherever there is a gap. If something must come sooner, the late-game AI (5.3) is the most valuable but depends on 5.2 and M4, so a thin version (goal-driven AI without full focus trees) could be built first and replaced later.
