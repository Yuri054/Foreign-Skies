extends SceneTree
## Plays the standing 1914 wars for 200 days with the AI and prints, for each power, how the shells
## went: the stock at the start and the end, what was made and burned, and the share of artillery
## days fought with no shells. Run: godot --headless --path . -s res://tools/shell_report.gd
func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var M = load("res://scripts/sim/military.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	gs.ai_enabled = true
	M.shell_stats.clear()
	var powers := ["GER", "FRA", "RUS", "GBR", "AUH", "ITA", "SRB"]
	var start := {}
	for t in powers:
		start[t] = gs.nations[t].equipment.shells
	var low := {}
	for t in powers:
		low[t] = 1e12
	for i in 200:
		clock.advance_day()
		for t in powers:
			low[t] = minf(low[t], gs.nations[t].equipment.shells)
	print("tag  start   end   lowest  burned  starved-share  wars")
	for t in powers:
		var s: Dictionary = M.shell_stats.get(t, {"unit_days": 0, "starved": 0, "used": 0.0})
		var share: float = float(s.starved) / maxf(1.0, float(s.unit_days))
		print("%s %6.0f %6.0f %6.0f %7.0f   %5.2f (%d unit-days)  %d" % [t, start[t], gs.nations[t].equipment.shells, low[t], s.used, share, s.unit_days, gs.wars_of(t).size()])
	quit()
