class_name FocusPanel
extends FloatingWindow
## The national focus tree of the player's nation: a grid of foci joined by lines to the ones they
## need, the focus in hand with its progress, and the chosen focus's effects with a Start button.
## Open with the Focus button in the top bar, or O.

const CELL := Vector2(160, 70)
const GAP := Vector2(14, 22)

var _title := Label.new()
var _current := Label.new()
var _progress := ProgressBar.new()
var _canvas := Control.new()
var _detail := Label.new()
var _start := Button.new()
var _cancel := Button.new()
var _buttons: Dictionary = {}
var _selected := ""
var _tag := ""
var _dirty := true


func _ready() -> void:
	add_to_group("focus_panel")
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title.add_theme_font_size_override("font_size", 16)
	box.add_child(_title)
	_current.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_current.custom_minimum_size = Vector2(640, 0)
	box.add_child(_current)
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 8)
	box.add_child(_progress)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(700, 200)
	_canvas.draw.connect(_draw_links)
	scroll.add_child(_canvas)
	box.add_child(scroll)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(640, 56)
	box.add_child(_detail)
	var row := HBoxContainer.new()
	_start.text = "Start focus"
	_start.focus_mode = Control.FOCUS_NONE
	_start.pressed.connect(_on_start)
	row.add_child(_start)
	_cancel.text = "Drop current focus"
	_cancel.focus_mode = Control.FOCUS_NONE
	_cancel.tooltip_text = "Progress on it is lost."
	_cancel.pressed.connect(_on_cancel)
	row.add_child(_cancel)
	box.add_child(row)
	setup_window("National focus", true, Vector2(740, 480), 6)
	GameState.focus_changed.connect(func(_t: String) -> void: _mark())
	GameState.player_changed.connect(func(_t: String) -> void: _mark())
	GameState.scenario_loaded.connect(_mark)
	Clock.day_ticked.connect(_on_day)
	_refresh()


func _mark() -> void:
	_dirty = true
	if visible:
		_refresh()


func _on_day() -> void:
	if visible and GameState.nations.has(_tag) and not GameState.nations[_tag].focus.is_empty():
		_refresh()


func toggle() -> void:
	toggle_window()
	if visible:
		_refresh()


func select(id: String) -> void:
	_selected = id
	_refresh()


func _refresh() -> void:
	var tag: String = GameState.player_tag
	if not GameState.nations.has(tag):
		return
	if tag != _tag or _dirty:
		_rebuild(tag)
		_dirty = false
	var n: Nation = GameState.nations[tag]
	_title.text = "%s: national focus" % n.display_name
	if n.focus.is_empty():
		_current.text = "No focus in hand. %d of %d done." % [n.focus_done.size(), Focus.tree_of(tag).size()]
		_progress.value = 0.0
	else:
		var f := Focus.find(tag, n.focus.id)
		_current.text = "Working on: %s, %d days left. %d of %d done." % [f.name, n.focus.days_left, n.focus_done.size(), Focus.tree_of(tag).size()]
		_progress.max_value = n.focus.days_total
		_progress.value = n.focus.days_total - n.focus.days_left
	for id: String in _buttons:
		var b: Button = _buttons[id]
		var why := Focus.block(GameState, tag, id)
		b.modulate = Color.WHITE
		b.disabled = false
		match why:
			"done":
				b.modulate = Fmt.GOOD
			"active":
				b.modulate = Fmt.WARN
			"locked":
				b.modulate = Fmt.DIM
			"busy":
				b.modulate = Color(0.85, 0.85, 0.85)
		b.set_pressed_no_signal(id == _selected)
	_show_detail(tag, n)
	_canvas.queue_redraw()


func _rebuild(tag: String) -> void:
	_tag = tag
	for b: Button in _buttons.values():
		b.queue_free()
	_buttons.clear()
	var far := Vector2.ZERO
	for f: Dictionary in Focus.tree_of(tag):
		var b := Button.new()
		b.text = "%s\n%d days%s" % [f.name, int(f.days), " (repeatable)" if f.get("repeatable", false) else ""]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.position = Vector2(f.x * (CELL.x + GAP.x), f.y * (CELL.y + GAP.y))
		b.size = CELL
		b.tooltip_text = "%s\n%s" % [f.desc, Focus.effects_text(f.effects)]
		var id: String = f.id
		b.pressed.connect(func() -> void: select(id))
		_canvas.add_child(b)
		_buttons[id] = b
		far = far.max(b.position + CELL)
	_canvas.custom_minimum_size = far + Vector2(4, 4)
	if _selected not in _buttons:
		_selected = ""


func _show_detail(tag: String, n: Nation) -> void:
	_start.disabled = true
	_cancel.visible = not n.focus.is_empty()
	if _selected == "":
		_detail.text = "Pick a focus to see what it does."
		_start.text = "Start focus"
		return
	var f := Focus.find(tag, _selected)
	var why := Focus.block(GameState, tag, _selected)
	var lines: PackedStringArray = ["%s: %s" % [f.name, f.desc], "Effects: %s." % Focus.effects_text(f.effects)]
	var need: PackedStringArray = []
	for req: String in f.requires:
		if req not in n.focus_done:
			need.append(Focus.find(tag, req).name)
	match why:
		"done":
			lines.append("Done.")
		"active":
			lines.append("In hand.")
		"busy":
			lines.append("Finish or drop the focus in hand first.")
	if not need.is_empty():
		lines.append("Needs: %s." % ", ".join(need))
	_detail.text = "\n".join(lines)
	_start.text = "Start (%d days)" % int(f.days)
	_start.disabled = why != ""


func _draw_links() -> void:
	for f: Dictionary in Focus.tree_of(_tag):
		if not _buttons.has(f.id):
			continue
		var to: Button = _buttons[f.id]
		for req: String in f.requires:
			if not _buttons.has(req):
				continue
			var from: Button = _buttons[req]
			var a := from.position + Vector2(CELL.x * 0.5, CELL.y)
			var b := to.position + Vector2(CELL.x * 0.5, 0.0)
			var done: bool = req in GameState.nations[_tag].focus_done
			var mid := (a.y + b.y) * 0.5
			var colour: Color = Fmt.GOOD if done else Fmt.DIM
			_canvas.draw_polyline(PackedVector2Array([a, Vector2(a.x, mid), Vector2(b.x, mid), b]), colour, 2.0)


func _on_start() -> void:
	var cmd := SetFocus.new(GameState.player_tag, _selected)
	GameState.issue(cmd)
	_refresh()


func _on_cancel() -> void:
	GameState.issue(SetFocus.new(GameState.player_tag, ""))
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O and not event.ctrl_pressed:
		toggle()
