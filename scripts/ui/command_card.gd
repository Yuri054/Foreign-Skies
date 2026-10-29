class_name CommandCard
extends Control
## One card of the command panel, in the manner of Hearts of Iron: an army, a fleet, a field marshal, or an empty
## slot. On top a strip of order icons (the front it holds, its plan); then a portrait plate, the commander's face
## (Portraits; else a head and shoulders in the nation's colour with his initials, or a fleet's ship count) and skill; then the name, a figure plate
## and thin strength and morale bars. The army's map colour runs down both sides.

signal pressed(shift: bool)
signal context_requested(at: Vector2)

const SIZE := Vector2(60, 96)
## The strip of order icons on top, and the portrait under it: as tall as the paintings are for its width (3 by 4).
const ORDER_H := 12.0
const PLATE_H := 75.0
const GOLD := Color(0.95, 0.78, 0.25)
const SELECT := Color(1.0, 0.95, 0.4)
const FIGHT := Color(0.95, 0.25, 0.2)
const WARN := Color(0.95, 0.6, 0.2)

## What the card shows. Set before adding it to the tree (see CommandPanel).
var title := ""
var badge := ""
var skill := ""
var line1 := ""
var line2 := ""
## 0..1 shares for the two bars; negative hides a bar.
var strength := -1.0
var morale := -1.0
var tint := Color(0.3, 0.34, 0.42)
var selected := false
var fighting := false
var marshal := false
## An empty slot: a grey tile with a plus (no general, no marshal, a new group).
var empty := false
## Small marks in the corner of the tile: "no supply", "marching", "aboard" and the like.
var marks: PackedStringArray = []
## The army's colour on the map (on a front shared out in sectors); transparent for none.
var army_colour := Color(0, 0, 0, 0)
## What the army holds ("front", "fallback", "garrison" or "") and its plan ("broad", "spearhead", "invasion" or ""),
## shown as icons on top; `executing` lights the plan green.
var front := ""
var plan := ""
var executing := false
## The commander's portrait (Portraits); without one, a head and shoulders stand in with his initials.
var portrait: Texture2D = null
var _hover := false


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


## The first letter of the first and last words of a name: "Joseph Joffre" gives "JJ".
static func initials(person: String) -> String:
	var words := person.strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	if words.size() == 1:
		return words[0].substr(0, 2).to_upper()
	return (words[0].substr(0, 1) + words[words.size() - 1].substr(0, 1)).to_upper()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Accept first: the handlers rebuild the panel and take this card out of the tree, after
		# which it could no longer mark the click as used and it would fall through to the map.
		if event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit(event.shift_pressed)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			context_requested.emit(get_global_mouse_position())


func _draw() -> void:
	var font := get_theme_default_font()
	var back := Color(0.08, 0.09, 0.12, 0.97)
	if _hover:
		back = back.lightened(0.08)
	draw_rect(Rect2(Vector2.ZERO, size), back)
	# The order strip on top: what the army is doing (its front, its plan), as on the cards of Hearts of Iron.
	var strip_top := Rect2(Vector2(0, 0), Vector2(size.x, ORDER_H))
	draw_rect(strip_top, Color(0.03, 0.035, 0.05, 0.95))
	var ox := 3.0
	for icon in _order_icons():
		var tex := Icons.get_icon(icon, int(ORDER_H) - 2)
		if tex != null:
			draw_texture(tex, Vector2(ox, 0.5), (Color(0.45, 1.0, 0.5) if executing and icon in ["offensive", "spearhead", "invasion"] else Color.WHITE))
			ox += ORDER_H
	if marshal:
		_text(font, "★", Vector2(0, ORDER_H - 2.0), size.x - 3.0, 10, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	# The portrait, whole, filling the card under the order strip (else a head and shoulders in the nation's colour
	# with the initials); the name and the figure plate stand over its foot, as on the cards of Hearts of Iron.
	var plate := Rect2(Vector2(2, ORDER_H + 1.0), Vector2(size.x - 4.0, PLATE_H))
	if portrait != null and not empty:
		draw_texture_rect(portrait, plate, false)
	else:
		var top_colour := (Color(0.2, 0.22, 0.27) if empty else tint.darkened(0.25))
		var bottom_colour := (Color(0.1, 0.11, 0.14) if empty else tint.darkened(0.65))
		draw_polygon(PackedVector2Array([plate.position, Vector2(plate.end.x, plate.position.y), plate.end, Vector2(plate.position.x, plate.end.y)]),
				PackedColorArray([top_colour, top_colour, bottom_colour, bottom_colour]))
		var c := plate.get_center() + Vector2(0, -8)
		var figure := Color(0.05, 0.06, 0.08, 0.85) if not empty else Color(0.32, 0.35, 0.4, 0.9)
		draw_circle(c + Vector2(0, -9), 8.0, figure)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-20, 22), c + Vector2(-16, 4), c + Vector2(-6, 0),
				c + Vector2(6, 0), c + Vector2(16, 4), c + Vector2(20, 22)]), figure)
		if empty:
			draw_line(c + Vector2(-6, 11), c + Vector2(6, 11), Color(0.4, 0.95, 0.45), 2.5)
			draw_line(c + Vector2(0, 5), c + Vector2(0, 17), Color(0.4, 0.95, 0.45), 2.5)
		else:
			_text(font, badge, Vector2(plate.position.x, c.y + 14.0), plate.size.x, 12, Color.WHITE)
	# A shade over the foot of the plate, so the name and figures read over the painting.
	var shade_top := plate.end.y - 30.0
	draw_polygon(PackedVector2Array([Vector2(plate.position.x, shade_top), Vector2(plate.end.x, shade_top), plate.end, Vector2(plate.position.x, plate.end.y)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.85), Color(0, 0, 0, 0.85)]))
	if not skill.is_empty():
		_text(font, skill, Vector2(plate.position.x + 1.0, plate.position.y + 9.0), plate.size.x - 3.0, 8, GOLD if marshal else Color(0.92, 0.94, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, true)
	var x := plate.position.x + 2.0
	for m in marks:
		_text(font, m, Vector2(x, plate.position.y + 10.0), -1.0, 9, WARN if m == "!" else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, true)
		x += 9.0
	# The army's colour on the map runs down both sides of its card.
	if army_colour.a > 0.0:
		draw_rect(Rect2(Vector2(0, ORDER_H), Vector2(3, size.y - ORDER_H)), army_colour)
		draw_rect(Rect2(Vector2(size.x - 3.0, ORDER_H), Vector2(3, size.y - ORDER_H)), army_colour)
	_text(font, title, Vector2(4, plate.end.y - 17.0), size.x - 8.0, 8, Color(0.92, 0.93, 0.97), HORIZONTAL_ALIGNMENT_CENTER, true)
	# The figure over the foot of the portrait, white on a dark plate (the divisions and men of an army, the ships of a
	# fleet).
	var figure_plate := Rect2(3, plate.end.y - 14.0, size.x - 6.0, 13.0)
	draw_rect(figure_plate, Color(0.02, 0.025, 0.03, 0.92))
	draw_rect(figure_plate, Color(0.45, 0.41, 0.3, 0.8), false, 1.0)
	_text(font, line1, Vector2(figure_plate.position.x, figure_plate.end.y - 3.0), figure_plate.size.x, 9, Color.WHITE)
	var bar_y := size.y - 6.0
	if strength >= 0.0:
		draw_rect(Rect2(4, bar_y, size.x - 8.0, 2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(4, bar_y, (size.x - 8.0) * clampf(strength, 0.0, 1.0), 2), Color(0.35, 0.8, 0.4))
	if morale >= 0.0:
		draw_rect(Rect2(4, bar_y + 3.0, size.x - 8.0, 2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(4, bar_y + 3.0, (size.x - 8.0) * clampf(morale, 0.0, 1.0), 2), Color(0.4, 0.65, 0.95))
	var border := Color(0.45, 0.41, 0.3)
	var width := 1.0
	if marshal:
		border = GOLD
		width = 2.0
	if fighting:
		border = FIGHT
		width = 2.0
	if selected:
		border = SELECT
		width = 3.0
	draw_rect(Rect2(Vector2.ZERO, size), border, false, width)


## The icons of the order strip: the kind of front the army holds, then its plan.
func _order_icons() -> Array[String]:
	var out: Array[String] = []
	match front:
		"front":
			out.append("frontline")
		"fallback":
			out.append("fallback")
		"garrison":
			out.append("garrison")
	match plan:
		"broad":
			out.append("offensive")
		"spearhead":
			out.append("spearhead")
		"invasion":
			out.append("invasion")
	return out


func _text(font: Font, text: String, at: Vector2, width: float, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER, shadow := false) -> void:
	if text.is_empty():
		return
	# Text wider than its room is cut short with an ellipsis.
	if width > 0.0 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		while text.length() > 1 and font.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			text = text.substr(0, text.length() - 1)
		text += "…"
	if shadow:
		draw_string(font, at + Vector2(1, 1), text, align, width, font_size, Color(0, 0, 0, 0.9))
	draw_string(font, at, text, align, width, font_size, color)
