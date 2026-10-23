class_name CityModels
extends Node3D
## The cities of the 3D map as small models of buildings, one per city of the scenario (cities.tsv).
## A city's size follows its people (Cities.population): the footprint grows with the square root of the
## population, and so do the number of buildings and how tall the middle of town is; towns have
## houses and a church spire, great cities blocks, cathedrals and towers, a capital a gilded dome, and a
## city in a province with factories has chimneys. The models are built from the city's number
## (the same city always looks the same), rebuilt when its people have grown or shrunk enough to
## show, and carry a flag in the colour of whoever holds the city. They stand on the ground where
## Map3D.ground_point puts the city, and are drawn only once the map is close enough for their rank.

## The most buildings one model may have.
const MAX_BUILDINGS := 240
## The zoom at which each rank of city appears (as in CityLayer).
const MIN_ZOOM := {1: 0.0, 2: 0.25, 3: 0.55}
const WALLS := [Color(0.86, 0.8, 0.66), Color(0.68, 0.45, 0.35), Color(0.72, 0.7, 0.66), Color(0.82, 0.68, 0.46), Color(0.78, 0.74, 0.62)]
const ROOFS := [Color(0.62, 0.27, 0.2), Color(0.3, 0.32, 0.36), Color(0.46, 0.34, 0.27), Color(0.55, 0.3, 0.22)]
const STONE := Color(0.62, 0.6, 0.56)
const GOLD := Color(0.9, 0.74, 0.3)
const BRICK := Color(0.4, 0.22, 0.18)

var _entries := {}
var _material: StandardMaterial3D
var _flag_mesh: QuadMesh
var _frame := 0


func _init() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.9
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flag_mesh = QuadMesh.new()
	_flag_mesh.size = Vector2(0.1, 0.06)


# ------------------------------------------------------------------ the model of one city (pure)

## The footprint radius of a city's model, in plane units at its base scale.
static func radius_for(pop: int) -> float:
	return clampf(0.1 + 0.32 * sqrt(float(pop) / 1000000.0), 0.1, 0.5)


## The size class of a population, steps of about a sixth of a percent change... small enough to
## follow growth, coarse enough that the model is not rebuilt every month.
static func bucket_of(pop: int) -> int:
	return int(log(maxf(float(pop), 1000.0) / 1000.0) * 7.0)


## How many buildings a city of this many people has (before the density of the edges thins them out).
static func building_target(pop: int) -> int:
	return mini(MAX_BUILDINGS, int(10.0 + 130.0 * sqrt(float(pop) / 1000000.0)))


## Builds the mesh of a city: {mesh, buildings, height} (height: the tallest roof, plane units).
static func build(city_id: int, pop: int, chimneys: int, capital: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = city_id * 7919 + 17
	var pf := sqrt(float(pop) / 1000000.0)
	var radius := radius_for(pop)
	var cell := 0.03 + 0.014 * pf
	var turn := rng.randf() * PI
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_disc(st, radius * 0.97, 0.006, Color(0.56, 0.51, 0.42))
	var target := building_target(pop)
	var span := int(ceil(radius / cell)) + 1
	var spots: Array[Vector3] = []     # x, z, closeness to the middle (0 to 1)
	for i in range(-span, span + 1):
		for j in range(-span, span + 1):
			if i % 5 == 0 or j % 5 == 0:
				continue      # streets and squares
			var p := Vector2(i * cell, j * cell).rotated(turn) + Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)) * cell
			var d := p.length() / radius
			if d > 1.0:
				continue
			if rng.randf() < pow(d, 2.0) * 0.55:
				continue      # the edges thin out
			spots.append(Vector3(p.x, p.y, 1.0 - d))
	# the closest to the middle first, so a cap on the count thins the edges
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
	var count := 0
	var tallest := 0.0
	var hmax := clampf(0.05 + 0.1 * pf, 0.05, 0.16)
	for s in spots:
		if count >= target:
			break
		var core: float = s.z
		var size := cell * rng.randf_range(0.75, 0.98)
		var walls: Color = WALLS[rng.randi() % WALLS.size()].lightened(rng.randf_range(-0.06, 0.08))
		var roof: Color = ROOFS[rng.randi() % ROOFS.size()].lightened(rng.randf_range(-0.05, 0.06))
		var height: float
		if core > 0.55 and pf > 0.25 and rng.randf() < core:
			height = (0.035 + hmax * pow(core, 1.5)) * rng.randf_range(0.7, 1.0)
			_box(st, Vector3(s.x, -0.008, s.y), Vector3(size * 1.05, height, size * 1.05), walls)
			_slab_roof(st, Vector3(s.x, -0.008 + height, s.y), Vector3(size * 1.05, 0.004, size * 1.05), roof.darkened(0.2))
		else:
			height = rng.randf_range(0.018, 0.03) + 0.012 * core
			_box(st, Vector3(s.x, -0.008, s.y), Vector3(size, height, size * rng.randf_range(0.8, 1.2)), walls)
			_gable(st, Vector3(s.x, -0.008 + height, s.y), Vector3(size * 1.08, height * 0.55, size * 1.1), roof, rng.randf() < 0.5)
			height *= 1.5
		tallest = maxf(tallest, height)
		count += 1
	# landmarks: a church for every town, a cathedral with twin towers for a great city
	if pop >= 15000:
		var at := Vector3(rng.randf_range(-0.25, 0.25) * radius, 0.003, rng.randf_range(-0.25, 0.25) * radius)
		var church := 0.04 + 0.03 * pf
		_box(st, at, Vector3(0.03 + 0.02 * pf, church, 0.03 + 0.02 * pf), STONE)
		_cone(st, at + Vector3(0, church, 0), 0.016 + 0.01 * pf, 0.05 + 0.05 * pf, Color(0.35, 0.42, 0.45))
		tallest = maxf(tallest, church + 0.05 + 0.05 * pf)
		if pop >= 250000:
			var at2 := at + Vector3(0.07 + 0.03 * pf, 0, 0.05)
			_box(st, at2, Vector3(0.024, church * 0.9, 0.024), STONE)
			_cone(st, at2 + Vector3(0, church * 0.9, 0), 0.014, 0.07, Color(0.35, 0.42, 0.45))
	if capital:
		var dome_at := Vector3(0.12 * radius, 0.003, -0.15 * radius)
		var base_h := 0.05 + 0.03 * pf
		_box(st, dome_at, Vector3(0.07, base_h, 0.07), STONE.lightened(0.1))
		_cylinder(st, dome_at + Vector3(0, base_h, 0), 0.032, 0.03, GOLD.darkened(0.15))
		_cone(st, dome_at + Vector3(0, base_h + 0.03, 0), 0.034, 0.05, GOLD)
		tallest = maxf(tallest, base_h + 0.08)
	for k in chimneys:
		var a := rng.randf() * TAU
		var r := radius * rng.randf_range(0.5, 0.95)
		var h := rng.randf_range(0.07, 0.12)
		var at := Vector3(cos(a) * r, 0.003, sin(a) * r)
		_box(st, at, Vector3(0.026, 0.03, 0.026), BRICK.lightened(0.1))
		_cylinder(st, at + Vector3(0, 0.03, 0), 0.007, h, BRICK)
		tallest = maxf(tallest, 0.03 + h)
	return {"mesh": st.commit(), "buildings": count, "height": tallest}


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(st, a, b, c, color)
	_tri(st, a, c, d, color)


## A box standing on `base` (the middle of its foot), `size` wide, tall and deep.
static func _box(st: SurfaceTool, base: Vector3, size: Vector3, color: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := base.y
	var y1 := base.y + size.y
	var p000 := Vector3(base.x - hx, y0, base.z - hz)
	var p100 := Vector3(base.x + hx, y0, base.z - hz)
	var p101 := Vector3(base.x + hx, y0, base.z + hz)
	var p001 := Vector3(base.x - hx, y0, base.z + hz)
	var q000 := Vector3(base.x - hx, y1, base.z - hz)
	var q100 := Vector3(base.x + hx, y1, base.z - hz)
	var q101 := Vector3(base.x + hx, y1, base.z + hz)
	var q001 := Vector3(base.x - hx, y1, base.z + hz)
	_quad(st, p001, p101, q101, q001, color)                      # south
	_quad(st, p100, p000, q000, q100, color.darkened(0.08))       # north
	_quad(st, p101, p100, q100, q101, color.darkened(0.04))       # east
	_quad(st, p000, p001, q001, q000, color.darkened(0.12))       # west
	_quad(st, q001, q101, q100, q000, color.lightened(0.05))      # top


## A pitched roof on a house: `size.y` is the ridge's rise, the ridge along x or z.
static func _gable(st: SurfaceTool, base: Vector3, size: Vector3, color: Color, along_x: bool) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var top := base.y + size.y
	var a := Vector3(base.x - hx, base.y, base.z - hz)
	var b := Vector3(base.x + hx, base.y, base.z - hz)
	var c := Vector3(base.x + hx, base.y, base.z + hz)
	var d := Vector3(base.x - hx, base.y, base.z + hz)
	if along_x:
		var r0 := Vector3(base.x - hx, top, base.z)
		var r1 := Vector3(base.x + hx, top, base.z)
		_quad(st, d, c, r1, r0, color)
		_quad(st, b, a, r0, r1, color.darkened(0.12))
		_tri(st, a, d, r0, color.darkened(0.2))
		_tri(st, c, b, r1, color.darkened(0.2))
	else:
		var r0 := Vector3(base.x, top, base.z - hz)
		var r1 := Vector3(base.x, top, base.z + hz)
		_quad(st, c, b, r0, r1, color.darkened(0.06))
		_quad(st, a, d, r1, r0, color.darkened(0.14))
		_tri(st, d, c, r1, color.darkened(0.2))
		_tri(st, b, a, r0, color.darkened(0.2))


static func _slab_roof(st: SurfaceTool, base: Vector3, size: Vector3, color: Color) -> void:
	_box(st, base, size, color)


static func _cylinder(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color) -> void:
	var n := 7
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(base.x + cos(a0) * radius, base.y, base.z + sin(a0) * radius)
		var p1 := Vector3(base.x + cos(a1) * radius, base.y, base.z + sin(a1) * radius)
		var t0 := p0 + Vector3(0, height, 0)
		var t1 := p1 + Vector3(0, height, 0)
		_quad(st, p1, p0, t0, t1, color.darkened(0.06 * float(i % 3)))
		_tri(st, t0, Vector3(base.x, base.y + height, base.z), t1, color.lightened(0.05))


static func _cone(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color) -> void:
	var n := 6
	var tip := base + Vector3(0, height, 0)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(base.x + cos(a0) * radius, base.y, base.z + sin(a0) * radius)
		var p1 := Vector3(base.x + cos(a1) * radius, base.y, base.z + sin(a1) * radius)
		_tri(st, p1, p0, tip, color.darkened(0.08 * float(i % 3)))


static func _disc(st: SurfaceTool, radius: float, y: float, color: Color) -> void:
	var n := 14
	var mid := Vector3(0, y, 0)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		_tri(st, mid, Vector3(cos(a1) * radius, y, sin(a1) * radius), Vector3(cos(a0) * radius, y, sin(a0) * radius), color)


# ------------------------------------------------------------------ the models on the map

## Whether a city of this rank is shown at this zoom.
static func shown_at(rank: int, zoom: float) -> bool:
	return zoom >= float(MIN_ZOOM.get(rank, 1.0))


## How big the models are drawn at this zoom: they grow a little as the map is brought closer.
static func scale_for(zoom: float) -> float:
	return 0.6 * clampf(pow(zoom / 0.5, 0.7), 0.5, 2.2)


## Moves, resizes, rebuilds and flags every city. `map` is the Map3D that knows where the ground is.
func update(map: Node, zoom: float) -> void:
	_frame += 1
	var rebuilt := 0
	for city: Dictionary in GameState.cities:
		var entry: Variant = _entries.get(city.id)
		var visible_now := shown_at(int(city.rank), zoom)
		var ground: Variant = map.ground_point(city.pos) if visible_now else null
		if ground == null:
			if entry != null:
				entry.root.visible = false
			continue
		if entry == null:
			entry = _make_entry(city)
			_entries[city.id] = entry
		var pop := Cities.population(GameState, city)
		var bucket := bucket_of(pop)
		if (bucket != entry.bucket or int(entry.chimneys) != Cities.chimneys(GameState, city)) and rebuilt < 4:
			_rebuild(entry, city, pop, bucket)
			rebuilt += 1
		entry.root.visible = true
		entry.root.position = ground
		entry.root.scale = Vector3.ONE * scale_for(zoom)
		var holder: String = GameState.province_controller[city.province]
		if holder != entry.holder:
			entry.holder = holder
			var colour: Color = GameState.nations[holder].color if GameState.nations.has(holder) else Color.WHITE
			(entry.flag.material_override as StandardMaterial3D).albedo_color = colour


func _make_entry(city: Dictionary) -> Dictionary:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.material_override = _material
	root.add_child(body)
	var pole := MeshInstance3D.new()
	pole.name = "pole"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = 0.004
	cyl.height = 1.0
	cyl.radial_segments = 4
	pole.mesh = cyl
	var pole_mat := StandardMaterial3D.new()
	pole_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pole_mat.albedo_color = Color(0.1, 0.1, 0.12)
	pole.material_override = pole_mat
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	flag.mesh = _flag_mesh
	var flag_mat := StandardMaterial3D.new()
	flag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flag_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flag.material_override = flag_mat
	root.add_child(flag)
	add_child(root)
	return {"root": root, "body": body, "pole": pole, "flag": flag, "bucket": -1, "holder": "", "chimneys": -1, "height": 0.1}


func _rebuild(entry: Dictionary, city: Dictionary, pop: int, bucket: int) -> void:
	var chimneys := Cities.chimneys(GameState, city)
	var built := build(int(city.id), pop, chimneys, int(city.rank) == 1)
	entry.body.mesh = built.mesh
	entry.bucket = bucket
	entry.chimneys = chimneys
	entry.height = built.height
	var rise: float = built.height + 0.06
	var foot := Vector2(radius_for(pop) * 0.8, radius_for(pop) * 0.7)
	entry.pole.scale = Vector3(1, rise, 1)
	entry.pole.position = Vector3(foot.x, rise * 0.5, foot.y)
	entry.flag.position = Vector3(foot.x + 0.05, rise - 0.02, foot.y)


## The model of a city by id, for tests ({} if it has none yet).
func entry_of(city_id: int) -> Dictionary:
	return _entries.get(city_id, {})


## The city whose model is under a point of the screen, as {pos (map pixels), kind, ground, men}, or {}.
func city_at(map: Node, screen: Vector2) -> Dictionary:
	var camera: Camera3D = map.get("_camera")
	if camera == null:
		return {}
	var best := {}
	var best_d := 22.0
	for city: Dictionary in GameState.cities:
		var entry: Variant = _entries.get(city.id)
		if entry == null or not entry.root.visible:
			continue
		var top: Vector3 = entry.root.position + Vector3(0, float(entry.height) * 0.5 * entry.root.scale.y, 0)
		if camera.is_position_behind(top):
			continue
		var d := camera.unproject_position(top).distance_to(screen)
		if d < best_d:
			best_d = d
			best = {"pos": city.pos, "kind": "city", "ground": entry.root.position, "men": 0.0}
	return best
