extends Control
## The guided intro. About twelve short steps from data/tutorial.json; each shows a card, outlines
## the real control it is about, and finishes when the player does the thing (a command, a click,
## a window opened, a map mode picked, the game saved). It never blocks anything: the overlay lets
## every click through, the clock is not touched, any step can be skipped and the whole tutorial
## ended at any moment. It is offered once, after the first new game's nation is chosen (the
## answer is kept in the settings file), and can be started again from the main menu. It keeps
## nothing in the game state, so a half-done tutorial does not touch a save.

signal step_changed(index: int)
signal finished

const DATA := "res://data/tutorial.json"

## Set by the main menu's Tutorial button: the map starts the tutorial as soon as a nation is chosen.
static var requested := false

var steps: Array = []
var index := -1
var active := false
var map_view: Sprite2D
var camera: Camera2D

var _card := PanelContainer.new()
var _title := Label.new()
var _text := Label.new()
var _count := Label.new()
var _got_it := Button.new()
var _skip := Button.new()
var _offer_row := HBoxContainer.new()
var _step_row := HBoxContainer.new()
var _camera_start := Vector2.ZERO
var _zoom_start := Vector2.ONE
var _pulse := 0.0


func _ready() -> void:
	add_to_group("tutorial")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	steps = load_steps()

	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.offset_left = -390.0
	_card.offset_right = -12.0
	_card.offset_top = 46.0
	_card.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_card.add_child(box)
	_count.modulate = Fmt.DIM
	box.add_child(_count)
	_title.add_theme_font_size_override("font_size", 17)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(340, 0)
	box.add_child(_text)
	box.add_child(_step_row)
	box.add_child(_offer_row)
	_got_it.text = "Got it"
	_got_it.focus_mode = Control.FOCUS_NONE
	_got_it.pressed.connect(func() -> void: complete("ack"))
	_step_row.add_child(_got_it)
	_skip.text = "Skip step"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(skip_step)
	_step_row.add_child(_skip)
	var end := Button.new()
	end.text = "End tutorial"
	end.focus_mode = Control.FOCUS_NONE
	end.pressed.connect(end_tutorial)
	_step_row.add_child(end)
	for pair in [["Start the tutorial", start], ["No thanks", decline_offer]]:
		var b := Button.new()
		b.text = pair[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(pair[1])
		_offer_row.add_child(b)
	_step_row.visible = false
	_offer_row.visible = false

	GameState.command_issued.connect(func(type: String) -> void: complete("command", type))
	GameState.game_saved.connect(func(_p: String) -> void: complete("signal", "game_saved"))
	if map_view != null:
		_connect_map()


## Called by the map scene once it has set map_view and camera.
func _connect_map() -> void:
	map_view.province_selected.connect(func(_id: int) -> void: complete("signal", "province_selected"))
	map_view.mode_changed.connect(func(mode: int, _sub: String) -> void:
		complete("signal", "mode_changed")
		complete("mode", mode)
	)


static func load_steps() -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	return data.get("steps", []) if data is Dictionary else []


## Whether the tutorial has already been offered (and answered) on this computer.
static func was_offered() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(UiSettings.path) == OK and bool(cfg.get_value("tutorial", "offered", false))


static func mark_offered() -> void:
	var cfg := ConfigFile.new()
	cfg.load(UiSettings.path)
	cfg.set_value("tutorial", "offered", true)
	cfg.save(UiSettings.path)


## What the map scene does once the player has chosen a nation in a new game: start the tutorial
## if the menu asked for it, else offer it the first time.
func after_nation_chosen() -> void:
	if requested:
		requested = false
		mark_offered()
		start()
	elif not was_offered():
		offer()


func offer() -> void:
	visible = true
	_card.visible = true
	_count.text = "Tutorial"
	_title.text = "New to the game?"
	_text.text = "A short guided intro (about twelve steps) shows the map, the economy, armies, diplomacy, the navy and saving. You can skip any step, stop at any time, and start it again from the main menu."
	_step_row.visible = false
	_offer_row.visible = true


func decline_offer() -> void:
	mark_offered()
	visible = false
	_offer_row.visible = false


func start() -> void:
	mark_offered()
	_offer_row.visible = false
	active = true
	visible = true
	index = -1
	_advance(0)


func end_tutorial() -> void:
	active = false
	index = -1
	visible = false
	finished.emit()


func skip_step() -> void:
	if active:
		_advance(index + 1)


## The step on show, or {}.
func current() -> Dictionary:
	return steps[index] if active and index >= 0 and index < steps.size() else {}


func _advance(to: int) -> void:
	index = to
	# A step for something this nation cannot do is passed over.
	while index < steps.size() and not _possible(steps[index]):
		index += 1
	if index >= steps.size():
		_show_end()
		return
	var step: Dictionary = steps[index]
	_card.visible = true
	_count.text = "Tutorial: step %d of %d" % [index + 1, steps.size()]
	_title.text = step.title
	_text.text = step.text
	_step_row.visible = true
	_got_it.visible = step.done.has("ack")
	if camera != null:
		_camera_start = camera.position
		_zoom_start = camera.zoom
	step_changed.emit(index)
	queue_redraw()


func _possible(step: Dictionary) -> bool:
	if step.get("requires", "") == "fleet":
		for f: Fleet in GameState.fleets.values():
			if f.tag == GameState.player_tag:
				return true
		return false
	return true


func _show_end() -> void:
	active = false
	_count.text = "Tutorial complete"
	_title.text = "That's the tour"
	_text.text = "You know the basics. The tutorial can be replayed from the main menu."
	_step_row.visible = false
	_offer_row.visible = true
	for c in _offer_row.get_children():
		c.queue_free()
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void:
		visible = false
		finished.emit()
	)
	_offer_row.add_child(close)
	step_changed.emit(index)


## Something happened that may finish the step on show: the kind of thing and which one.
func complete(kind: String, what: Variant = null) -> void:
	var step := current()
	if step.is_empty():
		return
	var done: Dictionary = step.done
	var met := false
	match kind:
		"command":
			met = done.get("command", "") == what
		"signal":
			met = done.get("signal", "") == what
		"mode":
			met = done.has("mode") and MapView.Mode.keys()[what] in done.mode
		"window":
			met = done.get("window", "") == what
		"ack":
			met = done.has("ack")
	if met:
		_advance(index + 1)


func _process(delta: float) -> void:
	if not active:
		return
	_pulse += delta
	queue_redraw()
	var step := current()
	if step.is_empty():
		return
	if step.done.get("signal", "") == "camera" and camera != null:
		if camera.position.distance_to(_camera_start) > 30.0 / camera.zoom.x or not camera.zoom.is_equal_approx(_zoom_start):
			complete("signal", "camera")
	elif step.done.has("window"):
		var w := get_tree().get_first_node_in_group(step.done.window)
		if w != null and w.visible:
			complete("window", step.done.window)


# Highlight ------------------------------------------------------------------------------------

## The control a step points at, or null.
func target_of(step: Dictionary) -> Control:
	var spec: Dictionary = step.get("highlight", {})
	if spec.has("group"):
		var n := get_tree().get_first_node_in_group(spec.group)
		return n if n is Control and n.is_visible_in_tree() else null
	if spec.has("button"):
		return _find_button(get_tree().root, spec.button)
	return null


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree():
		return node
	for c in node.get_children():
		var found := _find_button(c, text)
		if found != null:
			return found
	return null


func _draw() -> void:
	var step := current()
	if step.is_empty():
		return
	var target := target_of(step)
	if target == null:
		return
	var rect := target.get_global_rect().grow(4.0)
	var pulse := 0.5 + 0.5 * sin(_pulse * 4.0)
	draw_rect(rect, Color(1.0, 0.85, 0.3, 0.12 + 0.1 * pulse), true)
	draw_rect(rect, Color(1.0, 0.85, 0.3, 0.6 + 0.4 * pulse), false, 2.0)


const MapView := preload("res://scripts/map/map_view.gd")
