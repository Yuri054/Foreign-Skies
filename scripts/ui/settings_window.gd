extends FloatingWindow
## Settings: the UI scale, a slider from 50% to 200% that resizes the whole interface (Ctrl and
## + or -, and Ctrl 0, do the same from the keyboard), and the sound. The choice is saved. Toggle with F10, or the gear
## at the right end of the top bar.

var _slider := HSlider.new()
var _scale_label := Label.new()
## True while the slider is held: the scale is applied on release, because the slider itself
## grows and shrinks with the scale and would run away from the pointer.
var _scale_held := false
var _note := Label.new()
var _army_view := OptionButton.new()
var _map_3d := CheckButton.new()
var _updating := false
## Whether the window offers a way back to the main menu (the menu's own copy does not).
var offer_quit_to_menu := true


func _ready() -> void:
	add_to_group("settings_window")
	visible = false
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var label := Label.new()
	label.text = "UI scale"
	box.add_child(label)
	var scale_row := HBoxContainer.new()
	_slider.min_value = UiSettings.MIN_SCALE
	_slider.max_value = UiSettings.MAX_SCALE
	_slider.step = UiSettings.SCALE_STEP
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.drag_started.connect(func() -> void: _scale_held = true)
	_slider.drag_ended.connect(func(_changed: bool) -> void:
		_scale_held = false
		UiSettings.set_scale(get_window(), _slider.value)
		_sync()
	)
	_slider.value_changed.connect(func(v: float) -> void:
		_scale_label.text = "%d%%" % roundi(v * 100.0)
		if not _updating and not _scale_held:
			UiSettings.set_scale(get_window(), v)
			_sync()
	)
	scale_row.add_child(_slider)
	_scale_label.custom_minimum_size = Vector2(44, 0)
	_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_row.add_child(_scale_label)
	box.add_child(scale_row)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(240, 0)
	_note.modulate = Fmt.DIM
	_note.text = "Makes every menu and the map larger or smaller. Ctrl and + or - change it from the keyboard, Ctrl 0 resets it."
	box.add_child(_note)

	var reset := Button.new()
	reset.text = "Reset to 100%"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		UiSettings.set_scale(get_window(), 1.0)
		_sync()
	)
	box.add_child(reset)

	var armies := Label.new()
	armies.text = "Armies on the map"
	box.add_child(armies)
	for view: String in UiSettings.ARMY_VIEWS:
		_army_view.add_item(UiSettings.ARMY_VIEWS[view])
		_army_view.set_item_metadata(_army_view.item_count - 1, view)
	_army_view.focus_mode = Control.FOCUS_NONE
	_army_view.tooltip_text = "Which armies the map shows banners for. Hidden armies still fight and are listed in the Military window."
	_army_view.item_selected.connect(func(i: int) -> void:
		if not _updating:
			UiSettings.set_army_view(_army_view.get_item_metadata(i))
			get_tree().call_group("army_layer", "queue_redraw")
	)
	box.add_child(_army_view)

	_map_3d.text = "3D map (V)"
	_map_3d.focus_mode = Control.FOCUS_NONE
	_map_3d.tooltip_text = "Shows the map in 3D, tilted under a perspective camera. Page Up and Page Down tilt it; the flat map is the default."
	_map_3d.toggled.connect(func(on: bool) -> void:
		if not _updating:
			for m in get_tree().get_nodes_in_group("map_3d"):
				m.set_enabled(on)
	)
	box.add_child(_map_3d)

	var sound := Label.new()
	sound.text = "Sound"
	box.add_child(sound)
	for bus: String in Audio.BUSES:
		box.add_child(_audio_row(bus))

	var saves := Button.new()
	saves.text = "Save and load… (F6)"
	saves.focus_mode = Control.FOCUS_NONE
	saves.pressed.connect(func() -> void: get_tree().call_group("save_window", "toggle"))
	box.add_child(saves)
	if offer_quit_to_menu:
		var quit := Button.new()
		quit.text = "Quit to menu"
		quit.focus_mode = Control.FOCUS_NONE
		quit.pressed.connect(func() -> void:
			GameState.autosave_enabled = false
			get_tree().change_scene_to_file.call_deferred("res://scenes/menu.tscn")
		)
		box.add_child(quit)
	setup_window("Settings", true, Vector2(300, 360), 3, true)
	fit_window(box.get_combined_minimum_size().y + 4.0)
	_sync()


## A bus's name, its volume slider and its mute box.
func _audio_row(bus: String) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = bus
	label.custom_minimum_size = Vector2(70, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Audio.volume(bus)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float) -> void: Audio.set_volume(bus, v))
	row.add_child(slider)
	var mute := CheckBox.new()
	mute.text = "Mute"
	mute.focus_mode = Control.FOCUS_NONE
	mute.button_pressed = Audio.is_muted(bus)
	mute.toggled.connect(func(on: bool) -> void: Audio.set_muted(bus, on))
	row.add_child(mute)
	return row


func toggle() -> void:
	visible = not visible
	if visible:
		_sync()


## Shows the scale in force.
func _sync() -> void:
	_updating = true
	for m in get_tree().get_nodes_in_group("map_3d"):
		_map_3d.button_pressed = m.enabled
	_slider.value = UiSettings.scale
	_scale_label.text = "%d%%" % roundi(UiSettings.scale * 100.0)
	for i in _army_view.item_count:
		if _army_view.get_item_metadata(i) == UiSettings.army_view:
			_army_view.select(i)
	_updating = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		toggle()
