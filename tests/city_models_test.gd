extends SceneTree
## Headless test for the 3D cities: the model grows with the people (footprint, buildings, height),
## is the same every time for the same city, follows the province's population, is rebuilt when the
## size has changed enough, carries the holder's flag, and stands on the 3D map.
## Run: godot --headless --path . -s res://tests/city_models_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _vertices(built: Dictionary) -> int:
	var arrays: Array = built.mesh.surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


func _b(city_id: int, pop: int, chimneys := 0, capital := false, land := func(_p: Vector2) -> bool: return true) -> Dictionary:
	return load("res://scripts/map/city_models.gd").build(city_id, pop, {"chimneys": chimneys}, capital, Vector2(1000, 1000), land)


func _initialize() -> void:
	await process_frame
	var CM = load("res://scripts/map/city_models.gd")
	var CitiesC = load("res://scripts/sim/cities.gd")
	_check(CM.radius_for(20000) < CM.radius_for(300000) and CM.radius_for(300000) < CM.radius_for(2000000), "a bigger city has a bigger footprint")
	_check(CM.radius_for(7250000) <= 72.0 + 0.0001 and CM.radius_for(1) >= 9.0 - 0.0001, "held between a smallest and a largest size")
	var small = _b(5, 20000)
	var middling = _b(5, 300000)
	var great = _b(5, 2000000)
	_check(small.buildings < middling.buildings and middling.buildings < great.buildings, "a town has %d buildings, a city %d, a great city %d" % [small.buildings, middling.buildings, great.buildings])
	_check(small.height > 0.0 and great.height > 0.0, "with a tallest roof (%.1f and %.1f px)" % [small.height, great.height])
	_check(_vertices(small) < _vertices(great), "and its mesh is bigger")
	var again = _b(5, 300000)
	_check(_vertices(again) == _vertices(middling) and again.buildings == middling.buildings, "the same city is built the same way every time")
	_check(_vertices(_b(6, 300000)) != _vertices(middling), "other cities are built differently")
	_check(_vertices(_b(5, 300000, 4)) > _vertices(middling), "chimneys add to a city with factories")
	_check(_vertices(_b(5, 300000, 0, true)) != _vertices(middling), "and a capital has its palace")
	# No building stands where its foot would be in the sea: with the sea east of the city's middle,
	# nothing is built east of it.
	var coast = _b(5, 2000000, 2, true, func(p: Vector2) -> bool: return p.x < 1000.0)
	var east := 0.0
	for v in (coast.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		east = maxf(east, v.x)
	_check(coast.buildings > 20 and east <= 1.0, "no building crosses a coast (the furthest east is %.1f px, the city has %d buildings)" % [east, coast.buildings])
	_check(CM.bucket_of(300000) < CM.bucket_of(330000) and CM.bucket_of(300000) == CM.bucket_of(300500), "growth shows in a new size class, a few people do not")
	_check(CM.opacity_at(1, 0.3) == 0.0 and CM.opacity_at(3, 0.6) == 0.0, "from afar no city is drawn: the nations' colours show alone")
	_check(CM.opacity_at(1, 0.7) > 0.0 and CM.opacity_at(1, 0.7) < 1.0 and CM.opacity_at(3, 0.7) == 0.0, "capitals come up first, as the map is brought closer")
	_check(CM.opacity_at(1, 1.0) == 1.0 and CM.opacity_at(3, 1.4) == 1.0 and CM.opacity_at(2, 0.9) < CM.opacity_at(1, 0.9), "and every city is solid at last, the small ones later")

	var gs: Node = root.get_node("GameState")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("GER")
	var london: Dictionary = {}
	for c in gs.cities:
		if c.name == "London":
			london = c
	_check(CitiesC.population(gs, london) == london.pop, "a city holds what the scenario says at the start")
	gs.province_population[london.province] = int(gs.province_pop_base[london.province] * 1.5)
	_check(CitiesC.population(gs, london) == roundi(london.pop * 1.5), "and grows with its province (%d)" % CitiesC.population(gs, london))
	gs.province_population[london.province] = 1
	_check(CitiesC.population(gs, london) >= int(london.pop * 0.4) - 1, "but not below two fifths")
	gs.province_population[london.province] = gs.province_pop_base[london.province]
	var save = load("res://scripts/sim/save_game.gd")
	var snap: Dictionary = save.snapshot(gs)
	_check(not snap.state.has("province_pop_base"), "the base figures are not in saves (they are read again)")

	# On the 3D map.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var mode: Node = get_first_node_in_group("map_3d")
	main.camera.position = london.pos
	main.camera.zoom = Vector2(1.6, 1.6)
	mode.set_enabled(true)
	for i in 4:
		await process_frame
	var layer: Node = get_first_node_in_group("city_layer")
	_check(layer.markers_hidden, "the flat diamonds are hidden while the models stand")
	var entry: Dictionary = mode._cities.entry_of(london.id)
	_check(not entry.is_empty() and entry.root.visible, "London stands on the map")
	var bucket: int = entry.bucket
	gs.province_population[london.province] = int(gs.province_pop_base[london.province] * 2.0)
	for i in 3:
		await process_frame
	_check(mode._cities.entry_of(london.id).bucket > bucket, "when its province has doubled the model has grown (class %d to %d)" % [bucket, mode._cities.entry_of(london.id).bucket])
	var holder: String = gs.province_controller[london.province]
	var flag_colour: Color = (entry.flag.material_override as StandardMaterial3D).albedo_color
	_check(flag_colour.is_equal_approx(gs.nations[holder].color), "the flag is the holder's colour")
	gs.set_controller(london.province, "GER")
	for i in 3:
		await process_frame
	_check((mode._cities.entry_of(london.id).flag.material_override as StandardMaterial3D).albedo_color.is_equal_approx(gs.nations["GER"].color), "an occupied city shows the occupier's flag")
	gs.occupation[london.province] = {"tag": "GER", "days": 1}
	for i in 3:
		await process_frame
	_check((mode._cities.entry_of(london.id).smoke as MultiMeshInstance3D).visible, "a city whose province is being taken burns")
	gs.occupation.erase(london.province)
	var hit: Dictionary = mode.marker_at(mode._camera.unproject_position(entry.root.position + Vector3(0, float(entry.height) * 0.5 * entry.root.scale.y, 0)))
	_check(not hit.is_empty() and hit.get("kind", "") == "city", "a click on a city model is a click on the city")
	mode.cities_on = false
	_check(not layer.markers_hidden and not mode._cities.visible, "with the city models off the flat diamonds are back")
	# landmarks, harbours, stations, walls
	var LM = load("res://scripts/map/city_landmarks.gd")
	var names := {}
	for line in FileAccess.get_file_as_string("res://data/scenarios/july_1914/cities.tsv").split("\n"):
		var cols := line.split("\t")
		if cols.size() > 2:
			names[cols[1]] = true
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/landmarks.json"))
	var bad := 0
	var kinds := {}
	for city_name: String in data:
		if city_name.begins_with("_"):
			continue
		if not names.has(city_name):
			bad += 1
		for spec: Dictionary in data[city_name]:
			kinds[spec.type] = true
	_check(bad == 0, "every landmark city is a city of the scenario")
	for kind: String in kinds:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var h: float = LM.build(st, {"type": kind, "k": 1.0, "rot": 0.3}, Vector3(0, -4.0, 0))
		_check(h > 5.0 and st.commit().get_surface_count() == 1, "landmark %s builds" % kind)
	var plain = _b(5, 2000000)
	var london_lm = load("res://scripts/map/city_models.gd").build(5, 2000000, {"name": "London"}, true, Vector2(1000, 1000), func(_p: Vector2) -> bool: return true)
	_check(_vertices(london_lm) != _vertices(plain), "London has its landmarks")
	var sea := func(p: Vector2) -> bool: return p.x < 1030.0
	var CMc = load("res://scripts/map/city_models.gd")
	var dry = CMc.build(5, 800000, {}, false, Vector2(1000, 1000), sea)
	var port = CMc.build(5, 800000, {"port": 3, "naval": true, "rail": 4, "fort": 5}, false, Vector2(1000, 1000), sea)
	_check(_vertices(port) > _vertices(dry), "port, railway and walls add to the model")
	var aabb: AABB = port.mesh.get_aabb()
	_check(aabb.position.x + aabb.size.x < 30.0 + 18.0, "and nothing but ships goes out to sea")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
