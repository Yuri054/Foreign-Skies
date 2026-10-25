# Changelog

Versions are `major.minor.patch`. Each step of `PLAN.md` that changes how the game plays is a minor version
(`0.3.0`, `0.4.0`, ...); `1.0.0` is the first release we call finished. Fixes between steps bump the patch number.
The version lives in `project.godot` (`application/config/version`), shows in the corner of the main menu, and names
the Windows build the CI attaches to each release.

## 0.3.0

- War goals and justification: choose what a war is for (province claim or concession) when you justify it; scenario
  claims and defence give goals of their own. Goal terms cost half at peace and everything else more. The AI picks and
  fights for goals. Every war shows a "why" line.
- The AI is trained by self-play (40 generations) with no authored war plans: the great war lasts years.
- Instant occupation of undefended provinces; thicker, readable borders on the 3D map; smoother front lines.
- Music (three pieces) with a player and audio settings; camera: edge room, zoom to the mouse, no zoom over menus.
- Diplomacy mouse tip, more tooltips, buildings shown as paid in IC.
