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
## From this opacity a city has its name over the model.
const LABEL_OPACITY := 0.5


var _smoke_grey: ShaderMaterial
var _smoke_dark: ShaderMaterial


func _init() -> void:
	_smoke_grey = smoke_material(false)
	_smoke_dark = smoke_material(true)
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


## Builds the mesh of a city centred on `centre` (map pixels): see CityBuilder.build.
static func build(city_id: int, pop: int, info: Dictionary, capital: bool, centre: Vector2, is_land: Callable) -> Dictionary:
	return CityBuilder.build(city_id, pop, info, capital, centre, is_land)


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
	var named := {}
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
		if (bucket != entry.bucket or entry.features != Cities.features(GameState, city)) and rebuilt < 4:
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
		_fade(entry, opacity, colour, GameState.province_controller[city.province] != GameState.province_owner[city.province])
		_smoke(entry, opacity, GameState.occupation.has(city.province))
		_label(entry, city, pop, opacity, zoom)
		if opacity >= LABEL_OPACITY:
			named[city.id] = true
	var layer: Node = get_tree().get_first_node_in_group("city_layer") if is_inside_tree() else null
	if layer != null and layer.get("skip_names") != named:
		layer.set("skip_names", named)


## The name of a city over its model (and, close up, its people), as big on the screen as the flat map's name
## would be: the flat one is left out for the cities that have this.
func _label(entry: Dictionary, city: Dictionary, pop: int, opacity: float, zoom: float) -> void:
	var label: Label3D = entry.label
	label.visible = opacity >= LABEL_OPACITY
	if not label.visible:
		return
	var text: String = city.name
	if zoom >= CityLayer.POP_ZOOM:
		text += "  " + CityLayer.people(pop)
	if text != entry.label_text:
		entry.label_text = text
		label.text = text
	label.modulate = (CityLayer.CAPITAL_COLOR if int(city.rank) == 1 else CityLayer.NAME_COLOR) * Color(1, 1, 1, clampf((opacity - LABEL_OPACITY) / (1.0 - LABEL_OPACITY), 0.0, 1.0))
	label.pixel_size = 0.5 / maxf(zoom, 0.05)
	label.position = Vector3(0, float(entry.height) + 10.0 + 14.0 * label.pixel_size, 0)


## Fades a city: solid it uses the shared opaque material; faint, its own see-through one, tinted toward
## the colour of the nation that holds it, so it comes up out of the political colours.
func _fade(entry: Dictionary, opacity: float, nation: Color, occupied := false) -> void:
	var body: MeshInstance3D = entry.body
	if opacity >= 0.985 and not occupied:
		body.material_override = _material
		entry.opacity = 1.0
		entry.tint = Color.WHITE
	else:
		var fading: StandardMaterial3D = entry.fading
		if not is_equal_approx(float(entry.opacity), opacity) or entry.tint != nation or entry.get("ruined", false) != occupied:
			var tint := Color.WHITE.lerp(nation.lightened(0.2), (1.0 - opacity) * 0.6)
			if occupied:
				# A city in an enemy's hands: dulled and darkened, as after a siege.
				tint = tint.lerp(Color(0.55, 0.5, 0.47), 0.55)
			fading.albedo_color = Color(tint, opacity)
			entry.opacity = opacity
			entry.tint = nation
			entry.ruined = occupied
		body.material_override = fading
	for part: String in ["pole", "flag"]:
		var piece: MeshInstance3D = entry[part]
		var mat := piece.material_override as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if opacity < 0.985 else BaseMaterial3D.TRANSPARENCY_DISABLED
		if part == "pole":
			mat.albedo_color.a = opacity
		else:
			mat.albedo_color.a = opacity


## Smoke over a city: grey and thin from its chimneys; black and thick, from fires all over town, while an army
## is taking its province. Only the cities solid enough to see have any. The puffs are one MultiMesh whose
## shader (shaders/smoke.gdshader) lifts, widens and fades each of them by the clock: nothing is done by
## the processor from frame to frame.
func _smoke(entry: Dictionary, opacity: float, besieged: bool) -> void:
	var puffs: MultiMeshInstance3D = entry.smoke
	var stacks: PackedVector3Array = entry.stacks
	var on := opacity >= 0.95 and (besieged or not stacks.is_empty())
	puffs.visible = on
	if not on:
		return
	if entry.smoking == besieged:
		return
	entry.smoking = besieged
	var points := stacks
	if besieged:
		points = PackedVector3Array()
		var r: float = float(entry.radius)
		for i in 6:
			var a := float(i) * 1.047 + 0.4
			points.append(Vector3(cos(a), 0.0, sin(a)) * r * (0.2 + 0.1 * (i % 3)) + Vector3(0, 4.0, 0))
	var per: int = 10 if besieged else 5
	var mm := puffs.multimesh
	mm.instance_count = points.size() * per
	for s in points.size():
		for k in per:
			var i := s * per + k
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[s]))
			mm.set_instance_custom_data(i, Color(float(k) / per + float(s) * 0.37, float(s + k), 0.0, 0.0))
	puffs.material_override = _smoke_dark if besieged else _smoke_grey


static func smoke_material(dark: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/smoke.gdshader")
	mat.set_shader_parameter("dark", dark)
	return mat


static func make_smoke() -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.visible = false
	node.custom_aabb = AABB(Vector3(-120, -10, -120), Vector3(240, 200, 240))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


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
	var smoke := make_smoke()
	root.add_child(smoke)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.font_size = 26
	label.outline_size = 8
	label.outline_modulate = Color(0.04, 0.04, 0.05, 0.9)
	label.render_priority = 4
	label.outline_render_priority = 3
	label.shaded = false
	root.add_child(label)
	add_child(root)
	return {"label": label, "label_text": "", "smoke": smoke, "sources": PackedVector3Array(), "per": 1, "dark": false, "stacks": PackedVector3Array(), "smoking": null, "radius": 20.0, "root": root, "body": body, "pole": pole, "flag": flag, "fading": fading, "opacity": -1.0, "tint": Color.WHITE,
			"bucket": -1, "holder": "", "features": {}, "height": 10.0}


func _rebuild(entry: Dictionary, city: Dictionary, pop: int, bucket: int) -> void:
	var features := Cities.features(GameState, city)
	var built := build(int(city.id), pop, features, int(city.rank) == 1, city.pos, land_at)
	entry.body.mesh = built.mesh
	entry.bucket = bucket
	entry.features = features
	entry.stacks = PackedVector3Array(built.stacks)
	entry.radius = radius_for(pop)
	entry.smoking = null
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
