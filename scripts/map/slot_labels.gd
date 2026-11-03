extends Node2D
## In the Construction map mode, writes on each of the player's provinces what the building
## picked has there: levels built (and queued) out of the most allowed ("3/10"), and below it a
## pip for each civilian factory standing there.
## Drawn at a constant size on the screen, and only once the map is zoomed in far enough for the
## numbers not to run together.

const MIN_ZOOM := 0.45
const FONT_SIZE := 13
const FREE_COLOR := Color(0.75, 1.0, 0.75)
const FULL_COLOR := Color(1.0, 0.65, 0.55)
## Pip size and the most pips drawn, in screen pixels (the pip count past the cap is written as a
## number).
const PIP := 6.0
const MAX_PIPS := 8
const PIP_COLOR := Color(0.6, 0.85, 1.0)

var map_view: Sprite2D
var camera: Camera2D
var _last := Transform2D()


func _ready() -> void:
	z_index = 8
	GameState.economy_updated.connect(queue_redraw)
	GameState.scenario_loaded.connect(queue_redraw)
	GameState.player_changed.connect(func(_t: String) -> void: queue_redraw())


func _process(_delta: float) -> void:
	if camera == null:
		return
	var view := camera.get_canvas_transform()
	if view != _last:
		_last = view
		queue_redraw()


## What to write, as plain data: [{id, text, full, factories}] for the player's provinces (with
## its civilian factories), or nothing when the building picked is not one.
static func entries(gs: Node, building: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Economy.cfg.buildings.has(building):
		return out
	var tag: String = gs.player_tag
	var nation: Nation = gs.nations.get(tag)
	if nation == null:
		return out
	for id: int in nation.provinces:
		var entry := {"id": id, "factories": gs.province_buildings[id].get("civilian_factory", 0)}
		var level := Economy.levels_planned(gs, tag, id, building)
		var most := Economy.max_level()
		entry.text = "%d/%d" % [level, most]
		entry.full = level >= most
		out.append(entry)
	return out


func _draw() -> void:
	if map_view == null or camera == null or map_view.mode != map_view.Mode.CONSTRUCTION:
		return
	if camera.zoom.x < MIN_ZOOM:
		return
	var zoom := camera.zoom.x
	var half := get_viewport_rect().size / zoom / 2.0
	var view := Rect2(camera.get_screen_center_position() - half, half * 2.0).grow(40.0)
	var font := ThemeDB.fallback_font
	var px := 1.0 / zoom
	for e in entries(GameState, map_view.submode):
		var center: Vector2 = MapData.provinces[e.id].center
		if not view.has_point(center):
			continue
		var width := MapText.size_of(font, e.text, FONT_SIZE, px).x
		var at := center + Vector2(-width / 2.0, FONT_SIZE * px / 3.0)
		MapText.draw(self, font, at, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, FULL_COLOR if e.full else FREE_COLOR, px, Color(0, 0, 0, 0.85))
		_draw_pips(e.factories, center + Vector2(0.0, (FONT_SIZE * 0.5 + PIP + 3.0) * px), px, font)


## A pip for each civilian factory, in a row centred on `at`; past MAX_PIPS a number.
func _draw_pips(count: int, at: Vector2, px: float, font: Font) -> void:
	if count <= 0:
		return
	if count > MAX_PIPS:
		var text := "%d" % count
		var width := MapText.size_of(font, text, FONT_SIZE - 2, px).x
		MapText.draw(self, font, at + Vector2(-width / 2.0, PIP * 0.6 * px), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE - 2, PIP_COLOR, px, Color(0, 0, 0, 0.85))
		return
	var gap := PIP + 2.0
	var x := -gap * (count - 1) / 2.0
	for i in count:
		var rect := Rect2(at + Vector2(x - PIP / 2.0, -PIP / 2.0) * px, Vector2(PIP, PIP) * px)
		draw_rect(rect.grow(px), Color(0, 0, 0, 0.85))
		draw_rect(rect, PIP_COLOR)
		x += gap
