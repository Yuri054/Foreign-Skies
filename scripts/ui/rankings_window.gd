extends FloatingWindow
## How the nations compare, in three views of one figure at a time: a bar Chart of every nation
## in order, a Table with all the figures side by side (click a heading to sort by it), and a
## Trend line chart of the leaders and you over the months. Pick the figure at the top; click a
## nation anywhere to see it in the country panel. Open with the Rankings button beside the
## settings gear, or R.

const TABLE_COLUMNS := ["population", "gdp", "income", "treasury", "army", "prestige", "provinces"]
const TREND_LEADERS := 5
const YOU_COLOR := Color(0.78, 0.88, 1.0)

var _metric := "population"
var _sort := "population"
var _picker := OptionButton.new()
var _summary := Label.new()
var _tabs := TabContainer.new()
var _chart_rows := VBoxContainer.new()
var _table := GridContainer.new()
var _trend := TrendChart.new()
var _trend_note := Label.new()
var _dirty := false


func _ready() -> void:
	add_to_group("rankings_window")
	visible = false

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var top := HBoxContainer.new()
	var label := Label.new()
	label.text = "Compare by"
	label.modulate = Fmt.DIM
	top.add_child(label)
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m: Dictionary in Standings.METRICS:
		_picker.add_item(m.label)
		_picker.set_item_metadata(_picker.item_count - 1, m.id)
		_picker.set_item_tooltip(_picker.item_count - 1, m.tip)
	_picker.item_selected.connect(func(i: int) -> void:
		_metric = _picker.get_item_metadata(i)
		_sort = _metric
		_refresh()
	)
	top.add_child(_picker)
	box.add_child(top)
	_summary.modulate = Fmt.DIM
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)

	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_tabs.add_child(_scrolled(_chart_rows, "Chart"))
	_table.columns = 2 + TABLE_COLUMNS.size()
	_table.add_theme_constant_override("h_separation", 8)
	_table.add_theme_constant_override("v_separation", 2)
	_tabs.add_child(_scrolled(_table, "Table"))
	var trend_box := VBoxContainer.new()
	trend_box.name = "Trend"
	_trend.custom_minimum_size = Vector2(0, 240)
	trend_box.add_child(_trend)
	_trend_note.modulate = Fmt.DIM
	_trend_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trend_note.custom_minimum_size = Vector2(280, 0)
	_trend_note.text = "The five leaders and your nation, a point for each month since the start."
	trend_box.add_child(_trend_note)
	_tabs.add_child(trend_box)
	_tabs.tab_changed.connect(func(_i: int) -> void: _refresh())
	_chart_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart_rows.add_theme_constant_override("separation", 2)

	setup_window("Rankings", true, Vector2(620, 470), 5)

	GameState.economy_updated.connect(_mark_dirty)
	GameState.player_changed.connect(func(_t: String) -> void: _mark_dirty())
	GameState.scenario_loaded.connect(_mark_dirty)
	_refresh()


func _scrolled(content: Control, tab_name: String) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(380, 160)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


## Shows a figure on its chart (used by tests and other windows).
func show_metric(id: String) -> void:
	for i in _picker.item_count:
		if _picker.get_item_metadata(i) == id:
			_picker.select(i)
			_metric = id
			_sort = id
	if visible:
		_refresh()


func _mark_dirty() -> void:
	if not visible or _dirty:
		return
	_dirty = true
	_refresh.call_deferred()


# --- Figures as text -----------------------------------------------------------------------

static func format_value(id: String, v: float) -> String:
	match Standings.metric(id).get("kind", ""):
		"people", "men":
			return Fmt.people(v)
		"money":
			return "£%.1fM" % v if absf(v) < 1000.0 else "£%.2fB" % (v / 1000.0)
	return "%d" % roundi(v)


## Short form for axis labels.
static func short_value(id: String, v: float) -> String:
	match Standings.metric(id).get("kind", ""):
		"people", "men":
			return Fmt.people(v)
		"money":
			return "£%dM" % roundi(v)
	return "%d" % roundi(v)


# --- Refresh -------------------------------------------------------------------------------

func _refresh() -> void:
	_dirty = false
	if not GameState.nations.has(GameState.player_tag):
		return
	var metric := Standings.metric(_metric)
	var ranking := Standings.ranking(GameState, _metric)
	var me := GameState.player_tag
	var mine := Standings.rank_of(GameState, me, _metric)
	_summary.text = "%s: you are #%d of %d (%s). %s leads with %s." % [
			metric.label, mine, ranking.size(), format_value(_metric, Standings.value(GameState, me, _metric)),
			GameState.nations[ranking[0].tag].display_name, format_value(_metric, ranking[0].value)] if not ranking.is_empty() else ""
	match _tabs.current_tab:
		0:
			_refresh_chart(ranking)
		1:
			_refresh_table()
		2:
			_refresh_trend(ranking)


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _refresh_chart(ranking: Array[Dictionary]) -> void:
	_clear(_chart_rows)
	var biggest := 0.0
	for r in ranking:
		biggest = maxf(biggest, absf(r.value))
	biggest = maxf(biggest, 0.0001)
	for i in ranking.size():
		var tag: String = ranking[i].tag
		var value: float = ranking[i].value
		var n: Nation = GameState.nations[tag]
		var row := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.26, 0.38, 0.8) if tag == GameState.player_tag else Color(0, 0, 0, 0)
		style.set_corner_radius_all(2)
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		row.add_theme_stylebox_override("panel", style)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.tooltip_text = "Show %s in the country panel" % n.display_name
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_show_nation(tag)
		)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var rank := Label.new()
		rank.text = "%d" % (i + 1)
		rank.modulate = Fmt.DIM
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rank.custom_minimum_size = Vector2(22, 0)
		h.add_child(rank)
		var flag := FlagIcon.new(tag)
		flag.custom_minimum_size = Vector2(30, 20)
		var flag_box := CenterContainer.new()
		flag_box.add_child(flag)
		h.add_child(flag_box)
		var name := Label.new()
		name.text = n.display_name
		name.clip_text = true
		name.custom_minimum_size = Vector2(140, 0)
		h.add_child(name)
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(60, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ratio := absf(value) / biggest
		var color := n.color.lightened(0.15) if value >= 0.0 else Fmt.BAD
		bar.draw.connect(func() -> void:
			bar.draw_rect(Rect2(0, 2, bar.size.x, 12), Color(1, 1, 1, 0.05))
			bar.draw_rect(Rect2(0, 2, maxf(bar.size.x * ratio, 2.0), 12), color)
		)
		h.add_child(bar)
		var number := Label.new()
		number.text = format_value(_metric, value)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		number.custom_minimum_size = Vector2(74, 0)
		number.modulate = Fmt.BAD if value < 0.0 else Color.WHITE
		h.add_child(number)
		row.add_child(h)
		_chart_rows.add_child(row)


func _refresh_table() -> void:
	_clear(_table)
	var head_rank := Label.new()
	head_rank.text = "#"
	head_rank.modulate = Fmt.DIM
	_table.add_child(head_rank)
	var head_name := Label.new()
	head_name.text = "Nation"
	head_name.modulate = Fmt.DIM
	head_name.custom_minimum_size = Vector2(130, 0)
	_table.add_child(head_name)
	for id: String in TABLE_COLUMNS:
		var b := Button.new()
		b.text = Standings.metric(id).label + (" ▾" if id == _sort else "")
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Sort by %s. %s" % [Standings.metric(id).label.to_lower(), Standings.metric(id).tip]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_sort = id
			_refresh()
		)
		_table.add_child(b)
	var ranking := Standings.ranking(GameState, _sort)
	for i in ranking.size():
		var tag: String = ranking[i].tag
		var n: Nation = GameState.nations[tag]
		var color := YOU_COLOR if tag == GameState.player_tag else Color.WHITE
		var rank := Label.new()
		rank.text = "%d" % (i + 1)
		rank.modulate = Fmt.DIM
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_table.add_child(rank)
		var link := Button.new()
		link.text = n.display_name
		link.flat = true
		link.alignment = HORIZONTAL_ALIGNMENT_LEFT
		link.focus_mode = Control.FOCUS_NONE
		link.clip_text = true
		link.modulate = color
		link.tooltip_text = "Show %s in the country panel" % n.display_name
		link.pressed.connect(func() -> void: _show_nation(tag))
		_table.add_child(link)
		for id: String in TABLE_COLUMNS:
			var v := Standings.value(GameState, tag, id)
			var cell := Label.new()
			cell.text = format_value(id, v)
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cell.modulate = Fmt.BAD if v < 0.0 else color
			_table.add_child(cell)


func _refresh_trend(ranking: Array[Dictionary]) -> void:
	var metric := Standings.metric(_metric)
	var picked: Array[String] = []
	for i in mini(TREND_LEADERS, ranking.size()):
		picked.append(ranking[i].tag)
	if GameState.player_tag not in picked:
		picked.append(GameState.player_tag)
	var series: Array = []
	var longest := 0
	for tag in picked:
		var points := Standings.series(GameState, tag, _metric)
		longest = maxi(longest, points.size())
		var n: Nation = GameState.nations[tag]
		series.append({"name": n.display_name, "color": n.color.lightened(0.25), "points": points, "bold": tag == GameState.player_tag})
	var history: Array = GameState.standings_history
	var labels: PackedStringArray = [history[0].date if not history.is_empty() else "", history[history.size() - 1].date if not history.is_empty() else ""]
	var message := ""
	if longest < 2:
		message = "The history fills in month by month: let some time pass."
	var fmt := func(v: float) -> String: return short_value(_metric, v)
	_trend.set_data(metric.label, series, fmt, labels, message)


func _show_nation(tag: String) -> void:
	get_tree().call_group("nation_stats", "show_nation", tag)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and not event.ctrl_pressed:
		toggle()
