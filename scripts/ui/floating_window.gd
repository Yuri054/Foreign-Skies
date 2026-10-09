class_name FloatingWindow
extends PanelContainer
## The frame every menu of the game sits in. A menu extends this class, builds its content
## as direct children the usual way, and ends its _ready with setup_window(): the frame then
## wraps that content under a title bar with Minimize and Close buttons. The window can be
## dragged by the title bar and resized by any edge or corner, comes to the front when
## clicked, and stays on screen. Double-clicking the title bar minimizes it too.
##
## `visible` is how a menu opens and closes, as before; closing with the X sets it and emits
## `closed`. A menu that must be answered (a decision) turns the X off with `closable`.

signal closed
signal minimized_changed(is_minimized: bool)

## Width of the border strip that grabs the mouse for resizing, and the size of the square at
## each corner that resizes both ways at once (it reaches into the content, and is checked
## before the content sees the mouse).
const EDGE := 6.0
const CORNER := 20.0
## Space kept clear above (the top bar) and below (the map mode bar) when fitting a window.
const TOP_CLEARANCE := 40.0
const BOTTOM_CLEARANCE := 120.0
## Height the title bar, margins and spacing add around the content.
const CHROME_HEIGHT := 64.0

var title := "":
	set(value):
		title = value
		_title_label.text = value
var minimized := false
## True once the player has dragged an edge: the window then keeps the size they gave it.
var user_sized := false
var closable := true:
	set(value):
		closable = value
		_close_button.disabled = not value
		_close_button.tooltip_text = "Close" if value else "This must be answered first"
var min_window_width := 240.0

var _title_label := Label.new()
var _min_button := Button.new()
var _close_button := Button.new()
var _bar := PanelContainer.new()
var _holder := MarginContainer.new()
var _grip_row := HBoxContainer.new()
var _grip := Control.new()
var _dragging := false
var _drag_offset := Vector2.ZERO
var _resize_edges := Vector2i.ZERO
var _resize_start_rect := Rect2()
var _resize_start_mouse := Vector2.ZERO
var _full_height := 0.0


## Wraps the content already added as children. `window_size` is the starting size (a height
## of 0 means "fit the content", see fit_window); `cascade` offsets the default place for each
## successive window; `centered` puts it in the middle of the screen instead of the top right.
func setup_window(p_title: String, p_closable := true, window_size := Vector2(420, 0), cascade := 0, centered := false, border := Color(0.3, 0.34, 0.42)) -> void:
	var content: Array[Node] = []
	for c in get_children():
		content.append(c)
		remove_child(c)

	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.1, 0.12, 0.16, 1.0)
	background.border_color = border
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	background.content_margin_left = EDGE
	background.content_margin_right = EDGE
	background.content_margin_top = EDGE
	background.content_margin_bottom = EDGE
	add_theme_stylebox_override("panel", background)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.16, 0.19, 0.25, 1.0)
	bar_style.set_corner_radius_all(3)
	bar_style.content_margin_left = 8
	bar_style.content_margin_right = 3
	bar_style.content_margin_top = 2
	bar_style.content_margin_bottom = 2
	_bar.add_theme_stylebox_override("panel", bar_style)
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_bar.gui_input.connect(_on_bar_input)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_bar.add_child(row)
	_title_label.text = p_title
	title = p_title
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.clip_text = true
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_title_label)
	for b: Button in [_min_button, _close_button]:
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(26, 22)
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
		row.add_child(b)
	_min_button.text = "–"
	_min_button.tooltip_text = "Minimize"
	_min_button.pressed.connect(toggle_minimized)
	_close_button.text = "X"
	_close_button.pressed.connect(close_window)
	closable = p_closable
	root.add_child(_bar)

	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_holder)
	for c in content:
		_holder.add_child(c)
	# A grip in the bottom right corner, drawn so it can be seen and grabbed.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grip_row.add_child(spacer)
	_grip.custom_minimum_size = Vector2(16, 14)
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_grip.tooltip_text = "Drag to resize"
	_grip.draw.connect(_draw_grip)
	_grip.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_start_resize(Vector2i(1, 1), event.global_position)
			_grip.accept_event()
	)
	_grip_row.add_child(_grip)
	root.add_child(_grip_row)

	# Free-floating: top left anchored, placed by position and size.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END
	var view := get_viewport_rect().size
	size = Vector2(maxf(maxf(window_size.x, min_window_width), get_combined_minimum_size().x), window_size.y if window_size.y > 0.0 else 420.0)
	if centered:
		position = ((view - size) * 0.5).round()
	else:
		position = Vector2(view.x - size.x - 16.0 - 36.0 * cascade, TOP_CLEARANCE + 12.0 + 30.0 * cascade)
	_clamp_to_view()
	get_viewport().size_changed.connect(_clamp_to_view)
	visibility_changed.connect(func() -> void:
		if visible:
			move_to_front()
			_clamp_to_view.call_deferred()
	)


## Fits the height to the content (the height of what the window holds, without the
## frame) unless the player has resized the window or it is minimized.
func fit_window(content_height: float) -> void:
	if user_sized or minimized or not is_inside_tree():
		return
	var view := get_viewport_rect().size
	var room := maxf(view.y - position.y - BOTTOM_CLEARANCE, 160.0)
	size.y = clampf(content_height + CHROME_HEIGHT, 140.0, room)
	# A window whose content needs more width than it was given must not hang off the screen.
	size.x = maxf(size.x, get_combined_minimum_size().x)
	position.x = minf(position.x, maxf(view.x - size.x - 8.0, 8.0))


func close_window() -> void:
	if not closable:
		return
	visible = false
	closed.emit()


func toggle_minimized() -> void:
	set_minimized(not minimized)


func set_minimized(value: bool) -> void:
	if value == minimized:
		return
	minimized = value
	if minimized:
		_full_height = size.y
		_holder.visible = false
		_grip_row.visible = false
		size.y = 0.0  # clamps to the title bar
	else:
		_holder.visible = true
		_grip_row.visible = true
		size.y = maxf(_full_height, get_combined_minimum_size().y)
		_clamp_to_view()
	_min_button.text = "+" if minimized else "–"
	_min_button.tooltip_text = "Restore" if minimized else "Minimize"
	minimized_changed.emit(minimized)


func _clamp_to_view() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	position.x = clampf(position.x, 40.0 - size.x, maxf(view.x - 40.0, 0.0))
	position.y = clampf(position.y, TOP_CLEARANCE - 4.0, maxf(view.y - 30.0, TOP_CLEARANCE))


# --- Dragging and resizing -----------------------------------------------------------------

func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			move_to_front()
			if event.double_click:
				toggle_minimized()
				return
			_dragging = true
			_drag_offset = event.global_position - global_position


## Which edges the point (in this control's space) is on: x -1 left, 1 right; y -1 top, 1 bottom.
## A corner counts as both of its edges. The bottom corners are a square reaching into the
## content; the top corners are only the L of border around them, so the title bar's
## buttons stay clickable.
func _edges_at(pos: Vector2) -> Vector2i:
	if pos.x < 0.0 or pos.y < 0.0 or pos.x > size.x or pos.y > size.y:
		return Vector2i.ZERO
	if pos.y >= size.y - CORNER:
		if pos.x <= CORNER:
			return Vector2i(-1, 1)
		if pos.x >= size.x - CORNER:
			return Vector2i(1, 1)
	var on_left := pos.x <= EDGE
	var on_right := pos.x >= size.x - EDGE
	var on_top := pos.y <= EDGE
	var on_bottom := pos.y >= size.y - EDGE
	if on_top and pos.x <= CORNER:
		return Vector2i(-1, -1)
	if on_top and pos.x >= size.x - CORNER:
		return Vector2i(1, -1)
	if pos.y <= CORNER and on_left:
		return Vector2i(-1, -1)
	if pos.y <= CORNER and on_right:
		return Vector2i(1, -1)
	return Vector2i(-1 if on_left else (1 if on_right else 0), -1 if on_top else (1 if on_bottom else 0))


func _get_cursor_shape(pos := Vector2.ZERO) -> Control.CursorShape:
	if minimized:
		return Control.CURSOR_ARROW
	var e := _edges_at(pos)
	if e == Vector2i.ZERO:
		return Control.CURSOR_ARROW
	if e.x != 0 and e.y != 0:
		return Control.CURSOR_FDIAGSIZE if e.x == e.y else Control.CURSOR_BDIAGSIZE
	return Control.CURSOR_HSIZE if e.x != 0 else Control.CURSOR_VSIZE


func _start_resize(edges: Vector2i, mouse: Vector2) -> void:
	move_to_front()
	_resize_edges = edges
	_resize_start_rect = Rect2(position, size)
	_resize_start_mouse = mouse


func _draw_grip() -> void:
	var c := Color(0.62, 0.68, 0.78, 0.9)
	var s := _grip.size
	for i in 3:
		var o := 4.0 + i * 4.0
		_grip.draw_line(Vector2(s.x - 1.0, s.y - o), Vector2(s.x - o, s.y - 1.0), c, 1.5)


## Whether no other window is in front of this one at a point.
func _topmost_at(point: Vector2) -> bool:
	var parent := get_parent()
	if parent == null:
		return true
	for i in range(get_index() + 1, parent.get_child_count()):
		var sibling := parent.get_child(i)
		if sibling is Control and sibling.visible and sibling.has_method("setup_window") and sibling.get_global_rect().has_point(point):
			return false
	return true


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_dragging = false
			_resize_edges = Vector2i.ZERO
		elif get_global_rect().has_point(event.position) and _topmost_at(event.position):
			# A click on the border or in a corner starts a resize, before the content sees it.
			var e := _edges_at(event.position - global_position)
			if e != Vector2i.ZERO and not minimized and not _bar.get_global_rect().has_point(event.position):
				_start_resize(e, event.position)
				get_viewport().set_input_as_handled()
			elif get_parent() != null and get_parent().get_child(get_parent().get_child_count() - 1) != self:
				# A click anywhere in the window brings it to the front.
				move_to_front()
	elif event is InputEventMouseMotion:
		if _dragging:
			position = event.position - _drag_offset
			_clamp_to_view()
			get_viewport().set_input_as_handled()
		elif _resize_edges != Vector2i.ZERO:
			_resize_to(event.position)
			get_viewport().set_input_as_handled()


func _resize_to(mouse: Vector2) -> void:
	var delta := mouse - _resize_start_mouse
	var rect := _resize_start_rect
	var min_size := get_combined_minimum_size()
	if _resize_edges.x == 1:
		rect.size.x = maxf(rect.size.x + delta.x, min_size.x)
	elif _resize_edges.x == -1:
		var new_w := maxf(rect.size.x - delta.x, min_size.x)
		rect.position.x += rect.size.x - new_w
		rect.size.x = new_w
	if _resize_edges.y == 1:
		rect.size.y = maxf(rect.size.y + delta.y, min_size.y)
	elif _resize_edges.y == -1:
		var new_h := maxf(rect.size.y - delta.y, min_size.y)
		rect.position.y += rect.size.y - new_h
		rect.size.y = new_h
	rect.position.y = maxf(rect.position.y, TOP_CLEARANCE - 4.0)
	position = rect.position
	size = rect.size
	user_sized = true
