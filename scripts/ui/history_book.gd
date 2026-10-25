extends FloatingWindow
## The history book: what has happened in the run, written up. A page of the Nation screen (H) with tabs for the
## Timeline (a year at a time, with its headline figures and each month's headline), the Wars, the Map (who holds
## what now, and every change of owner), the Nations (how each stands against the start) and Export (Markdown or
## HTML on disk, or the Markdown to the clipboard). It reads GameState through History and changes nothing.

var _tabs := TabContainer.new()
var _year := OptionButton.new()
var _summary := Label.new()
var _timeline := VBoxContainer.new()
var _wars := VBoxContainer.new()
var _map_picture := TextureRect.new()
var _territory := Label.new()
var _nations := GridContainer.new()
var _export_status := Label.new()
var _updating := false


func _ready() -> void:
	add_to_group("history_book")
	visible = false
	_tabs.custom_minimum_size = Vector2(520, 380)
	add_child(_tabs)

	var timeline_page := VBoxContainer.new()
	timeline_page.name = "Timeline"
	var top := HBoxContainer.new()
	var label := Label.new()
	label.text = "Year"
	label.modulate = Fmt.DIM
	top.add_child(label)
	_year.focus_mode = Control.FOCUS_NONE
	_year.item_selected.connect(func(_i: int) -> void: _fill_timeline())
	top.add_child(_year)
	timeline_page.add_child(top)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.modulate = Fmt.DIM
	_summary.custom_minimum_size = Vector2(440, 0)
	timeline_page.add_child(_summary)
	timeline_page.add_child(_scrolled(_timeline))
	_tabs.add_child(timeline_page)

	var wars_page := _scrolled(_wars)
	wars_page.name = "Wars"
	_tabs.add_child(wars_page)

	var map_page := VBoxContainer.new()
	map_page.name = "Map"
	_map_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_picture.custom_minimum_size = Vector2(0, 170)
	map_page.add_child(_map_picture)
	_territory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_territory.custom_minimum_size = Vector2(440, 0)
	map_page.add_child(_scrolled(_territory))
	_tabs.add_child(map_page)

	_nations.columns = 4
	_nations.add_theme_constant_override("h_separation", 16)
	var nations_page := _scrolled(_nations)
	nations_page.name = "Nations"
	_tabs.add_child(nations_page)

	var export_page := VBoxContainer.new()
	export_page.name = "Export"
	export_page.add_theme_constant_override("separation", 8)
	var about := Label.new()
	about.text = "Write the whole history of this run out as a document: every year, the wars, the changes of the map and how the nations stand."
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(440, 0)
	export_page.add_child(about)
	export_page.add_child(_button("Export as Markdown", "Saves a .md file under the game's history folder.", func() -> void: _export("md")))
	export_page.add_child(_button("Export as a web page", "Saves an .html file with the map of the end inside it.", func() -> void: _export("html")))
	export_page.add_child(_button("Copy Markdown to the clipboard", "Puts the whole book on the clipboard as Markdown text.", _copy))
	_export_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_export_status.custom_minimum_size = Vector2(440, 0)
	_export_status.modulate = Fmt.DIM
	export_page.add_child(_export_status)
	_tabs.add_child(export_page)

	_tabs.tab_changed.connect(func(_i: int) -> void: _refresh())
	setup_window("History", true, Vector2(560, 0), 6)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh()
	)
	GameState.scenario_loaded.connect(func() -> void: _export_status.text = "")


func _scrolled(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.custom_minimum_size = Vector2(460, 240)
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


func _button(text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


func _line(text: String, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = color
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	return l


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## Shows what is true now on the tab that is open.
func _refresh() -> void:
	if not visible:
		return
	match _tabs.get_current_tab_control().name:
		"Timeline":
			_fill_years()
			_fill_timeline()
		"Wars":
			_fill_wars()
		"Map":
			_fill_map()
		"Nations":
			_fill_nations()


func _fill_years() -> void:
	var years := History.years(GameState)
	var keep := _year.selected
	_updating = true
	_year.clear()
	for y in years:
		_year.add_item(str(y))
		_year.set_item_metadata(_year.item_count - 1, y)
	_year.select(clampi(keep if keep >= 0 else years.size() - 1, 0, maxi(years.size() - 1, 0)))
	_updating = false


func _fill_timeline() -> void:
	if _updating or _year.item_count == 0:
		return
	var y: int = _year.get_item_metadata(_year.selected)
	_summary.text = History.year_summary(GameState, y)
	_clear(_timeline)
	var entries := History.timeline(GameState, y)
	if entries.is_empty():
		_timeline.add_child(_line("Nothing has been written down for %d yet." % y, Fmt.DIM))
	var last_month := ""
	for e: Dictionary in entries:
		var month: String = str(e.date).get_slice(" ", 1)
		if month != last_month:
			last_month = month
			var number := 1 + Clock.MONTH_NAMES.find(month)
			var head := _line("%s: %s" % [month, History.headline(GameState, y, number)], Color(0.75, 0.82, 0.95))
			_timeline.add_child(head)
		var color := Fmt.BAD if e.kind in ["war", "collapse"] else (Fmt.GOOD if e.kind == "peace" else Color.WHITE)
		var line := _line("%s  %s" % [e.date, e.text], color)
		line.tooltip_text = History.KINDS.get(e.kind, e.kind)
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		_timeline.add_child(line)


func _fill_wars() -> void:
	_clear(_wars)
	var wars := History.wars_section(GameState)
	if wars.is_empty():
		_wars.add_child(_line("No war has been fought.", Fmt.GOOD))
	for w: Dictionary in wars:
		_wars.add_child(_line(w.title, Color(0.75, 0.82, 0.95)))
		for l in w.lines:
			_wars.add_child(_line("  " + l, Fmt.DIM))


func _fill_map() -> void:
	_map_picture.texture = ImageTexture.create_from_image(History.map_image(GameState, 12))
	var lines := History.territory_lines(GameState)
	_territory.text = "\n".join(lines) if not lines.is_empty() else "No province has changed hands."


func _fill_nations() -> void:
	_clear(_nations)
	for h in ["Nation", "Provinces", "People", "Industry"]:
		var l := _line(h, Fmt.DIM)
		l.custom_minimum_size = Vector2(0, 0)
		_nations.add_child(l)
	for n: Dictionary in History.nations_section(GameState):
		var cells := [n.name, "%d (%+d)" % [n.provinces, n.d_provinces], "%s (%s)" % [Fmt.people(n.population), History._signed_people(n.d_population)], "%.1f (%+.1f)" % [n.industry, n.d_industry]]
		for c in cells:
			var l := _line(c)
			l.custom_minimum_size = Vector2(0, 0)
			_nations.add_child(l)


func _export(extension: String) -> void:
	var path := History.export(GameState, extension)
	if path == "":
		_export_status.text = "Could not write the file."
		_export_status.modulate = Fmt.BAD
	else:
		_export_status.text = "Saved to %s" % ProjectSettings.globalize_path(path)
		_export_status.modulate = Fmt.GOOD


func _copy() -> void:
	DisplayServer.clipboard_set(History.markdown(GameState))
	_export_status.text = "The book is on the clipboard."
	_export_status.modulate = Fmt.GOOD
