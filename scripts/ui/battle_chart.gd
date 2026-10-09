extends Control
## A small line chart for the battle screen: one line per side over the days of the battle.
## `series` is an array of {name, color, points: Array[Vector2]} with x = day and y = value;
## `percent` formats the value axis as a percentage of 1.0.

var title := ""
var series: Array = []
var percent := false

const LEFT := 46.0
const RIGHT := 8.0
const TOP := 20.0
const BOTTOM := 18.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 130)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(p_title: String, p_series: Array, p_percent := false) -> void:
	title = p_title
	series = p_series
	percent = p_percent
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var area := Rect2(LEFT, TOP, size.x - LEFT - RIGHT, size.y - TOP - BOTTOM)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.09, 0.12))
	draw_rect(area, Color(0.1, 0.12, 0.16))
	var x_max := 1.0
	var y_max := 0.0
	for s in series:
		for p: Vector2 in s.points:
			x_max = maxf(x_max, p.x)
			y_max = maxf(y_max, p.y)
	if percent:
		y_max = 1.0
	y_max = maxf(y_max, 1.0)
	# Value grid.
	for i in 5:
		var frac := i / 4.0
		var y := area.end.y - area.size.y * frac
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.08), 1.0)
		var value := y_max * frac
		var label := "%d%%" % roundi(value * 100.0) if percent else _short(value)
		draw_string(font, Vector2(4.0, y + 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, LEFT - 6.0, 10, Color(1, 1, 1, 0.55))
	# Day labels.
	draw_string(font, Vector2(area.position.x, size.y - 4.0), "start", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.55))
	var end_label := "day %d" % roundi(x_max)
	draw_string(font, Vector2(area.end.x - 60.0, size.y - 4.0), end_label, HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 10, Color(1, 1, 1, 0.55))
	# Lines.
	for s in series:
		var line := PackedVector2Array()
		for p: Vector2 in s.points:
			line.append(Vector2(area.position.x + area.size.x * p.x / x_max, area.end.y - area.size.y * clampf(p.y / y_max, 0.0, 1.0)))
		if line.size() > 1:
			draw_polyline(line, s.color, 2.0, true)
		for pt in line:
			draw_circle(pt, 2.5, s.color)
	# Title and legend.
	draw_string(font, Vector2(LEFT, 13.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8))
	var x := size.x - RIGHT
	for i in range(series.size() - 1, -1, -1):
		var s: Dictionary = series[i]
		var w := font.get_string_size(s.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		x -= w
		draw_string(font, Vector2(x, 13.0), s.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, s.color)
		x -= 16.0
		draw_line(Vector2(x, 9.0), Vector2(x + 12.0, 9.0), s.color, 3.0)
		x -= 10.0


func _short(v: float) -> String:
	return "%.1fM" % (v / 1_000_000.0) if v >= 1_000_000.0 else ("%dk" % roundi(v / 1000.0) if v >= 1000.0 else "%d" % roundi(v))
