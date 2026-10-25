extends SceneTree
## Explains a nation's offence on one day: its armies, what it could send, and for every enemy-held province next to its
## ground the odds it wants against the force it can bring.
## godot --headless --path . -s res://tools/ai_why.gd -- days tag [scenario_dir]
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var map = root.get_node("MapData")
	var Mil = load("res://scripts/sim/military.gd")
	var AIO = load("res://scripts/ai/ai_offense.gd")
	var A = load("res://scripts/ai/ai.gd")
	var args := OS.get_cmdline_user_args()
	gs.load_scenario(args[2] if args.size() > 2 else "res://data/scenarios/july_1914/")
	gs.ai_enabled = true
	gs.set_player("ESP")
	var tag: String = args[1]
	for d in int(args[0]):
		clock.advance_day()
	print("date ", clock.date_string(), " wars ", gs.wars_of(tag).size(), " campaign ", gs.ai_campaign.get(tag))
	var av = AIO._available(gs, tag)
	var total := 0.0
	for a in Mil.armies_of(gs, tag):
		total += a.power()
	var t = A.temperament(gs, tag)
	var budget: float = total * float(t.aggression) * float(A.cfg.offense.max_share)
	print("power ", int(total), " available ", av.size(), " budget ", int(budget), " odds ", A.required_odds(gs, tag))
	var AID = load("res://scripts/ai/ai_defense.gd")
	for f in gs.fronts.values():
		if f.tag == tag:
			print("  front vs ", f.against, ": ", f.army_ids.size(), " armies, power ", int(AID._power_on(gs, f)), " need ", int(AID._need(gs, f)), " anchors ", f.anchors.map(func(i): return map.provinces[i].name))
	for a in Mil.armies_of(gs, tag):
		print("  army ", a.id, " ", int(a.men() / 1000.0), "k power ", int(a.power()), " at ", map.provinces[a.province].name, " front ", a.front_id, " path ", a.path.size(), " avail ", av.has(a))
	for enemy in A.enemies(gs, tag):
		var fr = AIO._frontier(gs, tag, enemy)
		print("enemy ", enemy, " plan-defensive ", AIO._defensive(gs, tag, enemy), " frontier ", fr.size())
		for target in fr:
			var res: float = AIO._resistance(gs, tag, target)
			var req: float = AIO.odds_against(gs, tag, enemy) * res
			var picked = AIO._pick_force(gs, tag, target, av, req, budget, false)
			print("   target ", map.provinces[target].name, " supplied ", A.supplied(gs, tag, target), " resistance ", int(res), " required ", int(req), " picked ", (int(picked.power) if not picked.is_empty() else -1), " utility ", snappedf(AIO._worth(gs, tag, enemy, target), 0.01))
	quit()
