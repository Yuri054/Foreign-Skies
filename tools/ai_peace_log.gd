extends SceneTree
## Prints how each war of an AI-only run ended (who gave, the terms, the scores and urges just before).
## godot --headless --path . -s res://tools/ai_peace_log.gd -- days [scenario_dir] [seed]
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var P = load("res://scripts/sim/peace.gd")
	var args := OS.get_cmdline_user_args()
	gs.load_scenario(args[1] if args.size() > 1 else "res://data/scenarios/july_1914/")
	gs.ai_enabled = true
	gs.set_player("ESP")
	gs.ai_seed = int(args[2]) if args.size() > 2 else 0
	var seen := {}
	for d in int(args[0]):
		clock.advance_day()
		for w in gs.war_history:
			if seen.has(w.id):
				continue
			seen[w.id] = true
			var p: Dictionary = w.peace
			var how := "no treaty"
			if not p.is_empty():
				how = "%s took %s%s" % [p.taker, "white peace" if p.white else str(p.terms.size()) + " terms", " (forced)" if p.forced else ""]
			print("%s  %s v %s lasted %d d: %s | support %s %d %s %d | score %s %+.0f" % [w.end_date, w.a, w.b, w.end_day - w.start_day, how, w.a, gs.nations[w.a].war_support, w.b, gs.nations[w.b].war_support, w.a, float(p.get("score", 0.0))])
			for e in w.log.slice(maxi(w.log.size() - 3, 0)):
				print("      ", e.get("text", e) if e is Dictionary else e)
	quit()
