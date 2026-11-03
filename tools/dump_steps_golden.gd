extends SceneTree
## Writes what the GDScript economy does over time, for the Rust port (rust/fs_sim) to reproduce: Economy.step_day thirty
## times and Economy.step_month, month after month (income, construction points, the queue, manpower, war deaths), on a loaded scenario with nothing else running (no AI, no diplomacy),
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

	# 1. July 1914 at peace, with projects queued in six nations, for two years.
	gs.load_scenario(peace_dir)
	# Italy: a standing army just under what its people allow (so the cap binds), and a mobilization above what peace
	# allows (it is brought down).
	var ita = gs.nations["ITA"]
	var cap: int = Eco.standing_cap(gs, ita)
	ita.peacetime_army = cap - 500
	ita.mobilization = 0.7
	var jobs := _give_jobs(gs, Eco, ["GBR", "FRA", "GER", "RUS", "AUH", "ITA"])
	result["peace_with_works"] = {"spec": [{"tag": "ITA", "peacetime_army": cap - 500, "mobilization": B(0.7)}],
			"jobs": jobs, "months": _run(gs, Eco, 24), "end": _end_state(gs)}

	# 2. January 1900, nothing queued, one year.
	gs.load_scenario("res://data/scenarios/jan_1900/")
	result["jan_1900"] = {"months": _run(gs, Eco, 12), "end": _end_state(gs)}

	# 3. July 1914 at war: strain, blockade, debt, enemy-held ground, war deaths, projects, a year and a half.
	gs.load_scenario(peace_dir)
	var spec := [
		{"tag": "GER", "mobilization": 0.3, "men_exercising": 20000, "deaths_month": 30000.0, "focus_fx": {"income": 0.04, "cp": 0.75}},
		{"tag": "FRA", "treasury": -80.0, "blockade": 0.4, "mobilization": 0.15, "war_support": 25.0, "deaths_month": 50000.0,
				"war_dead": 200000.0},
		{"tag": "AUH", "mobilization": 0.5, "manpower": 123456, "war_support": 80.0, "deaths_month": 4000.0},
		{"tag": "SRB", "blockade": 0.9, "war_support": 60.0, "deaths_month": 9000.0},
		{"tag": "GBR", "treasury": 5000.0, "cp": 2000.0},
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
	var war_jobs := _give_jobs(gs, Eco, ["GER", "FRA", "AUH", "SRB", "RUS", "GBR"])
	# France queues work in a province Germany holds: it waits (and does not hold up the rest) until it is free.
	for c in changes:
		if gs.province_owner[c[0]] == "FRA":
			gs.nations["FRA"].construction.push_front(Eco.new_job(c[0], "railway", 45))
			war_jobs.push_front({"tag": "FRA", "province": c[0], "type": "railway", "days": 45, "front": true})
			break
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


## Queues a few projects in each nation, in its richest provinces, straight onto the end of the queue: two in the
## richest (the second waits for the first, one project a province at a time), then a railway and a construction
## sector, then a costly batch of factories that waits for gold. And a hull on the slips. [{tag, province, type, days}]
func _give_jobs(gs: Node, Eco: GDScript, tags: Array) -> Array:
	var out := []
	for tag in tags:
		var n = gs.nations[tag]
		var ids: Array = Array(n.provinces)
		ids.sort_custom(func(a: int, b: int) -> bool:
			return gs.province_base_income[a] > gs.province_base_income[b] or (gs.province_base_income[a] == gs.province_base_income[b] and a < b))
		var plan := [[0, "civilian_factory"], [0, "railway"], [1, "railway"], [2, "construction_sector"], [3, "civilian_factory"],
				[4, "civilian_factory"], [5, "trench"]]
		for pair in plan:
			if pair[0] >= ids.size():
				continue
			var id: int = ids[pair[0]]
			var type: String = pair[1]
			var days: int = int(Eco.build_plan(gs, id, type).days)
			n.construction.append(Eco.new_job(id, type, days))
			out.append({"tag": tag, "province": id, "type": type, "days": days})
		# a hull on the slips as well (the daily step counts its days down)
		n.shipbuilding.append({"type": "dreadnought", "province": ids[0], "days_total": 300, "days_left": 300})
		out.append({"tag": tag, "province": ids[0], "type": "dreadnought", "days": 300, "ship": true})
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
			nations.append({"tag": tag, "state": _state(n), "budget": _bits_of(n.budget), "jobs": _jobs(n.construction),
					"ships": _ships(n.shipbuilding)})
		rows.append(nations)
	return rows


func _jobs(list: Array) -> Array:
	var out := []
	for j in list:
		out.append([j.province, j.type, 1 if j.started else 0, j.days_total, j.days_left])
	return out


func _ships(list: Array) -> Array:
	var out := []
	for j in list:
		out.append([j.province, j.type, j.days_left])
	return out


func _state(n) -> Dictionary:
	return {"treasury": B(n.treasury), "cp": B(n.cp), "war_support": B(n.war_support), "war_dead": B(n.war_dead),
			"deaths_month": B(n.deaths_month), "mobilization": B(n.mobilization), "naval_budget": B(n.naval_budget),
			"manpower": n.manpower, "men_in_units": n.men_in_units, "peacetime_army": n.peacetime_army, "population": n.population}


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
	return {"population": pops, "frac": fracs, "buildings": buildings, "budgets": budgets}


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
