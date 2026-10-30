# The resource economy (0.5 to 0.17)

Foreign Skies ran on this economy until 0.17.0. It was taken out in 0.18.0 for the simpler gold economy (docs/REWORK.md,
R2 and R3). The whole game as it was is kept on the branch **`archive/resource-economy`** (0.17.0); this page says how
the old economy worked, so it can be brought back one day. The code is `scripts/sim/economy.gd`, `munitions.gd`,
`population.gd`, `buy_munitions.gd`, `set_economy_policy.gd`, `scripts/ai/ai_budget.gd` and `data/economy.json` on that
branch.

## Three pillars

- **Money**, GBP millions a year: a tax on the nation's output (GDP) paid the army, the navy, the state's own costs
  (civil spending), food and raw-material imports, interest on debt, the munitions stockpile's storage and state
  investment. A twelfth of the year's net was paid each month.
- **Industry**, construction points (IC) a day: the industrial output of the provinces times `ic_per_industry`, plus
  small works everywhere (`base_ic`), cut by the raw materials short and the workers called up. One queue took it:
  munitions first (the arms share), then hulls on the slips, then buildings, each project taking at most its cost over
  its fewest days.
- **Manpower**: a pool from the people (`manpower_share`), refilled monthly toward what mobilization allowed.

## Province output

Each province had a GDP: `population × gdp_per_capita × development × density modifier`, raised by its buildings
(factory, railway, port) and the owner's national focus. Its industrial share rose with density (urban provinces were
industrial). Food came from the land (`food_per_km2 × agri_yield`). Output was cached per province and summed per
nation; an occupier took a share of an occupied province's tax.

## Raw materials

Coal, iron and timber deposits (the province table's `resources.tsv`) were summed into one number of kt a year. A
nation's industry needed `need_per_industry` kt per GBP million of output, calibrated so the world just balanced at the
start. A shortfall was imported at a price (cut by blockade); what was still short slowed industry (never below the
floor); a surplus sold abroad. Food was a separate check: a deficit was imported, and what the blockade stopped was
famine, which cut output and people.

## Taxes, investment and growth

- **Tax rate** (5% to 40%): above the default it strained the economy (less growth, lower war support, war weariness);
  below it relieved it (more growth, a little more support). Revenue fell off a little at high rates (`tax_drag`).
- **Investment** (GBP millions a month): an expense that raised yearly growth by about a pound of output per pound
  invested, softly capped. Development compounded with growth, the baseline drift, focus growth and investment.
- **Population** grew monthly by the scenario's `pop_growth`, less famine and occupation, less the war dead.
- Civil spending and soldiers' wages were set at the start (calibrated for a small surplus) and drifted only with the
  baseline, so what buildings and growth added reached the budget.

## Munitions

`arms_share` of each day's IC went into a stockpile (in IC), which also cost a share of output, aged 10% a year and cost
storage. Guns in battle burned munitions each day (and a share when a line faced an enemy); a nation short of the day's
need fought with its guns weakened. Munitions could be bought abroad at a price, cut by blockade.

## Buildings

Factory (industry and GDP), railway (GDP, food, supply and movement through `Economy.infrastructure`), port (GDP and
trade, docking), trench and heavy fortification (defence). A level cost IC (rising per level, scaled to the province's
size) and half its IC value in money when begun; it took at least `min_days`.

## The AI

Once a month (`AIBudget`): the tax rate against deficit and debt, investment from a rich treasury's surplus, the arms
share from tension and war, munitions bought from abroad at war, one building where it earned most per pound, ships,
and diplomacy points in a crisis.

## Interface

Resource and output map modes, the top bar's money and IC, the Economy tab (taxes, investment, arms share, munitions,
the budget's lines, raw materials and food), the Build tab with IC costs and days, and focus effects naming GDP,
industry, trade, food and growth.
