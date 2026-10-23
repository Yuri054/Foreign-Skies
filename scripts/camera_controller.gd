extends Camera2D
## WASD / middle-mouse drag to pan, mouse wheel to zoom. The camera is kept on the map: its
## centre never goes so near an edge that the view would run past it (Camera2D's limits only
## hide the overshoot, and the position went on running away behind them, which is why the map
## seemed stuck at an edge).

@export var pan_speed: float = 800.0
@export var zoom_step: float = 1.1
@export var min_zoom: float = 0.2
@export var max_zoom: float = 3.0

## Turns the panning keys (radians), when the map is seen turned round (see Map3D).
var pan_rotation := 0.0
var _dragging := false


func _ready() -> void:
	add_to_group("camera_focus")
	get_viewport().size_changed.connect(keep_on_map)


## Centres the view on a map position.
func focus_on(pos: Vector2) -> void:
	position = pos
	keep_on_map()


## Pulls the centre back inside the area it may have: the map less half of what the view shows.
## A map smaller than the view (zoomed far out) is centred on that axis.
func keep_on_map() -> void:
	var half := get_viewport_rect().size / zoom / 2.0
	var lo := Vector2(limit_left, limit_top) + half
	var hi := Vector2(limit_right, limit_bottom) - half
	var x := (lo.x + hi.x) / 2.0 if lo.x > hi.x else clampf(position.x, lo.x, hi.x)
	var y := (lo.y + hi.y) / 2.0 if lo.y > hi.y else clampf(position.y, lo.y, hi.y)
	if x != position.x or y != position.y:
		position = Vector2(x, y)


func _process(delta: float) -> void:
	var dir := Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	if dir == Vector2.ZERO:
		return      # standing still: touch nothing, so the screen need not be drawn again
	position += dir.rotated(pan_rotation) * pan_speed * delta / zoom.x
	keep_on_map()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# The wheel belongs to a menu (or any other UI control) while the cursor is over one.
		var is_wheel: bool = event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		if is_wheel and get_viewport().gui_get_hovered_control() != null:
			return
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(zoom.x * zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(zoom.x / zoom_step)
			MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom.x
		keep_on_map()


## The furthest the map may be brought back: the zoom at which the whole map just fits the view
## (never above `min_zoom`, so a large window keeps its old limit).
func far_zoom() -> float:
	var map := Vector2(limit_right - limit_left, limit_bottom - limit_top)
	if map.x <= 0.0 or map.y <= 0.0:
		return min_zoom
	var size := get_viewport_rect().size
	return clampf(minf(size.x / map.x, size.y / map.y), 0.02, min_zoom)


func _set_zoom(value: float) -> void:
	var z := clampf(value, far_zoom(), max_zoom)
	zoom = Vector2(z, z)
	keep_on_map()
