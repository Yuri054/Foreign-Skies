extends SceneTree
## AI-only run that lists the crises that open and how they end, and how many wars follow: for tuning data/crises.json.
## Run: godot --headless --path . -s res://tools/dynamic_crisis_report.gd -- [scenario_dir] [years] [ai_seed]
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "res://data/scenarios/jan_1900/"
	var years := int(args[1]) if args.size() > 1 else 10
	gs.load_scenario(dir)
	gs.ai_enabled = true
	gs.ai_seed = int(args[2]) if args.size() > 2 else 0
	gs.set_player("ESP")
	var C = load("res://scripts/sim/crisis.gd")
	var D = load("res://scripts/sim/diplomacy.gd")
	var wars := [0]
	gs.war_changed.connect(func(_a: String, _b: String, w: bool) -> void: wars[0] += 1 if w else 0)
	gs.crisis_opened.connect(func(c: Dictionary) -> void: print("%d-%02d  OPEN   %s (%s, odds %.1f)" % [clock.year, clock.month, c.title, c.kind, C.odds_a(gs, c)]))
	gs.crisis_ended.connect(func(c: Dictionary, o: String) -> void: print("%d-%02d  END    %s -> %s" % [clock.year, clock.month, c.title, o]))
	for d in years * 365:
		clock.advance_day()
		if d % 365 == 364 and args.size() > 3:
			var rows: Array = []
			for a: String in gs.nations:
				for b: String in gs.nations:
					if a != b and C.may_quarrel(gs, a, b) and (b in D.neighbor_nations(gs, a) or (a in ["GBR", "FRA", "GER", "RUS", "AUH", "ITA"] and b in ["GBR", "FRA", "GER", "RUS", "AUH", "ITA"])):
						rows.append([C.score(gs, a, b), a + ">" + b])
			rows.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
			print("year %d top scores: %s (tension %d)" % [clock.year, str(rows.slice(0, 6).map(func(r: Array) -> String: return "%s %.2f" % [r[1], r[0]])), roundi(gs.tension)])
	print("tension %d, wars declared %d, crises opened %d" % [roundi(gs.tension), wars[0], gs.crisis_log.size() + gs.crises.size()])
	quit()
