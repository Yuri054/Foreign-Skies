extends SceneTree
## Writes what the GDScript game state holds right after a scenario is loaded, for the Rust port (rust/fs_sim) to
## reproduce: who owns and holds each province, its people, deposits and works, what each province makes, each nation's
## summed output and development, and the raw-materials constant. Floats are the bits of their 64-bit value.
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
			var deposit := []
			for r in gs.province_deposit[id]:
				deposit.append([r, B(gs.province_deposit[id][r])])
			provinces.append({"id": id, "owner": gs.province_owner[id], "controller": gs.province_controller[id],
					"population": gs.province_population[id], "buildings": buildings, "deposit": deposit,
					"gdp": B(gs.province_gdp[id]), "industry": B(gs.province_industry[id]),
					"food": B(gs.province_food[id]), "pool": B(gs.province_pool[id])})
		var nations := []
		for tag in gs.nations:
			var n = gs.nations[tag]
			var sums := {}
			for k in gs.economy_sums[tag]:
				sums[k] = B(gs.economy_sums[tag][k])
			nations.append({"tag": tag, "development": B(n.development), "agri_yield": B(n.agri_yield), "tax_rate": B(n.tax_rate),
					"pop_growth": B(n.pop_growth), "treasury": B(n.treasury), "capital": n.capital, "peacetime_army": n.peacetime_army,
					"materials_need_mult": B(n.materials_need_mult), "naval_budget": B(n.naval_budget),
					"population": n.population, "provinces": Array(n.provinces), "sums": sums, "state": _nation_state(n), "budget": _bits_of(n.budget)})
		result[name] = {"provinces": provinces, "nations": nations, "materials_k": B(gs.materials_k)}
		print(name, " ", provinces.size(), " provinces, ", nations.size(), " nations, materials_k ", gs.materials_k)
	# The same scenario with provinces held by an enemy: the owner loses their output, the holder collects a share of the tax.
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
		var sums := {}
		for k in gs.economy_sums[tag]:
			sums[k] = B(gs.economy_sums[tag][k])
		occupied_nations.append({"tag": tag, "sums": sums, "state": _nation_state(gs.nations[tag]), "budget": _bits_of(gs.nations[tag].budget)})
	result["july_1914_occupied"] = {"changes": changes, "nations": occupied_nations, "materials_k": B(gs.materials_k)}
	print("occupied: ", changes)
	# The same scenario with the economy under strain: mobilization, debt, blockade, famine, investment, heavy taxes, a
	# national focus, men on exercise, and two wars (which put war support's curve on the tax).
	gs.load_scenario(peace_dir)
	var spec := [
		{"tag": "GER", "mobilization": 0.3, "tax_rate": 0.2, "arms_share": 0.4, "men_exercising": 20000, "investment": 3.0,
				"focus_fx": {"gdp": 0.04, "industry": 0.03, "food": 0.02, "trade": 0.01, "growth": 0.002, "construction": 4.0}},
		{"tag": "FRA", "treasury": -80.0, "blockade": 0.4, "weariness": 0.1, "starving": true, "mobilization": 0.15, "war_support": 25.0},
		{"tag": "AUH", "tax_rate": 0.07, "mobilization": 0.5, "manpower": 123456, "war_support": 80.0, "materials_need_mult": 1.4},
		{"tag": "SRB", "blockade": 0.9, "starving": true, "weariness": 0.3, "munitions": 5000.0, "war_support": 60.0},
		{"tag": "GBR", "investment": 1.5, "tax_rate": 0.35},
		{"tag": "RUS", "war_support": 50.0, "blockade": 0.05, "arms_share": 1.7, "focus_fx": {"gdp": -0.02, "construction": 1.5}},
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
		var sums := {}
		for k in gs.economy_sums[tag]:
			sums[k] = B(gs.economy_sums[tag][k])
		stressed_nations.append({"tag": tag, "sums": sums, "state": _nation_state(gs.nations[tag]), "budget": _bits_of(gs.nations[tag].budget)})
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
	return {"civil_mult": B(n.civil_mult), "civil_base": B(n.civil_base), "civil_index": B(n.civil_index), "wage": B(n.wage),
			"naval_budget": B(n.naval_budget), "naval_overhead": B(n.naval_overhead), "manpower": n.manpower,
			"men_in_units": n.men_in_units, "men_exercising": n.men_exercising, "munitions": B(n.munitions),
			"arms_share": B(n.arms_share), "war_support": B(n.war_support), "mobilization": B(n.mobilization),
			"blockade": B(n.blockade), "treasury": B(n.treasury), "peacetime_army": n.peacetime_army}
