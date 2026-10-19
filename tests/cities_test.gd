extends SceneTree
## Headless test of the major cities: the list is read from the scenario, every city stands in a
## province of the map and on that province's ground, each nation's capital province holds its
## capital city, the biggest 1914 cities are there with sound populations, the layer shows more
## cities as the map zooms in, and the province card names the city.
## Run: godot --headless --path . -s res://tests/cities_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var map: Node = root.get_node("MapData")
	var Layer = load("res://scripts/map/city_layer.gd")
	_check(gs.cities.size() >= 80, "the scenario lists its major cities (%d)" % gs.cities.size())
	var by_name := {}
	var stray := 0
	var ids := {}
	for c in gs.cities:
		by_name[c.name] = c
		ids[c.id] = true
		var at: Vector2i = Vector2i(c.pos)
		if map.province_at_pixel(at) != c.province:
			stray += 1
	_check(stray == 0 and ids.size() == gs.cities.size(), "every city stands on its own province's ground, with its own id (%d stray)" % stray)
	for name in ["London", "Paris", "Berlin", "Vienna", "Moscow", "Saint Petersburg", "Constantinople", "Rome", "Warsaw", "Budapest"]:
		_check(by_name.has(name), "%s is there" % name)
	_check(by_name.London.pop > by_name.Paris.pop and by_name.Paris.pop > by_name.Rome.pop, "1914 populations: London, then Paris, then Rome")
	var sound := true
	for c in gs.cities:
		sound = sound and c.pop >= 5000 and c.pop <= 8_000_000 and c.rank >= 1 and c.rank <= 3
	_check(sound, "populations and ranks are sound")
	var missing: Array = []
	for tag in gs.nations:
		var cap: int = gs.nations[tag].capital
		var ok := false
		for c in gs.cities_by_province.get(cap, []):
			ok = ok or c.rank == 1
		if not ok:
			missing.append(tag)
	_check(missing.is_empty(), "every nation's capital province holds its capital city (%s)" % ", ".join(missing))
	var far: Array = Layer.visible_cities(gs.cities, 0.2)
	var mid: Array = Layer.visible_cities(gs.cities, 0.4)
	var near: Array = Layer.visible_cities(gs.cities, 1.0)
	_check(far.size() < mid.size() and mid.size() < near.size() and near.size() == gs.cities.size(), "zooming in shows more cities (%d, %d, %d)" % [far.size(), mid.size(), near.size()])
	_check(far.all(func(c: Dictionary) -> bool: return c.rank == 1), "the whole map shows only capitals")
	var paris: Dictionary = by_name.Paris
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for picker in get_nodes_in_group("nation_picker"):
		picker.queue_free()
	await process_frame
	gs.set_player("FRA")
	main.map_view.select(paris.province)
	await process_frame
	await process_frame
	var text: String = get_first_node_in_group("province_panel").plain_text()
	_check("Paris" in text and "Capital" in text, "the province card names the city and its rank")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
