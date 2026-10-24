# Foreign Skies: Design

A historical-pressure sandbox on a map of Europe. There is no score and no victory screen. You run one of 22 nations through the years in which the great powers drifted toward war, and what you do, and what the others do, decides whether the great war comes. This file describes the game as it is; `README.md` says how to run and test it.

## Pillars

- **The map is the interface.** A flat 2D map (or a 3D one with real relief, cities and unit models), map modes that carry most of the information, and one Nation screen for everything about running the country.
- **History pushes, it does not script.** Crises and events arrive on a calendar, but every one is a choice and the outcome depends on the state of the world. Whether 1914 ends in a general war is not decided in advance.
- **A few systems that fit together.** Money, industry and manpower are the whole economy. Diplomacy, war and the AI read the same numbers.

## Scenarios

| | Start | Shape |
|---|---|---|
| January 1900 | 1 Jan 1900, peace | The long campaign: 1900 borders (Albania and Macedonia Ottoman, Southern Dobruja Bulgarian), smaller populations and armies, no submarines, the Franco-Russian and Triple Alliances, no Entente. Historical pressure steers the AI (`pressure_ai`), as in 1914. |
| July 1914 | 28 Jul 1914, Austria-Hungary at war with Serbia | The short start, with the crisis already under way and tension at about 70, so the AI is already bold. The tutorial is played in 1900, not here. |

A scenario is a folder in `data/scenarios/` with `scenario.json` (nations, deployment, alliances, guarantees, relations, claims, AI plans, `owner_changes`, `start_tension`, `pressure_ai`), and `provinces.tsv` (people), `resources.tsv`, `navy.tsv`, `cities.tsv`. `tools/make_1900.py` builds the 1900 folder from the 1914 one and holds the numbers that differ.

## Systems

### Economy (`scripts/sim/economy.gd`, `data/economy.json`)
Three pillars, each with a number to read and a lever.
- **Money.** Income is tax on output (lever: the tax rate) plus tariffs at ports and the sale of surplus raw materials. It pays civil government, the army and navy, imports and debt interest. The treasury may go negative; debt costs interest. `Economy.calibrate` sets each nation's civil spending so a scenario starts with a balanced budget.
- **Industry.** Industrial output sets building capacity, spent a day at a time on one queue of buildings and ships. Raw materials are one ratio (own deposits plus imports against need) that scales industry; a blockade cuts imports. Food is a separate famine check.
- **Manpower.** Recruits from population are drawn on to raise units and refilled each month. Mobilization is the lever: more men under arms, lower factory output. In peace it may reach 40%; at war it is pushed up to a war floor.
Buildings: factory, railway, port, trench, fortification. National focus adds lasting effects. Big cities begin with the factories and railways they already had (`buildings` in the scenario, from `tools/make_start_buildings.py`), which is why they smoke.

### Military (`military.gd`, `navy.gd`, `data/military.json`, `data/navy.json`)
Infantry, cavalry and artillery in armies under generals, grouped into army groups. Combat uses strength, terrain, entrenchment and morale, which makes defence strong. Armies need supply from owned or occupied land. Fronts are lines of provinces armies hold; attack lines send an army group along one. Ships are squadrons in fleets that control sea zones, blockade and carry armies. Provinces have a controller apart from the owner; occupation takes days.

### Diplomacy (`diplomacy.gd`, `peace.gd`, `data/diplomacy.json`)
Relations between every pair; treaties (alliance, guarantee, non-aggression, passage, neutrality pact) with an entente grade; casus belli and claims; war declarations that cost diplomacy points and prestige; mobilization as a diplomatic act that alarms neighbours; calls to arms that put a join decision to the player; peace priced in war score, with provinces, indemnities and disarmament as terms. War support (0 to 100) falls with casualties and blockade and decides when a nation will take any peace.

### Historical pressure (`pressure.gd`, `data/events.json`)
- **Tension**, 0 to 100, is made of a base, the great powers' arms race, mobilization, wars between them, rivalry (and two rival blocs), and the lasting force of events, which fades. It shows as a flame in the top bar and on the Overview.
- In a `pressure_ai` scenario the AI starts no war of its own choosing below tension 30, and above that grows bolder with it; above 50 the great powers' quarrels worsen each month.
- **Events**: 33, from the Boxer Rising (1900) to the Liman von Sanders mission (1913) and Sarajevo (1914), plus a conference the player can call and an "on the brink" notice. Each fires on its date while its conditions hold. If it concerns the player, time stops and each answer is a button with its effects; otherwise the AI's choice is made and it is news. Effects: tension, relations, treasury, prestige, war support, diplomacy points, manpower, mobilization, grievance, treaties, wars. Events dated before a scenario's start are history already.
- **Public stands**: from the Overview any nation may spend diplomacy points on an appeal for calm (tension down) or to rattle the sabre (tension up, prestige and war support), once every half year.
- **No ending**: the game is an open sandbox. Nothing stops the clock; a general war, a peace or a long quiet are all just where the years lead.
- Nothing is guaranteed: left alone, the 1900 world drifts to a general war in 1914; a player who cools things down or hardens them changes that.

### AI (`scripts/ai/`, `data/ai.json`)
Every other nation plays by the same rules and a temperament (aggression and caution, raised by tension; how readily it makes peace is not). Its peacetime army grows with its people and output. It budgets (taxes, one building a month), raises and positions forces, defends and attacks along plans and fronts, builds and uses a navy, proposes and answers treaties, makes and accepts peace, picks national foci, and, late, forms ambitions against neighbours it could beat.

## Interface

- **Top bar:** nation, treasury and its monthly change, recruits (while mobilized or at war), diplomacy points, tension, the Nation button, date, pause and speed, settings.
- **Map:** map modes (1 to 6) with a strip for the variants and a legend, the province card, army and fleet banners, the command panel (C) for orders, the build queue, the news feed.
- **Nation screen (N):** one window with tabs: Overview (what needs attention, Europe's tension, recent events), Economy (E), Build (B), Military (M), Navy (Y), Diplomacy (F), Focus (O), Rankings (R). A right click on your own land opens it; on another nation it opens the country panel.
- **Decisions** stop time: join prompts, peace offers and events.
- **Pause menu (Esc):** resume, save and load, settings, main menu, and the list of keys. **Tutorial:** fourteen steps in 1900.

## Map and data

942 provinces on a 7857 by 5152 bitmap (`data/map/provinces.png`, one flat colour each; `provinces.tsv` has owner, area and centre), with generated adjacencies, coasts, ports, sea zones and borders. A shader paints ownership from a lookup texture, so a change of owner writes a few pixels. Land texture (satellite or painted), relief, and the province bitmap's smaller copies for far zooms are generated by scripts in `tools/`. 101 cities per scenario with about 40 famous landmarks (`data/landmarks.json`). The 3D map draws the flat map on a tilted plane raised by relief, with city models, unit models and cards that match the 2D banners, shader smoke and a quality setting.

## Architecture

- `GameState` (autoload) holds every fact; the map and UI only read it. `Clock` ticks days and months. All changes go through commands (`GameState.issue`), which is what makes saves, tests and the AI share one path.
- The running game does a day's step a stage a frame; tests and tools run all stages at once.
- Saves are the whole state as compressed variant bytes; derived tables are rebuilt on load.
- `Economy`, `Military`, `Navy`, `Diplomacy`, `Pressure`, `Focus` are static classes over that state; their numbers are in `data/`.
- Folders: `scripts/sim`, `scripts/ai`, `scripts/map`, `scripts/ui`, `data`, `tools`, `tests`.

## Testing and balance

Headless tests under `tests/` (`tools/run_tests.py`), with windowed ones under `xvfb`. `tools/balance_run.gd` prints a yearly table of the great powers (output, treasury, balance, people, armies, land), tension and wars for a long AI-only run of a scenario; used for the balance pass. `tools/soak.gd` and `tools/ui_soak.gd` fuzz the simulation and the interface. Pictures: `tools/screenshot_*.gd`.

## Balance notes (the 1900 scenario, AI only)

Output grows about 3% a year for the larger economies (building effects and baseline growth were halved from the first draft, and the national focus tariffs cut to a hundredth of output), treasuries stay within a few months of revenue, armies grow with the arms-race events, tension rises from the mid-20s to about 60 by 1912, the Balkan League's war comes in 1912 and the general war in 1914. A player who does nothing sees the same.

## Not in the game

Multiplayer; scripted outcomes; a score; land outside Europe (the Ottoman Empire and Russia are cut by the map's frame); technology.
