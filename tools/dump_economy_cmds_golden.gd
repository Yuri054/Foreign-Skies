extends SceneTree
## Writes what the GDScript does when the player manages the economy, for the Rust port (rust/fs_sim) to reproduce: works started
## (and refused for every reason), the queue reordered, mass orders stopped by a count, an amount of IC or the money, the policy
## sliders (tax, mobilization, arms, investment, standing army) and munitions bought abroad. Commands go through GameState.issue,
## which works the economy out again after each; the real game runs by itself for days between them. Floats are the bits of their
## 64-bit value.
##   godot --headless --path . -s res://tools/dump_economy_cmds_golden.gd -- rust/fs_sim/tests/golden/economy_cmds.json

var gs: Node
var clock: Node


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	var peace_dir := _make_peace_copy("july_1914")
	var campaigns := [
		{"name": "build", "player": "POR", "actions": [
			["build", "GBR", 0, "factory"], ["build", "GBR", 0, "factory"], ["build", "GBR", 1, "railway"], ["build", "GBR", 2, "port"], ["build", "GBR", 3, "farm"],
			["build", "GBR", 1000314, "nonsense"], ["build", "GBR", 1000999, "factory"], ["build", "GBR", 0, "trench"], ["build", "FRA", 1000314, "factory"], ["build", "XXX", 0, "factory"],
			["build", "GBR", 5, "fortification"], ["prio", "GBR", 1, "railway"], ["prio", "GBR", 0, "factory"], ["prio", "GBR", 0, "factory"], ["prio", "GBR", 0, "railway"], ["setlevel", "GBR", 12, "factory", 10], ["build", "GBR", 12, "factory"], ["prio", "GBR", 1, "factory"],
			["days", 40, 10], ["build", "GBR", 0, "factory"], ["days", 400, 50], ["treasury", "GBR", 1.0], ["build", "GBR", 6, "factory"], ["build", "GBR", 6, "railway"],
			["war", "GER", "GBR"], ["seize_one", "GBR", "GER", 7], ["build", "GBR", 7, "factory"], ["days", 30, 10]]},
		{"name": "mass", "player": "POR", "actions": [
			["mass", "GER", "factory", 5, 0.0], ["mass", "GER", "railway", 1000000, 20000.0], ["mass", "GER", "port", 3, 0.0], ["mass", "FRA", "farm", 1000000, 0.0],
			["mass", "XXX", "factory", 1, 0.0], ["mass", "FRA", "nonsense", 1, 0.0], ["treasury", "RUS", 60.0], ["mass", "RUS", "factory", 1000000, 0.0], ["days", 60, 20],
			["mass", "RUS", "railway", 1000000, 0.0], ["days", 200, 50]]},
		{"name": "policy", "player": "POR", "actions": [
			["policy", "GBR", "tax_rate", 0.5], ["policy", "GBR", "tax_rate", -1.0], ["policy", "GBR", "tax_rate", 0.2], ["policy", "GBR", "mobilization", 0.9], ["policy", "GBR", "mobilization", 0.1],
			["policy", "GBR", "arms_share", 0.5], ["policy", "GBR", "arms_share", 2.0], ["policy", "GBR", "investment", 5.0], ["policy", "GBR", "investment", 1000.0],
			["policy", "GBR", "standing_army", 400000.0], ["policy", "GBR", "standing_army", 5000000.0], ["policy", "GBR", "standing_army", -5.0], ["policy", "GBR", "standing_army", 120000.7],
			["policy", "GBR", "nonsense", 1.0], ["policy", "XXX", "tax_rate", 0.1], ["days", 40, 8], ["war", "GBR", "GER"], ["policy", "GBR", "mobilization", 1.5], ["policy", "GBR", "mobilization", 0.0],
			["days", 30, 10], ["policy", "GBR", "tax_rate", 0.3], ["days", 40, 10]]},
		{"name": "munitions", "player": "POR", "actions": [
			["munitions", "GBR", 3.0], ["munitions", "GBR", 0.0], ["munitions", "GBR", -2.0], ["munitions", "GBR", 99999.0], ["blockade", "GBR", 0.4], ["munitions", "GBR", 3.0],
			["pin", "GBR", 1.0], ["munitions", "GBR", 3.0], ["days", 20, 5], ["munitions", "XXX", 1.0]]},
	]
	var result := []
	for camp in campaigns:
		gs.player_tag = ""
		gs.load_scenario(peace_dir)
		gs.ai_enabled = false
		gs.pressure_ai = false
		gs.set_player(camp.player)
		var log := []
		var snaps := [_snapshot()]
		for act in camp.actions:
			_play(act, log, snaps)
		result.append({"name": camp.name, "player": camp.player, "log": log, "snaps": snaps})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _province(tag: String, k: int) -> int:
	if k >= 1000000:
		return k - 1000000
	if not gs.nations.has(tag):
		return 1
	var list = gs.nations[tag].provinces
	return list[k] if k < list.size() else 1


func _play(act: Array, log: Array, snaps: Array) -> void:
	match act[0]:
		"war":
			gs.set_war(act[1], act[2], true, "none", 0, {})
			log.append(act)
		"treasury":
			gs.nations[act[1]].treasury = act[2]
			log.append(act)
		"blockade":
			gs.nations[act[1]].blockade = act[2]
			log.append(act)
		"pin":
			gs.nations[act[1]].blockade_pinned = act[2]
			log.append(act)
		"setlevel":
			var id := _province(act[1], act[2])
			gs.province_buildings[id][act[3]] = act[4]
			log.append(["setlevel", id, act[3], act[4]])
		"seize_one":
			var id := _province(act[1], act[3])
			gs.set_controller(id, act[2])
			load("res://scripts/sim/economy.gd").recompute(gs)
			log.append(["seize", id, act[2]])
		"build":
			var id := _province(act[1], act[2])
			var cmd: GDScript = load("res://scripts/sim/construct_building.gd")
			var ok: bool = gs.issue(cmd.new(act[1], id, act[3]))
			log.append(["build", act[1], id, act[3], ok])
		"prio":
			var id := _province(act[1], act[2])
			var cmd: GDScript = load("res://scripts/sim/prioritize_construction.gd")
			var ok: bool = gs.issue(cmd.new(act[1], id, act[3]))
			log.append(["prio", act[1], id, act[3], ok])
		"mass":
			var cmd: GDScript = load("res://scripts/sim/mass_construct_building.gd")
			var c = cmd.new(act[1], act[2], act[3], act[4])
			var ok: bool = gs.issue(c)
			log.append(["mass", act[1], act[2], act[3], act[4], ok, Array(c.built).duplicate(), B(c.spent), B(c.gold), c.stopped_by])
		"policy":
			var cmd: GDScript = load("res://scripts/sim/set_economy_policy.gd")
			var ok: bool = gs.issue(cmd.new(act[1], act[2], act[3]))
			log.append(["policy", act[1], act[2], act[3], ok])
		"munitions":
			var cmd: GDScript = load("res://scripts/sim/buy_munitions.gd")
			var ok: bool = gs.issue(cmd.new(act[1], act[2]))
			log.append(["munitions", act[1], act[2], ok])
		"days":
			for i in act[1]:
				clock.advance_day()
				var shot: bool = i % act[2] == act[2] - 1 or i == act[1] - 1
				log.append(["day", shot])
				if shot:
					snaps.append(_snapshot())
			return
	snaps.append(_snapshot())
	log.append(["shot"])


func _snapshot() -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		var jobs := []
		for j in n.construction:
			jobs.append([j.province, j.type, B(j.points_total), B(j.points_left), B(j.rate), j.days_total, j.days_left])
		nations.append([B(n.treasury), B(n.tax_rate), B(n.mobilization), B(n.arms_share), B(n.investment), n.peacetime_army, B(n.munitions), B(n.budget.net),
				B(n.budget.gdp), B(n.budget.industry), jobs, B(n.construction_used), B(n.blockade), n.manpower])
	var works := []
	for id in range(1, gs.province_buildings.size()):
		var b: Dictionary = gs.province_buildings[id]
		if not b.is_empty():
			var items := []
			for k in b:
				items.append([k, b[k]])
			works.append([id, items])
	return {"day": clock.days_elapsed, "nations": nations, "works": works}


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
