extends SceneTree
## One nation's economy from a scenario's start under a fixed policy, with the AI off (no AI wars; scripted events
## still fire and are cleared unanswered), to compare what the player's economic choices do. tools/economy.py runs a
## grid of nations and policies and prints the table.
## Run: godot --headless --path . -s res://tools/economy_policies.gd -- tag years policy [scenario_dir]
## policy: a comma list of passive, fact, rail, port, all (the three in turn), focus (economic foci first), tax=X,
## mob=X, arms=X (the arms share; otherwise the scenario's). Prints "RESULT {...}": GDP, IC and revenue a month at the end and their change, treasury, net, development
## and war support, and the levels built.


func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var E = load("res://scripts/sim/economy.gd")
	var F = load("res://scripts/sim/focus.gd")
	var Build = load("res://scripts/sim/construct_building.gd")
	var Policy = load("res://scripts/sim/set_economy_policy.gd")
	var SetF = load("res://scripts/sim/set_focus.gd")
	var args := OS.get_cmdline_user_args()
	var tag: String = args[0]
	var years := int(args[1])
	var policy: PackedStringArray = args[2].split(",")
	gs.load_scenario(args[3] if args.size() > 3 else "res://data/scenarios/jan_1900/")
	gs.ai_enabled = false
	gs.set_player(tag)
	var n = gs.nations[tag]
	var start := {"gdp": float(n.budget.gdp), "ic": float(n.budget.construction_points), "dev": float(n.development)}
	var types: Array = []
	for p in policy:
		if p.begins_with("tax="):
			gs.issue(Policy.new(tag, "tax_rate", float(p.get_slice("=", 1))))
		elif p.begins_with("mob="):
			gs.issue(Policy.new(tag, "mobilization", float(p.get_slice("=", 1))))
		elif p.begins_with("arms="):
			gs.issue(Policy.new(tag, "arms_share", float(p.get_slice("=", 1))))
		elif p == "fact":
			types.append("factory")
		elif p == "rail":
			types.append("railway")
		elif p == "port":
			types.append("port")
		elif p == "all":
			types.append_array(["factory", "railway", "port"])
	var built := {}
	var turn := 0
	for d in years * 365:
		clock.advance_day()
		gs.pending_events.clear()
		# Keep the queue fed: every fifth day, add projects until the day's IC would be used.
		if not types.is_empty() and clock.day % 5 == 1:
			var wanted: float = n.budget.construction_points
			var given := 0.0
			for job in n.construction:
				given += float(job.rate)
			var guard := 0
			while given < wanted - 1.0 and n.construction.size() < 60 and guard < 20:
				guard += 1
				var placed := false
				for k in types.size():
					var type: String = types[(turn + k) % types.size()]
					var cands: Array = E.mass_candidates(gs, tag, type)
					if not cands.is_empty() and gs.issue(Build.new(tag, cands[0], type)):
						built[type] = int(built.get(type, 0)) + 1
						given += float(n.construction[n.construction.size() - 1].rate)
						turn += 1
						placed = true
						break
				if not placed:
					break
		if "focus" in policy and n.focus.is_empty():
			var pick := ""
			for f in F.tree_of(tag):
				var fx: Dictionary = f.effects
				if F.block(gs, tag, f.id) == "" and (fx.has("gdp") or fx.has("industry") or fx.has("growth") or fx.has("construction")):
					pick = f.id
					break
			if pick == "":
				for f in F.tree_of(tag):
					if F.block(gs, tag, f.id) == "":
						pick = f.id
						break
			if pick != "":
				gs.issue(SetF.new(tag, pick))
	var b: Dictionary = n.budget
	print("RESULT " + JSON.stringify({
		"tag": tag, "policy": args[2], "years": years,
		"gdp": snappedf(b.gdp / 12.0, 0.1), "gdp_change": snappedf(b.gdp / start.gdp - 1.0, 0.001),
		"ic": snappedf(b.construction_points, 1.0), "ic_change": snappedf(b.construction_points / start.ic - 1.0, 0.001),
		"revenue": snappedf(b.revenue / 12.0, 0.01), "net": snappedf(b.net / 12.0, 0.01), "treasury": roundi(n.treasury),
		"development": snappedf(n.development / start.dev - 1.0, 0.001), "war_support": roundi(n.war_support),
		"built": built, "foci": n.focus_done.size(),
		"munitions": roundi(n.munitions), "stock_days": roundi(minf(load("res://scripts/sim/munitions.gd").days_left(gs, tag), 99999.0)),
	}))
	quit()
