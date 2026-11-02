extends SceneTree
## Writes what the GDScript does when a nation loses its capital or enough ground to capitulate, for the Rust port (rust/fs_sim)
## to reproduce: wars with ground taken by the enemy in steps, Capitulation.step_day after each step (the capital moves, goes
## home again, the nation lays down its arms), and the peace each AI enemy dictates at once. The terms the AI asks and its
## answers are logged as they happen (a copy of Capitulation with the logging added is run) so that the Rust test can hand them
## to the port, which does not have the AI. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_capitulation_golden.gd -- rust/fs_sim/tests/golden/capitulation.json

func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _bits_map(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = B(d[k])
	return out



var Cap: GDScript
var gs: Node
var clock: Node
var Mil: GDScript
var PeaceCls: GDScript
var initial_owner: Array = []


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	Mil = load("res://scripts/sim/military.gd")
	var Eco: GDScript = load("res://scripts/sim/economy.gd")
	# Capitulation with its dictated peace logged
	var text := FileAccess.get_file_as_string("res://scripts/sim/capitulation.gd")
	text = text.replace("class_name Capitulation\n", "")
	text = text.replace("\t\tPeace.propose(gs, enemy, tag, \"demand\", terms)",
			"\t\tvar res: Dictionary = Peace.propose(gs, enemy, tag, \"demand\", terms)\n\t\tgs.get_meta(\"dlog\").append({\"enemy\": enemy, \"tag\": tag, \"war_id\": war.id, \"terms\": terms.duplicate(true), \"ok\": res.ok, \"accepted\": res.accepted})")
	text = text.replace("\t\tvar terms := AIPeace.price_terms(gs, enemy, tag, war)\n\t\tif not Peace.check(gs, enemy, tag, \"demand\", terms).ok:\n\t\t\tterms = []\n",
			"\t\tvar terms := AIPeace.price_terms(gs, enemy, tag, war)\n\t\tvar priced := terms.duplicate(true)\n\t\tif not Peace.check(gs, enemy, tag, \"demand\", terms).ok:\n\t\t\tterms = []\n")
	text = text.replace("\"terms\": terms.duplicate(true)", "\"terms\": priced")
	Cap = GDScript.new()
	Cap.source_code = text
	var err := Cap.reload()
	if err != OK:
		push_error("patched Capitulation did not compile")
		quit(1)
		return
	var peace_dir := _make_peace_copy("july_1914")
	var campaigns := [
		{"name": "france_ai", "player": "POR", "actions": [
			["war", "GER", "FRA"], ["step"], ["occupy", "FRA", "GER", 0.0, 0.3, false], ["step"], ["occupy", "FRA", "GER", 0.0, 0.0, true], ["step"], ["step"],
			["occupy", "FRA", "GER", 0.3, 0.55, false], ["step"], ["retake_capital", "FRA"], ["step"], ["occupy", "FRA", "GER", 0.0, 0.0, true], ["step"],
			["occupy", "FRA", "GER", 0.3, 1.0, false], ["step"], ["step"], ["days", 5], ["step"]]},
		{"name": "belgium_cannot_move", "player": "POR", "actions": [
			["war", "GER", "BEL"], ["war", "FRA", "BEL"], ["occupy", "BEL", "GER", 0.0, 1.0, true], ["step"], ["step"], ["step"]]},
		{"name": "france_player", "player": "FRA", "actions": [
			["war", "GER", "FRA"], ["occupy", "FRA", "GER", 0.0, 0.3, false], ["occupy", "FRA", "GER", 0.0, 0.0, true], ["step"], ["step"], ["choose", "FRA", 0],
			["choose", "FRA", -1], ["step"], ["retake_capital", "FRA"], ["step"], ["occupy", "FRA", "GER", 0.3, 1.0, true], ["step"], ["step"]]},
		{"name": "germany_player", "player": "GER", "actions": [
			["war", "GER", "FRA"], ["war", "GER", "BEL"], ["occupy", "FRA", "GER", 0.0, 1.0, true], ["step"], ["step"], ["occupy", "BEL", "GER", 0.0, 1.0, true], ["step"]]},
		{"name": "two_enemies", "player": "POR", "actions": [
			["war", "GER", "FRA"], ["war", "RUS", "FRA"], ["war", "AUH", "FRA"], ["occupy", "FRA", "GER", 0.0, 0.5, true], ["occupy", "FRA", "RUS", 0.5, 0.8, false],
			["occupy", "FRA", "AUH", 0.8, 1.0, false], ["step"], ["step"], ["days", 3], ["step"]]},
		{"name": "cannot_move_60", "player": "POR", "actions": [
			["war", "GER", "FRA"], ["occupy", "FRA", "GER", 0.0, 0.6, true], ["step"], ["step"]]},
		{"name": "cannot_move_70", "player": "POR", "actions": [
			["war", "GER", "FRA"], ["occupy", "FRA", "GER", 0.0, 0.7, true], ["step"], ["step"]]},
		{"name": "cannot_move_75", "player": "POR", "actions": [
			["war", "GER", "FRA"], ["occupy", "FRA", "GER", 0.0, 0.75, true], ["step"], ["step"]]},
		{"name": "choice_overtaken", "player": "FRA", "actions": [
			["war", "GER", "FRA"], ["occupy", "FRA", "GER", 0.0, 0.3, true], ["step"], ["seize", "FRA", "GER", 0], ["choose", "FRA", 0], ["step"]]},
		{"name": "peace_goes_home", "player": "POR", "actions": [
			["war", "GER", "FRA"], ["occupy", "FRA", "GER", 0.0, 0.3, false], ["occupy", "FRA", "GER", 0.0, 0.0, true], ["step"], ["step"],
			["retake_capital", "FRA"], ["end_war", "GER", "FRA"], ["step"], ["step"]]},
	]
	var result := []
	for camp in campaigns:
		gs.player_tag = ""
		gs.load_scenario(peace_dir)
		gs.ai_enabled = false
		gs.set_player(camp.player)
		Eco.recompute(gs)
		initial_owner = Array(gs.province_owner)
		gs.set_meta("dlog", [])
		var log := []
		var snaps := [_extra(_snapshot(gs, initial_owner, Mil))]
		for act in camp.actions:
			match act[0]:
				"war":
					gs.set_war(act[1], act[2], true, "none", 0, {})
					log.append(act)
				"occupy":
					var ids: Array = Array(gs.nations[act[1]].provinces).duplicate()
					ids.sort()
					var cap: int = gs.nations[act[1]].capital
					var n := ids.size()
					var chosen := []
					if act[3] == 0.0 and act[4] == 0.0:
						pass
					else:
						for i in range(int(act[3] * n), int(act[4] * n)):
							if ids[i] != cap:
								chosen.append(ids[i])
					if act[5]:
						chosen.append(cap)
					for id in chosen:
						gs.set_controller(id, act[2])
					log.append(["occupy", act[1], act[2], chosen])
				"retake_capital":
					var cap: int = gs.nations[act[1]].home_capital if gs.nations[act[1]].home_capital > 0 else gs.nations[act[1]].capital
					gs.set_controller(cap, act[1])
					log.append(["control", cap, act[1]])
				"seize":
					var sid: int = act[3]
					if sid == 0:
						sid = gs.capital_choice.get("candidates", [0])[0]
					gs.set_controller(sid, act[2])
					log.append(["control", sid, act[2]])
				"end_war":
					gs.set_war(act[1], act[2], false)
					log.append(act)
				"choose":
					var cands: Array = gs.capital_choice.get("candidates", [])
					var id: int = act[2]
					if id == 0 and not cands.is_empty():
						id = cands[0]
					var MoveCmd: GDScript = load("res://scripts/sim/move_capital.gd")
					var ok: bool = MoveCmd.new(act[1], id).execute(gs)
					log.append(["choose", act[1], id, ok])
				"step":
					var mark: int = gs.get_meta("dlog").size()
					Cap.step_day(gs)
					var dl: Array = gs.get_meta("dlog").slice(mark)
					log.append(["step", dl])
				"days":
					for i in act[1]:
						clock.days_elapsed += 1
					log.append(act)
			snaps.append(_extra(_snapshot(gs, initial_owner, Mil)))
		result.append({"name": camp.name, "player": camp.player, "log": log, "snaps": snaps})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _extra(snap: Dictionary) -> Dictionary:
	var progress := {}
	for tag in gs.nations:
		progress[tag] = B(Cap.progress(gs, tag))
	snap["progress"] = progress
	snap["choice"] = [gs.capital_choice.get("tag", ""), Array(gs.capital_choice.get("candidates", [])).duplicate(), gs.capital_choice.get("lost", 0)]
	var caps := []
	for w in gs.wars.values():
		caps.append([w.id, w.capitulated.keys()])
	for w in gs.war_history:
		caps.append([w.id, w.capitulated.keys()])
	snap["war_caps"] = caps
	return snap


func _snapshot(gs: Node, initial_owner: Array, Mil: GDScript) -> Dictionary:
	var ground := []
	for id in range(1, gs.province_owner.size()):
		if gs.province_owner[id] != initial_owner[id] or gs.province_controller[id] != gs.province_owner[id]:
			ground.append([id, gs.province_owner[id], gs.province_controller[id]])
	var armies := []
	for a in gs.armies.values():
		armies.append([a.id, a.tag, a.province, a.path.size(), a.still_days, a.attacking])
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		nations.append([B(n.prestige), B(n.treasury), n.capital, n.home_capital, n.provinces.size(), n.population, B(n.war_support), n.men_in_units, n.manpower, B(n.budget.net), n.capitulated, n.construction.size()])
	var indemnities := []
	for i in gs.indemnities:
		indemnities.append([i.payer, i.receiver, B(i.monthly), i.months_left])
	var restrictions := []
	for r in gs.restrictions:
		restrictions.append([r.nation, r.holder, r.get("kind", ""), Array(r.provinces).duplicate(), r.until_day])
	var claims := []
	for c in gs.claims:
		claims.append([c.holder, c.against, c.kind, Array(c.ids).duplicate(), c.expires_day, c.made_day, c.war, c.note])
	var history := []
	for w in gs.war_history:
		history.append([w.a, w.b, w.end_day, _bits_map(w.losses), _bits_map(w.battle_points)])
	var restricted := []
	for r in gs.restrictions:
		for id in range(1, gs.province_owner.size(), 5):
			restricted.append([r.nation, id, Mil.can_enter(gs, r.nation, id)])
	var cooldown := {}
	for k in gs.peace_cooldown:
		cooldown[k] = gs.peace_cooldown[k]
	return {"ground": ground, "armies": armies, "nations": nations, "indemnities": indemnities, "restrictions": restrictions, "claims": claims,
			"rivalries": _bits_map(gs.rivalries), "wars": gs.wars.size(), "history": history, "occupation": gs.occupation.size(),
			"pending": gs.pending_offers.size(), "next_offer": gs.next_offer_id, "restricted": restricted, "cooldown": cooldown}


func _make_peace_copy(name: String) -> String:
	var src := "res://data/scenarios/%s/" % name
	var dst := "user://peace_%s/" % name
	DirAccess.make_dir_recursive_absolute(dst)
	for file in DirAccess.get_files_at(src):
		if file.ends_with(".import"):
			continue
		if file == "scenario.json":
			var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src + file))
			sc.erase("starting_wars")
			var out := FileAccess.open(dst + file, FileAccess.WRITE)
			out.store_string(JSON.stringify(sc))
			out.close()
		else:
			DirAccess.copy_absolute(src + file, dst + file)
	return dst
