# Rework progress (work in progress, branch `rework-r2-r3`)

Last saved 2026-10-30. Main is at 0.17.0 (R1 released). This branch holds R2 and R3 together (the resource economy
taken out, the gold economy put in), not yet released.

## Done on this branch

- Backup: branch `archive/resource-economy` (pushed, at 0.17.0); docs/archive/RESOURCE_ECONOMY.md. (A tag could not be
  pushed from the session; add `v0.17-resource-economy` on that commit by hand if wanted.)
- Sim: scripts/sim/economy.gd rewritten (gold income: base from population, civilian factories 1.5, ports 0.3;
  expenses: unit upkeep, navy, building upkeep, interest; CP stockpile from construction sectors plus a quarter from the
  capital; queue paid at start, fixed days, one project a province, ten of a kind). data/economy.json new. Munitions,
  BuyMunitions, taxes, investment, food, materials, deposits, population growth removed. Units cost gold (military.json
  cost/upkeep; artillery has "guns": true), ships cost gold (navy.json cost, no ic). Save format 5 (older saves refused).
- Scenarios: starting buildings from tools/make_start_economy.py (civilian_factory, construction_sector, railway);
  old nation fields (development, agri_yield, pop_growth) and resources.tsv removed.
- Focus effects converted (income, cp, civilian_factories); tools/make_focus_trees.py converts too.
- AI: scripts/ai/ai_budget.gd rewritten (buildings by want per gold, standing army growth in peace, points);
  ai.json budget block new, munitions block gone; ai_navy checks gold.
- UI: economy panel (Gold, Construction, People), construction panel, top bar (gold and CP chips), overview, nation
  stats, rankings, province panel, map modes (Resources mode gone, Income mode), slot labels, build queue, navy and
  military panels, tutorial, MANUAL.md economy section.
- Tests: new economy_test, population_test, ai_budget_test, economy_words_test (fails on old-economy words in what
  the player reads; passes). munitions_test, tax_test, construction_points_test removed. Many tests adjusted.
- docs/REWORK.md: decisions recorded (capital CP trickle yes, no CP cap), R4/R6 now say raising a unit costs its
  manpower once.

## Still to do before releasing 0.18.0

1. Run the full suite (`SPEED_TESTS=0 python3 tools/run_tests.py`) and the windowed tests; fix what fails. Fixed but
   not yet re-run: construction_ui, map_modes, build_mode_view, military_map, nation_stats, diplomacy(_ui),
   demobilize, navy, ai_* tests, pressure, scandinavia, scenario_1900, tutorial, visibility, economy_run.
   Watch ai_history / road_to_1914 / pressure (the AI's army growth and weaker forts and trenches may shift them).
2. Balance check: an AI-only run (tools/campaign_report.gd) and the incomes after a few years.
3. Screenshots (CLAUDE.md): a tools/screenshot_economy.gd shot of the Economy tab, the Build tab and the top bar; look
   for faults.
4. DESIGN.md economy section, CHANGELOG 0.18.0, bump project.godot, release (push main and economy-2), then delete this
   file.
