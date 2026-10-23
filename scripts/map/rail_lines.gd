class_name RailLines
extends Node3D
## The railways on the 3D map: a line of track between each pair of neighbouring provinces that both have
## railway and one owner, following the ground. The mesh is built once in map pixels (heights in metres) and
## the node's scale puts it on the plane (pixels to plane units, metres to the relief's rise), so a moving
## camera moves it without building it again; it is built again when the railways change.

const STEP_PX := 9.0
const WIDTH_PX := 2.2
const LIFT_M := 60.0

var _mesh := MeshInstance3D.new()
var _material := ShaderMaterial.new()
var _dirty := true
var _built_relief := false


func _init() -> void:
	_material.shader = load("res://shaders/rails.gdshader")
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _ready() -> void:
	GameState.economy_updated.connect(func() -> void: _dirty = true)
	GameState.scenario_loaded.connect(func() -> void: _dirty = true)
	GameState.province_owner_changed.connect(func(_id: int, _a: String, _b: String) -> void: _dirty = true)


## Puts the lines where the map is now (`map` is the Map3D), building them first if the railways changed.
func update(map: Node) -> void:
	if _dirty or _built_relief != map.relief_on:
		_dirty = false
		_built_relief = map.relief_on
		_mesh.mesh = _build(map)
	var origin: Vector3 = map.plane_of(Vector2.ZERO)
	var per_px: float = map.units_per_px()
	position = origin
	_material.set_shader_parameter("half_extent", map.plane_extent() * 0.5)
	scale = Vector3(per_px, map.rise_per_metre() if map.relief_on else 0.0001, per_px)


func _build(map: Node) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for id in range(1, GameState.province_buildings.size()):
		var level: int = GameState.province_buildings[id].get("railway", 0)
		if level <= 0:
			continue
		for n: int in Military.neighbors(id):
			if n < id or GameState.province_buildings[n].get("railway", 0) <= 0 or GameState.province_owner[n] != GameState.province_owner[id]:
				continue
			var width := WIDTH_PX * (0.8 + 0.2 * minf(level, GameState.province_buildings[n].railway))
			_track(st, map, MapData.provinces[id].center, MapData.provinces[n].center, width)
			count += 1
	if count == 0:
		return ArrayMesh.new()
	return st.commit()


## One line of track from a to b, in short straight pieces that each rise or fall with the ground: a dark bed
## with a lighter line of rail down the middle.
func _track(st: SurfaceTool, map: Node, a: Vector2, b: Vector2, width: float) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) / STEP_PX))
	var side := (b - a).orthogonal().normalized() * width * 0.5
	var bed := Color(0.16, 0.14, 0.13)
	var rail := Color(0.62, 0.6, 0.58)
	var previous := a
	for i in range(1, steps + 1):
		var next := a.lerp(b, float(i) / steps)
		var y0: float = map.metres_at(previous) + LIFT_M
		var y1: float = map.metres_at(next) + LIFT_M
		CityParts.quad(st, Vector3(previous.x - side.x, y0, previous.y - side.y), Vector3(previous.x + side.x, y0, previous.y + side.y),
				Vector3(next.x + side.x, y1, next.y + side.y), Vector3(next.x - side.x, y1, next.y - side.y), bed)
		var thin := side * 0.28
		CityParts.quad(st, Vector3(previous.x - thin.x, y0 + 8.0, previous.y - thin.y), Vector3(previous.x + thin.x, y0 + 8.0, previous.y + thin.y),
				Vector3(next.x + thin.x, y1 + 8.0, next.y + thin.y), Vector3(next.x - thin.x, y1 + 8.0, next.y - thin.y), rail)
		previous = next
