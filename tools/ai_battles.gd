extends SceneTree
## Lists the battles between two nations in an AI-only run: when, where, who attacked, sizes and who won.
## godot --headless --path . -s res://tools/ai_battles.gd -- days tagA tagB [seed]
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var args := OS.get_cmdline_user_args()
	gs.load_scenario("res://data/scenarios/july_1914/")
	gs.ai_enabled = true
	gs.set_player("ESP")
	gs.ai_seed = int(args[3]) if args.size() > 3 else 0
	for d in int(args[0]):
		clock.advance_day()
	var rows := []
	for b: Dictionary in gs.battle_archive.values():
		if b.start_men.has(args[1]) and b.start_men.has(args[2]):
			var parts := []
			for t in b.start_men:
				parts.append("%s %dk(-%dk)" % [t, b.start_men[t] / 1000.0, b.lost.get(t, 0.0) / 1000.0])
			rows.append([b.start_day, "%s %s att=%s win=%s %dd %s" % [b.start_date, b.name, b.attacker, b.winner, b.days, " vs ".join(parts)]])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for r in rows:
		print(r[1])
	quit()
