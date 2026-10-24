extends CanvasLayer
## The pause menu (Esc): Resume, Save and load, Settings, Main menu, Quit. It stops the clock
## while it is open and puts it back as it was. It sits in a layer above the interface so it
## covers the windows, and first in the tree so that it sees an Esc last: a panel that uses Esc
## (clearing a selection) takes it first and marks it handled. It stays shut while the nation
## picker or a battle or peace screen is up.

const KEYS := "Move  WASD or arrow keys, wheel to zoom
Select  click · drag a box for several
Orders  right-click a province
Nation screen  N, with E B M Y F O R as its tabs
Command panel  C
Map modes  1 to 6 · 3D map  V
Time  Space pauses, + and - change speed
Settings  F10 · Save and load  F6 · Menu  Esc"

var _root := Control.new()
var _was_paused := false
var _open := false


func _ready() -> void:
	add_to_group("pause_menu")
	layer = 5
	_root.visible = false
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	# This layer sits outside the interface layer, which hands out the theme, so the panel takes the window's own.
	panel.theme = get_window().theme
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_button(box, "Resume", close)
	_button(box, "Save and load…", func() -> void:
		close()
		get_tree().call_group("save_window", "toggle")
	)
	_button(box, "Settings…", func() -> void:
		close()
		get_tree().call_group("settings_window", "toggle")
	)
	_button(box, "Main menu", to_main_menu)
	_button(box, "Quit", func() -> void: get_tree().quit())
	box.add_child(HSeparator.new())
	var keys := Label.new()
	keys.text = KEYS
	keys.modulate = Fmt.DIM
	box.add_child(keys)
	var note := Label.new()
	note.text = "Progress since the last save is lost when you leave."
	note.modulate = Fmt.DIM
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)


func _button(box: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	box.add_child(b)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_was_paused = Clock.paused
	Clock.paused = true
	_root.visible = true


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	Clock.paused = _was_paused


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func to_main_menu() -> void:
	_open = false
	GameState.autosave_enabled = false
	get_tree().change_scene_to_file.call_deferred("res://scenes/menu.tscn")


## Whether something else owns Esc right now.
func _busy() -> bool:
	if get_tree().get_first_node_in_group("nation_picker") != null:
		return true
	for group in ["battle_screen", "naval_battle_screen", "peace_screen"]:
		var node := get_tree().get_first_node_in_group(group)
		if node != null and node.visible:
			return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _open or not _busy():
			toggle()
			get_viewport().set_input_as_handled()
