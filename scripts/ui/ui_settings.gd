class_name UiSettings
extends RefCounted
## Player settings that outlast a session, kept in user://settings.cfg. For now: the UI scale.
## The scale is the root window's content scale factor, so every menu, the top bar and the
## map grow or shrink together, and everything laid out against the screen (the top bar, the
## windows, the right-click menu) adapts to the smaller or larger room that leaves.

## Where the settings live. Tests point it somewhere else so they never touch the real file.
static var path := "user://settings.cfg"
const SCALES := [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
const MIN_SCALE := 0.75
const MAX_SCALE := 2.0

static var scale := 1.0


## Reads the saved settings and puts the theme and scale on the window.
static func apply_saved(window: Window) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		scale = clampf(float(cfg.get_value("ui", "scale", 1.0)), MIN_SCALE, MAX_SCALE)
	window.theme = UiTheme.build()
	window.content_scale_factor = scale


## Changes the scale (snapped to the nearest preset) and saves it. Returns the scale used.
static func set_scale(window: Window, value: float) -> float:
	var best: float = SCALES[0]
	for s: float in SCALES:
		if absf(s - value) < absf(best - value):
			best = s
	scale = best
	window.content_scale_factor = scale
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("ui", "scale", scale)
	cfg.save(path)
	return scale


## The next preset up or down from the current scale.
static func step_scale(window: Window, direction: int) -> float:
	var index := 0
	for i in SCALES.size():
		if absf(SCALES[i] - scale) < absf(SCALES[index] - scale):
			index = i
	return set_scale(window, SCALES[clampi(index + direction, 0, SCALES.size() - 1)])
