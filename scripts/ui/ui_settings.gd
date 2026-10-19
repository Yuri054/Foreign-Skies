class_name UiSettings
extends RefCounted
## Player settings that outlast a session, kept in user://settings.cfg. For now: the UI scale.
## The scale is the root window's content scale factor, so every menu, the top bar and the
## map grow or shrink together, and everything laid out against the screen (the top bar, the
## windows, the right-click menu) adapts to the smaller or larger room that leaves.

## Where the settings live. Tests point it somewhere else so they never touch the real file.
static var path := "user://settings.cfg"
## The steps Ctrl and + or - go through. The slider in Settings takes any value in between, in
## steps of SCALE_STEP.
const SCALES := [0.5, 0.6, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
const MIN_SCALE := 0.5
const MAX_SCALE := 2.0
const SCALE_STEP := 0.05

static var scale := 1.0

## Which armies the map draws: "all", "allies" (yours and your allies') or "own".
const ARMY_VIEWS := {"all": "Everything I can see", "allies": "Mine and allies'", "own": "Mine only"}
static var army_view := "all"
## Whether the command panel at the bottom shows its cards (C hides them).
static var command_open := true


## Reads the saved settings and puts the theme and scale on the window.
static func apply_saved(window: Window) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		scale = clampf(float(cfg.get_value("ui", "scale", 1.0)), MIN_SCALE, MAX_SCALE)
		var view := str(cfg.get_value("map", "army_view", "all"))
		army_view = view if ARMY_VIEWS.has(view) else "all"
		command_open = bool(cfg.get_value("ui", "command_open", true))
	window.theme = UiTheme.build()
	window.content_scale_factor = scale
	UiCursor.install()


## Changes the scale (rounded to SCALE_STEP, held between the smallest and largest) and saves
## it. Returns the scale used.
static func set_scale(window: Window, value: float) -> float:
	scale = clampf(snappedf(value, SCALE_STEP), MIN_SCALE, MAX_SCALE)
	window.content_scale_factor = scale
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("ui", "scale", scale)
	cfg.save(path)
	return scale


## Chooses which armies the map draws and saves it. Returns false for an unknown view.
static func set_army_view(view: String) -> bool:
	if not ARMY_VIEWS.has(view):
		return false
	army_view = view
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("map", "army_view", view)
	cfg.save(path)
	return true


## Shows or hides the command panel and saves the choice.
static func set_command_open(open: bool) -> void:
	command_open = open
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("ui", "command_open", open)
	cfg.save(path)


## Whether the map draws the armies of `tag` for the player `player`.
static func shows_army(gs: Node, player: String, tag: String) -> bool:
	if army_view == "all" or tag == player:
		return true
	return army_view == "allies" and Diplomacy.are_allied(gs, player, tag)


## The next preset up or down from the current scale.
static func step_scale(window: Window, direction: int) -> float:
	var index := 0
	for i in SCALES.size():
		if absf(SCALES[i] - scale) < absf(SCALES[index] - scale):
			index = i
	return set_scale(window, SCALES[clampi(index + direction, 0, SCALES.size() - 1)])
