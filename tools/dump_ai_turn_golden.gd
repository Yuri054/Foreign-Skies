extends SceneTree
## Writes what the AI's budget and focus do in the real game, for the Rust port (rust/fs_sim) to reproduce. The game's own day is driven here
## stage by stage (economy, focus, navy, armies, diplomacy, crises) with the parts of the AI's turn that are ported (AIBudget, without
## its navy, and AIFocus) in the place the game gives the AI, then the day's last stage; the rest of the AI's turn does nothing. Scenarios,
## some with wars begun and a front drawn for each side, run for hundreds of days; every few days the nations' policies, money, works,
## foci and the months of their last budget are written down. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_ai_turn_golden.gd -- rust/fs_sim/tests/golden/ai_turn.json

var gs: Node
var clock: Node
var Eco: GDScript
var Foc: GDScript
var Nav: GDScript
var Mil: GDScript
var Dip: GDScript
var Cri: GDScript
var AIc: GDScript
var AIB: GDScript
var AIF: GDScript
var AIFo: GDScript
var AIAm: GDScript
var parts: Array = []


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	Eco = load("res://scripts/sim/economy.gd")
	Foc = load("res://scripts/sim/focus.gd")
	Nav = load("res://scripts/sim/navy.gd")
	Mil = load("res://scripts/sim/military.gd")
	Dip = load("res://scripts/sim/diplomacy.gd")
	Cri = load("res://scripts/sim/crisis.gd")
	AIc = load("res://scripts/ai/ai.gd")
	AIB = load("res://scripts/ai/ai_budget.gd")
	AIF = load("res://scripts/ai/ai_focus.gd")
	AIFo = load("res://scripts/ai/ai_forces.gd")
	AIAm = load("res://scripts/ai/ai_ambition.gd")
	var Design: GDScript = load("res://scripts/sim/designate_front.gd")
	clock.day_ticked.disconnect(gs._on_day_ticked)
	clock.day_ticked.connect(_day)
	var runs := [
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 400, "every": 5, "player": "GER", "wars": []},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 500, "every": 5, "player": "GBR", "wars": []},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 300, "every": 5, "player": "POR", "wars": [["GER", "FRA"], ["ITA", "AUH"], ["RUS", "OTT"]]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 400, "every": 5, "player": "USA", "wars": [["RUS", "OTT"], ["FRA", "GER"], ["GBR", "ESP"]]},
		# the treasuries thrown about (by a factor for each nation in tag order), so that every branch of the budget is tried
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 500, "every": 5, "player": "GER", "wars": [], "purse": [-3.0, 0.1, 8.0, 40.0, 1.0, 0.0, 200.0]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 700, "every": 5, "player": "GBR", "wars": [], "purse": [60.0, -5.0, 0.3, 12.0, 1.0, 3.0]},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 400, "every": 5, "player": "POR", "wars": [["GER", "FRA"], ["ITA", "AUH"], ["RUS", "OTT"]], "purse": [0.2, 30.0, -2.0, 5.0, 100.0]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1500, "every": 10, "player": "USA", "wars": [], "purse": [1.0]},
	]
	var ALL := ["forces", "budget", "focus", "ambition"]
	var LAX := {"ambition": {"threshold": 0.3, "start_delay_days": 0, "review_days": 30, "give_up_days": 150, "cooldown_days": 45, "odds_margin": 0.8, "min_aggression": 0.3}, "forces": {"demob_after_days": 20}}
	runs.append_array([
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 500, "every": 5, "player": "POR", "wars": [["GER", "FRA"], ["ITA", "AUH"], ["RUS", "OTT"]], "parts": ALL},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 800, "every": 10, "player": "GBR", "wars": [["AUH", "SRB"], ["GER", "RUS"]], "parts": ALL, "purse": [3.0, 0.5, 10.0, 1.0]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 900, "every": 10, "player": "USA", "wars": [["RUS", "OTT"], ["FRA", "GER"]], "parts": ALL},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1500, "every": 10, "player": "GBR", "wars": [], "parts": ALL, "pressure": true},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 900, "every": 10, "player": "SRB", "wars": [], "parts": ALL, "pressure": true},
		# the AI's ambition and demobilizing loosened, so that they are tried (the same numbers are set by the Rust test)
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 800, "every": 10, "player": "GBR", "wars": [["GER", "FRA"], ["ITA", "AUH"]], "parts": ALL, "ai_cfg": LAX},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1000, "every": 10, "player": "USA", "wars": [["RUS", "OTT"], ["FRA", "GER"]], "parts": ALL, "ai_cfg": LAX},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 700, "every": 10, "player": "SRB", "wars": [], "parts": ALL, "ai_cfg": LAX, "pressure": true},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1200, "every": 10, "player": "GBR", "wars": [], "parts": ALL, "ai_cfg": LAX, "pressure": true, "purse": [2.0, 0.5, 20.0]},
	])
	var result := []
	for run in runs:
		gs.player_tag = ""
		gs.load_scenario(run.dir)
		gs.ai_enabled = false
		gs.pressure_ai = run.get("pressure", false)
		gs.set_player(run.player)
		parts = run.get("parts", ["budget", "focus"])
		AIc.load_config()
		for section in run.get("ai_cfg", {}):
			for k in run.ai_cfg[section]:
				AIc.cfg[section][k] = run.ai_cfg[section][k]
		var setup := []
		var purse: Array = run.get("purse", [])
		if not purse.is_empty():
			var tags: Array = gs.nations.keys()
			tags.sort()
			for i in tags.size():
				gs.nations[tags[i]].treasury *= purse[i % purse.size()]
		for w in run.wars:
			Dip.start_war(gs, w[0], w[1], true)
			for pair in [[w[0], w[1]], [w[1], w[0]]]:
				var cmd = Design.new(pair[0], "Front " + pair[1], [] as Array[int], pair[1], "line", 0)
				var ok: bool = cmd.execute(gs)
				setup.append([pair[0], pair[1], ok])
		var snaps := [_snapshot()]
		for d in run.days:
			clock.advance_day()
			if d % run.every == run.every - 1:
				snaps.append(_snapshot())
		result.append({"name": run.name, "player": run.player, "wars": run.wars, "purse": run.get("purse", []), "parts": run.get("parts", ["budget", "focus"]), "pressure": run.get("pressure", false), "ai_cfg": run.get("ai_cfg", {}), "setup": setup, "every": run.every, "snaps": snaps})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


## The game's day (GameState._day_stage_list) with the ported parts of the AI's turn where the AI goes.
func _day() -> void:
	gs.finish_day()
	gs.in_day_step = true
	Eco.step_day(gs)
	Foc.step_day(gs)
	Nav.step_day(gs)
	Mil.step_day(gs)
	Dip.step_day(gs)
	Cri.step_day(gs)
	for tag in AIc.due_nations(gs):
		if "forces" in parts:
			if not gs.wars_of(tag).is_empty():
				AIFo.step(gs, tag)
			else:
				AIFo.rebuild(gs, tag)
				AIFo.demobilize(gs, tag)
		var stamp: int = clock.year * 12 + clock.month
		if "budget" in parts and gs.ai_budget_stamp.get(tag, 0) != stamp and AIc.cfg.budget.enabled:
			gs.ai_budget_stamp[tag] = stamp
			AIB._taxes(gs, tag)
			AIB._arms(gs, tag)
			AIB._buildings(gs, tag)
			AIB._points(gs, tag)
		if "focus" in parts:
			AIF.step(gs, tag)
		if "ambition" in parts:
			AIAm.step(gs, tag)
	gs.in_day_step = false
	if gs.economy_dirty:
		gs.economy_dirty = false
		gs.budget_dirty = false
		Eco.recompute(gs)
	elif gs.budget_dirty:
		gs.budget_dirty = false
		Eco.refresh_now(gs)


func _snapshot() -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		var jobs := []
		for j in n.construction:
			jobs.append([j.province, j.type, j.days_left, B(j.points_left)])
		nations.append([B(n.treasury), B(n.tax_rate), B(n.investment), B(n.arms_share), B(n.munitions), B(n.diplomacy_points), B(n.prestige),
				B(n.mobilization), B(n.budget.get("net", 0.0)), jobs, n.focus.get("id", "") if not n.focus.is_empty() else "", n.focus_done.duplicate(),
				JSON.stringify(n.focus_count), gs.ai_budget_stamp.get(tag, 0), n.provinces.size()])
	var owners := []
	for id in range(1, gs.province_owner.size()):
		owners.append(gs.province_owner[id])
	var armies := []
	for a in gs.armies.values():
		armies.append([a.id, a.tag, a.province, B(a.men()), a.units.size()])
	var recruiting := []
	for tag in gs.nations:
		recruiting.append(gs.nations[tag].recruiting.map(func(j): return [j.type, j.province, j.days_left]))
	var manpower := []
	for tag in gs.nations:
		manpower.append([gs.nations[tag].manpower, gs.nations[tag].men_in_units])
	var wars := []
	for w in gs.wars.values():
		wars.append([w.id, w.a, w.b])
	return {"day": clock.days_elapsed, "date": clock.date_string(), "nations": nations, "owners": owners, "tension": B(gs.tension), "armies": armies, "recruiting": recruiting,
			"manpower": manpower, "wars": wars, "ambition": gs.ai_ambition.duplicate(true), "ambition_wait": gs.ai_ambition_wait.duplicate(), "plans": JSON.stringify(gs.ai_plans)}
