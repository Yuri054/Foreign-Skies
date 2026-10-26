extends SceneTree
## One game of AIs against each other for training: some nations play by a candidate set of parameters, the rest by
## the baseline's, and every nation's result is printed (one RESULT line of JSON). Nothing here knows any nation or
## any history: the war begins with the scenario's two alliance blocs at war (a neutral way to get fighting), and a nation's score is how
## much of Europe's people and output it controls at the end against what it controlled at the start (percentage
## points, W_VALUE), the change in its share of Europe's provinces (W_PROVINCES), its share of Europe's soldiers
## (W_MEN: a little, so a nation is not rewarded for an army it never uses), less W_WAR_MONTH for each month it spent at
## war (so a war ended well beats a war dragged on).
##   godot --headless --path . -s res://tools/ai_arena.gd -- job.json
## job.json: {"scenario": "res://data/scenarios/july_1914/", "days": 400, "seed": 3, "group_a": ["GER", ...],
##            "candidate": {"offense.odds_bold": 0.9}, "baseline": {}, "start": "blocs"}
## `candidate` and `baseline` map dotted paths in data/ai.json to numbers; group_a nations play the candidate, the rest
## the baseline. "start": "blocs" begins with the blocs at war, "peace" lets the scenario run as it is.
const W_VALUE := 100.0
const W_PROVINCES := 50.0
const W_MEN := 5.0
const W_WAR_MONTH := 0.2


func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var AI = load("res://scripts/ai/ai.gd")
	AudioServer.set_bus_mute(0, true)   # a silent game: no sound events, and the music players have nothing to do
	for p in root.get_node("Audio")._players:
		p.stop()
	root.get_node("Audio").set_process(false)
	var job: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	gs.load_scenario(job.get("scenario", "res://data/scenarios/july_1914/"))
	gs.ai_enabled = true
	gs.set_player("ESP")
	gs.player_tag = ""
	gs.ai_seed = int(job.get("seed", 1))
	var base_cfg: Dictionary = AI.cfg
	AI.overrides.clear()
	var cand_cfg := _with(base_cfg, job.get("candidate", {}))
	var base_set := _with(base_cfg, job.get("baseline", {}))
	var group_a: Array = job.get("group_a", [])
	for tag in gs.nations:
		AI.overrides[tag] = cand_cfg if tag in group_a else base_set
	if job.get("start", "blocs") == "blocs":
		var blocs: Dictionary = gs.scenario.get("blocs", {})
		var names: Array = blocs.keys()
		for i in names.size():
			for j in range(i + 1, names.size()):
				for a: String in blocs[names[i]]:
					for b: String in blocs[names[j]]:
						gs.set_war(a, b, true, "none")
	var start := _state(gs)
	var days := int(job.get("days", 400))
	var battles := [0]
	gs.battle_fought.connect(func(_p: int, _t: Array) -> void: battles[0] += 1)
	var war_days := {}
	for d in days:
		clock.advance_day()
		gs.pending_events.clear()
		gs.pending_offers.clear()
		gs.pending_joins.clear()
		for tag in gs.nations:
			if not gs.wars_of(tag).is_empty():
				war_days[tag] = int(war_days.get(tag, 0)) + 1
	var end := _state(gs)
	var scores := {}
	for tag in gs.nations:
		var s: float = W_VALUE * (end.value.get(tag, 0.0) - start.value.get(tag, 0.0))
		s += W_PROVINCES * (end.provinces.get(tag, 0.0) - start.provinces.get(tag, 0.0))
		s += W_MEN * (end.men.get(tag, 0.0) / maxf(end.men_total, 1.0) - start.men.get(tag, 0.0) / maxf(start.men_total, 1.0))
		s -= W_WAR_MONTH * float(war_days.get(tag, 0)) / 30.0
		if absf(s) > 0.0001:
			scores[tag] = snappedf(s, 0.001)
	print("RESULT ", JSON.stringify({"scores": scores, "battles": battles[0], "wars": gs.wars.size(), "seed": gs.ai_seed}))
	quit()


## A copy of the config with dotted-path numbers set.
func _with(cfg: Dictionary, changes: Dictionary) -> Dictionary:
	var out: Dictionary = cfg.duplicate(true)
	for path: String in changes:
		var keys := path.split(".")
		var node: Dictionary = out
		for i in keys.size() - 1:
			node = node[keys[i]]
		node[keys[keys.size() - 1]] = changes[path]
	return out


## What each nation controls: the share of Europe's people and output (GDP and industry) in the provinces it holds, and its men.
func _state(gs: Node) -> Dictionary:
	var pop_total := 0.0
	var out_total := 0.0
	for id in range(1, gs.province_owner.size()):
		pop_total += gs.province_population[id]
		out_total += gs.province_gdp[id] + gs.province_industry[id]
	var value := {}
	var provinces := {}
	var count := float(gs.province_owner.size() - 1)
	for id in range(1, gs.province_owner.size()):
		var c: String = gs.province_controller[id]
		var v: float = 0.5 * gs.province_population[id] / maxf(pop_total, 1.0) + 0.5 * (gs.province_gdp[id] + gs.province_industry[id]) / maxf(out_total, 1.0)
		value[c] = value.get(c, 0.0) + v
		provinces[c] = provinces.get(c, 0.0) + 1.0 / maxf(count, 1.0)
	var men := {}
	var men_total := 0.0
	for a in gs.armies.values():
		men[a.tag] = men.get(a.tag, 0.0) + a.men()
		men_total += a.men()
	return {"value": value, "provinces": provinces, "men": men, "men_total": men_total}
