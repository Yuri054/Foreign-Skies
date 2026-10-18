extends Control
## The start screen: New game, Continue, Load, Settings, Quit. New game lists the scenarios
## found under data/scenarios/ (see Scenarios) and, on Play, loads the chosen one and opens the
## map, which asks for a nation. Continue loads the newest save; Load lists them all. A loaded
## game opens on the map with its own nation (Scenarios.resume).

const MAIN_SCENE := "res://scenes/main.tscn"
const Tutorial := preload("res://scripts/ui/tutorial.gd")
const MenuBackdrop := preload("res://scripts/ui/menu_backdrop.gd")

var _box := VBoxContainer.new()
var _title := Label.new()
var _scenarios: Array[Dictionary] = []
var _scenario_list := ItemList.new()
var _blurb := Label.new()
var _status := Label.new()
var _continue := Button.new()
var _settings := preload("res://scripts/ui/settings_window.gd").new()
var _page := "main"
## Tests turn this off, so that starting or loading a game does not change the scene.
var opens_map := true


func _ready() -> void:
	add_to_group("main_menu")
	UiSettings.apply_saved(get_window())
	GameState.autosave_enabled = false
	Scenarios.resume = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color(0.07, 0.09, 0.12)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.clip_contents = true
	add_child(back)
	back.add_child(MenuBackdrop.new())
	# Darkest on the left, where the menu is, so the buttons read against the map.
	var shade := TextureRect.new()
	var fade := Gradient.new()
	fade.set_color(0, Color(0.03, 0.04, 0.07, 0.85))
	fade.set_color(1, Color(0.03, 0.04, 0.07, 0.0))
	fade.set_offset(0, 0.25)
	var ramp := GradientTexture2D.new()
	ramp.gradient = fade
	ramp.fill_from = Vector2(0, 0.5)
	ramp.fill_to = Vector2(1, 0.5)
	shade.texture = ramp
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", UiTheme.ornate(24.0))
	margin.add_child(panel)
	_box.custom_minimum_size = Vector2(420, 0)
	_box.add_theme_constant_override("separation", 10)
	panel.add_child(_box)

	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.76))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Fmt.DIM
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scenarios = Scenarios.list()
	_settings.offer_quit_to_menu = false
	add_child(_settings)
	show_page("main")


## Which page is showing: "main", "new" or "load".
func page() -> String:
	return _page


func show_page(page: String) -> void:
	_page = page
	for c in _box.get_children():
		_box.remove_child(c)
		if c != _title and c != _status:
			c.queue_free()
	_box.add_child(_title)
	match page:
		"new":
			_build_new()
		"load":
			_build_load()
		_:
			_build_main()
	_box.add_child(_status)


func _build_main() -> void:
	_title.text = "Europa: The Last Battle"
	var latest := latest_save()
	_continue = _button("Continue" if latest.is_empty() else "Continue: %s, %s" % [
			latest.header.get("nation", ""), latest.header.get("date", "")], continue_game)
	_continue.disabled = latest.is_empty()
	_button("New game", func() -> void: show_page("new"))
	_button("Load game", func() -> void: show_page("load"))
	_button("Tutorial", start_tutorial)
	_button("Settings", func() -> void: _settings.toggle())
	_button("Quit", func() -> void: get_tree().quit())
	_status.text = ""


func _build_new() -> void:
	_title.text = "New game"
	_scenario_list = ItemList.new()
	_scenario_list.custom_minimum_size = Vector2(0, 110)
	for s in _scenarios:
		var i := _scenario_list.add_item("%s  (%s)" % [s.name, s.start_date])
		_scenario_list.set_item_disabled(i, not s.playable)
		if _scenario_list.get_selected_items().is_empty() and s.playable:
			_scenario_list.select(i)
	_scenario_list.item_selected.connect(func(_i: int) -> void: _show_blurb())
	_scenario_list.item_activated.connect(func(_i: int) -> void: start_new())
	_box.add_child(_scenario_list)
	_blurb = Label.new()
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(0, 60)
	_box.add_child(_blurb)
	_show_blurb()
	_button("Play", start_new)
	_button("Back", func() -> void: show_page("main"))
	_status.text = ""


func _show_blurb() -> void:
	var s := selected_scenario()
	_blurb.text = "" if s.is_empty() else "%s\n%s" % [s.start_date, s.description]


func _build_load() -> void:
	_title.text = "Load game"
	var saves := SaveGame.list_saves()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_box.add_child(scroll)
	if saves.is_empty():
		var none := Label.new()
		none.text = "No saved games yet."
		none.modulate = Fmt.DIM
		list.add_child(none)
	for s in saves:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		var head: Dictionary = s.header
		if head.has("error"):
			label.text = "%s: %s" % [s.file, head.error]
			label.modulate = Fmt.WARN
		else:
			label.text = "%s\n%s, %s" % [s.file, head.get("nation", ""), head.get("date", "")]
		row.add_child(label)
		var load_button := Button.new()
		load_button.text = "Load"
		load_button.disabled = head.has("error")
		load_button.pressed.connect(func() -> void: load_save(s.path))
		row.add_child(load_button)
		list.add_child(row)
	_button("Back", func() -> void: show_page("main"))
	_status.text = ""


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	_box.add_child(b)
	return b


func selected_scenario() -> Dictionary:
	var sel := _scenario_list.get_selected_items()
	return {} if sel.is_empty() else _scenarios[sel[0]]


## The newest save that can be read, or {}.
func latest_save() -> Dictionary:
	for s in SaveGame.list_saves():
		if not s.header.has("error"):
			return s
	return {}


## Loads the chosen scenario and opens the map, where the nation is chosen.
func start_new(dir := "") -> void:
	if dir.is_empty():
		dir = selected_scenario().get("dir", "")
	if dir.is_empty():
		return
	GameState.load_scenario(dir)
	Scenarios.resume = false
	_open_map()


## A new game of the first scenario with the tutorial to follow the choice of a nation.
func start_tutorial() -> void:
	var first := _scenarios.filter(func(s: Dictionary) -> bool: return s.playable)
	if first.is_empty():
		return
	start_new(first[0].dir)
	Tutorial.requested = true


func continue_game() -> void:
	var latest := latest_save()
	if not latest.is_empty():
		load_save(latest.path)


## Loads a save and opens the map with the saved nation. Says what went wrong if it cannot.
func load_save(path: String) -> bool:
	var err := GameState.load_game(path)
	if not err.is_empty():
		_status.text = err
		_status.modulate = Fmt.WARN
		return false
	Scenarios.resume = true
	_open_map()
	return true


func _open_map() -> void:
	if not opens_map:
		return
	get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
