# The big rework: war's end, economy, manpower, units, supply

The plan for the next round of work, agreed with the player. It replaces the resource economy (coal, iron, wood, food,
IC, materials, munitions, investment, population growth) with a few simple systems, each one readable at a glance:

- **Gold** pays for everything: building, armies, upkeep.
- **Construction points (CP)**, a second currency made by construction sectors, are spent with gold to start a
  building.
- **Equipment**, made by military factories, arms your divisions.
- **Manpower** comes from a mobilization slider; it causes **devastation**, which the budget pays to repair.
- **Supply** flows from logistics hubs and ports.

Every rule here answers to VISION.md. Where a number is given it is a starting point for tuning, not a promise; the
targets in the tables are what the tuning aims at.

## The stages

Each stage is a release of its own: the full test suite green, new tests, screenshots of what changed, MANUAL.md and
CHANGELOG.md updated. The big stages also get AI-only campaign runs (tools/campaign_report.gd, tools/economy.py) to
check the world still reaches 1914 and wars still end.

| Stage | Work | Done when (playtest) |
|---|---|---|
| R1 | Capitulation and an automatic peace conference, with war score for it; province value counts cities and buildings; the capital is a large share of it, and can move | Taking Paris costs France a third of its value; France, still holding Lyon and Marseille, moves its capital and fights on, and capitulates once 80% of its value is lost, a peace conference opening on its own. Belgium, holding little but Brussels, capitulates when Brussels falls. |
| R2 | Backup, then the resource economy taken out of the game and the interface | No coal, iron, wood, food, IC, materials, munitions or investment anywhere in the game or its text; a test searches the interface text and fails on any of them. The old system is kept on a branch and in docs/archive. |
| R3 | The new economy: gold, base income, civilian factories, construction sectors and CP, building upkeep, the per-province caps, one project per province | Germany makes about 25 gold a month in 1914; a civilian factory pays back in three to four years; every nation starts with a civilian factory and a construction sector, and a small nation at peace visibly grows its income every year. |
| R4 | Manpower and devastation: the mobilization slider, reconstruction in the budget | Raising France's mobilization raises its manpower a day and its reconstruction bill by what the tooltip said; when the treasury cannot pay it, devastation builds up and France's military factories and supply suffer where it does. |
| R5 | The other buildings: ports, logistics hubs (replacing railways), forts, trenches; military factories and equipment | Each building's effect shows as a number in its tooltip and on the map; a nation with military factories fills an equipment stockpile shown in the top bar. |
| R6 | Units: soft attack, hard attack, armor, maximum entrenchment, speed, gold cost, equipment cost | The battle screen says why a fight goes as it does; a division cannot be raised without its equipment, and losses draw on the stockpile. |
| R7 | Supply and logistics | A big army pushing far from its hubs slows and weakens; a logistics hub behind the front fixes it; a supply map mode shows it. |
| R8 | Research (research centers) and aircraft (air bases) | Their own projects, planned when R1 to R7 have settled. |

Within a stage the order is always: the rules and numbers in this file, the simulation, the AI, the interface, the
tests, screenshots checked for faults, the manual and changelog, the release.

## R1: capitulation and the automatic peace conference

Today a nation only "collapses" when it holds no land at all, and nothing opens a peace conference by itself.

- **Province value**: one measure of what a province is worth, used everywhere the war needs one (war score for
  occupying it, capitulation, its price in a peace deal): its population, plus its **city** (more for a bigger one),
  plus its **buildings** (each counted by what it cost). A built-up industrial province is worth far more to take, and
  costs more to demand in peace, than empty farmland.
- **The capital is a large part of it**: the capital carries a capital bonus sized so that it is about a third of the
  nation's whole value (`capital_share`). Taking it is the biggest single blow in a war, in war score and towards
  capitulation.
- **Capitulation progress** is the share of the nation's value that its enemies hold (a lost capital counting with
  its bonus). At 80% the nation capitulates. Since the capital is a third, no nation reaches 80% with its capital
  still in its hands.
- **Moving the capital**: when its capital falls, a nation that still holds enough value (at least `relocation_share`
  of its value, about 25%) moves its capital and fights on: the AI to its most valuable city (or its best town when it
  has no city left),
  the **player picks** the city from a list (time stops until they do). The new capital is a capital for everything else (supply, the map, the interface) and
  carries a **smaller** capital bonus (half), so taking a second capital still hurts but a nation cannot be counted
  as losing a whole capital twice. A nation that does not hold enough value to move its capital capitulates when it
  falls. Retaking the old capital moves the capital back.
- **Capitulation**: its armies lay down their arms (they are disbanded; their men return to manpower), and its allies
  fight on without it. The war with it goes straight to a **peace conference** (scripts/sim/conference.gd), the
  winners taking turns as they do today; capitulation adds `capitulation_score` to every enemy's war score against
  that nation, shown as the line "Capitulation" in the war panel.
- The war panel and the peace screen show each side's capitulation progress against the 80%, so the player sees it
  coming.

## R2: taking the resource economy out

- **Backup first**: the branch `archive/resource-economy` and the tag `v0.16-resource-economy` keep the whole game as
  it is now; `docs/archive/RESOURCE_ECONOMY.md` describes how it worked (deposits, IC, materials, munitions, food,
  investment, population growth), so it can come back intact one day. Nothing of it stays in the game as dead code.
- **Out of the game**: coal, iron, wood, food and their deposits; IC and industry points; materials and imports;
  munitions and their stockpiles; investment; tax strain; food imports and famine; population growth (manpower takes
  its place, R4). The railway building becomes the logistics hub (R5).
- **Out of the interface**: the resource map modes, the top bar's resource and IC readouts, the Economy and Build
  tabs' resource rows and tooltips, the munitions purchase, the investment slider, the national focus effects that
  name them. A test reads every label, tooltip and data file the player sees and fails if any of the removed words
  are left.

## R3: the new economy

### Gold

One currency, called **gold** everywhere (interface, tooltips, manual). A nation's monthly income:

```
income = base income (from population, fixed) + civilian factories × 1.5 + ports × 0.3
         × war and blockade modifiers
expenses = army upkeep + building upkeep + navy upkeep + reconstruction (R4)
```

- **Base income** comes from each province's population, slightly concave (so small nations get relatively more),
  and does not grow: growth comes from building.
- **Targets for 1914**: Germany about 25 gold a month, the United Kingdom about 28, France about 20, Russia about 18,
  Austria-Hungary about 14, Italy about 10, Serbia about 1.
- **Army upkeep** is the big expense: about 0.05 to 0.1 gold a month a division, so a great power's peacetime army
  costs about a fifth to a quarter of its income.
- Diplomacy that costs money (gifts, indemnities in peace deals) is rescaled to gold in the same pass.

### Construction points

- **CP is a currency**, like gold: construction sectors add it to a national stockpile every day, and starting a
  building spends its gold and its CP at once. There is no pool shared out over the queue.
- **Every nation starts with at least one civilian factory and one construction sector**, so even the smallest can
  earn and build from the first day; no special help for small nations is needed.
- A **construction sector** adds about 1 CP a day. Germany starts with about 2 or 3.
- **Building takes time**: once paid for, each kind of building takes a fixed number of days to finish (a civilian
  factory about 60, a fort 30, a trench 7). Paying more does not make it faster.
- **One project per province at a time**: a second building in a province can only be started once the first is done.
  Projects in different provinces run side by side; how many is limited only by gold and CP.
- **The queue**: the player can still queue several buildings; the queue starts each one as soon as its province is
  free and the gold and CP are there, in the order queued.
- **The balance**: a typical nation's spare gold a month should buy about what its sectors make in CP a month. In peace
  gold is usually what limits you; once rich, CP does, and that is when a construction sector pays. Both have to
  matter, or one of them is pointless.

### Buildings and their caps

**At most 10 of each kind of building in a province**, whatever the province: ten civilian factories, ten military
factories and ten ports in Kent is allowed, an eleventh civilian factory is not. No cost rises per level: a factory
costs the same in Berlin as in Belgrade, which keeps it readable.

| Building | Gold | CP | Upkeep a month | Effect |
|---|---|---|---|---|
| Civilian factory | 60 | 240 | 0 | +1.5 gold a month |
| Military factory | 60 | 240 | 0.10 | equipment (R5) |
| Construction sector | 40 | 160 | 0.05 | +1 CP a day |
| Port | 30 | 120 | 0 | docking, naval invasions from it, +0.3 gold a month, supply in the province and its neighbours |
| Logistics hub | 40 | 160 | 0.08 | supply capacity and faster marching up to 2 provinces away (replaces railways) |
| Fort | 15 | 80 | 0.03 | +10% defence a level |
| Trench | 5 | 30 | 0.01 | +4% defence a level; cheap and quick; lost when the enemy takes the province |
| Air base | 30 | 120 | 0.05 | aircraft (R8) |
| Research center | 80 | 300 | 0.20 | research (R8) |

The civilian factory pays back in 40 months. A small nation starts with one already earning, and its next takes a few
years of saving; after that each one comes sooner. Ports, at 30 gold for 0.3 a month, pay back slower, in 100 months; they are built for
what else they do.

**Air bases and research centers wait for R8**: they are not offered until the systems behind them exist, so the
player never pays upkeep on a building that does nothing.

**Starting buildings**: each scenario's nations get civilian factories, construction sectors and the rest worked out
from today's industry, railways and works, so the shape of 1914 stays about the same; every nation gets at least one
civilian factory and one construction sector, in its capital if nowhere else.

## R4: manpower, devastation and reconstruction

Population no longer grows. Manpower comes from a **mobilization slider** instead.

- **Raising a unit costs manpower once**: its men (12,000 for an infantry division) leave the manpower pool when its
  training begins, so the slider is what limits how fast an army grows, and the gold and equipment of R6 what it
  costs to arm. Losses are replaced from the pool; disbanding returns the men to it.

- **The slider** has marked levels, from 0 (no manpower) to 5 (the whole country under arms). Each level gives a daily
  manpower from the nation's population, the same rate per head for every nation, and wears its provinces down:

  | Level | Name | Manpower a day (France) | Devastation a month, every province |
  |---|---|---|---|
  | 0 | Disarmed | 0 | 0 |
  | 1 | Volunteers | 100 | 0.5 |
  | 2 | Limited (the peacetime ceiling) | 300 | 1.5 |
  | 3 | Partial | 700 | 3 |
  | 4 | General | 1,500 | 6 |
  | 5 | Total | 3,000 | 10 |

  At level 1 France fills an infantry division (12,000 men) in four months; at level 5, in four days.
- **Devastation** is a number, 0 to 100, in each province. Mobilization adds to it every day in every province of the
  nation; battles fought in a province and enemy occupation add more there.
- **Reconstruction is a line in the national budget**, with a setting: **paused** (pay nothing, devastation builds
  up), **normal** (repair as fast as mobilization adds it, the bill the slider's tooltip shows) or **priority** (twice
  the spending, to clear old devastation after a war). Paused and priority are real choices: save gold now and live
  with weaker factories and supply, or pay to recover faster.
- **Reconstruction** spends gold: every month the nation spends gold to bring devastation down in
  the provinces it holds, `reconstruction_cost` gold for each point repaired, scaled by the province's value. Paid in
  full, devastation is repaired as fast as mobilization adds it, so a mobilized country pays for its manpower in gold
  every month, and the slider's tooltip says how much. Not paid (an empty treasury, or reconstruction paused), it builds
  up.
- **What devastation does, where it is**: it cuts that province's military factory output by its share, and its supply
  capacity by half of it. It does **not** cut income: that cost is the reconstruction bill. A Devastation map mode
  shades every province.
- **Occupied provinces** are not repaired: their owner cannot reach them and the occupier does not pay for them.
- **The manpower pool has a cap**, about two months of the current level's generation plus what the army would need
  to refill, so a nation cannot bank years of manpower at level 1 and then disarm. Disbanding divisions and sending
  armies home return their men to the pool.
- **In peace** the slider goes up to level 2 (going above level 1 alarms the neighbours, as mobilizing does today); at
  war, to 5.

## R5: the other buildings, military factories and equipment

- **Ports**: a fleet docks and refits only in a port; naval invasions sail from one; +0.3 gold a month; supply to the
  province and its neighbours.
- **Logistics hubs** replace railways: supply capacity and faster marching in their province and up to 2 provinces
  away. The scenarios' railways become hubs in the provinces that had the most.
- **Forts and trenches**: forts are the strong, dear works (+10% defence a level); trenches the cheap, quick ones
  (+4% a level), lost when the enemy takes the province. Both stack with the entrenchment a division digs itself
  (R6's maximum entrenchment).
- **Military factories** make **equipment** into a national stockpile, shown in the top bar, cut by devastation.
  One kind of equipment to start with; a second (artillery) only if R6 needs it.

## R6: units

Every unit type gets: **soft attack** (against unarmored targets), **hard attack** (against armor), **armor**,
**maximum entrenchment**, **speed**, and five flat costs: a one-time **manpower cost to raise** (the unit's men, taken
from the manpower pool when training begins), **gold to raise**, **gold upkeep a month**, **equipment to raise** and
**equipment upkeep a month** (wear: rifles lost, guns worn out).

| Unit | Manpower to raise (once) | Gold to raise | Gold a month | Equipment to raise | Equipment a month |
|---|---|---|---|---|---|
| Infantry division | 12,000 | 15 | 0.10 | 400 | 4 |
| Cavalry division | 4,000 | 15 | 0.12 | 300 | 3 |
| Artillery brigade | 3,000 | 25 | 0.15 | 600 | 8 |

- **The balance**: gold to raise is what a great power can find for a new division every week or two in war; the real
  limit on raising an army is **equipment**. A military factory makes about 10 equipment a day, so one factory
  equips an infantry division about every 40 days, and Germany's military factories several divisions a month.
  Gold upkeep is what keeps a peacetime army at about a fifth of a great power's income (Germany's 50 divisions in
  peace: about 5 gold a month).
- A division raised costs its manpower, gold and equipment once, when training begins (it cannot start without all
  three; the raise panel shows each); only gold and equipment are charged monthly after that. The manpower is not a
  monthly cost: the men leave the pool once and come back to it when the unit is disbanded. Without the equipment upkeep, its strength wears down.
- Losses in battle draw replacement men from manpower and equipment from the stockpile.
- In battle, damage is the attacker's soft or hard attack, by the share of the target that is armored, less what the
  defender's armor blocks; the battle screen breaks this down.

## R7: supply and logistics

Today supply is yes or no: in range of friendly ground or not. It becomes a flow:

- **Supply capacity** in each province: a little from its development, more from logistics hubs and ports nearby, less
  for devastation and terrain.
- **Supply need**: each division draws supply; armies in a province share its capacity.
- **Short of supply**: an army that draws more than it gets loses speed, attack and then strength, by how short it is.
  A supply map mode shows capacity and need.

## R8: research and air

Research centers make research for a technology system; air bases host aircraft. Each is a project of its own,
planned in its own document once R1 to R7 have settled.

## Open questions

- **Old saves**: saves from before R2 will not load into the new economy; old saves stay readable on the archive branch.

Decided: the player picks the city a capital moves to (the AI moves to its most valuable); reconstruction has a setting
(paused, normal, priority); a nation's capital makes a quarter of a construction sector's CP a day, so one that has lost
every sector can still rebuild; the CP stockpile has no cap.
