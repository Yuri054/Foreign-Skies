class_name UiCursor
extends RefCounted
## The mouse pointer of the game, in the look of the interface (see UiTheme): a cream arrow in a
## dark outline with a thin gold rule inside it, and a lit gold one over anything that can be
## clicked. Drawn here in code, like the frames, so there is no image file. Godot swaps between
## the two by itself (arrow, pointing hand) according to the control under the mouse.

const SIZE := 32
## Where a click lands: the point of the arrow, and the tip of the finger.
const HOTSPOT := Vector2(3, 3)
const HAND_HOTSPOT := Vector2(13, 3)
## The arrow's outline, in pixels of the SIZE square.
const ARROW: PackedVector2Array = [
	Vector2(3.0, 3.0), Vector2(3.0, 25.0), Vector2(8.6, 19.8), Vector2(12.6, 29.0),
	Vector2(17.0, 27.1), Vector2(13.0, 18.2), Vector2(20.5, 18.2),
]
## The pointing hand: shapes that are joined into one, each a capsule {a, b, r} (a line with a
## round end of radius r) or a polygon {poly}.
static var HAND: Array = [
	{"a": Vector2(13.0, 5.4), "b": Vector2(13.0, 17.0), "r": 2.7},    # the index finger, pointing up
	{"a": Vector2(17.2, 15.6), "b": Vector2(17.2, 19.0), "r": 2.4},   # the curled fingers
	{"a": Vector2(21.4, 16.8), "b": Vector2(21.4, 20.0), "r": 2.4},
	{"a": Vector2(25.2, 18.6), "b": Vector2(25.2, 21.0), "r": 2.2},
	{"a": Vector2(8.6, 18.4), "b": Vector2(6.3, 14.6), "r": 2.3},     # the thumb, out to the side
	{"poly": PackedVector2Array([Vector2(8.4, 17.0), Vector2(15.6, 14.6), Vector2(27.4, 18.4), Vector2(27.2, 25.4),
			Vector2(22.6, 30.2), Vector2(13.0, 30.2), Vector2(9.0, 25.6)])},    # the palm and the back of the hand
]

static var installed := false
static var _arrow: Image
static var _hand: Image


## Puts the pointers in place (once). Skipped when there is no screen to show them on.
static func install() -> void:
	if installed or DisplayServer.get_name() == "headless":
		return
	installed = true
	Input.set_custom_mouse_cursor(arrow_image(), Input.CURSOR_ARROW, HOTSPOT)
	Input.set_custom_mouse_cursor(hand_image(), Input.CURSOR_POINTING_HAND, HAND_HOTSPOT)


static func arrow_image() -> Image:
	if _arrow == null:
		_arrow = _draw([{"poly": ARROW}], UiTheme.CREAM, UiTheme.GOLD)
	return _arrow


## The pointer over a button or a link: a gold hand with a cream rule, one finger out.
static func hand_image() -> Image:
	if _hand == null:
		_hand = _draw(HAND, UiTheme.GOLD.lightened(0.15), UiTheme.CREAM)
	return _hand


## A shape drawn pixel by pixel from its distance to the outline: a dark edge outside, a rule
## inside it, then the fill shaded a little darker toward the bottom. Four by four samples a
## pixel smooth the edges.
static func _draw(shapes: Array, fill: Color, rule: Color) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var ink := Color(0.03, 0.03, 0.04)
	for y in SIZE:
		for x in SIZE:
			var sum := Color(0, 0, 0, 0)
			var covered := 0
			for sy in 4:
				for sx in 4:
					var p := Vector2(x + (sx + 0.5) / 4.0, y + (sy + 0.5) / 4.0)
					var d := _distance(shapes, p)
					if d > 1.6:
						continue
					var c := ink
					if d < 0.0:
						c = rule if d > -1.1 else fill * lerpf(1.0, 0.78, clampf(p.y / SIZE, 0.0, 1.0))
					sum += Color(c.r, c.g, c.b, 0.0)
					covered += 1
			if covered > 0:
				img.set_pixel(x, y, Color(sum.r / covered, sum.g / covered, sum.b / covered, covered / 16.0))
	return img


## Distance from a point to the joined shapes' edge: negative inside, positive outside.
static func _distance(shapes: Array, p: Vector2) -> float:
	var best := INF
	for shape: Dictionary in shapes:
		if shape.has("poly"):
			best = minf(best, _polygon_distance(shape.poly, p))
		else:
			var a: Vector2 = shape.a
			var b: Vector2 = shape.b
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t) - float(shape.r))
	return best


static func _polygon_distance(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var n := poly.size()
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return -best if Geometry2D.is_point_in_polygon(p, poly) else best
