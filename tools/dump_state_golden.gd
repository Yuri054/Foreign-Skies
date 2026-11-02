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
	for name in ["july_1914", "jan_1900"]:
		gs.load_scenario("res://data/scenarios/%s/" % name)
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
					"population": n.population, "provinces": Array(n.provinces), "sums": sums})
		result[name] = {"provinces": provinces, "nations": nations, "materials_k": B(gs.materials_k)}
		print(name, " ", provinces.size(), " provinces, ", nations.size(), " nations, materials_k ", gs.materials_k)
	# The same scenario with provinces held by an enemy: the owner loses their output, the holder collects a share of the tax.
	gs.load_scenario("res://data/scenarios/july_1914/")
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
		occupied_nations.append({"tag": tag, "sums": sums})
	result["july_1914_occupied"] = {"changes": changes, "nations": occupied_nations, "materials_k": B(gs.materials_k)}
	print("occupied: ", changes)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	quit(0)
