class_name Map3D
extends Node
## The map seen in 3D, as a mode that can be switched on and off (V). The map and everything drawn
## on it (borders, armies, fleets, cities, labels) are the ordinary 2D layers: while the mode is on
## they are moved into an off-screen viewport, 1.5 times the window, and that picture is laid on a
## flat plane that a perspective camera looks at. Looking straight down (90 degrees) it is the 2D
## map again; tilting it (Page Up and Page Down, Shift and the wheel, Ctrl and the middle button)
## brings the horizon into view, and [ and ] (or Ctrl and the middle button, moved sideways) turn it
## round. Panning and zooming go on as before: they move the 2D camera inside
## the picture. The mouse is followed through the plane: a click on it is turned into the click on
## the picture that lies under it, and sent to the layers, so selecting, ordering and box-selecting
## work unchanged (a click is followed down onto the raised ground, see `height_units`). The relief
## is real: data/map/relief.png (tools/build_relief.py) holds the ground's height, and the plane is
## raised by it (exaggerated, `RELIEF_EXAGGERATION`) and lit from the north west. The windows and the top bar stay on the screen as they are. Off, the layers go
## back to where they were.

signal toggled(on: bool)

## How many times the window's size the off-screen picture is (so that top-down it is sharp).
const SCALE := 1.5
const MAX_SIZE := Vector2i(3840, 2160)
const FOV := 50.0
const MIN_TILT := 35.0
const MAX_TILT := 90.0
const DEFAULT_TILT := 58.0
const TILT_STEP := 4.0
const YAW_STEP := 15.0
## The plane is this many units high; its width follows the picture's shape.
const PLANE_HEIGHT := 9.0
const SEA := Color(0.045, 0.065, 0.1)
## The relief picture: grey is the square root of the height, TOP_M metres at 255 (tools/build_relief.py).
const RELIEF_PATH := "res://data/map/relief.png"
const RELIEF_TOP_M := 3000.0
## How much taller than true the ground is drawn, and the most it may rise (plane units).
const RELIEF_EXAGGERATION := 16.0
const RELIEF_MAX := 1.0
const KM_PER_PX := 0.6928
## The land texture shows as if the flat map were zoomed in this far, while the 3D map is on.
const LAND_ZOOM_FLOOR := 0.65
const SELECT_COLOR := Color(1.0, 0.95, 0.4)
const BATTLE_COLOR := Color(0.95, 0.25, 0.2)
## Plane subdivisions: the ground is a grid of this many by this many squares.
const GRID := Vector2i(260, 146)

var enabled := false
## The angle of the camera above the horizon, in degrees: 90 looks straight down.
var tilt := DEFAULT_TILT
## How far the map is turned round, in degrees: 0 has north at the top of the screen.
var yaw := 0.0
var main: Node2D
var _sub: SubViewport
var _scene: Node3D
var _camera: Camera3D
var _plane_size := Vector2(16.0, PLANE_HEIGHT)
## The layers moved into the off-screen viewport and where each stood: [{node, index}].
var _moved: Array = []
var _tilting := false
var _last_mapped := Vector2(-1, -1)
var _material: ShaderMaterial
var _relief: Image
## Whether the ground is raised by its relief (off, the plane is flat).
var relief_on := true
## Whether armies and fleets stand up as small models (a pole with a flag, a little ship) on the map,
## not as the flat banners (which stay for the flat map).
var markers_on := true:
	set(value):
		markers_on = value
		_set_layers_to_markers(enabled and markers_on)
var _marker_root: Node3D
var _unit_mat: StandardMaterial3D
var _battle_mat: ShaderMaterial
var _sea_offsets := {}
var _last_cam_pos := Vector2.ZERO
var _last_cam_zoom := Vector2.ONE
var _touched := true
var _frame_count := 0
var _markers_dirty := true
var _city_signature: Array = []
var _marker_signature: Array = []
var _entries_cache: Array = []
## Whether armies and fleets stand as models of soldiers and ships once the map is close (else banners only).
var units_models_on := true
## The zoom at which the models start to come up, and at which they are whole.
const UNIT_ZOOM := [0.9, 1.6]
## Map pixels of the width of a formation, in model units: scales a model so that a formation is about this wide on the map.
const UNIT_SCALE := 7.0
## The same for a line of ships, which is much longer than a formation.
const FLEET_SCALE := 1.6
## Whether the cities stand up as models of buildings (see CityModels).
var cities_on := true:
	set(value):
		cities_on = value
		if _cities != null:
			_cities.visible = cities_on
		if _rails != null:
			_rails.visible = cities_on
		_set_city_markers(enabled and cities_on)
var _cities: CityModels
var _rails: RailLines
var _standees: Array = []
var _shown: Array = []
var _marker_frame := 0
## The part of the map the picture shows, in map pixels: where its top left is and how big it is.
var _view_origin := Vector2.ZERO
var _view_size := Vector2(1, 1)


func _ready() -> void:
	add_to_group("map_3d")


func toggle() -> void:
	set_enabled(not enabled)


func set_enabled(on: bool) -> void:
	if on == enabled or main == null:
		return
	if on:
		_enter()
	else:
		_leave()
	toggled.emit(enabled)


# ------------------------------------------------------------------ geometry (pure)

## Where a camera ray meets the flat plane (which lies in the XZ plane, `plane_size` units across),
## as a point of the picture from 0 to 1 on each side; (-1, -1) if it misses.
static func plane_hit(origin: Vector3, direction: Vector3, plane_size: Vector2, height := 0.0) -> Vector2:
	if absf(direction.y) < 0.00001:
		return Vector2(-1, -1)
	var t := (height - origin.y) / direction.y
	if t < 0.0:
		return Vector2(-1, -1)
	var p := origin + direction * t
	var uv := Vector2(p.x / plane_size.x + 0.5, p.z / plane_size.y + 0.5)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv


## The turn to give the panning keys so that "up" goes toward the top of a screen turned by `yaw` degrees.
static func pan_rotation_for(yaw_degrees: float) -> float:
	return -deg_to_rad(yaw_degrees)


## How far the camera stands from the plane's centre so that, looking straight down, the screen
## shows 1 / SCALE of the picture's height (one picture pixel to one screen pixel).
static func camera_distance(plane_height: float, scale := SCALE) -> float:
	return (plane_height / scale) / (2.0 * tan(deg_to_rad(FOV) / 2.0))


## The size of the off-screen picture for a window: SCALE times it, held to MAX_SIZE in the same shape.
static func picture_size(window: Vector2i, scale := SCALE) -> Vector2i:
	var size := Vector2(window) * scale
	var fit := minf(1.0, minf(float(MAX_SIZE.x) / size.x, float(MAX_SIZE.y) / size.y))
	return Vector2i((size * fit).round())


# ------------------------------------------------------------------ switching

func _enter() -> void:
	OS.low_processor_usage_mode = false     # the smoke and the sprites move by the clock of the shaders
	var window := get_window()
	_sub = SubViewport.new()
	_sub.size = picture_size(window.size, picture_scale())
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.handle_input_locally = true
	_sub.disable_3d = true
	add_child(_sub)
	_plane_size = Vector2(PLANE_HEIGHT * float(_sub.size.x) / float(_sub.size.y), PLANE_HEIGHT)
	_moved.clear()
	for child in main.get_children():
		if child is CanvasItem:
			_moved.append({"node": child, "index": child.get_index()})
	for entry in _moved:
		main.remove_child(entry.node)
		_sub.add_child(entry.node)
	var cam2d: Camera2D = main.get("camera")
	if cam2d != null:
		cam2d.make_current()
	_build_scene()
	enabled = true
	_set_layers_to_markers(markers_on)
	_watch_layers(true)
	_set_city_markers(cities_on)
	_set_land_floor(LAND_ZOOM_FLOOR)
	_apply_tilt()
	get_tree().call_group("event_feed", "say", "3D map on. Page Up and Page Down tilt it, [ and ] turn it, V goes back to the flat map.", Fmt.DIM)


func _leave() -> void:
	OS.low_processor_usage_mode = true
	_watch_layers(false)
	_set_layers_to_markers(false)
	_set_city_markers(false)
	_set_land_floor(0.0)
	enabled = false
	for entry in _moved:
		var node: Node = entry.node
		if node.get_parent() == _sub:
			_sub.remove_child(node)
		main.add_child(node)
		main.move_child(node, mini(entry.index, main.get_child_count() - 1))
	_moved.clear()
	var cam2d: Camera2D = main.get("camera")
	if cam2d != null:
		cam2d.make_current()
	if _scene != null:
		_scene.queue_free()
		_scene = null
	if _sub != null:
		_sub.queue_free()
		_sub = null
	_camera = null
	_material = null
	_marker_root = null
	_cities = null
	_rails = null
	_standees.clear()
	_shown.clear()
	_tilting = false
	var flat_cam: Camera2D = main.get("camera")
	if flat_cam != null:
		flat_cam.set("pan_rotation", 0.0)


func _build_scene() -> void:
	_scene = Node3D.new()
	add_child(_scene)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SEA
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.86, 0.95)
	env.ambient_light_energy = 0.75
	var world := WorldEnvironment.new()
	world.environment = env
	_scene.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.84)
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-52.0, -135.0, 0.0)
	_scene.add_child(sun)
	var mesh := PlaneMesh.new()
	mesh.size = _plane_size
	mesh.subdivide_width = GRID.x
	mesh.subdivide_depth = GRID.y
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D picture : source_color, filter_linear;
uniform sampler2D relief : hint_default_black, filter_linear, repeat_disable;
uniform vec2 view_origin;
uniform vec2 view_size;
uniform vec2 map_size;
// Plane units a relief metre rises (0 for a flat plane), and the metres a texel of the relief spans.
uniform float rise;
uniform float texel_m;
varying vec2 ground_uv;
float metres(vec2 uv) {
	float g = textureLod(relief, uv, 0.0).r;
	return g * g * 3000.0;
}
void vertex() {
	ground_uv = (view_origin + UV * view_size) / map_size;
	VERTEX.y += metres(ground_uv) * rise;
}
void fragment() {
	vec4 c = texture(picture, UV);
	vec2 e = 1.0 / vec2(textureSize(relief, 0));
	float dx = (metres(ground_uv + vec2(e.x, 0.0)) - metres(ground_uv - vec2(e.x, 0.0))) / (2.0 * texel_m);
	float dz = (metres(ground_uv + vec2(0.0, e.y)) - metres(ground_uv - vec2(0.0, e.y))) / (2.0 * texel_m);
	vec3 n = normalize(vec3(-dx * 3.5, 1.0, -dz * 3.5));
	vec3 light = normalize(vec3(-0.55, 0.85, -0.6));
	float shade = dot(n, light) - light.y;
	float lit = rise > 0.0 ? clamp(1.0 + shade * 0.8, 0.7, 1.3) : 1.0;
	// The edges of the picture melt into the background, so a tilt shows no hard border.
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	ALBEDO = c.rgb * lit;
	ALPHA = smoothstep(0.0, 0.05, edge);
}
"""
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("picture", _sub.get_texture())
	var tex: Texture2D = load(RELIEF_PATH)
	if tex != null:
		_material.set_shader_parameter("relief", tex)
		if _relief == null:
			_relief = tex.get_image()
		_material.set_shader_parameter("map_size", Vector2(MapData.map_size))
		_material.set_shader_parameter("texel_m", float(MapData.map_size.x) / float(tex.get_width()) * KM_PER_PX * 1000.0)
	var plane := MeshInstance3D.new()
	plane.mesh = mesh
	plane.material_override = _material
	_scene.add_child(plane)
	_cities = CityModels.new()
	_cities.visible = cities_on
	_scene.add_child(_cities)
	_rails = RailLines.new()
	_rails.visible = cities_on
	_scene.add_child(_rails)
	_marker_root = Node3D.new()
	_scene.add_child(_marker_root)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.near = 0.05
	_camera.far = 200.0
	_scene.add_child(_camera)
	_camera.make_current()


func _apply_tilt() -> void:
	if _camera == null:
		return
	tilt = clampf(tilt, MIN_TILT, MAX_TILT)
	yaw = wrapf(yaw, -180.0, 180.0)
	var d := camera_distance(PLANE_HEIGHT, picture_scale())
	var angle := deg_to_rad(tilt)
	var turn := deg_to_rad(yaw)
	var at := Vector3(0.0, sin(angle) * d, cos(angle) * d).rotated(Vector3.UP, turn)
	_camera.look_at_from_position(at, Vector3.ZERO, Vector3(0, 0, -1).rotated(Vector3.UP, turn))
	# The keys that pan the map go the way the screen's top points.
	var flat_cam: Camera2D = main.get("camera")
	if flat_cam != null:
		flat_cam.set("pan_rotation", pan_rotation_for(yaw))


## How many times the window the off-screen picture of the flat map is, by the quality chosen in the settings.
func picture_scale() -> float:
	return float(UiSettings.QUALITY_SCALES.get(UiSettings.quality_3d, SCALE))


## Sets the quality and, if the 3D map is on, rebuilds the picture at its size.
func apply_quality() -> void:
	if enabled:
		set_enabled(false)
		set_enabled(true)


## Whether the flat map's picture needs painting again this frame: every frame while the map is being moved,
## zoomed or touched, and otherwise ten times a second, enough for what moves by itself (armies, smoke, the clock).
func _picture_due() -> bool:
	var cam2d: Camera2D = main.get("camera")
	var moving := false
	if cam2d != null:
		moving = cam2d.position != _last_cam_pos or cam2d.zoom != _last_cam_zoom
		_last_cam_pos = cam2d.position
		_last_cam_zoom = cam2d.zoom
	var due := moving or _touched or _frame_count % 6 == 0
	_touched = false
	return due


func _input(event: InputEvent) -> void:
	if enabled and (event is InputEventMouse or event is InputEventKey):
		_touched = true


func _process(_delta: float) -> void:
	if not enabled or _sub == null or _material == null:
		return
	_frame_count += 1
	_sub.render_target_update_mode = SubViewport.UPDATE_ONCE if _picture_due() else SubViewport.UPDATE_DISABLED
	var inverse := _sub.get_canvas_transform().affine_inverse()
	_view_origin = inverse * Vector2.ZERO
	_view_size = inverse.basis_xform(Vector2(_sub.size))
	_material.set_shader_parameter("view_origin", _view_origin)
	_material.set_shader_parameter("view_size", _view_size)
	_material.set_shader_parameter("rise", rise_per_metre() if relief_on else 0.0)
	_marker_frame += 1
	if markers_on:
		_update_markers()
	if cities_on and _cities != null:
		# The models follow the ground as the camera moves; otherwise they need looking at only now and then
		# (a city grows or burns by the day, not by the frame).
		var cam: Camera2D = main.get("camera")
		var sig := [cam.position, cam.zoom, picture_scale(), tilt, yaw] if cam != null else []
		if sig != _city_signature or _frame_count % 15 == 0:
			_city_signature = sig
			_cities.update(self, cam.zoom.x if cam != null else 0.5)
			if _rails != null:
				_rails.update(self)


## Plane units a metre of height rises while the picture shows `_view_size` map pixels: true to
## scale, times RELIEF_EXAGGERATION, and held so that the highest ground (RELIEF_TOP_M) never rises
## more than RELIEF_MAX.
func rise_per_metre() -> float:
	var units_per_px := PLANE_HEIGHT / maxf(_view_size.y, 1.0)
	var per_metre := units_per_px / (KM_PER_PX * 1000.0) * RELIEF_EXAGGERATION
	return minf(per_metre, RELIEF_MAX / RELIEF_TOP_M)


## How many plane units a map pixel measures right now (it follows the zoom of the flat map).
func units_per_px() -> float:
	return PLANE_HEIGHT / maxf(_view_size.y, 1.0)


## How high the ground stands (plane units) at a point of the picture, 0 to 1 on each side.
func height_units(uv: Vector2) -> float:
	if not relief_on or _relief == null:
		return 0.0
	var at := (_view_origin + uv * _view_size) / Vector2(MapData.map_size)
	if at.x < 0.0 or at.y < 0.0 or at.x > 1.0 or at.y > 1.0:
		return 0.0
	var px := Vector2i(clampi(int(at.x * _relief.get_width()), 0, _relief.get_width() - 1), clampi(int(at.y * _relief.get_height()), 0, _relief.get_height() - 1))
	var g := _relief.get_pixelv(px).r
	return g * g * RELIEF_TOP_M * rise_per_metre()


# ------------------------------------------------------------------ unit models

func _set_land_floor(value: float) -> void:
	if main != null and main.get("map_view") != null:
		main.map_view.land_zoom_floor = value


## The flat diamonds of the cities give way to their models (the names stay).
func _set_city_markers(on: bool) -> void:
	var layer := _layer("city_layer")
	if layer != null:
		layer.set("markers_hidden", on)
		if not on:
			layer.set("skip_names", {})


func _layer(group: String) -> Node:
	return get_tree().get_first_node_in_group(group)


## The flat banners give way to listed markers while the models stand in their place.
func _set_layers_to_markers(on: bool) -> void:
	for group in ["army_layer", "fleet_layer"]:
		var layer := _layer(group)
		if layer != null:
			layer.set("markers_only", on)
	if not on and _marker_root != null:
		for s in _standees:
			s.visible = false
		_shown.clear()


## Everything the map has a model for: [{kind, pos (map pixels), tag, text, men, picked, fighting}].
func marker_entries() -> Array:
	var out: Array = []
	var armies := _layer("army_layer")
	if armies != null:
		for m: Dictionary in armies.collect_markers():
			var entry := m.duplicate()
			entry["kind"] = "army"
			out.append(entry)
	var fleets := _layer("fleet_layer")
	if fleets != null:
		for m: Dictionary in fleets.collect_markers():
			var entry := m.duplicate()
			entry["kind"] = "fleet"
			entry["guess"] = false
			out.append(entry)
	return out


## A model's height in plane units: bigger armies stand taller.
static func standee_height(kind: String, men: float) -> float:
	if kind == "fleet":
		return 0.16
	return 0.12 + 0.05 * log(1.0 + men / 1000.0) / log(10.0)


## Where a map position falls on the plane, at sea level (whether or not the picture shows it).
func plane_of(world: Vector2) -> Vector3:
	var at := (_sub.get_canvas_transform() * world) / Vector2(_sub.size)
	return Vector3((at.x - 0.5) * _plane_size.x, 0.0, (at.y - 0.5) * _plane_size.y)


## The size of the plane the picture is laid on.
func plane_extent() -> Vector2:
	return _plane_size


## The height of the ground at a map position, in metres (0 with the relief off).
func metres_at(world: Vector2) -> float:
	if not relief_on or _relief == null:
		return 0.0
	var at := world / Vector2(MapData.map_size)
	if at.x < 0.0 or at.y < 0.0 or at.x > 1.0 or at.y > 1.0:
		return 0.0
	var px := Vector2i(clampi(int(at.x * _relief.get_width()), 0, _relief.get_width() - 1), clampi(int(at.y * _relief.get_height()), 0, _relief.get_height() - 1))
	var g := _relief.get_pixelv(px).r
	return g * g * RELIEF_TOP_M


## Where a point of the 3D scene falls on the screen (far off it if it is behind the camera).
func screen_of(point: Vector3) -> Vector2:
	if _camera == null or _camera.is_position_behind(point):
		return Vector2(-100000, -100000)
	return _camera.unproject_position(point)


## Where a map position is in the 3D scene (on the ground), or null off the picture.
func ground_point(world: Vector2) -> Variant:
	if _sub == null:
		return null
	var at := (_sub.get_canvas_transform() * world) / Vector2(_sub.size)
	if at.x < -0.02 or at.x > 1.02 or at.y < -0.02 or at.y > 1.02:
		return null
	return Vector3((at.x - 0.5) * _plane_size.x, height_units(at), (at.y - 0.5) * _plane_size.y)


## The layers repaint when anything about their banners changes (armies, selection, zoom): then the list of
## markers is worked out again, and not before.
func _mark_markers_dirty() -> void:
	_markers_dirty = true


func _watch_layers(connect_them: bool) -> void:
	for group in ["army_layer", "fleet_layer"]:
		var layer := _layer(group)
		if layer == null:
			continue
		if connect_them and not layer.draw.is_connected(_mark_markers_dirty):
			layer.draw.connect(_mark_markers_dirty)
		elif not connect_them and layer.draw.is_connected(_mark_markers_dirty):
			layer.draw.disconnect(_mark_markers_dirty)
	_markers_dirty = true


func _update_markers() -> void:
	if _marker_root == null or _camera == null:
		return
	# Nothing to do while the layers have not changed and the picture has not moved.
	var cam2d: Camera2D = main.get("camera")
	var signature := [cam2d.position, cam2d.zoom, relief_on, units_models_on, _sub.size] if cam2d != null else []
	if not _markers_dirty and signature == _marker_signature:
		return
	_marker_signature = signature
	if _markers_dirty:
		_entries_cache = marker_entries()
		_markers_dirty = false
	var entries := _entries_cache
	_shown.clear()
	for entry: Dictionary in entries:
		var ground: Variant = ground_point(entry.pos)
		if ground == null:
			continue
		if _shown.size() >= 220:
			break
		entry["ground"] = ground
		_shown.append(entry)
	while _standees.size() < _shown.size():
		var node := _make_standee()
		_marker_root.add_child(node)
		_standees.append(node)
	for i in _standees.size():
		var node: Node3D = _standees[i]
		if i >= _shown.size():
			node.visible = false
			continue
		_set_standee(node, _shown[i])


func _make_standee() -> Node3D:
	var root := Node3D.new()
	var model := MeshInstance3D.new()
	model.name = "model"
	model.material_override = _unit_material()
	model.visible = false
	root.add_child(model)
	# The banner card: what the flat map draws for the same armies, painted once into a small picture
	# (a layer that paints one card) and stood up as a sprite that always faces the camera.
	# Where the men are fighting, smoke rises from the group (the same puffs as a burning city's).
	var battle := CityModels.make_smoke()
	battle.name = "battle"
	battle.material_override = _battle_material()
	var puffs := battle.multimesh
	puffs.instance_count = 24
	for i in 24:
		var at := Vector3(cos(i * 2.4) * 9.0, 2.0, sin(i * 2.4) * 9.0)
		puffs.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
		puffs.set_instance_custom_data(i, Color(float(i % 4) / 4.0 + float(i / 4) * 0.37, float(i), 0.0, 0.0))
	root.add_child(battle)
	var view := SubViewport.new()
	view.name = "card_view"
	view.size = Vector2i(ArmyLayer.CARD_SIZE)
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(view)
	var sprite := Sprite3D.new()
	sprite.name = "card"
	sprite.texture = view.get_texture()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.render_priority = 2
	sprite.transparent = true
	root.add_child(sprite)
	return root


## Where the water is from a place on the coast, as a step in map pixels (zero if the place is in the water already).
func _sea_offset(pos: Vector2) -> Vector2:
	var key := Vector2i(pos.round())
	if _sea_offsets.has(key):
		return _sea_offsets[key]
	var best := Vector2.ZERO
	if CityModels.land_at(pos):
		for r in [6.0, 12.0, 20.0, 30.0, 45.0]:
			for i in 16:
				var dir := Vector2.from_angle(TAU * i / 16.0)
				if not CityModels.land_at(pos + dir * r):
					best = dir * (r + 14.0)
					break
			if best != Vector2.ZERO:
				break
	_sea_offsets[key] = best
	return best


func _battle_material() -> ShaderMaterial:
	if _battle_mat == null:
		_battle_mat = CityModels.smoke_material(true)
		_battle_mat.set_shader_parameter("scale_mul", 0.45)
		_battle_mat.set_shader_parameter("rise_mul", 0.5)
		_battle_mat.set_shader_parameter("strength", 0.9)
	return _battle_mat


## The lit, vertex-coloured material every unit model shares.
func _unit_material() -> StandardMaterial3D:
	if _unit_mat == null:
		_unit_mat = StandardMaterial3D.new()
		_unit_mat.vertex_color_use_as_albedo = true
		_unit_mat.roughness = 0.9
		_unit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _unit_mat


## How far the models have come up as the map is brought close: 0 (only the banner) to 1 (the whole formation).
static func model_growth(zoom: float) -> float:
	var t := clampf((zoom - UNIT_ZOOM[0]) / (UNIT_ZOOM[1] - UNIT_ZOOM[0]), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _unit_mesh(entry: Dictionary, colour: Color) -> ArrayMesh:
	if entry.kind == "fleet":
		return UnitModels.fleet_mesh(UnitModels.fleet_line(entry.get("classes", {})), colour)
	return UnitModels.army_mesh(UnitModels.army_counts(entry.get("comp", {}), entry.men), colour)


func _set_standee(node: Node3D, entry: Dictionary) -> void:
	var tag: String = entry.tag
	var colour: Color = GameState.nations[tag].color
	var fleet: bool = entry.kind == "fleet"
	node.visible = true
	node.position = entry.ground
	var model: MeshInstance3D = node.get_node("model")
	var cam2d: Camera2D = main.get("camera")
	var zoom: float = cam2d.zoom.x if cam2d != null else 1.0
	var growth := model_growth(zoom) if units_models_on else 0.0
	model.visible = growth > 0.02
	var lift := 0.0
	if model.visible:
		var mesh := _unit_mesh(entry, colour)
		model.mesh = mesh
		var heading: Variant = entry.get("heading")
		if heading != null:
			model.rotation.y = -float(heading)      # a marching army faces the way it goes
		model.position = Vector3.ZERO
		if fleet:
			# A port is on the coast: the ships lie off it, in the water, the line along the shore.
			var off := _sea_offset(entry.pos)
			if off != Vector2.ZERO:
				var water: Variant = ground_point(entry.pos + off)
				if water != null:
					model.position = Vector3(water.x - entry.ground.x, water.y - entry.ground.y, water.z - entry.ground.z)
				model.rotation.y = -(off.angle() + PI * 0.5)
		var scale_by := units_per_px() * (FLEET_SCALE if fleet else UNIT_SCALE) * growth
		model.scale = Vector3.ONE * scale_by
		lift = mesh.get_aabb().end.y * scale_by
	var battle: MultiMeshInstance3D = node.get_node("battle")
	battle.visible = bool(entry.fighting) and model.visible
	battle.scale = Vector3.ONE * units_per_px() * (FLEET_SCALE if fleet else UNIT_SCALE) * growth
	# the card, as big on the screen as the flat map's banner: a card pixel is what a screen pixel is
	# worth in plane units, which is what a map pixel is worth over the zoom
	var sprite: Sprite3D = node.get_node("card")
	var per_pixel := units_per_px() / maxf(zoom, 0.05)
	sprite.pixel_size = per_pixel
	var banner: Rect2 = ArmyLayer.CARD_BANNER if not fleet else FleetLayer.CARD_BANNER
	sprite.offset = Vector2(0.0, ArmyLayer.CARD_SIZE.y * 0.5 - banner.get_center().y)
	var up := lift + banner.size.y * 0.5 * per_pixel + 0.01
	sprite.position = Vector3(0, up, 0)
	entry["anchor"] = entry.ground + Vector3(0, up, 0)
	var key := _card_key(entry)
	if node.get_meta("card_key", "") != key:
		node.set_meta("card_key", key)
		_paint_card(node, entry)


func _card_key(entry: Dictionary) -> String:
	var parts: Array = [entry.kind, entry.tag, roundi(entry.men / 100.0), entry.picked, entry.fighting, entry.guess, entry.get("name", ""),
			entry.get("icon", ""), entry.get("count", 0), entry.get("squadrons", 0), entry.get("fleets", 0), entry.get("mission", ""),
			entry.get("mixed", false), roundi(float(entry.get("aboard", 0.0)) / 1000.0), str(entry.get("comp", {})) if entry.get("expanded", false) else "",
			str(entry.get("shown_comp", {}))]
	return "|".join(PackedStringArray(parts.map(func(x: Variant) -> String: return str(x))))


## Repaints a standee's card picture from its marker.
func _paint_card(node: Node3D, entry: Dictionary) -> void:
	var view: SubViewport = node.get_node("card_view")
	var painter: Node2D = view.get_node_or_null("painter")
	var fleet: bool = entry.kind == "fleet"
	if painter != null and painter.get_meta("fleet", false) != fleet:
		painter.free()
		painter = null
	if painter == null:
		painter = (FleetLayer.new() if fleet else ArmyLayer.new())
		painter.name = "painter"
		painter.set("card_only", true)
		painter.set_meta("fleet", fleet)
		view.add_child(painter)
	painter.call("set_card", entry)
	view.render_target_update_mode = SubViewport.UPDATE_ONCE


## The model under a point of the screen, as its entry ({} if none): the click is then sent to the
## place the model stands, so a model is picked as its banner would be.
func marker_at(screen: Vector2) -> Dictionary:
	if _camera == null:
		return {}
	var best := {}
	var best_d := 26.0
	if cities_on and _cities != null:
		var found := _cities.city_at(self, screen)
		if not found.is_empty():
			best = found
			best_d = 12.0
	if not markers_on:
		return best
	for entry: Dictionary in _shown:
		var top: Vector3 = entry.get("anchor", entry.ground + Vector3(0, standee_height(entry.kind, entry.men) * 0.7, 0))
		if _camera.is_position_behind(top):
			continue
		var d := _camera.unproject_position(top).distance_to(screen)
		if d < best_d:
			best_d = d
			best = entry
	return best


## Where a point of the screen falls on the off-screen picture, in its pixels; (-1, -1) off it.
func to_picture(screen: Vector2) -> Vector2:
	if _camera == null or _sub == null:
		return Vector2(-1, -1)
	var origin := _camera.project_ray_origin(screen)
	var direction := _camera.project_ray_normal(screen)
	var uv := plane_hit(origin, direction, _plane_size)
	# Down onto the raised ground: the ray meets the surface where it is, not where the flat plane is.
	for i in 5:
		if uv.x < 0.0:
			return uv
		var next := plane_hit(origin, direction, _plane_size, height_units(uv))
		if next.x < 0.0 or next.distance_squared_to(uv) < 0.0000001:
			uv = next if next.x >= 0.0 else uv
			break
		uv = next
	return uv * Vector2(_sub.size)


# ------------------------------------------------------------------ input

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	if event.keycode == KEY_V:
		toggle()
		get_viewport().set_input_as_handled()
	elif enabled and event.keycode == KEY_PAGEUP:
		tilt += TILT_STEP
		_apply_tilt()
		get_viewport().set_input_as_handled()
	elif enabled and event.keycode == KEY_PAGEDOWN:
		tilt -= TILT_STEP
		_apply_tilt()
		get_viewport().set_input_as_handled()
	elif enabled and event.keycode == KEY_BRACKETLEFT:
		yaw -= YAW_STEP
		_apply_tilt()
		get_viewport().set_input_as_handled()
	elif enabled and event.keycode == KEY_BRACKETRIGHT:
		yaw += YAW_STEP
		_apply_tilt()
		get_viewport().set_input_as_handled()
	elif enabled and event.keycode == KEY_HOME:
		tilt = DEFAULT_TILT
		yaw = 0.0
		_apply_tilt()
		get_viewport().set_input_as_handled()


## What the interface did not use goes to the layers inside the picture, the mouse moved to where
## it lies on it.
func _unhandled_input(event: InputEvent) -> void:
	if not enabled or _sub == null:
		return
	if event is InputEventKey:
		_sub.push_input(event.duplicate())
		return
	if not (event is InputEventMouse):
		return
	if event is InputEventMouseButton:
		var wheel: bool = event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		if wheel and event.shift_pressed and event.pressed:
			tilt += TILT_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else -TILT_STEP
			_apply_tilt()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.ctrl_pressed:
			_tilting = event.pressed
			return
	if event is InputEventMouseMotion and _tilting:
		tilt = clampf(tilt - event.relative.y * 0.25, MIN_TILT, MAX_TILT)
		yaw += event.relative.x * 0.25
		_apply_tilt()
		return
	var at := to_picture(event.position)
	var model := marker_at(event.position)
	if not model.is_empty():
		at = _sub.get_canvas_transform() * (model.pos as Vector2)
	if at.x < 0.0:
		return
	var forwarded: InputEventMouse = event.duplicate()
	forwarded.position = at
	forwarded.global_position = at
	if forwarded is InputEventMouseMotion:
		forwarded.relative = at - _last_mapped if _last_mapped.x >= 0.0 else Vector2.ZERO
		forwarded.velocity = Vector2.ZERO
	_last_mapped = at
	_sub.push_input(forwarded)
