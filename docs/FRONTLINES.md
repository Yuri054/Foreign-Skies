# Frontlines, round 2: command, fronts and battle orders

The design for the Hearts of Iron style command system the player asked for: fronts held by an army or by an army
group under a field marshal, cohesion modes, fallback, spearhead and garrison orders, planning, aggressiveness and
phase lines. It builds on the systems already in the game (`Front`, `ArmyGroup`, `AttackLine`, `Army`,
`Military.step_fronts`) and is delivered in stages, each one released and playable on its own.

## How the request maps onto this game

| The request | In Foreign Skies |
|---|---|
| Tile | A province (942 of them, about 50 km across). Fronts, orders and sectors are chains of provinces. |
| Division | A `Unit` (an infantry, cavalry or artillery division, or a guard or fortress unit). |
| Army under a general (up to 24 divisions) | An `Army` with its general. Today an army is one stack in one province; see *Detachments*. |
| Army group under a field marshal | An `ArmyGroup` with its marshal (exists). |
| Frontline polyline | A `Front`: the border with one enemy (follows the war) or a hand-drawn chain of provinces. |
| Offensive line | An `AttackLine` (exists: a group attacks one enemy, run by the AI's campaign logic). |
| Adapter / wrapper interfaces | Not needed: the request's template assumed foreign code. Here the system is written into the game's own classes. Every player order stays a `Command`, so it saves, replays and is tested like the rest. |
| Event hooks (OnTileOwnerChanged, OnUnitManualCommandIssued) | The game already counts control changes (`GameState.control_version`) and emits `armies_changed` / `fronts_changed`; the solver re-deals only when those change, and manual orders go through `MoveArmy`. |

## The one structural change: detachments

To spread an army's divisions along a stretch of front, an army must be able to stand in several provinces at once.
An army on a front therefore **deploys as detachments**: stacks (`Army` objects with `parent_id` set to the army) that
each hold one province of the army's sector. A detachment keeps its army's general, front, group and symbol; on the map
and in the lists it reads as part of its army ("1st Army, 3 of 5"). When the army leaves the front, its detachments
march back together and merge into it again. Two detachments of the same army in one province merge by themselves.

Fronts the AI sets up keep today's whole-army behaviour until the new solver is proven (a front's `spread` flag, on
for the player's fronts); the AI moves to it in a later stage.

## The solver

1. **Ordering the line.** A front's provinces are put in order along the line: the chain of neighbouring provinces from
   one end to the other (a border front is a set, not a chain, so it is walked from its westernmost/northernmost end,
   always to the nearest unvisited neighbour on the line; separate pieces are ordered along the line's main axis).
2. **Weighing each province.** Each province of the line gets a weight: 1, plus the enemy strength next to it (so
   threatened ground draws more divisions), plus a little for a fort, a city or a port.
3. **Army fronts.** One army's divisions are dealt to the provinces of the line in proportion to their weights
   (largest remainder, so the counts add up), at least one where there are enough.
4. **Broad fronts (army groups).** The ordered line is cut into **contiguous sectors**, one per army, each sector's
   weight in proportion to the army's strength. Armies take sectors in the order they already stand along the line
   (by the mean position of their detachments), so sectors never cross and divisions of different armies never mix.
   Each army then deals its divisions within its own sector as in 3.
5. **Moving as little as possible.** From the counts each province should have and what stands there, surplus
   divisions go to the nearest provinces short of them, within the **cohesion** limit; a division moves only if the
   gain is worth it (no shuffling for a difference of one).

## Cohesion and manual orders

- **Rigid**: a division moves at most `rigid_hops` provinces (2) from where it stands; a gap far off is not filled.
- **Balanced** (the default): at most `balanced_hops` (6).
- **Flexible**: anywhere along the front.
- **Manual override**: a division or detachment the player orders by hand is **pinned**: the front manager leaves it
  alone until it reaches the place it was sent, or the order is cancelled; then it rejoins the front's balancing. It
  stays on its front throughout (today a hand order takes an army off its front).

## Specialised lines and orders

- **Fallback line**: a front drawn in the nation's own ground, away from the enemy. The armies go to it and dig in;
  ground prepared before the enemy arrives is entrenched further (`fallback_entrench` extra levels) and faster.
- **Spearhead**: an attack order aimed at one enemy province. The armies converge on the provinces next to it and
  attack it together, instead of spreading the attack along the whole border.
- **Garrison**: low-priority guard duty on chosen provinces (ports, cities, supply hubs, the capital). An army on
  garrison holds them with a share of its divisions and is the first drawn on when a front needs more.

## Planning and aggressiveness

- **Planning**: a division standing still on a front with an attack order accumulates planning, up to
  `planning_max` (a bonus to its attack, +30% at most) in `planning_days`; moving or attacking spends it (it decays
  while marching and while fighting). The front's card shows the planning reached.
- **Aggressiveness** of an attack order: **Careful** attacks only at odds of `careful_odds` (2 to 1) or better and stops
  when morale falls under `careful_morale`; **Balanced** attacks at the AI's usual odds and stops at the usual morale;
  **Aggressive** attacks at even odds and does not stop for morale or losses.

## Phase lines

An attack order can have a chain of objective lines (A, then B, then C). When the armies reach line A, it becomes their
front (they dig in and plan there), and the attack on B starts from it once planning is done (or at once, if
aggressive).

## Visual design (from the player's brief and reference pictures)

Reference: `docs/frontlines/reference_single_army.png` (one army: barbed front line, a broad push arrow to a target
line round Warsaw) and `docs/frontlines/reference_army_group.png` (an army group: the master line with each army's
sector in its own colour, two armies' arrows to their own target lines).

- **Barbed front line**: a thick ribbon along the province borders of the line, with short ticks (barbs) every few
  pixels pointing back into friendly ground; in the army's colour (each army gets a distinct colour of its own).
- **Broad fronts**: one continuous master line along the whole front, cut into each army's colour for its sector,
  with small bracket marks where one sector ends and the next begins, and a label "72 Divisions - Army Group 1".
- **Fallback lines**: dashed and striped, in friendly ground.
- **Push arrows**: a wide, translucent arrow from the middle of the front line, curving (a Bezier) to the middle of the
  target line, solid at the base and fading toward the point, with "12 Divisions - Army 1" repeated along its body;
  the target line drawn barbed in the army's colour, and the label repeated along the lines too.
- **Spearhead arrows**: narrow, bold, converging on one province.
- **Target striping**: the enemy provinces between the front and the target line hatched diagonally, half
  transparent, cleared as they are taken.
- **Badges and paths**: the unit banners outlined in their army's colour when it is selected; a thin solid line from a
  marching stack to its province of the line; a dashed line with a train symbol for moves by rail.
- **Status marks** on banners: a green tick (planning done), a yellow triangle (low supply), a red mark (not assigned).
- **Rendering**: the lines and arrows are drawn over everything (no depth test against the relief), on the flat map
  and in 3D.

This becomes a stage of its own (F7), after F2: lines first, then arrows with the attack orders.

## Stages

| Stage | Work | Done when (playtest) |
|---|---|---|
| F1 (done, 0.13.0) | Detachments; ordered lines and weights; one army's divisions spread along its front; regroup on release | A German army of 20 divisions put on the Belgian border spreads over it in a few days, more where the enemy is; released, it marches back into one army. |
| F2 (done, 0.13.0) | Broad fronts: a front given to an army group, contiguous sectors per army | Three armies of a group on the French border hold three sectors side by side, none mixed; a fourth army added takes a sector without the others crossing. |
| F3 (done, 0.13.0) | Cohesion modes and manual pinning | On Rigid, a gap at one end is not filled from the other end; a division sent by hand is left alone until it arrives, then rejoins. |
| F4 | Fallback lines and garrisons | A fallback line drawn behind the border is held and dug in deeper than the border; ports on garrison keep a division each. |
| F5 | Spearheads, planning, aggressiveness | A spearhead takes one province with the force of the whole army; planning shows and raises the attack; Careful stops where Aggressive goes on. |
| F7 (lines done, 0.13.1; arrows, striping and status marks with F5 and F6) | The visual design above: barbed lines in army colours, sector brackets, arrows, striping, badges | On the flat map and in 3D, a player can tell at a glance which army holds which stretch, where each attack goes and what it is aiming at. |
| F6 | Phase lines; the AI uses broad fronts | A two-phase offensive digs in on line A and goes on to line B; AI-only campaign runs keep the road to 1914 and wars that end. |

Every stage keeps the full test suite green, adds tests of its own, and updates `DESIGN.md`, `MANUAL.md` and the
changelog.
