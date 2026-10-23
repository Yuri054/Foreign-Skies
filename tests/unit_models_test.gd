extends SceneTree
## 3D models of armies and fleets: formations by make-up and size, lines of ships, caching, and the models
## coming up on the 3D map as it is brought close.

var _failures := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok:   ", what)
	else:
		_failures += 1
		print("FAIL: ", what)


func _vertices(mesh: ArrayMesh) -> int:
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


func _initialize() -> void:
	await process_frame
	var UM = load("res://scripts/map/unit_models.gd")
	var Map3DC = load("res://scripts/map/map_3d.gd")
	var grey := Color(0.5, 0.5, 0.5)
	_check(UM.army_counts({}, 30000.0) == {"infantry": 3}, "an army of unknown make-up is infantry by its men")
	var big: Dictionary = UM.army_counts({"infantry": 30, "cavalry": 4, "artillery": 6}, 0.0)
	var total := 0
	for k in big:
		total += big[k]
	_check(total <= 11 and big.cavalry >= 1 and big.artillery >= 1, "a great army is shown by at most nine units, every kind kept (%s)" % big)
	var small: ArrayMesh = UM.army_mesh({"infantry": 1}, grey)
	var larger: ArrayMesh = UM.army_mesh({"infantry": 6, "cavalry": 2, "artillery": 2}, grey)
	_check(_vertices(larger) > _vertices(small) * 2, "a bigger army is a bigger model")
	_check(UM.army_mesh({"infantry": 1}, grey) == small, "the same army is the same mesh (cached)")
	_check(UM.army_mesh({"infantry": 1}, Color(0.2, 0.3, 0.8)) != small, "another nation has its own")
	var line: Array = UM.fleet_line({"dreadnought": 3, "cruiser": 2, "destroyer": 12, "submarine": 4, "transport": 2})
	_check(line.size() <= UM.MAX_SHIPS and line.has("dreadnought") and line.has("submarine"), "a great fleet is at most eight ships, each class kept (%s)" % [line])
	_check(UM.fleet_line({}).size() == 1, "a fleet with nothing listed is one ship")
	for type: String in ["dreadnought", "cruiser", "destroyer", "submarine", "transport"]:
		var m: ArrayMesh = UM.fleet_mesh([type], grey)
		_check(_vertices(m) > 100 and m.get_aabb().size.x > 8.0, "a %s is a ship" % type)
	_check(_vertices(UM.fleet_mesh(["dreadnought"], grey)) > _vertices(UM.fleet_mesh(["destroyer"], grey)), "a dreadnought has more to it than a destroyer")
	_check(Map3DC.model_growth(0.5) == 0.0 and Map3DC.model_growth(5.0) == 1.0 and Map3DC.model_growth(1.2) > 0.0, "the models come up between the far and the near zoom")

	var gs: Node = root.get_node("GameState")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	var mode: Node = get_first_node_in_group("map_3d")
	var army = gs.armies.values()[0]
	main.camera.position = root.get_node("MapData").provinces[army.province].center
	main.camera.zoom = Vector2(2.0, 2.0)
	mode.set_enabled(true)
	for i in 8:
		await process_frame
	var shown := 0
	var models := 0
	for node: Node3D in mode._standees:
		if node.visible:
			shown += 1
			if (node.get_node("model") as MeshInstance3D).visible and (node.get_node("model") as MeshInstance3D).mesh != null:
				models += 1
	_check(shown > 0 and models == shown, "close to the map every banner has a model (%d of %d)" % [models, shown])
	var cards := 0
	for node: Node3D in mode._standees:
		if node.visible and str(node.get_meta("card_key", "")) != "" and (node.get_node("card") as Sprite3D).texture != null and node.get_node("card_view/painter").get("card_only"):
			cards += 1
	_check(cards == shown, "each has a card painted as the flat map paints its banner (%d)" % cards)
	army.fighting = true
	gs.armies_changed.emit()
	for i in 8:
		await process_frame
	var burning := 0
	for node: Node3D in mode._standees:
		if node.visible and (node.get_node("battle") as MeshInstance3D if false else node.get_node("battle")).visible:
			burning += 1
	_check(burning > 0, "where men are fighting, smoke rises from their model")
	army.fighting = false
	main.camera.zoom = Vector2(0.5, 0.5)
	for i in 8:
		await process_frame
	var far_models := 0
	for node: Node3D in mode._standees:
		if node.visible and (node.get_node("model") as MeshInstance3D).visible:
			far_models += 1
	_check(far_models == 0, "far from it only banners")
	print("FAILURES: ", _failures)
	quit(_failures)
