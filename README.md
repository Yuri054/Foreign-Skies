# Europa: The Last Battle

A real-time grand strategy game on a flat 2D map of Europe, July 1914. Pick any nation, manage its
economy, armies, navy and diplomacy, and see whether the alliances hold. Single player; the AI plays
every other nation. The design is in [DESIGN.md](DESIGN.md).

## Running it

You need [Godot 4.7](https://godotengine.org/) (the project is set to 4.7, GL Compatibility renderer).

1. Open the project folder in Godot and press F5, or run `godot --path .` from this folder.
2. The first launch imports the map images; wait for it to finish.
3. On the main menu choose **New game** (or **Tutorial**, a guided twelve-step intro), then a nation.

Saves and settings are written to Godot's user folder (`user://saves/`, `user://settings.cfg`).

## Playing

| Input | Does |
|---|---|
| W A S D, wheel, middle-drag | Pan and zoom the map |
| Click | Select a province (or army, fleet, sea zone) |
| Right click | Order selected armies or fleets; otherwise show the country panel |
| Box drag | Select every army and fleet inside the box |
| Space, `-` `+` | Pause, change speed (five speeds) |
| 1 to 6 | Map modes (political, diplomacy, economy, population, military with its sea control and blockade variants, terrain) |
| C | Show or hide the command panel (armies and fleets as cards along the bottom) |
| E, B, M, F, N | Economy (with its Production tab), Construction, Military, Diplomacy and Navy windows |
| F5, Shift+F5, F6 | Quick save, quick load, save and load window |
| F10, Ctrl and `+` `-` | Settings, UI scale |
| Esc | Clear a selection, otherwise the pause menu |

The game saves itself on the first of every month into three rotating autosave slots.

## Testing

Every test is a headless script under `tests/`:

```
godot --headless --path . -s res://tests/save_load_test.gd      # one test
python tools/run_tests.py                                       # all of them
GODOT=/path/to/godot python tools/run_tests.py save_load menu   # a few, with the executable named
```

A test passes when it prints `FAILURES: 0`. Run `godot --headless --path . --import` once after
adding a new script with a `class_name`, so Godot learns the class. `tests/playthrough_test.gd`
plays a hundred days at four nations in the real map scene and prints the load time, memory and the
cost of a day; `tools/ai_report.gd` plays the whole AI war and prints a month-by-month report.

## Layout

| Folder | Holds |
|---|---|
| `scripts/sim/` | The simulation: `GameState`, the clock, economy, military, navy, diplomacy, commands, saving |
| `scripts/ai/` | The AI: defence, offence, navy, landings, diplomacy, budget |
| `scripts/map/` | Map data, the map view and its shader, army and fleet layers |
| `scripts/ui/` | Panels, windows, menus, tutorial |
| `scripts/audio.gd` | Sound (the `Audio` autoload) |
| `data/` | Map bitmaps and tables, scenarios, balance files (`economy.json`, `military.json`, `navy.json`, `ai.json`, ...), `audio.json`, `tutorial.json` |
| `tools/` | Build scripts for the map data, the audio, and the test runner |
| `tests/` | The headless tests |

Everything that can be a number is in `data/`. All changes to the world go through commands
(`GameState.issue`), which is what makes saves, tests and the AI share one path.

## Rebuilding generated data

Python 3 scripts in `tools/` build the map tables and the stock sounds (`python tools/make_audio.py`
writes `data/audio/`; replace any file with your own recording of the same name).

## Windows export

Install the export templates through *Editor > Manage Export Templates*, add a Windows Desktop
preset under *Project > Export*, and export. `export_presets.cfg` is not committed.
