extends Node2D
## The major cities, as small markers with their names. Drawn at a constant size on the screen:
## capitals always, great cities once the map is a little closer and large ones closer still, and
## a name that would land on one already written is left out (the bigger city wins). Hidden in the
## Construction mode, where the slot numbers use the same ground.

const FONT_SIZE := 12
## The zoom at which each rank of city appears (the camera goes from 0.2 to 3).
const MIN_ZOOM := {1: 0.0, 2: 0.3, 3: 0.65}
const MARKER := 4.0
const NAME_COLOR := Color(0.95, 0.91, 0.8)
const CAPITAL_COLOR := Color(0.95, 0.78, 0.38)
const INK := Color(0.04, 0.04, 0.05, 0.9)

var map_view: Sprite2D
var camera: Camera2D
var _last := Transform2D()


func _ready() -> void:
	z_index = 3
	GameState.scenario_loaded.connect(queue_redraw)


func _process(_delta: float) -> void:
	if camera == null:
		return
	var view := camera.get_canvas_transform()
	if view != _last:
		_last = view
		queue_redraw()


## The cities worth writing at this zoom, biggest first: the ones whose rank has appeared.
static func visible_cities(cities: Array, zoom: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in cities:
		if zoom >= float(MIN_ZOOM.get(c.rank, 1.0)):
			out.append(c)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.rank < b.rank or (a.rank == b.rank and a.pop > b.pop))
	return out


## A short figure for a city's people: "2.9M" or "340k".
static func people(pop: int) -> String:
	return "%.1fM" % (pop / 1000000.0) if pop >= 1000000 else "%dk" % roundi(pop / 1000.0)


func _draw() -> void:
	if map_view == null or camera == null or map_view.mode == map_view.Mode.CONSTRUCTION:
		return
	var zoom := camera.zoom.x
	var half := get_viewport_rect().size / zoom / 2.0
	var view := Rect2(camera.get_screen_center_position() - half, half * 2.0).grow(60.0)
	var font := ThemeDB.fallback_font
	var px := 1.0 / zoom
	var taken: Array[Rect2] = []
	for c in visible_cities(GameState.cities, zoom):
		var at: Vector2 = c.pos
		if not view.has_point(at):
			continue
		var width := MapText.size_of(font, c.name, FONT_SIZE, px).x
		# The name sits to the right of the marker; the box it takes, in map units.
		var box := Rect2(at + Vector2(MARKER + 3.0, -FONT_SIZE * 0.5) * px, Vector2(width, FONT_SIZE * px)).grow(2.0 * px)
		var near := false
		for t in taken:
			if t.intersects(box):
				near = true
				break
		if near and c.rank > 1:
			continue
		taken.append(box)
		_marker(at, c.rank == 1, px)
		var color := CAPITAL_COLOR if c.rank == 1 else NAME_COLOR
		MapText.draw(self, font, at + Vector2(MARKER + 3.0, FONT_SIZE * 0.33) * px, c.name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, color, px, INK)


## A diamond for a city, a star-like double diamond for a capital.
func _marker(at: Vector2, capital: bool, px: float) -> void:
	var r := (MARKER + (1.5 if capital else 0.0)) * px
	var diamond := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	draw_colored_polygon(diamond, CAPITAL_COLOR if capital else NAME_COLOR)
	var ring := diamond.duplicate()
	ring.append(diamond[0])
	draw_polyline(ring, INK, 1.4 * px, true)
	if capital:
		var core := (MARKER - 1.5) * px * 0.55
		draw_circle(at, core, INK)
