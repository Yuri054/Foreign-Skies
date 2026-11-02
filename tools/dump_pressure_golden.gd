extends SceneTree
## Writes what the GDScript historical pressure does over the years, for the Rust port (rust/fs_sim) to reproduce: Economy,
## Diplomacy and Pressure month after month (the events that come up, the ones the player is asked, their effects and the
## tension), with the player answering each question in a fixed way and taking public stands now and then. The run is cut off
## before a month in which the game starts a war. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_pressure_golden.gd -- rust/fs_sim/tests/golden/pressure.json


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
	var Pre: GDScript = load("res://scripts/sim/pressure.gd")
	var result := {}
	var peace_dir := _make_peace_copy("july_1914")
	var runs := [
		{"name": "july_fra", "dir": peace_dir, "scenario": "july_1914", "player": "FRA", "months": 48},
		{"name": "july_srb", "dir": peace_dir, "scenario": "july_1914", "player": "SRB", "months": 48},
		{"name": "jan_ger", "dir": "res://data/scenarios/jan_1900/", "scenario": "jan_1900", "player": "GER", "months": 120},
		{"name": "jan_srb", "dir": "res://data/scenarios/jan_1900/", "scenario": "jan_1900", "player": "SRB", "months": 120},
		{"name": "jan_bel", "dir": "res://data/scenarios/jan_1900/", "scenario": "jan_1900", "player": "BEL", "months": 120},
	]
	for run in runs:
		gs.load_scenario(run.dir)
		gs.set_player(run.player)
		var start := {"tension": B(gs.tension), "impulse": B(gs.tension_impulse), "arms_base": B(gs.tension_arms_base), "bonus": B(gs.tension_bonus),
				"pressure_ai": gs.pressure_ai, "pressure_start": gs.pressure_start, "history": gs.tension_history.size(), "relations": _bits_map(gs.relations)}
		var months := []
		var answers := []
		var appeals := []
		var stopped := ""
		for m in run.months:
			# the days of the month pass, then the month's business, in the game's order
			var crossed := false
			while not crossed:
				clock.day += 1
				clock.days_elapsed += 1
				if clock.day > clock.days_in_month(clock.year, clock.month):
					clock.day = 1
					clock.month += 1
					if clock.month > 12:
						clock.month = 1
						clock.year += 1
					crossed = true
			Eco.step_month(gs)
			Dip.step_month(gs)
			Pre.step_month(gs)
			if gs.wars.size() > 0:
				stopped = "month %d: a war began" % (m + 1)
				break
			# public stands now and then
			if m == 4 or m == 9 or m == 20:
				for pair in [[run.player, "calm"], ["GER", "rattle"], ["GBR", "calm"], [run.player, "rattle"]]:
					var ok: bool = Pre.appeal(gs, pair[0], pair[1])
					appeals.append([m + 1, pair[0], pair[1], ok])
			# the player answers what they are asked, a fixed way
			var asked := []
			for d in gs.pending_events:
				asked.append([d.id, d.options.size()])
			for item in asked:
				var option: int = int(item[0]) % int(item[1])
				var ok: bool = Pre.answer(gs, item[0], option)
				answers.append([m + 1, item[0], option, ok])
			months.append(_snapshot(gs, m, answers.size()))
		result[run.name] = {"scenario": run.scenario, "player": run.player, "start": start, "answers": answers, "appeals": appeals, "months": months, "stopped": stopped}
		print(run.name, ": ", months.size(), " months, ", answers.size(), " answers, ", gs.events_fired.size(), " events fired, stopped: ", stopped)
	var Mil: GDScript = load("res://scripts/sim/military.gd")
	var UnitCls: GDScript = load("res://scripts/sim/unit.gd")

	# 1. A year of tension under strain: great powers mobilizing, a bigger German army, and two wars (which the run only stops
	# for if they multiply).
	gs.load_scenario(peace_dir)
	gs.set_player("POR")
	gs.nations["GER"].mobilization = 0.8
	gs.nations["RUS"].mobilization = 0.7
	gs.nations["AUH"].mobilization = 0.5
	for tag in ["GER", "FRA", "AUH", "SRB"]:
		gs.nations[tag].war_support = 80.0
	var extra = Mil.new_army(gs, "GER", "Extra", gs.nations["GER"].provinces[0])
	for i in 4:
		extra.units.append(UnitCls.new("infantry"))
	gs.set_war("GER", "FRA", true)
	gs.set_war("AUH", "SRB", true)
	Eco.recompute(gs)
	var strain_months := []
	# seven months: in the eighth the AI nations at war open peace talks (Peace.step_month), which are not ported
	for m in 7:
		var crossed := false
		while not crossed:
			clock.day += 1
			clock.days_elapsed += 1
			if clock.day > clock.days_in_month(clock.year, clock.month):
				clock.day = 1
				clock.month += 1
				if clock.month > 12:
					clock.month = 1
					clock.year += 1
				crossed = true
		Eco.step_month(gs)
		Dip.step_month(gs)
		Pre.step_month(gs)
		strain_months.append(_snapshot(gs, m, 0))
	result["strain"] = {"months": strain_months, "extra_army_tag": "GER", "extra_units": 4, "wars": [["GER", "FRA"], ["AUH", "SRB"]],
			"mobilization": {"GER": 0.8, "RUS": 0.7, "AUH": 0.5}, "war_support": 80.0}

	# 2. Who the events turn to (the roles that name a nation by what it is now), in different states of the world.
	var selectors := ["$player", "$lost_ground", "$winner", "$empire", "$suitor", "$trade_partner", "$great_neighbour", "$most_armed", "$second_armed"]
	var pick_cases := []
	for state in ["plain", "tied", "troubled"]:
		gs.load_scenario(peace_dir)
		if state == "tied":
			gs.nations["GBR"].men_in_units = 900000
			gs.nations["FRA"].men_in_units = 900000
			gs.nations["GER"].men_in_units = 900000
		if state == "troubled":
			gs.nations["AUH"].war_support = 30.0
			gs.nations["OTT"].war_support = 35.0
			gs.nations["RUS"].war_support = 30.0
		for player in ["FRA", "SRB", "BEL", "GER", "POR", "ESP"]:
			gs.set_player(player)
			for sel in selectors:
				pick_cases.append([state, player, sel, Pre._pick_role(gs, sel)])
	result["picks"] = pick_cases

	# 3. Effects at the extremes, one after another, with what each leaves.
	gs.load_scenario(peace_dir)
	gs.set_player("POR")
	var roles := {"a": "GER", "b": "FRA"}
	var effects := [{"tension": 7.0}, {"relation": ["a", "b", -250.0]}, {"relation": ["a", "a", 5.0]}, {"relation": ["a", "XXX", 5.0]}, {"grievance": ["a", "b", 30.0]},
			{"grievance": ["a", "b", 90.0]}, {"treaty": ["nap", "a", "b", {}, "test pact"]}, {"treaty": ["nap", "a", "b", {}, "again"]},
			{"end_treaty": ["nap", "a", "b"]}, {"end_treaty": ["alliance", "a", "b"]}, {"treasury": ["a", 12.5]}, {"revenue": ["b", 0.5]},
			{"prestige": ["a", -3.0]}, {"war_support": ["a", 130.0]}, {"war_support": ["b", -130.0]}, {"points": ["a", 500.0]},
			{"manpower": ["a", -3.0]}, {"manpower": ["b", 0.25]}, {"mobilize": ["a", 4.0]}, {"mobilize": ["b", -4.0]}, {"treasury": ["XXX", 5.0]}]
	var direct := []
	for fx in effects:
		Pre._apply(gs, fx, roles)
		direct.append({"fx": fx, "after": _snapshot(gs, 0, 0), "rel": B(gs.relations.get("FRA|GER", 0.0)), "base": B(gs.relation_base.get("FRA|GER", 0.0)),
				"grievance": gs.grievance.get("GER>FRA", -1.0)})
	result["direct_effects"] = {"roles": roles, "list": direct}

	# 4. The events that choose by tension: at low tension and at high.
	var dict_events := []
	for e in Pre.events:
		if e.ai_option is Dictionary or (e.has("b_ai_option") and e.b_ai_option is Dictionary):
			dict_events.append(e.id)
	var choices := []
	for id in dict_events:
		for impulse in [0.0, 45.0]:
			gs.load_scenario(peace_dir)
			gs.set_player("POR")
			gs.tension_impulse = impulse
			Pre._update(gs)
			var e: Dictionary = Pre._event(id)
			var rs := {}
			var fallback := ["GER", "FRA", "GBR"]
			var k := 0
			for role in e.actors:
				var tag: String = e.actors[role]
				rs[role] = tag if not tag.begins_with("$") else fallback[k]
				k += 1
			Pre._post(gs, e, rs)
			choices.append({"event": id, "impulse": impulse, "roles": rs, "wars": gs.wars.size(), "after": _snapshot(gs, 0, 0), "relations": _bits_map(gs.relations)})
	result["choices"] = choices
	# 5. Every event that has a condition, in a spread of worlds: whether it may come up.
	var conditions := []
	for state in ["base", "tense", "calm", "notai", "hostile", "friendly", "late", "war", "minor", "great", "late+notai", "late+war", "late+minor", "late+great", "late+tense", "late+calm", "late+hostile", "late+friendly", "late+war+tense", "late+tense+hostile", "late+tense+hostile+war", "late+tense+friendly"]:
		gs.load_scenario(peace_dir)
		gs.set_player("POR")
		for token in state.split("+"):
			match token:
				"tense":
					gs.tension = 70.0
				"calm":
					gs.tension = 5.0
				"notai":
					gs.pressure_ai = false
				"hostile", "friendly":
					for a in ["GBR", "FRA", "GER", "RUS", "AUH", "ITA"]:
						for b in ["GBR", "FRA", "GER", "RUS", "AUH", "ITA"]:
							if a < b:
								gs.relations["%s|%s" % [a, b]] = -80.0 if token == "hostile" else 80.0
				"late":
					gs.pressure_start = gs.pressure_start - 100
				"war":
					gs.set_war("GER", "FRA", true)
					gs.set_war("AUH", "SRB", true)
				"minor":
					gs.set_player("SRB")
				"great":
					gs.set_player("GER")
		for e in Pre.events:
			if e.has("condition"):
				conditions.append([state, e.id, Pre._condition_ok(gs, e)])
	result["conditions"] = conditions
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _snapshot(gs: Node, m: int, answered: int) -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		nations.append([B(n.prestige), B(n.treasury), B(n.war_support), B(n.mobilization), n.manpower, B(n.diplomacy_points)])
	var pending := []
	for d in gs.pending_events:
		var roles := []
		for k in d.roles:
			roles.append([k, d.roles[k]])
		var labels := []
		for o in d.options:
			labels.append(o.label)
		pending.append([d.id, d.event, d.title, d.text, roles, labels, d.as_b, d.deferred.size(), d.date])
	var chronicle := []
	for c in gs.chronicle:
		chronicle.append([c.date, c.title, c.text])
	var fired := {}
	for k in gs.events_fired:
		fired[k] = gs.events_fired[k]
	var hist: Array = gs.tension_history
	var snap := {"tension": B(gs.tension), "impulse": B(gs.tension_impulse), "arms_base": B(gs.tension_arms_base), "bonus": B(gs.tension_bonus),
			"fired": fired, "pending": pending, "chronicle": chronicle, "history_len": hist.size(), "history_last": B(hist[hist.size() - 1]),
			"next_uid": gs.next_event_uid, "nations": nations, "treaties": gs.treaties.size(), "appeal_ready": gs.appeal_ready.duplicate()}
	if m % 12 == 11:
		snap["relations"] = _bits_map(gs.relations)
		snap["relation_base"] = _bits_map(gs.relation_base)
	return snap


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
