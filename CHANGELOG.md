# Changelog

Versions are `major.minor.patch`. A minor version (`0.6.0`, `0.7.0`, ...) is for a large change to how the game plays;
most updates, features included, bump the patch number (`0.5.1`, `0.5.2`, ...). `1.0.0` is the first release we call
finished.
The version lives in `project.godot` (`application/config/version`), shows in the corner of the main menu, and names
the Windows build the CI attaches to each release.

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
