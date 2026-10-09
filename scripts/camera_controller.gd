extends Camera2D
## WASD / middle-mouse drag to pan, mouse wheel to zoom.

@export var pan_speed: float = 800.0
@export var zoom_step: float = 1.1
@export var min_zoom: float = 0.2
@export var max_zoom: float = 3.0

var _dragging := false


func _ready() -> void:
	add_to_group("camera_focus")


## Centres the view on a map position.
func focus_on(pos: Vector2) -> void:
	position = pos


func _process(delta: float) -> void:
	var dir := Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	position += dir * pan_speed * delta / zoom.x


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


func _set_zoom(value: float) -> void:
	var z := clampf(value, min_zoom, max_zoom)
	zoom = Vector2(z, z)
