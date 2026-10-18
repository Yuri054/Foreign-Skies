class_name CommandCard
extends Control
## One card of the command panel: an army, a fleet, a field marshal, or an empty slot. A dark
## tile on top carries the commander's initials (or the unit count of a fleet) and a skill
## figure; below it are a name, one or two lines of figures and thin strength and morale bars.
## There are no portraits: the badge stands in for them.

signal pressed(shift: bool)
signal context_requested(at: Vector2)

const SIZE := Vector2(72, 72)
const TILE_H := 30.0
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
		if event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(event.shift_pressed)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			context_requested.emit(get_global_mouse_position())
			accept_event()


func _draw() -> void:
	var font := get_theme_default_font()
	var back := Color(0.1, 0.12, 0.16, 0.96)
	if _hover:
		back = back.lightened(0.08)
	draw_rect(Rect2(Vector2.ZERO, size), back)
	var tile := Rect2(Vector2(2, 2), Vector2(size.x - 4.0, TILE_H))
	draw_rect(tile, Color(0.16, 0.18, 0.23) if empty else tint.darkened(0.45))
	if empty:
		var c := tile.get_center()
		draw_line(c + Vector2(-7, 0), c + Vector2(7, 0), Color(0.5, 0.54, 0.62), 2.0)
		draw_line(c + Vector2(0, -7), c + Vector2(0, 7), Color(0.5, 0.54, 0.62), 2.0)
	else:
		# A dark head and shoulders behind the initials, as a stand-in portrait.
		var c := tile.get_center() + Vector2(0, 3)
		draw_circle(c + Vector2(0, -6), 6.0, tint.darkened(0.2))
		draw_rect(Rect2(c + Vector2(-12, 1), Vector2(24, 11)), tint.darkened(0.2))
		_text(font, badge, Vector2(tile.position.x, tile.position.y + 21.0), tile.size.x, 16, Color.WHITE)
		if not skill.is_empty():
			_text(font, skill, Vector2(tile.position.x, tile.end.y - 2.0), tile.size.x - 3.0, 9, GOLD if marshal else Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_RIGHT)
	var x := 4.0
	for m in marks:
		_text(font, m, Vector2(x, tile.position.y + 10.0), -1.0, 10, WARN if m == "!" else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		x += 10.0
	var y := tile.end.y + 10.0
	_text(font, title, Vector2(3, y), size.x - 6.0, 9, Color(0.92, 0.94, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	y += 9.0
	_text(font, line1, Vector2(3, y), size.x - 6.0, 9, Color(0.7, 0.74, 0.82), HORIZONTAL_ALIGNMENT_LEFT)
	if not line2.is_empty():
		y += 8.0
		_text(font, line2, Vector2(3, y), size.x - 6.0, 8, Color(0.6, 0.64, 0.72), HORIZONTAL_ALIGNMENT_LEFT)
	var bar_y := size.y - 7.0
	if strength >= 0.0:
		draw_rect(Rect2(3, bar_y, size.x - 6.0, 2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(3, bar_y, (size.x - 6.0) * clampf(strength, 0.0, 1.0), 2), Color(0.35, 0.8, 0.4))
	if morale >= 0.0:
		draw_rect(Rect2(3, bar_y + 3.0, size.x - 6.0, 2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(3, bar_y + 3.0, (size.x - 6.0) * clampf(morale, 0.0, 1.0), 2), Color(0.4, 0.65, 0.95))
	var border := Color(0.3, 0.34, 0.42)
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


func _text(font: Font, text: String, at: Vector2, width: float, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	if text.is_empty():
		return
	# Text wider than its room is cut short with an ellipsis.
	if width > 0.0 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		while text.length() > 1 and font.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			text = text.substr(0, text.length() - 1)
		text += "…"
	draw_string(font, at, text, align, width, font_size, color)
