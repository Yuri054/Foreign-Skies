extends SceneTree
## Times each part of the daily step over an AI run (no player input, no fuzzing).
## Run: godot --headless --path . -s res://tools/profile_days.gd -- [years] [nation]

var totals := {}
var worst := {}


func _t(label: String, callable: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	callable.call()
	var dt := Time.get_ticks_usec() - t0
	totals[label] = totals.get(label, 0) + dt
	worst[label] = maxi(worst.get(label, 0), dt)


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 2
	var player: String = args[1] if args.size() > 1 else "ESP"
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var Eco = load("res://scripts/sim/economy.gd")
	var Nav = load("res://scripts/sim/navy.gd")
	var Mil = load("res://scripts/sim/military.gd")
	var Dip = load("res://scripts/sim/diplomacy.gd")
	var AIc = load("res://scripts/ai/ai.gd")
	Mil.profile = true
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player(player)
	gs.ai_enabled = true
	for c in clock.day_ticked.get_connections():
		clock.day_ticked.disconnect(c.callable)
	var days := years * 365
	var started := Time.get_ticks_usec()
	for i in days:
		clock.advance_day()
		_t("economy.step_day", func() -> void: Eco.step_day(gs))
		_t("navy.step_day", func() -> void: Nav.step_day(gs))
		_t("military.step_day", func() -> void: Mil.step_day(gs))
		_t("diplomacy.step_day", func() -> void: Dip.step_day(gs))
		_t("ai.step_day", func() -> void: AIc.step_day(gs))
		if gs.economy_dirty:
			gs.economy_dirty = false
			gs.budget_dirty = false
			_t("recompute", func() -> void: Eco.recompute(gs))
		elif gs.budget_dirty:
			gs.budget_dirty = false
			_t("refresh_now", func() -> void: Eco.refresh_now(gs))
	var whole := float(Time.get_ticks_usec() - started) / days / 1000.0
	print("PROFILE %d days, %.1f ms a day in all" % [days, whole])
	var keys := totals.keys()
	keys.sort_custom(func(a, b) -> bool: return totals[a] > totals[b])
	for k in keys:
		print("  %-20s %6.1f ms a day, worst %6.1f ms" % [k, float(totals[k]) / days / 1000.0, float(worst[k]) / 1000.0])
	print("  inside military.step_day:")
	for k in Mil.timings:
		print("    %-14s %6.1f ms a day, worst %6.1f ms" % [k, float(Mil.timings[k]) / days / 1000.0, float(Mil.worst[k]) / 1000.0])
	quit(0)
