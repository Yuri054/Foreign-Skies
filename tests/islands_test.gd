extends SceneTree
## Headless test of the islands added by tools/add_islands.py: each has an owner, people, a
## coast, a port, and belongs to its owner's province list.
## Run: godot --headless --path . -s res://tests/islands_test.gd

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
	var md: Node = root.get_node("MapData")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var want := {"Isle of Man": "GBR", "Channel Islands": "GBR", "Malta": "GBR", "Cyprus": "GBR", "Faroe Islands": "DEN", "Åland": "RUS"}
	var found := {}
	for id in range(1, md.provinces.size()):
		var name: String = md.provinces[id].name
		if want.has(name):
			found[name] = id
	for name in want:
		_check(found.has(name), "%s is a province" % name)
		if not found.has(name):
			continue
		var id: int = found[name]
		_check(gs.province_owner[id] == want[name], "%s belongs to %s" % [name, want[name]])
		_check(gs.province_population[id] > 10000, "%s has people (%d)" % [name, gs.province_population[id]])
		_check(md.provinces[id].coastal, "%s has a coast" % name)
		_check(gs.nations[want[name]].provinces.has(id), "%s is in %s's list" % [name, want[name]])
		_check(not md.zones_of_port(id).is_empty(), "%s opens on a sea zone" % name)
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
