# Plan: the reset

Written 24 October 2026. The old plan (finishing M1 to M6) is done; `DESIGN.md` records what exists. This plan replaces it after the verdict that the game is janky and unfun: systems added one at a time, never designed together; no goal; menus that grew instead of being planned; a start date (July 1914) that leaves no road to the war.

## Decisions (from the owner)

- **Spirit:** a historical-pressure sandbox. No score and no victory screen. The pull is surviving and steering through the years of tension toward a great war, with events and crises that push the player along.
- **Start:** two scenarios, `1900` (a long campaign from 1 January 1900) and `1914` (the short July 1914 start, kept as a quick start).
- **Economy:** replaced by one simple model of three pillars, not patched.
- **Menus:** one nation screen with tabs, a slim top bar, and the map.

## The new economy (replaces money/IC/flows/programs/laws/lines/stockpiles)

Three pillars, each with one number the player can read and one or two levers.

1. **Money** (£M a year). Income is tax on the nation's output (lever: tax rate). It pays the army and navy (men and ships), the upkeep of buildings, and debt interest. The balance moves the treasury; debt is allowed but costs interest and credit (relations and prestige drag). One budget view, no per-item funding sliders.
2. **Industry** (points a day). One pool from factories and the economy's size, spent on one queue: buildings, ships and army units (and their kit, folded into the unit's price). Materials are one number, **supply of raw materials** (own deposits plus imports), which scales industry and which a blockade cuts. **Food** stays as a separate famine check (it drives unrest and population).
3. **Manpower**. The pool from population, drawn on by raising units, refilled by growth; mobilization is the lever (more men under arms, less output).

Removed or folded: the economy laws, programs and policies, production lines and equipment stockpiles, the ten-resource flow solver, intensities, the shell and chemicals and draft-animal chains, and the separate ship and building pools. Focus effects, treaties and diplomacy points are kept but retargeted at the three pillars.

## Milestones

| | Theme | Done means |
|---|---|---|
| R1 | Economy core (sim) | The new model replaces the old one in `scripts/sim`; the data file is rewritten; commands and saves updated; the suite passes with obsolete tests removed or rewritten |
| R2 | AI | The AI budgets, builds and raises forces with the new model and still plays a war and a peace (history checks pass) |
| R3 | Nation screen | One tabbed window (Overview, Economy, Military, Navy, Diplomacy, Focus) replaces the separate windows; the top bar is slim; hotkeys are listed and consistent; flows from map to window are short |
| R4 (done) | Historical pressure | A tension system and a calendar of crises and events for 1900 to 1914 (Moroccan and Balkan crises, naval race, alliance shifts); events offer choices that move relations, tension, money and manpower |
| R5 (done) | Scenarios | A `1900` scenario (borders, alliances, populations, armies and fleets as of 1900) beside `1914`; a scenario choice on the menu; both load and play to a war |
| R6 | Finish | Tutorial rewritten for the new screens; balance pass (a ten-year AI run ends in a plausible world); README and DESIGN rewritten; the old plan notes removed |

R1 first, because everything else reads it. R3 can follow R1 even while R2 is in progress. R4 and R5 are independent of each other once R1 is done.

## Rules for the work

- Each milestone ends with the whole suite green, committed and pushed to `main`.
- When a system is removed its data, commands, tests, UI and tutorial text go in the same commit. No dead switches.
- Each screen is checked by looking at a screenshot of it, not only by its test.
