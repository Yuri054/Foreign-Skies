extends FloatingWindow
## Settings. For now: the UI scale, which resizes the whole interface (Ctrl and + or -, and
## Ctrl 0, do the same from the keyboard). The choice is saved. Toggle with F10, or the gear
## at the right end of the top bar.

var _picker := OptionButton.new()
var _note := Label.new()
var _updating := false


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
	setup_window("Settings", true, Vector2(300, 190), 3, true)
	fit_window(box.get_combined_minimum_size().y + 4.0)
	_sync()


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
