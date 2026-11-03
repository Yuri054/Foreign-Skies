extends SceneTree
## Writes what the GDScript game state holds right after a scenario is loaded, for the Rust port (rust/fs_sim) to
## reproduce: who owns and holds each province, its people, buildings and base income, each nation's summed provinces and
## budget, also with enemy-held ground and under strain. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_state_golden.gd -- rust/fs_sim/tests/golden/state.json


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	var gs: Node = root.get_node("GameState")
	var result := {}
	var peace_dir := _make_peace_copy("july_1914")
	for name in ["july_1914", "jan_1900"]:
		gs.load_scenario(peace_dir if name == "july_1914" else "res://data/scenarios/%s/" % name)
		var count: int = gs.province_owner.size()
		var provinces := []
		for id in range(1, count):
			var buildings := []
			for type in gs.province_buildings[id]:
				buildings.append([type, gs.province_buildings[id][type]])
			provinces.append({"id": id, "owner": gs.province_owner[id], "controller": gs.province_controller[id],
					"population": gs.province_population[id], "buildings": buildings, "base_income": B(gs.province_base_income[id])})
		var nations := []
		for tag in gs.nations:
			var n = gs.nations[tag]
			nations.append({"tag": tag, "treasury": B(n.treasury), "capital": n.capital, "peacetime_army": n.peacetime_army,
					"naval_budget": B(n.naval_budget), "population": n.population, "provinces": Array(n.provinces),
					"sums": _bits_of(gs.economy_sums[tag]), "state": _nation_state(n), "budget": _bits_of(n.budget)})
		result[name] = {"provinces": provinces, "nations": nations}
		print(name, " ", provinces.size(), " provinces, ", nations.size(), " nations")
	# The same scenario with provinces held by an enemy: the owner loses their income, the holder collects a share of it.
	gs.load_scenario(peace_dir)
	var changes := []
	var moved := {"GER": 0, "AUH": 0, "FRA": 0}
	var takers := {"GER": "FRA", "AUH": "SRB", "FRA": "GER"}
	var limits := {"GER": 4, "AUH": 3, "FRA": 2}
	for id in range(1, gs.province_owner.size()):
		var owner_tag: String = gs.province_owner[id]
		if moved.has(owner_tag) and moved[owner_tag] < limits[owner_tag]:
			gs.set_controller(id, takers[owner_tag])
			changes.append([id, takers[owner_tag]])
			moved[owner_tag] += 1
	load("res://scripts/sim/economy.gd").recompute(gs)
	var occupied_nations := []
	for tag in gs.nations:
		occupied_nations.append({"tag": tag, "sums": _bits_of(gs.economy_sums[tag]), "state": _nation_state(gs.nations[tag]), "budget": _bits_of(gs.nations[tag].budget)})
	result["july_1914_occupied"] = {"changes": changes, "nations": occupied_nations}
	print("occupied: ", changes)
	# The same scenario with the economy under strain: mobilization, debt, blockade, a national focus, and two wars (which
	# put war support's curve on the income).
	gs.load_scenario(peace_dir)
	var spec := [
		{"tag": "GER", "mobilization": 0.3, "focus_fx": {"income": 0.04, "cp": 0.75}},
		{"tag": "FRA", "treasury": -80.0, "blockade": 0.4, "mobilization": 0.15, "war_support": 25.0},
		{"tag": "AUH", "mobilization": 0.5, "manpower": 123456, "war_support": 80.0},
		{"tag": "SRB", "blockade": 0.9, "war_support": 60.0},
		{"tag": "GBR", "treasury": -3.5},
		{"tag": "RUS", "war_support": 50.0, "blockade": 0.05, "focus_fx": {"income": -0.02, "cp": 1.5}},
	]
	for entry in spec:
		var n = gs.nations[entry.tag]
		for k in entry:
			if k != "tag":
				n.set(k, entry[k])
	gs.set_war("GER", "FRA", true)
	gs.set_war("AUH", "SRB", true)
	load("res://scripts/sim/economy.gd").recompute(gs)
	var spec_out := []
	for entry in spec:
		var e := {}
		for k in entry:
			if entry[k] is Dictionary:
				e[k] = _bits_of(entry[k])
			elif entry[k] is float:
				e[k] = B(entry[k])
			else:
				e[k] = entry[k]
		spec_out.append(e)
	var stressed_nations := []
	for tag in gs.nations:
		stressed_nations.append({"tag": tag, "sums": _bits_of(gs.economy_sums[tag]), "state": _nation_state(gs.nations[tag]), "budget": _bits_of(gs.nations[tag].budget)})
	result["july_1914_stressed"] = {"spec": spec_out, "wars": [["GER", "FRA"], ["AUH", "SRB"]], "nations": stressed_nations}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	quit(0)


## July 1914 without the war it opens with (wars are not ported yet): a copy of the scenario folder with starting_wars removed.
func _make_peace_copy(name: String) -> String:
	var src := "res://data/scenarios/%s/" % name
	var dst := "user://peace_%s/" % name
	DirAccess.make_dir_recursive_absolute(dst)
	for file in DirAccess.get_files_at(src):
		if file.ends_with(".import"):
			continue
		if file == "scenario.json":
			var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src + file))
			sc.erase("starting_wars")
			var out := FileAccess.open(dst + file, FileAccess.WRITE)
			out.store_string(JSON.stringify(sc))
			out.close()
		else:
			DirAccess.copy_absolute(src + file, dst + file)
	return dst


## A dictionary of numbers (and dictionaries of them) with every float as its bits.
func _bits_of(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var v = d[k]
		if v is Dictionary:
			out[k] = _bits_of(v)
		elif v is float:
			out[k] = B(v)
		else:
			out[k] = v
	return out


func _nation_state(n) -> Dictionary:
	return {"naval_budget": B(n.naval_budget), "naval_overhead": B(n.naval_overhead), "manpower": n.manpower,
			"men_in_units": n.men_in_units, "men_exercising": n.men_exercising, "war_support": B(n.war_support),
			"mobilization": B(n.mobilization), "blockade": B(n.blockade), "treasury": B(n.treasury),
			"peacetime_army": n.peacetime_army, "cp": B(n.cp)}
