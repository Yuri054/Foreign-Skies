extends SceneTree
## Counts what the AI does in each year of a long run: wars begun, peaces, treaties signed,
## justifications, foci finished. Run:
##   godot --headless --path . -s res://tools/late_report.gd -- [years] [seed]
var wars := 0
var peaces := 0
var treaties := 0
var cbs := 0
var foci := 0


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 5
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	gs.ai_enabled = true
	gs.war_changed.connect(func(_a: String, _b: String, at_war: bool) -> void:
		if at_war:
			wars += 1
		else:
			peaces += 1
	)
	gs.treaty_changed.connect(func(_t: Treaty, added: bool) -> void:
		if added:
			treaties += 1
	)
	gs.casus_belli_ready.connect(func(_h: String, _t: String) -> void: cbs += 1)
	gs.focus_completed.connect(func(_t: String, _i: String) -> void: foci += 1)
	for year in years:
		wars = 0
		peaces = 0
		treaties = 0
		cbs = 0
		foci = 0
		for d in 365:
			clock.advance_day()
		print("year %d: wars begun %d, ended %d, treaties %d, claims %d, foci %d, at war now %d, decl %s" % [year + 1, wars, peaces, treaties, cbs, foci, gs.wars.size(), str(gs.ai_declarations)])
	quit(0)
