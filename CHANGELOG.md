# Changelog

Versions are `major.minor.patch`. A minor version (`0.6.0`, `0.7.0`, ...) is for a large change to how the game plays;
most updates, features included, bump the patch number (`0.5.1`, `0.5.2`, ...). `1.0.0` is the first release we call
finished.
The version lives in `project.godot` (`application/config/version`), shows in the corner of the main menu, and names
the Windows build the CI attaches to each release.
From 0.10.2 on, every entry's heading gives the date and time it was released, in UTC: `## 0.10.2 (2026-10-26 17:11 UTC)`.

## 0.14.1 (2026-10-29 03:47 UTC)

- The fronts list on the Military tab counts the men of every detachment along a front, not only the army's own stack
  (the Eastern Front read 36k for 282k), and says "1 army".
- Front labels on the map no longer cover one another: a label that would lie on another is moved up clear of it.

## 0.14.0 (2026-10-29 03:42 UTC)

Fallback lines, garrisons and plans of attack: the rest of the front system in `docs/FRONTLINES.md`.

- **Attack plans.** Select an army on a front and, on the Military tab, click **Push to line** and the enemy provinces to
  reach, or **Spearhead** and one province to strike toward. A push sends each stack at the enemy province next to it
  that leads toward the line, stacks bound for the same province attacking together; a spearhead gathers the whole army
  next to the next province on the way and strikes it at once.
- **Planning**: an army with a plan standing on its front plans, up to +30% to its attacks after two weeks, ready to go
  after one (a green tick on its banners). Marching or fighting spends it. **Launch** sets the plan going once it is
  ready; **Halt** stops it.
- **Aggressiveness**: Careful attacks only at two to one and stops when morale is low; Balanced at fair odds; Aggressive
  at even odds, at once, whatever the morale.
- **Phase lines**: **Add phase** gives a plan a further line. Once the first is taken the army plans again from where it
  stands and pushes on.
- **Fallback lines**: a front drawn in your own ground, away from the enemy, is dashed on the map; armies on it dig in
  two levels deeper and half again as fast.
- **Garrisons**: the Garrison button marks provinces of yours to guard (ports, cities, the capital); an army on a
  garrison keeps divisions in each.
- **On the map**: a push is a wide translucent arrow in its army's colour, curving from its stretch of the front to a
  barbed target line, with the enemy ground in between hatched until taken; a spearhead is a narrow arrow ringed at its
  target; later phases are dashed. Banners show a yellow triangle for low supply and a red "!" for an army at war on no
  front. On the flat map and in 3D.

## 0.13.1 (2026-10-29 03:12 UTC)

Fronts drawn as on a Hearts of Iron war map (the first part of the visual brief in `docs/FRONTLINES.md`).

- **Barbed lines**: a front is a bold ribbon along the border with a comb of barbs on your side of it.
- **Each army in its own colour**: on a front shared by several armies, each army's stretch is drawn in a colour of its
  own, with a white bracket where one stretch ends and the next begins, and a label for each army ("10 divisions ·
  Breslau Corps"); the front's own label counts its divisions.
- **Banners** of the stacks on such a front carry a strip in their army's colour, so each stack can be matched to its
  stretch of the line. On the flat map and in 3D.

## 0.13.0 (2026-10-29 02:52 UTC)

The first part of the new front system (the plan is `docs/FRONTLINES.md`).

- **Armies spread along their fronts.** An army put on a front deploys as detachments, one stack of its divisions to a
  province of the line, more where enemy divisions are massed opposite. The detachments keep their army's general and
  name, and when the army is released they march back and join it again.
- **Broad fronts.** Put several armies, or a whole army group (the new "Assign army group" list on the Military tab), on
  one front and each army holds a stretch of its own, sized by its divisions, side by side in the order they stand;
  divisions of different armies never mix. The front's details list each army's stretch.
- **Cohesion**: Rigid (a division moves at most two provinces to fill a gap), Balanced (six) or Flexible (anywhere).
- **Hand orders pin, not release.** Sending a stack of a front somewhere by hand keeps it on its front: the front leaves
  it alone until it gets there. Release takes an army off its front.
- The AI's fronts keep working as before for now.

## 0.12.3 (2026-10-29 02:34 UTC)

- **Ships in port lie on the water**, on the flat map and in 3D. Each port has a harbour spot: the open water off its
  harbour town, in its own sea zone, worked out once; the fleet's banner, its 3D models and the routes into the port use
  it (before, the banner stood over the province's middle, inland).
- In 3D a fleet in port lies moored in rows of three, and any fleet is turned, moved a little way out into the roads or
  at last drawn smaller until none of it is over land.

## 0.12.2 (2026-10-29 02:14 UTC)

The 3D map's armies, fleets and cities, made easier to read.

- **Armies stand on stands**, as on a wargames table: each division a small base in its nation's colour, with a file of
  three soldiers on it (the first carrying the flag), a horseman or a gun. The uniforms are the nation's own colour,
  never near-black, with a light rim so they stand out from the ground; French blue and German grey tell apart at a
  glance. Guns are sized to the men and have two gunners. An army stands on the highest ground under it, so hills no
  longer cut through it.
- **Ships push white water**: a bow wave along each side and a wake behind, see-through and fading out.
- **Smoke is round puffs**, ragged at the edge and lit from above, over factories, burning towns and battles; it was
  square.
- **Railways** run from the station to the edge of the town, a gravel bed with two rails, instead of dark bars floating
  out over the country.

## 0.12.1 (2026-10-29 01:53 UTC)

- **The sea moves on the 3D map.** Waves run with the westerlies, from long swell to short chop, and stay put on the map
  as you pan; the sun leaves a soft path on the water and the sky shows in it toward the horizon as you tilt; the
  shallows near the coasts are lighter, and surf breaks on every shore and round every island. The map's own colours
  and lines still show through. The settings (the gear) can still the sea on a slower graphics card.
- `tools/build_coast.py` writes `data/map/coast.png`, how far each place is from the shore, which the water reads.

## 0.12.0 (2026-10-28 02:39 UTC)

The game stops trying to be a history simulation: your effort now compounds, and any nation can climb. What the game is
for is written down in `VISION.md`.

- **Investment compounds, with no ceiling.** Each pound a year you put into state investment adds about a pound to your
  yearly output, and the extra revenue can be invested again. The state's costs and your soldiers' pay no longer grow
  with the economy, so a growing country frees more money every year.
- **Buildings count for much more.** A factory adds 10% industry and 3% output a level (6% and 1.5% before), a railway 6%
  output, a port 5% output and 2% trade, and provinces take more levels (factories 10, railways 8, ports 5). Buildings
  cost half the money they did. A fully built province makes about twice what it did bare.
- **The AI grows, but less well than you.** It invests at most half a percent of its output a year, and baseline growth
  is halved for everyone, so a focused player outgrows it.
- **Each 1 January the news says how your year went**: output growth, your rank among the economies, and whom you passed.
- Measured over 50 years from 1900 with the AI running the world: Italy, building and investing, is the largest economy
  by about 1940; Serbia, with a 15% tax, buildings and investment, climbs from 19th to 13th; Luxembourg from 20th to
  15th. A nation that does nothing falls behind.
- Fix: while you choose a nation, the top bar no longer shows any nation's figures.

## 0.11.1 (2026-10-27 00:55 UTC)

- **Spectator mode.** The nation picker has a "Watch as a spectator" button: the computer runs every nation and you
  watch. Right-click any nation to see its panel; the Nation screen opens on Rankings and History.
- Choosing a nation no longer shows Germany (the scenario's own nation) in the top bar as if it were already yours: it
  says "Choosing a nation" until you pick one.

## 0.11.0 (2026-10-27 00:29 UTC)

The economy has a point: it is for spending, on growth or on guns, and the choice between them is yours.

- **Money buys the army.** A new **Standing army** slider (Economy tab, People) sets how many men you keep under arms in
  peace, up to a fifth of your manpower. Each division costs a sum a month, and the page says how many more your surplus
  keeps, how many the treasury can raise, how many your recruits fill and how many months the treasury pays for a full
  mobilization.
- **A soldier costs what your people earn.** A Serbian soldier costs less than half what a British one does, so small and
  poor nations can pay for their armies; every nation now starts with a small surplus (8% of revenue).
- **Growth reaches the treasury.** The state's own spending follows the people, not the factories, so most of what a
  building adds stays in the budget.
- **Buildings cost money too**, paid when they are begun, then industry as before. The Build tab says, for the best place
  now, what a level costs, what the budget gains a year and how many years the money takes to come back. Mass build stops
  when the money runs out. Trenches and fortifications still cost only industry.
- The cabinet briefing says when money lies idle in peace and what it could buy.
- The AI's peacetime army grows only while its budget is in surplus, and the AI invests its surplus sooner, so its
  treasuries no longer pile up.
- Measured over 14 years from 1900: a Germany that builds until 1908 and then arms ends with 10% more output than one
  that does nothing, twice the army of one that builds everything and more divisions than one that only arms. The road
  to 1914 is unchanged.

## 0.10.2 (2026-10-26 17:11 UTC)`.

## 0.10.2 (2026-10-26 17:11 UTC)

The first release since 0.5.7: it carries everything from 0.6.0 to here (those versions were not released on their own).

- The tutorial teaches demands, how a war ends (war score and peace) and arms production.
- A great power gives up at most a quarter of its provinces at one peace (a beaten Britain could lose nearly half).
- The AI was trained again under the new rules; the new numbers made wars shorter and broke the shell shortage of 1914,
  so the old ones stay (DESIGN.md has the account).
- The README and the demand picker's screenshot follow the new rules.

## 0.10.1

- Cavalry has a role: it takes ground after a battle in half the time and harries a beaten army as it falls back (up to
  15% more of it lost).
- A nation may try to mediate a crisis only once.

## 0.10.0

- Justify war is gone: a demand does its work. Make a demand (Diplomacy tab) opens the picker, where you choose what you
  ask (provinces, or a concession, now also "no new warships"); the nation has a deadline to answer, and if it refuses,
  you hold a casus belli with the demand as the war's goal. AI nations make demands where they used to build a case.
  Saves with a case under way load with the casus belli it would have made (save format 4).
- One public stand at a time for any nation: a call for calm weighs as much as the nation making it (a great power's,
  when Europe is tense, as much as the old conference of the powers); rattling the sabre also costs the goodwill of your
  neighbours. The conference and "on the brink" events are gone.
- Small nations have something to decide: two or more events of their own for Denmark, Luxembourg, the Netherlands,
  Romania, Switzerland, Norway, Sweden, Portugal, Spain and Albania, and, for a small nation you lead, a great power
  courting you, a trade treaty and an incident on the border every year or two. Crises that concern you come a little
  more often.
- No event option does nothing any more.
- Ambitions: set your nation a direction on the Overview (keep out of the great war, unify the nation, become a great
  power); the History book records how it went.

## 0.9.0

- After the war the world goes on. Land lost at a peace leaves the loser a claim to it for 25 years and a lasting
  resentment of the winner; it is a reason for war and the first thing the loser demands in a crisis.
- New crises: a nation demands back what it lost, and a great power demands that another build no more warships for some
  years (a new peace term too).
- Ground lost at the peace after a war is a provocation: the loser may go to war for it even in a calm Europe, if it can
  win. A refused demand makes the demander keener on war.
- Mediation by the powers succeeds a little less often, and the same two nations quarrel at most every four years.
- Events from the state of the world: the lost provinces (after a peace), unrest in an empire, a conference on armaments.
- Every focus tree ends in foci that can be taken again, so no nation runs out of national efforts; the AI takes them
  once its tree is done. The briefing asks for a focus only when one can be started.
- Once two great powers have fought a war to its end, tension's arms race is measured against a base that follows the
  armies slowly: a lasting army becomes the norm, a new race shows, and armies sent home ease it.

## 0.8.0

- Munitions: industry now arms the guns. An Arms production slider puts a share of each day's industry into a stockpile of
  munitions before buildings and ships; it costs a little output, and the stockpile ages and costs money to keep. In battle
  the guns burn munitions every day (and a line facing the enemy burns some), and guns without shells fight much weaker. In
  a war you can buy munitions abroad, if the sea is open. The great powers start the July 1914 war with about four months
  in store: the shell crisis comes by itself.
- The staff report, the army cards and the cabinet briefing say when the guns are short of shells or the stockpile is low.
- Saves carry format version 3; older saves load with the usual arms share and an empty stockpile.
- Taxes: above the usual 10% every point costs growth and support evenly (no free rate up to 20%); under it the economy
  grows faster. The AI eases its taxes to 8% when rich.
- State investment: a sum a month into the country's development, with a diminishing return. The AI invests a surplus.
- Civil spending follows the output the state actually has, so a mobilized or blockaded country also spends less; the
  mobilization slider says what it costs a month before you move it.
- Send home: armies can be sent back to the reserve in peace, and their upkeep stops at once (the command panel). The AI
  sends its men home some months after a war, down to about its peacetime army.
- Small countries have an economy: the small works everywhere give IC in proportion to the economy, and buildings are
  priced to the province (a factory by its industry), so a Serbian factory pays back its IC in about 16 years, not 357.
- The Economy tab fits the window; raw materials and food stand under "Imports and the blockade", and the briefing no
  longer says to build mines.
- A project's days left no longer read one day too many.
- A nation conquered while mobilized no longer keeps its neighbours mobilized for ever.

## 0.7.0

- The road to 1914: in the 1900 game the AI starts no war of its own while Europe is calm (its war gate falls from tension
  48 in 1900 to 35 by 1912), the nations have temperaments of their own (the Balkan states bold, the neutrals timid), and the
  old quarrels (Alsace-Lorraine, the Balkans, the Straits) are a floor under grievance that fades slowly. Old rivals sign no
  pact or alliance. The 1900 starting relations, lost in an earlier change, are back.
- A nation that stands apart from the blocs is no easy target: the AI weighs heavily against attacking one, and a war on one
  with no reason costs more in the world's eyes, in prestige and in tension.
- Crises open only when the demander's side could carry them, and old claims are pressed only once Europe is tense.

## 0.6.0

- Peace: taking a capital no longer lets the winner dictate anything. A nation is beaten when its people will not fight on,
  or the enemy holds its capital and its war support is spent, or the enemy holds most of it; it then gives more than the
  war score pays for, but only the ground the winner holds, the war's goal and money.
- Land taken at a peace must touch the winner's own, through the other provinces taken or across a sea it holds or has a
  coast on, and a capital goes only with the whole country. The peace screen, the AI, conferences, crises and war goals all
  keep to it, and the peace screen says what is cut off.
- Conferences: a counter-offer waits a month, and is put to the enemy again when taken; the enemy weighs the whole package.
- No more indemnities "of 0.0 a month".

## 0.5.7

- `tools/trailer.gd` renders a one-minute trailer from the game itself (see the README).

## 0.5.6

- A player's guide (MANUAL.md) and screenshots in the README; the pause menu's key list names the History tab.

## 0.5.5

- Battle staff report: on the battle screen of a battle you are in, how it is going (what each side loses a day, how long until
  each is at half strength) and what would change it (a quarter more fighting power, a weaker enemy, a further level of trench),
  each worked out by the rules the fighting uses.
- Event options now show their largest effect under the description.
- You can press a demand on another nation (a claimed province, a border province, reparations, or a withdrawal of armies)
  from the Diplomacy tab: it opens a crisis with a deadline, and a refusal leaves you a casus belli for it.

## 0.5.4

- Difficulty: Historical, Challenging or Sandbox, chosen on the New game page and saved with the game. A preset only retunes
  how the AI nations and the crisis generator behave; it gives no one anything the rules do not.
- Coalition AI: allies keep off each other's targets, and allies that all want peace take it together at a conference. On
  Challenging a nation also stays in the war with its allies unless its people or its fortunes are failing.

## 0.5.3

- Staff tools: a Supply variant of the Military map mode (green where your armies are supplied from home, amber to red as
  the range runs out, red beyond it), and an order preview: with armies selected, the province under the mouse shows the days
  the road takes, the date of arrival, the stages that would be out of supply, and what you can see of the enemy there (a
  range, from what your intelligence allows, with the odds on men alone).

## 0.5.2

- Peace conferences: when allies are at war with the same enemy, the peace screen lists them with what each would ask
  (for its own goal, within its own war score) and offers a joint peace. The enemy takes or refuses the whole package; a
  refusal may come back as a smaller counter-offer you can accept. The partner with the highest war score chairs and gains
  standing, and nobody at the table is held to have deserted the others.

## 0.5.1

- The history book (the History tab, key H): a year-by-year timeline with a headline for each month, the wars with their
  goals, battles and peace terms, the map of the end with every change of owner, and how each nation stands against the
  start. It can be exported as Markdown or as a web page (with the map inside), or copied to the clipboard.

## 0.5.0

- Dynamic crises: the quarrels of the world now open crises with demands and deadlines (a claimed province, a border
  province, reparations, or the withdrawal of border armies). The nation asked yields, refuses (the demander gets a
  casus belli for it), mobilizes (a demander that cannot win backs down) or appeals to the powers. Any third nation, you
  included, can mediate or back a side from the Diplomacy tab. When it is your crisis you are asked at once.
- The briefing lists crises you must answer or may act on; crises are written into the chronicle and the news.

## 0.4.2

- Saves carry a format version (now 2). Saves from version 1 still load; a save from a newer game, or one too old, is
  refused with a message that says which.
- `tools/validate_data.py` checks the data files (events, claims, focus trees, the AI's trained parameters, music); the CI
  runs it and the Python tool tests before the game tests and before each build.
- The trainer's `apply` walks the JSON instead of matching text, so a key of the same name elsewhere cannot be changed by mistake.

## 0.4.1

- Three more pieces: *Ein letzter Tanzschritt* joins the peace rotation, *Mechanical March* and *Brandschaftsmarsch* the war
  rotation; they fade in and out like the rest and show in the music player's list.

## 0.4.0

- Cabinet briefing on the Overview: the three things to look at now, worst first, each with the reason and a button to
  the tab that deals with it (debt, famine, a fallen capital, a case being built against you, a stronger rival, tension).
- Tension breakdown: what it is made of, the worst rivalries and a chart of the last two years.
- "Why" lines: the diplomacy panel says what a nation intends toward you (ready to attack, or what holds it back), and the
  peace screen says where the enemy stands on peace and what pushes or holds it. Both read the numbers the AI uses.

## 0.3.0

- War goals and justification: choose what a war is for (province claim or concession) when you justify it; scenario
  claims and defence give goals of their own. Goal terms cost half at peace and everything else more. The AI picks and
  fights for goals. Every war shows a "why" line.
- The AI is trained by self-play (40 generations) with no authored war plans: the great war lasts years.
- Instant occupation of undefended provinces; thicker, readable borders on the 3D map; smoother front lines.
- Music (three pieces) with a player and audio settings; camera: edge room, zoom to the mouse, no zoom over menus.
- Diplomacy mouse tip, more tooltips, buildings shown as paid in IC.
