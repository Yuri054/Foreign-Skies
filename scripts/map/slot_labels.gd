extends Node2D
## In the Construction map mode, writes on each of the player's provinces what the building
## picked has there: used and total slots for the factories ("3/5"), levels built and the most
## allowed for railways and ports ("1/3"). Drawn at a constant size on the screen, and only
## once the map is zoomed in far enough for the numbers not to run together.

const MIN_ZOOM := 0.45
const FONT_SIZE := 13
const FREE_COLOR := Color(0.75, 1.0, 0.75)
const FULL_COLOR := Color(1.0, 0.65, 0.55)

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


## What to write, as plain data: [{id, text, full}] for the player's provinces, or nothing
## when the building picked is not one.
static func entries(gs: Node, building: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Economy.cfg.buildings.has(building):
		return out
	var def: Dictionary = Economy.cfg.buildings[building]
	var tag: String = gs.player_tag
	var nation: Nation = gs.nations.get(tag)
	if nation == null:
		return out
	for id: int in nation.provinces:
		if def.get("slot", false):
			var used := Economy.slots_used(gs, id)
			var cap := Economy.slots_of(gs, id)
			out.append({"id": id, "text": "%d/%d" % [used, cap], "full": used >= cap})
		else:
			var level: int = gs.province_buildings[id].get(building, 0)
			var most: int = def.get("max_level", 1)
			out.append({"id": id, "text": "%d/%d" % [level, most], "full": level >= most})
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
