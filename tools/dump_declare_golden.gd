extends SceneTree
## Writes what the GDScript does when war is declared and when allies are asked to join, for the Rust port (rust/fs_sim) to
## reproduce: a log of actions (declarations, scenario wars with the allies called, the player's answers, days passing with
## the call-ups they bring) played from the July 1914 scenario, and after every action the conflicts, wars, pending and
## called join decisions, opinions, prestige, war support, casus belli and treaties. The AI's say in joining is not asked of
## the Rust port: the nations that were called (or declined) in each conflict are written down as its answers. Floats are the
## bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_declare_golden.gd -- rust/fs_sim/tests/golden/declare.json

var Dip: GDScript
var Eco: GDScript
var gs: Node
var clock: Node


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _bits_map(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = B(d[k])
	return out


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	Eco = load("res://scripts/sim/economy.gd")
	Dip = load("res://scripts/sim/diplomacy.gd")
	var peace_dir := _make_peace_copy("july_1914")
	var campaigns := [
		{"name": "balkans_gbr_yes", "player": "GBR", "policy": "yes", "actions": [
			["start_war", "AUH", "SRB", true], ["days", 5], ["days", 25], ["days", 60]]},
		{"name": "balkans_gbr_no", "player": "GBR", "policy": "no", "actions": [
			["start_war", "AUH", "SRB", true], ["days", 30], ["days", 60]]},
		{"name": "balkans_ita_alt", "player": "ITA", "policy": "alt", "actions": [
			["start_war", "AUH", "SRB", true], ["days", 20], ["declare", "FRA", "GER", "reconquest", 0], ["days", 40]]},
		{"name": "balkans_fra", "player": "FRA", "policy": "yes", "actions": [
			["start_war", "GER", "FRA", true], ["start_war", "AUH", "SRB", true], ["days", 45], ["declare", "ITA", "AUH", "border_claim", 0], ["days", 30]]},
		{"name": "aggression", "player": "POR", "policy": "yes", "actions": [
			["declare", "GER", "BEL", "none", 0], ["mob", "GER", 0.5], ["declare", "GER", "BEL", "none", 0], ["declare", "AUH", "BEL", "ally_called", 0], ["days", 3],
			["declare", "FRA", "GER", "reconquest", 0], ["declare", "GBR", "GER", "guarantee_defence", 0], ["declare", "GER", "FRA", "none", 0],
			["days", 10], ["declare", "ITA", "AUH", "border_claim", 0], ["declare", "DEN", "GER", "reconquest", 0],
			["declare", "GER", "RUS", "none", 0], ["mob", "AUH", 0.35], ["declare", "AUH", "SRB", "none", 0], ["declare", "AUH", "SRB", "none", 0],
			["days", 40]]},
		{"name": "neutral_victim", "player": "BEL", "policy": "no", "actions": [
			["mob", "RUS", 0.4], ["declare", "RUS", "BEL", "none", 0], ["declare", "FRA", "RUS", "ally_called", 0], ["declare", "AUH", "SRB", "none", 0],
			["mob", "AUH", 0.4], ["declare", "AUH", "SRB", "none", 0], ["answer_all"], ["days", 20], ["violate", "GER", "BEL"], ["answer_all"], ["days", 30]]},
		{"name": "fabricated", "player": "GRE", "policy": "no", "actions": [
			["cb", "RUS", "OTT", "fabricated_claim", 4000, {"kind": "provinces", "ids": [], "label": "fab"}],
			["cb", "GER", "FRA", "unprovoked_aggression", 4000, null], ["declare", "RUS", "OTT", "fabricated_claim", 0], ["declare", "GER", "FRA", "unprovoked_aggression", 0], ["days", 15],
			["declare", "GRE", "OTT", "none", 0], ["mob", "GRE", 0.5], ["declare", "GRE", "OTT", "none", 0], ["days", 30], ["answer_all"], ["days", 30]]},
		{"name": "russia_declines", "player": "RUS", "policy": "no", "actions": [["start_war", "AUH", "SRB", true], ["days", 30]]},
		{"name": "france_declines", "player": "FRA", "policy": "no", "actions": [["start_war", "GER", "BEL", true], ["days", 30]]},
		{"name": "conflict_ai", "player": "POR", "policy": "yes", "actions": [
			["start_war", "ITA", "AUH", false], ["start_war", "RUS", "AUH", true], ["days", 30]]},
		{"name": "conflict_player", "player": "ITA", "policy": "yes", "actions": [
			["start_war", "ITA", "AUH", false], ["start_war", "RUS", "AUH", true], ["days", 30]]},
		{"name": "real_july_1914", "player": "GBR", "policy": "yes", "real": true, "actions": [["days", 20], ["declare", "ITA", "AUH", "border_claim", 0], ["days", 40]]},
		{"name": "gate_edge", "player": "POR", "policy": "yes", "actions": [
			["cb", "GER", "FRA", "unprovoked_aggression", 0, null], ["declare", "GER", "FRA", "unprovoked_aggression", 0],
			["mob", "GER", 0.3], ["declare", "GER", "BEL", "none", 0], ["days", 10]]},
	]
	var result := []
	for camp in campaigns:
		gs.player_tag = ""
		if camp.get("real", false):
			# the scenario as it ships: its own war begins as it loads, with the player's seat not yet taken
			gs.load_scenario("res://data/scenarios/july_1914/")
			gs.ai_enabled = false
		else:
			gs.load_scenario(peace_dir)
			gs.ai_enabled = false
			gs.set_player(camp.player)
		Eco.recompute(gs)
		var log := []
		var snaps := []
		snaps.append(_snapshot())
		for act in camp.actions:
			_play(act, camp.policy, log, snaps)
		var answers := {}
		for gid in gs.war_groups:
			var g: Dictionary = gs.war_groups[gid]
			for tag in g.declined:
				answers["%s|%d" % [tag, gid]] = false
			for tag in g.called:
				answers["%s|%d" % [tag, gid]] = true
		result.append({"name": camp.name, "real": camp.get("real", false), "player": gs.player_tag, "log": log, "snaps": snaps, "answers": answers})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


## Carries out one action, then logs it (with the player's answers it brought) and takes a snapshot.
func _play(act: Array, policy: String, log: Array, snaps: Array) -> void:
	match act[0]:
		"start_war":
			Dip.start_war(gs, act[1], act[2], act[3])
			log.append(act)
			snaps.append(_snapshot())
			_answer_pending(policy, log, snaps)
		"declare":
			var ok: bool = Dip.declare_war(gs, act[1], act[2], act[3], act[4])
			log.append(act + [ok])
			snaps.append(_snapshot())
			_answer_pending(policy, log, snaps)
		"mob":
			gs.nations[act[1]].mobilization = act[2]
			log.append(act)
			snaps.append(_snapshot())
		"cb":
			var cb := {"holder": act[1], "target": act[2], "kind": act[3], "expires_day": act[4]}
			if act[5] != null:
				cb["goal"] = act[5]
			gs.casus_belli.append(cb)
			log.append(act)
			snaps.append(_snapshot())
		"violate":
			Dip.violate_border(gs, act[1], act[2])
			log.append(act)
			snaps.append(_snapshot())
			_answer_pending(policy, log, snaps)
		"answer_all":
			_answer_pending(policy, log, snaps)
		"days":
			for i in act[1]:
				Eco.step_day(gs)
				Dip.step_day(gs)
				clock.days_elapsed += 1
				if gs.economy_dirty:
					gs.economy_dirty = false
					Eco.recompute(gs)
				var shot: bool = i % 5 == 4 or i == act[1] - 1
				log.append(["day", shot])
				if shot:
					snaps.append(_snapshot())
			_answer_pending(policy, log, snaps)


func _answer_pending(policy: String, log: Array, snaps: Array) -> void:
	var count := 0
	while not gs.pending_joins.is_empty():
		var d: Dictionary = gs.pending_joins[0]
		var joins: bool = policy == "yes" or (policy == "alt" and count % 2 == 0)
		var ok: bool = Dip.answer_join(gs, d.id, joins)
		log.append(["answer", d.id, joins, ok])
		snaps.append(_snapshot())
		count += 1


func _decision(d: Dictionary) -> Array:
	return [d.id, d.tag, d.group, d.side, d.kind, d.ally, d.treaty_id, d.cb, d.conflict, d.enemies.duplicate(), d.get("since", -1)]


func _snapshot() -> Dictionary:
	var wars := []
	for key in gs.wars:
		var w = gs.wars[key]
		wars.append([w.id, w.a, w.b, w.casus_belli, w.war_group, w.start_day, JSON.stringify(w.goal)])
	var groups := []
	for gid in gs.war_groups:
		var g: Dictionary = gs.war_groups[gid]
		var members := []
		for t in g.members:
			members.append([t, g.members[t]])
		groups.append([gid, g.attacker, g.defender, members, g.declined.keys(), g.called.keys(), g.get("violation", false)])
	var pending := []
	for d in gs.pending_joins:
		pending.append(_decision(d))
	var calls := []
	for key in gs.join_calls:
		calls.append([key, _decision(gs.join_calls[key])])
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		nations.append([tag, B(n.mobilization), B(n.prestige), B(n.war_support)])
	var cbs := []
	for c in gs.casus_belli:
		cbs.append([c.holder, c.target, c.kind, c.expires_day, JSON.stringify(c.get("goal", null))])
	var treaties := []
	for t in gs.treaties:
		treaties.append([t.id, t.kind, t.a, t.b, t.end_day])
	var options := []
	var tags := ["GER", "FRA", "RUS", "AUH", "SRB", "ITA", "GBR", "BEL", "OTT", "GRE", "BUL", "ROM", "DEN", "POR"]
	for a in tags:
		for b in tags:
			if not gs.nations.has(a) or not gs.nations.has(b):
				continue
			var opts: Array = Dip.casus_belli_options(gs, a, b)
			var can := []
			for cb in opts:
				can.append(Dip.can_declare(gs, a, b, cb))
			options.append([a, b, Dip.declare_block(gs, a, b), opts, can, Dip.is_neutral(gs, b)])
	return {"day": clock.days_elapsed, "wars": wars, "groups": groups, "pending": pending, "calls": calls, "nations": nations,
			"relations": _bits_map(gs.relations), "grievance": _bits_map(gs.grievance), "cbs": cbs, "treaties": treaties,
			"counters": [gs.next_decision_id, gs.next_war_group, gs.next_war_id, gs.ai_declarations.total, gs.ai_declarations.unjustified, B(gs.tension_impulse)],
			"options": options}


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
