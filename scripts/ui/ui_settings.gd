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
## The land texture on the map: "satellite", "painted" or "off".
static var land_style := "satellite"
const LAND_STYLES := ["satellite", "painted", "off"]
## How sharp the 3D map is: the off-screen picture of the flat map as a multiple of the window. Higher is
## sharper and costs the graphics card more.
const QUALITY_SCALES := {"low": 0.75, "medium": 1.0, "high": 1.5}
static var quality_3d := "medium"
## Whether the 3D map's sea moves (waves, sun, shallows, surf). Off for a slower graphics card.
static var water_3d := true
## Whether the command panel at the bottom shows its cards (C shows or hides them). It starts
## closed: only its small button shows.
static var command_open := false
## Whether the province card at the top left also shows the rows under its Details button.
static var province_details := false


## Reads the saved settings and puts the theme and scale on the window.
static func apply_saved(window: Window) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		scale = clampf(float(cfg.get_value("ui", "scale", 1.0)), MIN_SCALE, MAX_SCALE)
		var view := str(cfg.get_value("map", "army_view", "all"))
		army_view = view if ARMY_VIEWS.has(view) else "all"
		var land := str(cfg.get_value("map", "land_style", "satellite"))
		land_style = land if LAND_STYLES.has(land) else "satellite"
		var quality := str(cfg.get_value("map", "quality_3d", "medium"))
		quality_3d = quality if QUALITY_SCALES.has(quality) else "medium"
		water_3d = bool(cfg.get_value("map", "water_3d", true))
		command_open = bool(cfg.get_value("ui", "command_open", false))
		province_details = bool(cfg.get_value("ui", "province_details", false))
	window.theme = UiTheme.build()
	# Whatever is drawn without a theme (the map's names and banners, the charts) uses the same face.
	ThemeDB.fallback_font = UiTheme.font()
	ThemeDB.fallback_font_size = UiTheme.FONT_SIZE
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


## Shows or folds away the province card's details and saves the choice.
static func set_land_style(style: String) -> bool:
	if not LAND_STYLES.has(style):
		return false
	land_style = style
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("map", "land_style", style)
	cfg.save(path)
	return true


static func set_quality_3d(quality: String) -> bool:
	if not QUALITY_SCALES.has(quality):
		return false
	quality_3d = quality
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("map", "quality_3d", quality)
	cfg.save(path)
	return true


static func set_water_3d(on: bool) -> void:
	water_3d = on
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("map", "water_3d", on)
	cfg.save(path)


static func set_province_details(on: bool) -> void:
	province_details = on
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("ui", "province_details", on)
	cfg.save(path)


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
