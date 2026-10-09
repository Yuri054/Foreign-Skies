class_name TrendChart
extends Control
## A line chart of several series over time, for the rankings: x is a month index, y a figure
## that may be negative. `series` is an array of {name, color, points: Array[Vector2], bold}.
## `formatter` turns a y value into the axis label; `x_labels` are the texts under the two
## ends of the time axis.

var title := ""
var series: Array = []
var formatter := Callable()
var x_labels: PackedStringArray = ["", ""]
var message := ""

const LEFT := 58.0
const RIGHT := 10.0
const TOP := 22.0
const BOTTOM := 20.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 190)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(p_title: String, p_series: Array, p_formatter: Callable, p_x_labels: PackedStringArray, p_message := "") -> void:
	title = p_title
	series = p_series
	formatter = p_formatter
	x_labels = p_x_labels
	message = p_message
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var area := Rect2(LEFT, TOP, size.x - LEFT - RIGHT, size.y - TOP - BOTTOM)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.09, 0.12))
	draw_rect(area, Color(0.1, 0.12, 0.16))
	draw_string(font, Vector2(8.0, 15.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))
	if message != "":
		draw_string(font, area.position + Vector2(10.0, area.size.y * 0.5), message, HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 20.0, 12, Color(1, 1, 1, 0.6))
		return
	var x_max := 1.0
	var y_min := INF
	var y_max := -INF
	for s in series:
		for p: Vector2 in s.points:
			x_max = maxf(x_max, p.x)
			y_min = minf(y_min, p.y)
			y_max = maxf(y_max, p.y)
	if y_min == INF:
		return
	y_min = minf(y_min, 0.0)
	y_max = maxf(y_max, y_min + 1.0)
	var span := y_max - y_min
	# Value grid.
	for i in 5:
		var frac := i / 4.0
		var y := area.end.y - area.size.y * frac
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.08), 1.0)
		var text: String = formatter.call(y_min + span * frac) if formatter.is_valid() else str(roundi(y_min + span * frac))
		draw_string(font, Vector2(4.0, y + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, LEFT - 8.0, 10, Color(1, 1, 1, 0.55))
	if y_min < 0.0:
		var zero_y := area.end.y - area.size.y * (-y_min / span)
		draw_line(Vector2(area.position.x, zero_y), Vector2(area.end.x, zero_y), Color(1, 1, 1, 0.3), 1.0)
	draw_string(font, Vector2(area.position.x, size.y - 5.0), x_labels[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.55))
	draw_string(font, Vector2(area.end.x - 140.0, size.y - 5.0), x_labels[1], HORIZONTAL_ALIGNMENT_RIGHT, 140.0, 10, Color(1, 1, 1, 0.55))
	# Lines, the bold ones last so they sit on top.
	for pass_bold in [false, true]:
		for s in series:
			if bool(s.get("bold", false)) != pass_bold:
				continue
			var line := PackedVector2Array()
			for p: Vector2 in s.points:
				line.append(Vector2(area.position.x + area.size.x * p.x / x_max, area.end.y - area.size.y * (p.y - y_min) / span))
			if line.size() > 1:
				draw_polyline(line, s.color, 3.0 if pass_bold else 1.8, true)
			if line.size() > 0:
				draw_circle(line[line.size() - 1], 3.0 if pass_bold else 2.2, s.color)
	# Legend, right aligned on the title line.
	var x := size.x - RIGHT
	for i in range(series.size() - 1, -1, -1):
		var s: Dictionary = series[i]
		var w := font.get_string_size(s.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		x -= w
		draw_string(font, Vector2(x, 14.0), s.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, s.color)
		x -= 14.0
		draw_line(Vector2(x, 10.0), Vector2(x + 10.0, 10.0), s.color, 3.0)
		x -= 8.0
