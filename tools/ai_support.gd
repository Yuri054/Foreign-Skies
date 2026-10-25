extends SceneTree
## Prints, month by month, a nation's war support, what moves it and its wars: for judging why a war ends.
## godot --headless --path . -s res://tools/ai_support.gd -- tag [months] [scenario_dir] [seed]
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var WS = load("res://scripts/sim/war_support.gd")
	var args := OS.get_cmdline_user_args()
	gs.load_scenario(args[2] if args.size() > 2 else "res://data/scenarios/july_1914/")
	gs.ai_enabled = true
	gs.set_player("ESP")
	gs.ai_seed = int(args[3]) if args.size() > 3 else 0
	var tag: String = args[0]
	var wins := [0]
	var losses := [0]
	var prev := [gs.nations[tag].war_support]
	var by_size := {}
	gs.war_support_changed.connect(func(t: String, v: float) -> void:
		if t == tag:
			var k := "%+.1f" % (v - prev[0])
			by_size[k] = by_size.get(k, 0) + 1
			prev[0] = v)
	var last := -1
	for d in int(args[1] if args.size() > 1 else 8) * 31:
		clock.advance_day()
		if clock.month == last:
			continue
		last = clock.month
		if gs.wars_of(tag).is_empty():
			continue
		var ch: Dictionary = WS.monthly_changes(gs, tag)
		var parts := []
		for k in ch:
			if absf(ch[k]) >= 0.05:
				parts.append("%s %.1f" % [k, ch[k]])
		var enemies := []
		for w in gs.wars_of(tag):
			enemies.append(w.other(tag))
		print("%d-%02d %s support %.0f | %s | at war with %s | deltas %s" % [clock.year, clock.month, tag, gs.nations[tag].war_support, ", ".join(parts), ",".join(enemies), by_size])
		by_size.clear()
	quit()
