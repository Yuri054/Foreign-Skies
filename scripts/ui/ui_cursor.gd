class_name UiCursor
extends RefCounted
## The mouse pointer of the game, in the look of the interface (see UiTheme): a cream arrow in a
## dark outline with a thin gold rule inside it, and a lit gold one over anything that can be
## clicked. Drawn here in code, like the frames, so there is no image file. Godot swaps between
## the two by itself (arrow, pointing hand) according to the control under the mouse.

const SIZE := 32
## Where the point of the arrow is, which is where a click lands.
const HOTSPOT := Vector2(3, 3)
## The arrow's outline, in pixels of the SIZE square.
const ARROW: PackedVector2Array = [
	Vector2(3.0, 3.0), Vector2(3.0, 25.0), Vector2(8.6, 19.8), Vector2(12.6, 29.0),
	Vector2(17.0, 27.1), Vector2(13.0, 18.2), Vector2(20.5, 18.2),
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
	Input.set_custom_mouse_cursor(hand_image(), Input.CURSOR_POINTING_HAND, HOTSPOT)


static func arrow_image() -> Image:
	if _arrow == null:
		_arrow = _draw(UiTheme.CREAM, UiTheme.GOLD)
	return _arrow


## The pointer over a button or a link: the same arrow, gold, with a cream rule.
static func hand_image() -> Image:
	if _hand == null:
		_hand = _draw(UiTheme.GOLD.lightened(0.15), UiTheme.CREAM)
	return _hand


## The arrow drawn pixel by pixel from its distance to the outline: a dark edge outside, a rule
## inside it, then the fill shaded a little darker toward the bottom. Four by four samples a
## pixel smooth the edges.
static func _draw(fill: Color, rule: Color) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var ink := Color(0.03, 0.03, 0.04)
	for y in SIZE:
		for x in SIZE:
			var sum := Color(0, 0, 0, 0)
			var covered := 0
			for sy in 4:
				for sx in 4:
					var p := Vector2(x + (sx + 0.5) / 4.0, y + (sy + 0.5) / 4.0)
					var d := _signed_distance(p)
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


## Distance from a point to the arrow's edge: negative inside, positive outside.
static func _signed_distance(p: Vector2) -> float:
	var best := INF
	var n := ARROW.size()
	for i in n:
		var a: Vector2 = ARROW[i]
		var b: Vector2 = ARROW[(i + 1) % n]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return -best if Geometry2D.is_point_in_polygon(p, ARROW) else best
