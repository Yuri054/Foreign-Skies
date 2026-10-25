# Changelog

Versions are `major.minor.patch`. Each step of `PLAN.md` that changes how the game plays is a minor version
(`0.3.0`, `0.4.0`, ...); `1.0.0` is the first release we call finished. Fixes between steps bump the patch number.
The version lives in `project.godot` (`application/config/version`), shows in the corner of the main menu, and names
the Windows build the CI attaches to each release.

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
