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


func _initialize() -> void:
	await process_frame
	var CM = load("res://scripts/map/city_models.gd")
	var CitiesC = load("res://scripts/sim/cities.gd")
	_check(CM.radius_for(20000) < CM.radius_for(300000) and CM.radius_for(300000) < CM.radius_for(2000000), "a bigger city has a bigger footprint")
	_check(CM.radius_for(7250000) <= 0.5 + 0.0001, "held to a largest size")
	_check(CM.building_target(20000) < CM.building_target(300000) and CM.building_target(300000) < CM.building_target(2000000), "and more buildings")
	var small = CM.build(5, 20000, 0, false)
	var middling = CM.build(5, 300000, 0, false)
	var great = CM.build(5, 2000000, 0, false)
	_check(small.buildings < middling.buildings and middling.buildings < great.buildings, "a town has %d buildings, a city %d, a great city %d" % [small.buildings, middling.buildings, great.buildings])
	_check(small.height < great.height, "the great city stands taller (%.2f against %.2f)" % [small.height, great.height])
	_check(_vertices(small) < _vertices(great), "and its mesh is bigger")
	var again = CM.build(5, 300000, 0, false)
	_check(_vertices(again) == _vertices(middling) and again.buildings == middling.buildings, "the same city is built the same way every time")
	_check(_vertices(CM.build(6, 300000, 0, false)) != _vertices(middling), "other cities are built differently")
	_check(_vertices(CM.build(5, 300000, 4, false)) > _vertices(middling), "chimneys add to a city with factories")
	_check(_vertices(CM.build(5, 300000, 0, true)) > _vertices(middling), "and a capital has its dome")
	_check(CM.bucket_of(300000) < CM.bucket_of(330000) and CM.bucket_of(300000) == CM.bucket_of(300500), "growth shows in a new size class, a few people do not")
	_check(CM.shown_at(1, 0.2) and not CM.shown_at(3, 0.3) and CM.shown_at(3, 0.8), "capitals show from afar, small towns only close up")
	_check(CM.scale_for(1.0) > CM.scale_for(0.4), "models grow as the map is brought closer")

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
	main.camera.zoom = Vector2(1.0, 1.0)
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
	var hit: Dictionary = mode.marker_at(mode._camera.unproject_position(entry.root.position + Vector3(0, 0.1, 0)))
	_check(not hit.is_empty() and hit.get("kind", "") == "city", "a click on a city model is a click on the city")
	mode.cities_on = false
	_check(not layer.markers_hidden and not mode._cities.visible, "with the city models off the flat diamonds are back")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
