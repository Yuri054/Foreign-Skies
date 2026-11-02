extends SceneTree
## Writes what the GDScript national focus does over time, for the Rust port (rust/fs_sim) to reproduce: every nation takes
## up the first focus of its tree it may, and the next when that is done, while Economy.step_day, Focus.step_day and
## Economy.step_month run for a good while (forty-eight months for July 1914, long enough for the repeatable foci that follow the trees) with nothing else going on. After each month: each nation's focus, what it
## has done, the bonuses it gives, and what its effects moved (treasury, war support, army, prestige, diplomacy points),
## and the relations and claims they made. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_focus_golden.gd -- rust/fs_sim/tests/golden/focus.json


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var Eco: GDScript = load("res://scripts/sim/economy.gd")
	var Foc: GDScript = load("res://scripts/sim/focus.gd")
	var result := {}
	var peace_dir := _make_peace_copy("july_1914")
	for run in [["july_1914", peace_dir, 48], ["jan_1900", "res://data/scenarios/jan_1900/", 18]]:
		gs.load_scenario(run[1])
		var start_days: int = clock.days_elapsed
		var relations0 := {}
		for k in gs.relations:
			relations0[k] = B(gs.relations[k])
		var starts := []
		var months := []
		for month in run[2]:
			for d in 30:
				for tag in gs.nations:
					if gs.nations[tag].focus.is_empty():
						for f in Foc.tree_of(tag):
							if Foc.block(gs, tag, f.id) == "":
								Foc.start(gs, tag, f.id)
								starts.append([clock.days_elapsed - start_days, tag, f.id])
								break
				Eco.step_day(gs)
				Foc.step_day(gs)
				if gs.economy_dirty:
					gs.economy_dirty = false
					gs.budget_dirty = false
					Eco.recompute(gs)
				clock.days_elapsed += 1
			Eco.step_month(gs)
			months.append(_snapshot(gs))
		result[run[0]] = {"relations0": relations0, "claims0": gs.casus_belli.size() - _claims_made(months), "starts": starts, "months": months}
	# Effects applied by hand, to reach the ones the trees do not use early: a claim, army growth, relations that rise and fall past
	# their limits, points past their maximum, and a name that is not a nation.
	gs.load_scenario(peace_dir)
	clock.days_elapsed = 100
	var direct_relations0 := {}
	for k in gs.relations:
		direct_relations0[k] = B(gs.relations[k])
	var cases := [
		["GBR", {"gdp": 0.02, "construction": 2.0, "diplomacy": 0.4, "prestige": 3.0, "points": 15.0, "treasury": 12.5, "war_support": -7.0,
				"army_size": 0.05, "relation": [["FRA", 12.0], ["GER", -30.0], ["XXX", 5.0]], "claim": ["FRA", "XXX"]}],
		["ITA", {"food": 0.1, "trade": 0.01, "growth": 0.004, "industry": 0.0, "points": 400.0, "war_support": 90.0, "army_size": 0.333,
				"relation": [["AUH", 200.0], ["GER", -500.0]], "claim": ["AUH"]}],
		["GER", {"prestige": -2.0, "points": -5.0, "treasury": -30.0, "army_size": -0.1}],
	]
	var direct_out := []
	for c in cases:
		Foc.apply_effects(gs, c[0], c[1])
		direct_out.append([c[0], c[1]])
	var direct_snapshot := _snapshot(gs)
	result["direct"] = {"relations0": direct_relations0, "effects": direct_out, "days": 100, "after": direct_snapshot}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _claims_made(months: Array) -> int:
	return months[months.size() - 1].claims.size()


func _snapshot(gs: Node) -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		var fx := {}
		for k in n.focus_fx:
			fx[k] = B(n.focus_fx[k])
		var counts := {}
		for k in n.focus_count:
			counts[k] = n.focus_count[k]
		nations.append({"tag": tag, "focus": [n.focus.get("id", ""), n.focus.get("days_left", 0), n.focus.get("days_total", 0)],
				"done": n.focus_done.duplicate(), "count": counts, "fx": fx, "treasury": B(n.treasury), "war_support": B(n.war_support),
				"peacetime_army": n.peacetime_army, "manpower": n.manpower, "prestige": B(n.prestige),
				"points": B(n.diplomacy_points), "development": B(n.development), "net": B(n.budget.net)})
	var relations := {}
	for k in gs.relations:
		relations[k] = B(gs.relations[k])
	var claims := []
	for c in gs.casus_belli:
		claims.append([c.holder, c.target, c.kind, c.expires_day])
	return {"nations": nations, "relations": relations, "claims": claims}


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
