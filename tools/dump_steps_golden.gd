extends SceneTree
## Writes what the GDScript economy does over time, for the Rust port (rust/fs_sim) to reproduce: Economy.step_day thirty
## times and Economy.step_month, month after month, on a loaded scenario with nothing else running (no AI, no diplomacy),
## and each nation's figures after every month. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_steps_golden.gd -- rust/fs_sim/tests/golden/steps.json


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


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


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	var gs: Node = root.get_node("GameState")
	var Eco: GDScript = load("res://scripts/sim/economy.gd")
	var result := {}
	var peace_dir := _make_peace_copy("july_1914")

	# 1. July 1914 at peace, with works under construction in six nations, for two years.
	gs.load_scenario(peace_dir)
	# Italy: a standing army just under what its people allow (so the cap binds), a leftover weariness that eases in peace, and
	# a mobilization above what peace allows (it is brought down).
	var ita = gs.nations["ITA"]
	var cap: int = Eco.standing_cap(gs, ita)
	var peace_spec := [{"tag": "ITA", "peacetime_army": cap - 500, "weariness": 0.2, "mobilization": 0.7}]
	for entry in peace_spec:
		for k in entry:
			if k != "tag":
				gs.nations[entry.tag].set(k, entry[k])
	var jobs := _give_jobs(gs, Eco, ["GBR", "FRA", "GER", "RUS", "AUH", "ITA"])
	jobs.append_array(_give_stuck_jobs(gs, Eco, "GBR"))
	result["peace_with_works"] = {"spec": [{"tag": "ITA", "peacetime_army": cap - 500, "weariness": B(0.2), "mobilization": B(0.7)}],
			"jobs": jobs, "months": _run(gs, Eco, 24), "end": _end_state(gs)}

	# 2. January 1900, nothing built, one year.
	gs.load_scenario("res://data/scenarios/jan_1900/")
	result["jan_1900"] = {"months": _run(gs, Eco, 12), "end": _end_state(gs)}

	# 3. July 1914 at war: strain, blockade, famine, enemy-held ground, war deaths, works, a year and a half.
	gs.load_scenario(peace_dir)
	var spec := [
		{"tag": "GER", "mobilization": 0.3, "tax_rate": 0.2, "arms_share": 0.4, "men_exercising": 20000, "investment": 3.0,
				"deaths_month": 30000.0, "focus_fx": {"gdp": 0.04, "industry": 0.03, "food": 0.02, "trade": 0.01, "growth": 0.002, "construction": 4.0}},
		{"tag": "FRA", "treasury": -80.0, "blockade": 0.4, "weariness": 0.1, "starving": true, "mobilization": 0.15, "war_support": 25.0,
				"deaths_month": 50000.0, "war_dead": 200000.0},
		{"tag": "AUH", "tax_rate": 0.07, "mobilization": 0.5, "manpower": 123456, "war_support": 80.0, "materials_need_mult": 1.4, "deaths_month": 4000.0},
		{"tag": "SRB", "blockade": 0.9, "starving": true, "weariness": 0.3, "munitions": 5000.0, "war_support": 60.0, "deaths_month": 9000.0},
		{"tag": "GBR", "investment": 1.5, "tax_rate": 0.35},
	]
	for entry in spec:
		var n = gs.nations[entry.tag]
		for k in entry:
			if k != "tag":
				n.set(k, entry[k])
	gs.set_war("GER", "FRA", true)
	gs.set_war("AUH", "SRB", true)
	var changes := [[1, "SRB"], [2, "SRB"], [3, "SRB"], [165, "GER"], [166, "GER"], [356, "FRA"], [357, "FRA"]]
	for c in changes:
		gs.set_controller(c[0], c[1])
	Eco.recompute(gs)
	var war_jobs := _give_jobs(gs, Eco, ["GER", "FRA", "AUH", "SRB", "RUS"])
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
	result["at_war"] = {"spec": spec_out, "wars": [["GER", "FRA"], ["AUH", "SRB"]], "controllers": changes, "jobs": war_jobs,
			"months": _run(gs, Eco, 18), "end": _end_state(gs)}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


## Starts a few works in each nation, in its biggest provinces, straight into the queue: [{tag, province, type, ic, days}].
func _give_jobs(gs: Node, Eco: GDScript, tags: Array) -> Array:
	var out := []
	for tag in tags:
		var n = gs.nations[tag]
		var ids: Array = Array(n.provinces)
		ids.sort_custom(func(a: int, b: int) -> bool: return gs.province_gdp[a] > gs.province_gdp[b] or (gs.province_gdp[a] == gs.province_gdp[b] and a < b))
		var types := ["factory", "railway", "port", "factory"]
		for i in 4:
			var id: int = ids[i]
			var type: String = types[i]
			var ic: float = Eco.level_cost(gs, id, type)
			var days: int = int(Eco.cfg.buildings[type].min_days)
			n.construction.append(Eco.new_job(id, type, ic, days))
			out.append({"tag": tag, "province": id, "type": type, "ic": B(ic), "days": days})
		# a hull on the slips as well (its job has the same fields the daily step reads)
		var hull = Eco.new_job(ids[0], "dreadnought", 9000.0, 300)
		n.shipbuilding.append(hull)
		out.append({"tag": tag, "province": ids[0], "type": "dreadnought", "ic": B(9000.0), "days": 300, "ship": true})
	return out


## Two works that get no points (their rate is nothing) but are nearly done: one just above the point at which the game
## counts a project as finished, one just below it.
func _give_stuck_jobs(gs: Node, Eco: GDScript, tag: String) -> Array:
	var out := []
	var ids: Array = Array(gs.nations[tag].provinces)
	for left in [0.005, 0.00005]:
		var id: int = ids[out.size() + 5]
		var job = Eco.new_job(id, "railway", 100.0, 10)
		job.points_left = left
		job.rate = 0.0
		gs.nations[tag].construction.append(job)
		out.append({"tag": tag, "province": id, "type": "railway", "ic": B(100.0), "days": 10, "points_left": B(left), "rate": B(0.0)})
	return out


func _run(gs: Node, Eco: GDScript, months: int) -> Array:
	var rows := []
	for m in months:
		for d in 30:
			Eco.step_day(gs)
		Eco.step_month(gs)
		var nations := []
		for tag in gs.nations:
			var n = gs.nations[tag]
			nations.append({"tag": tag, "state": _state(n), "net": B(n.budget.net), "gdp": B(n.budget.gdp), "industry": B(n.budget.industry),
					"revenue": B(n.budget.revenue), "cp": B(n.budget.construction_points), "jobs": _jobs(n.construction), "ships": _jobs(n.shipbuilding)})
		rows.append(nations)
	return rows


func _jobs(list: Array) -> Array:
	var out := []
	for j in list:
		out.append([j.province, j.type, B(j.points_left), B(j.given), j.days_left])
	return out


func _state(n) -> Dictionary:
	return {"treasury": B(n.treasury), "development": B(n.development), "civil_index": B(n.civil_index), "wage": B(n.wage),
			"civil_mult": B(n.civil_mult), "civil_base": B(n.civil_base), "munitions": B(n.munitions), "construction_used": B(n.construction_used),
			"war_support": B(n.war_support), "weariness": B(n.weariness), "war_dead": B(n.war_dead), "deaths_month": B(n.deaths_month),
			"mobilization": B(n.mobilization), "naval_budget": B(n.naval_budget), "manpower": n.manpower, "men_in_units": n.men_in_units,
			"peacetime_army": n.peacetime_army, "population": n.population, "starving": 1 if n.starving else 0,
			"munitions_used_last": B(n.munitions_used_last), "munitions_used_month": B(n.munitions_used_month)}


func _end_state(gs: Node) -> Dictionary:
	var pops := []
	var fracs := []
	var buildings := []
	for id in range(1, gs.province_owner.size()):
		pops.append(gs.province_population[id])
		fracs.append(B(gs.province_pop_frac[id]))
		var b := []
		for t in gs.province_buildings[id]:
			b.append([t, gs.province_buildings[id][t]])
		buildings.append(b)
	var budgets := {}
	for tag in gs.nations:
		budgets[tag] = _bits_of(gs.nations[tag].budget)
	return {"population": pops, "frac": fracs, "buildings": buildings, "budgets": budgets, "materials_k": B(gs.materials_k)}


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
