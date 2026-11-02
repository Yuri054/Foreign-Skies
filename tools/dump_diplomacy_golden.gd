extends SceneTree
## Writes what the GDScript diplomacy does over time, for the Rust port (rust/fs_sim) to reproduce: the treaties, relations
## and rivalries a scenario loads with, and then Diplomacy.step_day (mobilization, alarms, call-ups) and
## Diplomacy.step_month (points, relation projects, prestige, grievance, gifts, war support, the drift of opinion)
## running with the economy for a year and a half, with some of the great powers mobilizing. Floats are the bits of
## their 64-bit value.
##   godot --headless --path . -s res://tools/dump_diplomacy_golden.gd -- rust/fs_sim/tests/golden/diplomacy.json


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _bits_map(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = B(d[k])
	return out


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var Eco: GDScript = load("res://scripts/sim/economy.gd")
	var Dip: GDScript = load("res://scripts/sim/diplomacy.gd")
	var result := {}
	var peace_dir := _make_peace_copy("july_1914")
	for run in [["july_1914", peace_dir, 18], ["jan_1900", "res://data/scenarios/jan_1900/", 12]]:
		gs.load_scenario(run[1])
		var treaties := []
		for t in gs.treaties:
			treaties.append([t.id, t.kind, t.a, t.b, t.start_day, t.end_day, JSON.stringify(t.terms), t.note])
		var start := {"treaties": treaties, "relations": _bits_map(gs.relations), "relation_base": _bits_map(gs.relation_base),
				"rivalries": _bits_map(gs.rivalries), "next_treaty_id": gs.next_treaty_id}
		# Pressure on the system: great powers mobilizing, an opinion project, gifts that fade, a casus belli that lapses and
		# a rivalry that fades away.
		var spec := {"mobilization": {"GER": 0.6, "RUS": 0.5, "AUH": 0.45}, "projects": [{"from": "GBR", "to": "FRA", "months_left": 4}],
				"gifts": {"GBR>FRA": 3.0, "FRA>GBR": 0.06}, "cbs": [{"holder": "GER", "target": "FRA", "kind": "test", "expires_day": 90}, {"holder": "FRA", "target": "GER", "kind": "test2", "expires_day": 121}],
				"prestige": {"SRB": -100.0, "GBR": 30.0}, "points_price": {"ITA": 2.5},
				"rivalries": {"AUH>ITA": 0.5}, "grievance": {"SRB>AUH": 40.0, "FRA>GER": 120.0}}
		for tag in spec.mobilization:
			gs.nations[tag].mobilization = spec.mobilization[tag]
		for p in spec.projects:
			gs.relation_projects.append(p.duplicate())
		for k in spec.gifts:
			gs.gift_memory[k] = spec.gifts[k]
		for cb in spec.cbs:
			gs.casus_belli.append(cb.duplicate())
		for k in spec.rivalries:
			gs.rivalries[k] = spec.rivalries[k]
		for k in spec.grievance:
			gs.grievance[k] = spec.grievance[k]
		for k in spec.prestige:
			gs.nations[k].prestige = spec.prestige[k]
		for k in spec.points_price:
			gs.nations[k].points_price = spec.points_price[k]
		Eco.recompute(gs)
		var months := []
		for month in run[2]:
			for d in 30:
				Eco.step_day(gs)
				Dip.step_day(gs)
				clock.days_elapsed += 1
			Eco.step_month(gs)
			Dip.step_month(gs)
			months.append(_snapshot(gs))
		result[run[0]] = {"start": start, "spec": spec, "months": months}
	# War support at war: what moves it each month (in the game's order), and the month's step on top of the strained
	# economy, with two wars, enemy-held ground, debt, blockade and men lost.
	gs.load_scenario(peace_dir)
	var War_spec := [
		{"tag": "GER", "mobilization": 0.3, "tax_rate": 0.2, "men_lost_month": 120000.0, "war_support": 70.0},
		{"tag": "FRA", "treasury": -900.0, "blockade": 0.4, "tax_rate": 0.3, "men_lost_month": 50000.0, "war_support": 55.0},
		{"tag": "AUH", "men_lost_month": 30000.0, "war_support": 80.0, "tax_rate": 0.07},
		{"tag": "SRB", "blockade": 0.9, "men_lost_month": 5000.0, "war_support": 60.0},
		{"tag": "GBR", "tax_rate": 0.35, "war_support": 40.0},
		{"tag": "RUS", "tax_rate": 0.05, "war_support": 56.0},
	]
	for entry in War_spec:
		for k in entry:
			if k != "tag":
				gs.nations[entry.tag].set(k, entry[k])
	gs.set_war("GER", "FRA", true)
	gs.set_war("AUH", "SRB", true)
	var war_controllers := [[1, "SRB"], [2, "SRB"], [3, "SRB"], [165, "GER"], [166, "GER"], [356, "FRA"], [357, "FRA"]]
	for c in war_controllers:
		gs.set_controller(c[0], c[1])
	Eco.recompute(gs)
	var WS: GDScript = load("res://scripts/sim/war_support.gd")
	var changes := {}
	for tag in gs.nations:
		var list := []
		var d: Dictionary = WS.monthly_changes(gs, tag)
		for k in d:
			list.append([k, B(d[k])])
		changes[tag] = list
	WS.step_month(gs)
	var ws_out := []
	for e in War_spec:
		var o := {}
		for k in e:
			o[k] = B(e[k]) if e[k] is float else e[k]
		ws_out.append(o)
	result["war_support"] = {"spec": ws_out, "controllers": war_controllers, "wars": [["GER", "FRA"], ["AUH", "SRB"]], "changes": changes, "after": _snapshot(gs)}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _snapshot(gs: Node) -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		nations.append({"tag": tag, "mobilization": B(n.mobilization), "points": B(n.diplomacy_points), "prestige": B(n.prestige),
				"points_price": B(n.points_price), "war_support": B(n.war_support), "treasury": B(n.treasury), "net": B(n.budget.net),
				"manpower": n.manpower, "men_in_units": n.men_in_units})
	var calls := {}
	for k in gs.mobilization_calls:
		var c = gs.mobilization_calls[k]
		calls[k] = [c.tag, c["for"], c.against, c.day]
	var projects := []
	for p in gs.relation_projects:
		projects.append([p.from, p.to, p.months_left])
	var cbs := []
	for c in gs.casus_belli:
		cbs.append([c.holder, c.target, c.kind, c.expires_day])
	return {"nations": nations, "relations": _bits_map(gs.relations), "relation_base": _bits_map(gs.relation_base),
			"grievance": _bits_map(gs.grievance), "rivalries": _bits_map(gs.rivalries), "alarms": gs.alarms.duplicate(),
			"calls": calls, "projects": projects, "gifts": _bits_map(gs.gift_memory), "cbs": cbs, "join_calls": gs.join_calls.size()}


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
