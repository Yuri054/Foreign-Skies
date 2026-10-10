extends FloatingWindow
## Save and load. Type a name and press Save, or press Load on a game in the list. F5 saves to
## the "quicksave" slot and Shift+F5 loads it; F6 opens this window, as does the Settings window.
## The game also saves itself on the first of each month into three rotating "autosave" slots
## (GameState.autosave). Files are in user://saves/; rules in SaveGame.

var _name_edit := LineEdit.new()
var _list := VBoxContainer.new()
var _status := Label.new()


func _ready() -> void:
	add_to_group("save_window")
	visible = false
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var row := HBoxContainer.new()
	box.add_child(row)
	_name_edit.placeholder_text = "Name of the save"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t: String) -> void: _save_named())
	row.add_child(_name_edit)
	var save := Button.new()
	save.text = "Save"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save_named)
	row.add_child(save)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	box.add_child(scroll)

	_status.modulate = Fmt.DIM
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(300, 0)
	_status.text = "F5 quick save, Shift+F5 quick load."
	box.add_child(_status)
	setup_window("Save and load", true, Vector2(420, 380), 3, true)
	visibility_changed.connect(func() -> void:
		if visible:
			refresh()
	)


func toggle() -> void:
	visible = not visible


## Saves to a slot. Returns whether it worked, and says so.
func save_to(slot: String) -> bool:
	var err := GameState.save_game(slot_path(slot))
	_say("Saved %s." % slot if err.is_empty() else err, err.is_empty())
	if visible:
		refresh()
	return err.is_empty()


func load_from(slot: String) -> bool:
	var err := GameState.load_game(slot_path(slot))
	_say("Loaded %s." % slot if err.is_empty() else err, err.is_empty())
	return err.is_empty()


static func slot_path(slot: String) -> String:
	return SaveGame.dir + clean_name(slot) + SaveGame.EXT


## A file name from what the player typed.
static func clean_name(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		out += c if (c.is_valid_identifier() or c in " -.") and c != "/" else "_"
	return out.left(40) if not out.is_empty() else "save"


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var saves := SaveGame.list_saves()
	if saves.is_empty():
		var none := Label.new()
		none.text = "No saved games yet."
		none.modulate = Fmt.DIM
		_list.add_child(none)
	for s in saves:
		_list.add_child(_row(s))


func _row(s: Dictionary) -> Control:
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
	load_button.focus_mode = Control.FOCUS_NONE
	load_button.pressed.connect(func() -> void: load_from(s.file))
	row.add_child(load_button)
	var delete := Button.new()
	delete.text = "Delete"
	delete.focus_mode = Control.FOCUS_NONE
	delete.pressed.connect(func() -> void:
		DirAccess.remove_absolute(s.path)
		refresh()
	)
	row.add_child(delete)
	return row


func _save_named() -> void:
	save_to(clean_name(_name_edit.text) if not _name_edit.text.strip_edges().is_empty() else "save")
	_name_edit.text = ""


func _say(text: String, good: bool) -> void:
	_status.text = text
	_status.modulate = Fmt.GOOD if good else Fmt.WARN
	get_tree().call_group("event_feed", "say", text, Fmt.GOOD if good else Fmt.WARN)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F5:
		if event.shift_pressed:
			load_from("quicksave")
		else:
			save_to("quicksave")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F6:
		toggle()
		get_viewport().set_input_as_handled()
