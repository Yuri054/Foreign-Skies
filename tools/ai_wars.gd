extends SceneTree
## Lists the wars running on given days: age, war score and each side's urge for peace and war support.
## godot --headless --path . -s res://tools/ai_wars.gd -- day1,day2,... [scenario_dir] [seed]
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var AP = load("res://scripts/ai/ai_peace.gd")
	var P = load("res://scripts/sim/peace.gd")
	var args := OS.get_cmdline_user_args()
	gs.load_scenario(args[1] if args.size() > 1 else "res://data/scenarios/july_1914/")
	gs.ai_enabled = true
	gs.set_player("ESP")
	gs.ai_seed = int(args[2]) if args.size() > 2 else 0
	var days := []
	for s in args[0].split(","):
		days.append(int(s))
	var d := 0
	for stop in days:
		while d < stop:
			clock.advance_day()
			d += 1
		print("== day ", d, " ", clock.date_string(), " tension ", int(gs.tension), " wars ", gs.wars.size())
		for w in gs.wars.values():
			print("   %s v %s  age %d d  score %s %+.0f  urge %s %.0f / %s %.0f  support %d/%d" % [w.a, w.b, clock.days_elapsed - w.start_day, w.a, P.war_score(gs, w, w.a), w.a, AP.urge(gs, w.a, w), w.b, AP.urge(gs, w.b, w), gs.nations[w.a].war_support, gs.nations[w.b].war_support])
	quit()
