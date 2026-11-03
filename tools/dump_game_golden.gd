extends SceneTree
## Writes what the real game does day after day with nobody at the helm, for the Rust port (rust/fs_sim) to reproduce end to end:
## a scenario loaded as it ships, its own war begun, orders given to some armies, and then the clock driven day by day, so that
## the game's own stages run in the game's own order (economy, focus, navy, armies, diplomacy, the month's steps). The AI is off
## and the crises are off (neither is ported). The nations' money, people and standing, the ground, the armies, the fleets, the
## wars, opinions and tension are written down every few days. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_game_golden.gd -- rust/fs_sim/tests/golden/game.json

var gs: Node
var clock: Node
var Mil: GDScript


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
	Mil = load("res://scripts/sim/military.gd")
	var MoveCmd: GDScript = load("res://scripts/sim/move_army.gd")
	var runs := [
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 400, "every": 10, "orders": [["AUH", "SRB", 3], ["SRB", "AUH", 3]]},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 300, "every": 10, "player": "POR", "wars": [["GER", "FRA"], ["ITA", "AUH"]],
				"orders": [["GER", "FRA", 4], ["FRA", "GER", 4], ["ITA", "AUH", 3], ["RUS", "GER", 3], ["GER", "RUS", 3], ["AUH", "ITA", 3]]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 400, "every": 10, "orders": []},
	]
	var result := []
	for run in runs:
		gs.player_tag = ""
		gs.load_scenario(run.dir)
		gs.ai_enabled = false
		gs.pressure_ai = false
		var log := []
		if run.has("player"):
			gs.set_player(run.player)
		var dip: GDScript = load("res://scripts/sim/diplomacy.gd")
		for w in run.get("wars", []):
			dip.start_war(gs, w[0], w[1], true)
		for o in run.orders:
			var sent := 0
			for a in Mil.armies_of(gs, o[0]):
				if sent >= o[2]:
					break
				var target := _border_target(o[0] if false else o[1], a.province, sent)
				if target == 0:
					continue
				var cmd = MoveCmd.new(o[0], a.id, target)
				var ok: bool = cmd.execute(gs)
				log.append([o[0], a.id, target, ok])
				if ok:
					sent += 1
		var snaps := [_snapshot()]
		for d in run.days:
			clock.advance_day()
			if d % run.every == run.every - 1:
				snaps.append(_snapshot())
		var answers := {}
		for gid in gs.war_groups:
			var g: Dictionary = gs.war_groups[gid]
			for tag in g.declined:
				answers["%s|%d" % [tag, gid]] = false
			for tag in g.called:
				answers["%s|%d" % [tag, gid]] = true
		result.append({"name": run.name, "player": gs.player_tag, "orders": log, "extra_wars": run.get("wars", []), "set_player": run.get("player", ""), "every": run.every, "snaps": snaps, "answers": answers})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _border_target(enemy: String, from: int, index: int) -> int:
	var seen := {from: 0}
	var queue := [from]
	var found := []
	while not queue.is_empty() and found.size() <= index + 1:
		var cur: int = queue.pop_front()
		if gs.province_owner[cur] == enemy and gs.province_controller[cur] == enemy:
			found.append(cur)
		for n in Mil.neighbors(cur):
			if not seen.has(n):
				seen[n] = seen[cur] + 1
				queue.append(n)
	return found[index] if found.size() > index else (found[0] if not found.is_empty() else 0)


func _snapshot() -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		nations.append([B(n.treasury), B(n.prestige), B(n.war_support), B(n.mobilization), n.population, n.manpower, n.men_in_units, B(n.blockade),
				n.capital, B(n.budget.net), B(n.diplomacy_points), n.provinces.size(), B(n.cp), n.capitulated, B(n.budget.income), B(n.budget.cp)])
	var armies := []
	for a in gs.armies.values():
		armies.append([a.id, a.tag, a.province, B(a.men()), a.path.size(), a.fighting])
	var fleets := []
	for f in gs.fleets.values():
		fleets.append([f.id, f.zone, f.port, f.ships.size()])
	var wars := []
	for w in gs.wars.values():
		wars.append([w.id, w.a, w.b, w.war_group])
	var hist := []
	for w in gs.war_history:
		hist.append([w.id, w.end_day])
	var owners := []
	var controllers := []
	var pops := 0
	for id in range(1, gs.province_owner.size()):
		owners.append(gs.province_owner[id])
		controllers.append(gs.province_controller[id])
		pops += gs.province_population[id]
	var AIP: GDScript = load("res://scripts/ai/ai_peace.gd")
	var urges := []
	for w in gs.wars.values():
		for tag in [w.a, w.b]:
			var p: Dictionary = AIP.proposal(gs, tag, w)
			var parts: Dictionary = AIP.urge_parts(gs, tag, w)
			urges.append([w.id, tag, B(parts.total), B(parts.score), B(parts.quiet), B(parts.allies), p.get("mode", ""), JSON.stringify(p.get("demands", []))])
	var Pea: GDScript = load("res://scripts/sim/peace.gd")
	var accepts := []
	for w in gs.wars.values():
		for pair in [[w.a, w.b], [w.b, w.a]]:
			for mode in ["demand", "offer"]:
				var taker: String = pair[0] if mode == "demand" else pair[1]
				var giver: String = pair[1] if mode == "demand" else pair[0]
				var held := []
				for id in gs.nations[giver].provinces:
					if gs.province_controller[id] == taker:
						held.append(id)
				var sets := [[], [{"kind": "indemnity", "share": 0.1, "months": 12}]]
				if not held.is_empty():
					sets.append([{"kind": "province", "ids": held.slice(0, 1)}])
					sets.append([{"kind": "province", "ids": held.slice(0, 3)}, {"kind": "indemnity", "share": 0.2, "months": 12}])
				for demands in sets:
					var c: Dictionary = Pea.check(gs, pair[0], pair[1], mode, demands)
					if not c.ok:
						accepts.append([w.id, pair[0], mode, JSON.stringify(demands), "no"])
						continue
					var offer := {"id": 0, "war_id": w.id, "from": pair[0], "to": pair[1], "mode": mode, "taker": c.taker, "giver": c.giver, "demands": demands, "cost": c.cost, "forced": c.forced, "day": 0}
					accepts.append([w.id, pair[0], mode, JSON.stringify(demands), "yes" if AIP.accepts(gs, offer) else "refuses"])
	return {"accepts": accepts, "urges": urges, "day": clock.days_elapsed, "date": clock.date_string(), "nations": nations, "armies": armies, "fleets": fleets, "wars": wars, "history": hist,
			"owners": owners, "controllers": controllers, "pop": pops, "relations": _bits_map(gs.relations), "tension": B(gs.tension),
			"pending": gs.pending_events.size(), "chronicle": gs.chronicle.size() if "chronicle" in gs else -1, "treaties": gs.treaties.size(),
			"groups": gs.war_groups.size(), "calls": gs.join_calls.size(), "grievance": _bits_map(gs.grievance),
			"rivalries": _bits_map(gs.rivalries), "indemnities": gs.indemnities.map(func(i): return [i.payer, i.receiver, B(i.monthly), i.months_left]),
			"claims": gs.claims.map(func(c): return [c.holder, c.against, Array(c.ids).duplicate(), c.expires_day]), "cooldown": gs.peace_cooldown.duplicate(),
			"restrictions": gs.restrictions.size(), "tparts": _bits_map(load("res://scripts/sim/pressure.gd").parts(gs)), "arms_base": B(gs.tension_arms_base), "impulse": B(gs.tension_impulse), "relation_base": _bits_map(gs.relation_base)}
