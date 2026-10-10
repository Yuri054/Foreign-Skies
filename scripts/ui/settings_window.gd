extends FloatingWindow
## Settings. For now: the UI scale, which resizes the whole interface (Ctrl and + or -, and
## Ctrl 0, do the same from the keyboard). The choice is saved. Toggle with F10, or the gear
## at the right end of the top bar.

var _picker := OptionButton.new()
var _note := Label.new()
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
	_picker.focus_mode = Control.FOCUS_NONE
	for s: float in UiSettings.SCALES:
		_picker.add_item("%d%%" % roundi(s * 100.0))
		_picker.set_item_metadata(_picker.item_count - 1, s)
	_picker.item_selected.connect(func(i: int) -> void:
		if not _updating:
			UiSettings.set_scale(get_window(), _picker.get_item_metadata(i))
			_sync()
	)
	box.add_child(_picker)
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
	for i in _picker.item_count:
		if is_equal_approx(_picker.get_item_metadata(i), UiSettings.scale):
			_picker.select(i)
	_updating = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		toggle()
