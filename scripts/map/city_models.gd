class_name CityModels
extends Node3D
## The cities of the 3D map as small models of buildings, one per city of the scenario (cities.tsv).
## A city's size follows its people (Cities.population): the footprint grows with the square root of the
## population, and so do the number of buildings and the height of the middle of town. The model is
## laid out in map pixels, on the same scale as the ground it stands on: streets in a rotated grid,
## terraced houses with tiled gable roofs in blocks, taller flat-roofed blocks in the middle, a church
## spire for every town, a cathedral with two towers for a great city, a gilded dome for a capital,
## and sheds and chimneys where the province has factories. The edge of town is uneven, and no
## building is put where its foot would be in the sea. The model is built from the city's number (the
## same city always looks the same), rebuilt when its people have grown or shrunk enough to show, and
## carries a flag in the colour of whoever holds the city.

## The most buildings one model may have.
const MAX_BUILDINGS := 520
## The zooms between which each rank of city fades in, from nothing to solid: from afar the nations'
## colours show alone, and the cities come up through them as the map is brought closer.
const FADE_ZOOM := {1: [0.45, 0.95], 2: [0.6, 1.15], 3: [0.8, 1.35]}
const WALLS := [Color(0.89, 0.84, 0.72), Color(0.84, 0.76, 0.6), Color(0.8, 0.8, 0.76), Color(0.86, 0.78, 0.7), Color(0.76, 0.69, 0.58)]
const TILES := [Color(0.66, 0.31, 0.21), Color(0.58, 0.27, 0.19), Color(0.5, 0.36, 0.28)]
const SLATE := Color(0.34, 0.36, 0.4)
const STONE := Color(0.72, 0.7, 0.65)
const COPPER := Color(0.36, 0.52, 0.46)
const GOLD := Color(0.92, 0.76, 0.32)
const BRICK := Color(0.5, 0.28, 0.22)
## How deep the walls reach below the city's own ground level, so that hills do not show gaps.
const FOOT := 4.0

var _entries := {}
var _material: StandardMaterial3D
var _flag_mesh: QuadMesh
## How faint a city may be and still be drawn at all.
const MIN_OPACITY := 0.03


func _init() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flag_mesh = QuadMesh.new()
	_flag_mesh.size = Vector2(7.0, 4.2)


# ------------------------------------------------------------------ the model of one city (pure)

## The footprint radius of a city's model, in map pixels.
static func radius_for(pop: int) -> float:
	return clampf(6.0 + 40.0 * sqrt(float(pop) / 1000000.0), 9.0, 72.0)


## A size class of a population: about 15% apart, so a model follows growth without being rebuilt
## every month.
static func bucket_of(pop: int) -> int:
	return int(log(maxf(float(pop), 1000.0) / 1000.0) * 7.0)


## Builds the mesh of a city centred on `centre` (map pixels): {mesh, buildings, height}. `is_land` says
## whether a map pixel is land (a building stands only where its whole foot is).
static func build(city_id: int, pop: int, chimneys: int, capital: bool, centre: Vector2, is_land: Callable) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = city_id * 7919 + 17
	var pf := sqrt(float(pop) / 1000000.0)
	var radius := radius_for(pop)
	var pitch := 4.4 + 0.5 * pf
	var turn := rng.randf() * PI
	var phase_a := rng.randf() * TAU
	var phase_b := rng.randf() * TAU
	var basis := Basis(Vector3.UP, turn)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span := int(ceil(radius * 1.35 / pitch)) + 1
	var spots: Array[Dictionary] = []
	for i in range(-span, span + 1):
		for j in range(-span, span + 1):
			if i % 6 == 0 or j % 6 == 0:
				continue      # streets and squares
			var local := Vector2(i, j) * pitch
			var p := local.rotated(turn)
			var angle := atan2(p.y, p.x)
			var limit := radius * (1.0 + 0.22 * sin(3.0 * angle + phase_a) + 0.12 * sin(5.0 * angle + phase_b))
			var d := p.length() / limit
			if d > 1.0:
				continue
			if rng.randf() < pow(d, 3.0) * 0.3:
				continue      # the edge thins out
			spots.append({"i": i, "j": j, "p": p, "d": d})
	spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	var count := 0
	var tallest := 0.0
	var half := pitch * 0.42
	for s: Dictionary in spots:
		if count >= MAX_BUILDINGS:
			break
		var p: Vector2 = s.p
		var foot_ok := true
		for corner in [Vector2(half, half), Vector2(-half, half), Vector2(half, -half), Vector2(-half, -half)]:
			if not is_land.call(centre + p + corner.rotated(turn) * 1.3):
				foot_ok = false
				break
		if not foot_ok:
			continue
		var core := 1.0 - float(s.d)
		var block := int(floorf((s.i + 2.0) / 6.0)) * 31 + int(floorf((s.j + 2.0) / 6.0)) * 17
		var level := mini(5, 1 + int(core * minf(2.2 + 1.2 * pf, 4.2)) + (absi(block) % 2))
		var walls: Color = WALLS[(absi(block) + (s.i + s.j) % 2) % WALLS.size()].lightened(rng.randf_range(-0.04, 0.05))
		var size := Vector3(pitch * rng.randf_range(0.84, 0.92), 2.2 + 1.2 * level + rng.randf_range(0.0, 0.5), pitch * rng.randf_range(0.86, 0.93))
		var at := Vector3(p.x, -FOOT, p.y)
		_box(st, at, Vector3(size.x, size.y + FOOT, size.z), walls, basis)
		var top := at + Vector3(0, size.y + FOOT, 0)
		if level <= 2:
			var roof: Color = TILES[(absi(block) + s.i) % TILES.size()].lightened(rng.randf_range(-0.04, 0.05))
			_gable(st, top, Vector3(size.x * 1.08, size.x * 0.42, size.z * 1.06), roof, basis, (absi(block) % 2) == 0)
			tallest = maxf(tallest, size.y + size.x * 0.42)
		else:
			_box(st, top, Vector3(size.x * 1.04, 0.7, size.z * 1.04), SLATE.lightened(rng.randf_range(0.0, 0.1)), basis)
			tallest = maxf(tallest, size.y + 0.7)
		count += 1
	# landmarks: a church for every town, a cathedral with two towers for a great city
	var near := radius * 0.2
	if pop >= 12000:
		var church_at := Vector3(rng.randf_range(-near, near), -FOOT, rng.randf_range(-near, near))
		var k := 0.65 + 0.25 * pf if pop >= 250000 else 0.6 + 0.3 * pf
		var reach := 13.0 * k if pop >= 250000 else 7.5 * k
		var spot: Variant = _land_spot([church_at, Vector3.ZERO, Vector3(-near, -FOOT, near), Vector3(near, -FOOT, -near)], centre, is_land, reach)
		if spot != null:
			if pop >= 250000:
				tallest = maxf(tallest, _cathedral(st, spot, basis, k))
			else:
				tallest = maxf(tallest, _church(st, spot, basis, k))
	if capital:
		var k := 0.65 + 0.2 * pf
		var spot: Variant = _land_spot([Vector3(radius * 0.28, -FOOT, -radius * 0.22), Vector3(-radius * 0.28, -FOOT, radius * 0.22), Vector3(0, -FOOT, radius * 0.3), Vector3(0, -FOOT, -radius * 0.3)], centre, is_land, 11.0 * k)
		if spot != null:
			tallest = maxf(tallest, _palace(st, spot, basis, k))
	for k in chimneys:
		var a := rng.randf() * TAU
		var r := radius * rng.randf_range(0.55, 0.9)
		var at := Vector3(cos(a) * r, -FOOT, sin(a) * r)
		if _land_spot([at], centre, is_land, 10.0) == null:
			continue
		_box(st, at, Vector3(14.0, 4.0 + FOOT, 6.0), BRICK.lightened(0.08), basis)
		_gable(st, at + Vector3(0, 4.0 + FOOT, 0), Vector3(14.5, 3.0, 6.4), SLATE, basis, true)
		var stack_at := at + Vector3(6.0, 0, 1.5)
		_cylinder(st, stack_at, 0.9, 4.0 + FOOT + rng.randf_range(10.0, 16.0), BRICK)
		tallest = maxf(tallest, 14.0 + 4.0)
	return {"mesh": st.commit(), "buildings": count, "height": tallest}


## The first of the candidate spots (offsets from the city's middle, y ignored) whose whole foot, a square
## of `reach` pixels about it, is on land; null if none.
static func _land_spot(spots: Array, centre: Vector2, is_land: Callable, reach: float) -> Variant:
	for at: Vector3 in spots:
		var here := centre + Vector2(at.x, at.z)
		var ok := true
		for corner in [Vector2.ZERO, Vector2(reach, reach), Vector2(-reach, reach), Vector2(reach, -reach), Vector2(-reach, -reach)]:
			if not is_land.call(here + corner):
				ok = false
				break
		if ok:
			return at
	return null


static func _church(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	var nave := Vector3(5.0 * k, 5.5 * k + FOOT, 11.0 * k)
	_box(st, at, nave, STONE, basis)
	_gable(st, at + basis * Vector3(0, nave.y, 0), Vector3(5.4 * k, 3.0 * k, 11.2 * k), SLATE, basis, false)
	var tower_at := at + basis * Vector3(0, 0, 6.2 * k)
	var tower := Vector3(3.4 * k, 12.0 * k + FOOT, 3.4 * k)
	_box(st, tower_at, tower, STONE.darkened(0.05), basis)
	_cone(st, tower_at + Vector3(0, tower.y, 0), 2.3 * k, 10.0 * k, SLATE.darkened(0.1))
	return tower.y + 10.0 * k - FOOT


static func _cathedral(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	var nave := Vector3(8.0 * k, 8.5 * k + FOOT, 20.0 * k)
	_box(st, at, nave, STONE, basis)
	_gable(st, at + basis * Vector3(0, nave.y, 0), Vector3(8.6 * k, 4.5 * k, 20.4 * k), COPPER, basis, false)
	_box(st, at + basis * Vector3(0, 0, 0), Vector3(20.0 * k, 6.0 * k + FOOT, 6.0 * k), STONE.darkened(0.04), basis)
	var best := 0.0
	for side in [-1.0, 1.0]:
		var tower_at := at + basis * Vector3(side * 2.6 * k, 0, 11.4 * k)
		var tower := Vector3(3.6 * k, 20.0 * k + FOOT, 3.6 * k)
		_box(st, tower_at, tower, STONE.darkened(0.06), basis)
		_cone(st, tower_at + Vector3(0, tower.y, 0), 2.6 * k, 12.0 * k, COPPER)
		best = tower.y + 12.0 * k - FOOT
	return best


static func _palace(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	var base := Vector3(16.0 * k, 8.0 * k + FOOT, 16.0 * k)
	_box(st, at, base, STONE.lightened(0.06), basis)
	_box(st, at + Vector3(0, base.y, 0), Vector3(17.0 * k, 1.0, 17.0 * k), STONE.darkened(0.12), basis)
	var drum_at := at + Vector3(0, base.y + 1.0, 0)
	_cylinder(st, drum_at, 5.5 * k, 5.0 * k, STONE)
	_cone(st, drum_at + Vector3(0, 5.0 * k, 0), 5.8 * k, 5.5 * k, GOLD.darkened(0.1))
	_cone(st, drum_at + Vector3(0, 10.0 * k, 0), 1.2 * k, 5.0 * k, GOLD)
	return base.y + 1.0 + 15.0 * k - FOOT


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(st, a, b, c, color)
	_tri(st, a, c, d, color)


## A box standing on `base` (the middle of its foot), `size` wide, tall and deep, turned by `basis`. The
## walls are a shade darker near the ground.
static func _box(st: SurfaceTool, base: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var low := minf(size.y, FOOT + 2.2)
	var c := func(x: float, y: float, z: float) -> Vector3: return base + basis * Vector3(x, y, z)
	var p000: Vector3 = c.call(-hx, 0.0, -hz)
	var p100: Vector3 = c.call(hx, 0.0, -hz)
	var p101: Vector3 = c.call(hx, 0.0, hz)
	var p001: Vector3 = c.call(-hx, 0.0, hz)
	var m000: Vector3 = c.call(-hx, low, -hz)
	var m100: Vector3 = c.call(hx, low, -hz)
	var m101: Vector3 = c.call(hx, low, hz)
	var m001: Vector3 = c.call(-hx, low, hz)
	var q000: Vector3 = c.call(-hx, size.y, -hz)
	var q100: Vector3 = c.call(hx, size.y, -hz)
	var q101: Vector3 = c.call(hx, size.y, hz)
	var q001: Vector3 = c.call(-hx, size.y, hz)
	var shade := color.darkened(0.14)
	_quad(st, p001, p101, m101, m001, shade)
	_quad(st, p100, p000, m000, m100, shade.darkened(0.06))
	_quad(st, p101, p100, m100, m101, shade.darkened(0.03))
	_quad(st, p000, p001, m001, m000, shade.darkened(0.1))
	_quad(st, m001, m101, q101, q001, color)
	_quad(st, m100, m000, q000, q100, color.darkened(0.08))
	_quad(st, m101, m100, q100, q101, color.darkened(0.04))
	_quad(st, m000, m001, q001, q000, color.darkened(0.12))
	_quad(st, q001, q101, q100, q000, color.lightened(0.04))


## A pitched roof on a building: `size.y` is the ridge's rise, the ridge along the building's x or z.
static func _gable(st: SurfaceTool, base: Vector3, size: Vector3, color: Color, basis: Basis, along_x: bool) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var top := size.y
	var c := func(x: float, y: float, z: float) -> Vector3: return base + basis * Vector3(x, y, z)
	var a: Vector3 = c.call(-hx, 0.0, -hz)
	var b: Vector3 = c.call(hx, 0.0, -hz)
	var cc: Vector3 = c.call(hx, 0.0, hz)
	var d: Vector3 = c.call(-hx, 0.0, hz)
	if along_x:
		var r0: Vector3 = c.call(-hx, top, 0.0)
		var r1: Vector3 = c.call(hx, top, 0.0)
		_quad(st, d, cc, r1, r0, color)
		_quad(st, b, a, r0, r1, color.darkened(0.14))
		_tri(st, a, d, r0, color.darkened(0.22))
		_tri(st, cc, b, r1, color.darkened(0.22))
	else:
		var r0: Vector3 = c.call(0.0, top, -hz)
		var r1: Vector3 = c.call(0.0, top, hz)
		_quad(st, cc, b, r0, r1, color.darkened(0.04))
		_quad(st, a, d, r1, r0, color.darkened(0.16))
		_tri(st, d, cc, r1, color.darkened(0.22))
		_tri(st, b, a, r0, color.darkened(0.22))


static func _cylinder(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color) -> void:
	var n := 8
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(base.x + cos(a0) * radius, base.y, base.z + sin(a0) * radius)
		var p1 := Vector3(base.x + cos(a1) * radius, base.y, base.z + sin(a1) * radius)
		var t0 := p0 + Vector3(0, height, 0)
		var t1 := p1 + Vector3(0, height, 0)
		_quad(st, p1, p0, t0, t1, color.darkened(0.05 * float(i % 3)))
		_tri(st, t0, Vector3(base.x, base.y + height, base.z), t1, color.lightened(0.05))


static func _cone(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color) -> void:
	var n := 8
	var tip := base + Vector3(0, height, 0)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(base.x + cos(a0) * radius, base.y, base.z + sin(a0) * radius)
		var p1 := Vector3(base.x + cos(a1) * radius, base.y, base.z + sin(a1) * radius)
		_tri(st, p1, p0, tip, color.darkened(0.07 * float(i % 3)))


# ------------------------------------------------------------------ the models on the map

## How solid a city of this rank is at this zoom: 0 (not there) to 1.
static func opacity_at(rank: int, zoom: float) -> float:
	var ends: Array = FADE_ZOOM.get(rank, [1.0, 1.5])
	var t := clampf((zoom - float(ends[0])) / (float(ends[1]) - float(ends[0])), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Whether a map pixel is land: a province or the grey background, not the sea.
static func land_at(px: Vector2) -> bool:
	return MapData.province_at_pixel(Vector2i(px.floor())) != MapData.SEA


## Moves, resizes, rebuilds and flags every city. `map` is the Map3D that knows where the ground is
## and how many plane units a map pixel is.
func update(map: Node, zoom: float) -> void:
	var rebuilt := 0
	var per_px: float = map.units_per_px()
	for city: Dictionary in GameState.cities:
		var entry: Variant = _entries.get(city.id)
		var opacity := opacity_at(int(city.rank), zoom)
		var ground: Variant = map.ground_point(city.pos) if opacity >= MIN_OPACITY else null
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
		entry.root.scale = Vector3.ONE * per_px
		var holder: String = GameState.province_controller[city.province]
		var colour: Color = GameState.nations[holder].color if GameState.nations.has(holder) else Color.WHITE
		if holder != entry.holder:
			entry.holder = holder
			(entry.flag.material_override as StandardMaterial3D).albedo_color = colour
		_fade(entry, opacity, colour)


## Fades a city: solid it uses the shared opaque material; faint, its own see-through one, tinted toward
## the colour of the nation that holds it, so it comes up out of the political colours.
func _fade(entry: Dictionary, opacity: float, nation: Color) -> void:
	var body: MeshInstance3D = entry.body
	if opacity >= 0.985:
		body.material_override = _material
		entry.opacity = 1.0
	else:
		var fading: StandardMaterial3D = entry.fading
		if not is_equal_approx(float(entry.opacity), opacity) or entry.tint != nation:
			var tint := Color.WHITE.lerp(nation.lightened(0.2), (1.0 - opacity) * 0.6)
			fading.albedo_color = Color(tint, opacity)
			entry.opacity = opacity
			entry.tint = nation
		body.material_override = fading
	for part: String in ["pole", "flag"]:
		var piece: MeshInstance3D = entry[part]
		var mat := piece.material_override as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if opacity < 0.985 else BaseMaterial3D.TRANSPARENCY_DISABLED
		if part == "pole":
			mat.albedo_color.a = opacity
		else:
			mat.albedo_color.a = opacity


func _make_entry(_city: Dictionary) -> Dictionary:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.material_override = _material
	var fading := StandardMaterial3D.new()
	fading.vertex_color_use_as_albedo = true
	fading.roughness = 0.95
	fading.cull_mode = BaseMaterial3D.CULL_DISABLED
	fading.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	root.add_child(body)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.28
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
	flag_mat.billboard_keep_scale = true
	flag.material_override = flag_mat
	root.add_child(flag)
	add_child(root)
	return {"root": root, "body": body, "pole": pole, "flag": flag, "fading": fading, "opacity": -1.0, "tint": Color.WHITE,
			"bucket": -1, "holder": "", "chimneys": -1, "height": 10.0}


func _rebuild(entry: Dictionary, city: Dictionary, pop: int, bucket: int) -> void:
	var chimneys := Cities.chimneys(GameState, city)
	var built := build(int(city.id), pop, chimneys, int(city.rank) == 1, city.pos, land_at)
	entry.body.mesh = built.mesh
	entry.bucket = bucket
	entry.chimneys = chimneys
	entry.height = built.height
	var rise: float = built.height + 5.0
	var foot := Vector2(radius_for(pop) * 0.55, -radius_for(pop) * 0.5)
	if not land_at(city.pos + foot):
		foot = Vector2.ZERO
	entry.pole.scale = Vector3(1, rise, 1)
	entry.pole.position = Vector3(foot.x, rise * 0.5 - FOOT, foot.y)
	entry.flag.position = Vector3(foot.x + 3.8, rise - FOOT - 2.2, foot.y)


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
