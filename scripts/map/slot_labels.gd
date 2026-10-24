extends Node2D
## In the Construction map mode, writes on each of the player's provinces what the building
## picked has there: used and total slots for the factories ("3/5"), levels built and the most
## allowed for railways and ports ("1/3"). Above the number sit icons for the resources the
## province yields (coal, iron, timber), below it a pip for each civilian factory standing there.
## Drawn at a constant size on the screen, and only once the map is zoomed in far enough for the
## numbers not to run together.

const MIN_ZOOM := 0.45
const FONT_SIZE := 13
const FREE_COLOR := Color(0.75, 1.0, 0.75)
const FULL_COLOR := Color(1.0, 0.65, 0.55)
## Icon size, pip size and the most pips drawn, in screen pixels (the pip count past the cap is
## written as a number).
const ICON := 14.0
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


## What to write, as plain data: [{id, text, full, deposits, factories}] for the player's
## provinces (the resources it yields, and its civilian factories), or nothing when the building
## picked is not one.
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
		var entry := {"id": id, "deposits": deposits_of(gs, id), "factories": gs.province_buildings[id].get("factory", 0)}
		var level: int = gs.province_buildings[id].get(building, 0)
		var most: int = def.get("max_level", 1)
		entry.text = "%d/%d" % [level, most]
		entry.full = level >= most
		out.append(entry)
	return out


## The resources a province yields (those with a deposit worth working), richest first.
static func deposits_of(gs: Node, id: int) -> Array[String]:
	var found: Array[String] = []
	var amounts: Dictionary = gs.province_deposit[id]
	for r in Economy.resource_ids():
		if amounts.get(r, 0.0) >= Economy.cfg.materials.min_deposit:
			found.append(r)
	found.sort_custom(func(a: String, b: String) -> bool: return amounts[a] > amounts[b])
	return found


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
		_draw_deposits(e.deposits, center + Vector2(0.0, -(FONT_SIZE * 0.5 + ICON * 0.6) * px), px)
		_draw_pips(e.factories, center + Vector2(0.0, (FONT_SIZE * 0.5 + PIP + 3.0) * px), px, font)


## A row of resource icons centred on `at`.
func _draw_deposits(deposits: Array, at: Vector2, px: float) -> void:
	var gap := ICON + 3.0
	var x := -gap * (deposits.size() - 1) / 2.0
	for r: String in deposits:
		_draw_icon(r, at + Vector2(x, 0.0) * px, px)
		x += gap


## One resource icon centred on `at`: a lump of coal, an ingot of iron, a tree for timber.
func _draw_icon(resource: String, at: Vector2, px: float) -> void:
	var color := Color(Economy.cfg.resources[resource].color)
	var h := ICON / 2.0
	var shape := PackedVector2Array()
	match resource:
		"coal":
			shape = [Vector2(-h, 0.2 * h), Vector2(-0.55 * h, -0.8 * h), Vector2(0.4 * h, -h), Vector2(h, -0.1 * h), Vector2(0.6 * h, h), Vector2(-0.5 * h, 0.9 * h)]
			color = color.lightened(0.15)
		"iron":
			shape = [Vector2(-0.55 * h, -0.7 * h), Vector2(0.55 * h, -0.7 * h), Vector2(h, 0.7 * h), Vector2(-h, 0.7 * h)]
		_:
			shape = [Vector2(0.0, -h), Vector2(h, 0.45 * h), Vector2(-h, 0.45 * h)]
	var scaled := PackedVector2Array()
	for v in shape:
		scaled.append(at + v * px)
	draw_colored_polygon(scaled, color)
	scaled.append(scaled[0])
	draw_polyline(scaled, Color(0, 0, 0, 0.9), px * 1.2, true)
	if resource == "wood":
		draw_rect(Rect2(at + Vector2(-0.14 * h, 0.45 * h) * px, Vector2(0.28 * h, 0.55 * h) * px), Color(0.45, 0.3, 0.15))


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
