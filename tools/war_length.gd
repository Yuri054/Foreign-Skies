extends SceneTree
## AI-only run that reports how long each burst of fighting lasts (from the first declaration to the day no war is left),
## how many wars it drew in and how it ended: for tuning the length of the great war.
## Run: godot --headless --path . -s res://tools/war_length.gd -- [scenario_dir] [years] [bystander] [ai_seed]
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "res://data/scenarios/jan_1900/"
	var years := int(args[1]) if args.size() > 1 else 16
	gs.load_scenario(dir)
	gs.ai_enabled = true
	gs.ai_seed = int(args[3]) if args.size() > 3 else 0
	gs.set_player(args[2] if args.size() > 2 else "ESP")
	var start := [-1]
	var peak := [0]
	var declared := [0]
	gs.war_changed.connect(func(_a: String, _b: String, w: bool) -> void: declared[0] += 1 if w else 0)
	var total := years * 365
	for d in total:
		clock.advance_day()
		var n: int = gs.wars.size()
		peak[0] = maxi(peak[0], n)
		if n > 0 and start[0] < 0:
			start[0] = d
			peak[0] = n
			declared[0] = n
		elif n == 0 and start[0] >= 0:
			print("%d-%02d  fighting lasted %.1f months (%d declared, peak %d at once)" % [clock.year, clock.month, (d - start[0]) / 30.4, declared[0], peak[0]])
			start[0] = -1
	if start[0] >= 0:
		print("still fighting after %.1f months (%d declared, peak %d)" % [(total - start[0]) / 30.4, declared[0], peak[0]])
	quit()
