extends SceneTree
## Plays the same scenario AI-only under several seeds and prints, for each, what the great powers took and lost and how
## the wars ended: for judging whether a war is varied and balanced.
## godot --headless --path . -s res://tools/ai_scoreboard.gd -- seeds(comma) [days] [scenario_dir] [tags]
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var args := OS.get_cmdline_user_args()
	var days := int(args[1]) if args.size() > 1 else 365
	var dir: String = args[2] if args.size() > 2 else "res://data/scenarios/july_1914/"
	var tags: PackedStringArray = (args[3] if args.size() > 3 else "GER,FRA,AUH,RUS,GBR,ITA").split(",")
	for sd in args[0].split(","):
		gs.load_scenario(dir)
		gs.ai_enabled = true
		gs.set_player("ESP")
		gs.ai_seed = int(sd)
		var start_day: int = clock.days_elapsed
		var battles := [0]
		var handlers := func(_p: int, _t: Array) -> void: battles[0] += 1
		gs.battle_fought.connect(handlers)
		var first_peace := {}
		var seen := {}
		var end := start_day + days
		while clock.days_elapsed < end:
			clock.advance_day()
			for w in gs.war_history:
				if not seen.has(w.id):
					seen[w.id] = true
					if w.a in tags and w.b in tags and not first_peace.has("%s%s" % [w.a, w.b]):
						first_peace["%s-%s" % [w.a, w.b]] = clock.days_elapsed - start_day
		gs.battle_fought.disconnect(handlers)
		var parts := []
		for tag in tags:
			var held := 0
			for id in range(1, gs.province_controller.size()):
				if gs.province_controller[id] == tag and gs.province_owner[id] != tag:
					held += 1
			var lost := 0
			for id in gs.nations[tag].provinces:
				if gs.province_controller[id] != tag:
					lost += 1
			var owned: int = gs.nations[tag].provinces.size()
			parts.append("%s +%d/-%d (%d)" % [tag, held, lost, owned])
		print("seed %s: %d battles, %d wars now | %s | peace after days %s" % [sd, battles[0], gs.wars.size(), "  ".join(parts), str(first_peace)])
	quit()
