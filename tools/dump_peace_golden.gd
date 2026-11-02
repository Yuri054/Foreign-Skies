extends SceneTree
## Writes what the GDScript peace rules do, for the Rust port (rust/fs_sim) to reproduce: wars fought for forty days with the
## game's own code, then what each side's war score is, what demands of every kind would cost and be refused for, peace made
## on terms chosen from the score (ground, an indemnity, a disarmed border; the player's answer to an offer; white peace), what
## each leaves behind (ground, armies pulled back, prestige, claims, rivalries, clauses, indemnities), and a few months after
## it. The AI's say in whether it accepts an offer is not asked: the terms are carried out as accepted. Floats are the bits of
## their 64-bit value.
##   godot --headless --path . -s res://tools/dump_peace_golden.gd -- rust/fs_sim/tests/golden/peace.json


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
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var Eco: GDScript = load("res://scripts/sim/economy.gd")
	var Mil: GDScript = load("res://scripts/sim/military.gd")
	var Pea: GDScript = load("res://scripts/sim/peace.gd")
	var MoveCmd: GDScript = load("res://scripts/sim/move_army.gd")
	var result := {}
	var peace_dir := _make_peace_copy("july_1914")
	var campaigns := [
		{"name": "west", "player": "BEL", "wars": [["GER", "FRA", "none", ""], ["GER", "BEL", "", "provinces"]]},
		{"name": "east", "player": "POR", "wars": [["AUH", "SRB", "", "concession"], ["RUS", "AUH", "ally_called", "defence"], ["RUS", "GER", "", "provinces"]]},
		{"name": "south", "player": "GRE", "wars": [["ITA", "AUH", "none", ""], ["OTT", "GRE", "", "nationality"], ["BUL", "SRB", "", "provinces"]]},
	]
	for camp in campaigns:
		gs.load_scenario(peace_dir)
		gs.ai_enabled = false
		gs.set_player(camp.player)
		var goals := []
		for w in camp.wars:
			var goal := {}
			match w[3]:
				"provinces", "nationality":
					var ids := []
					for index in 2:
						var t := _border_target(gs, Mil, w[0], w[1], gs.nations[w[0]].provinces[0], index)
						if t > 0 and not ids.has(t):
							ids.append(t)
					goal = {"kind": w[3], "ids": ids, "label": ""}
				"concession":
					goal = {"kind": "concession", "demand": {"kind": "indemnity", "share": 0.1, "months": 12}, "label": ""}
				"defence":
					goal = {"kind": "defence", "label": ""}
			goals.append(goal)
			gs.set_war(w[0], w[1], true, w[2], 0, goal)
		var works := []
		for w in camp.wars:
			for pair in [[w[0], w[1]], [w[1], w[0]]]:
				var mine = Mil.armies_of(gs, pair[0])
				if mine.is_empty():
					continue
				for index in 2:
					var target := _border_target(gs, Mil, pair[0], pair[1], mine[0].province, index)
					if target > 0:
						for kind in [["fortification", 3 + index], ["trench", 4]]:
							gs.province_buildings[target][kind[0]] = kind[1]
							works.append([target, kind[0], kind[1]])
		Eco.recompute(gs)
		var orders := []
		for w in camp.wars:
			for pair in [[w[0], w[1]], [w[1], w[0]]]:
				var sent := 0
				for a in Mil.armies_of(gs, pair[0]):
					if sent >= 3:
						break
					var target := _border_target(gs, Mil, pair[0], pair[1], a.province, sent)
					if target == 0:
						continue
					var cmd = MoveCmd.new(pair[0], a.id, target)
					var ok: bool = cmd.execute(gs)
					orders.append([pair[0], a.id, target, ok])
					if ok:
						sent += 1
		var days := 40
		for day in days:
			Eco.step_day(gs)
			Mil.step_day(gs)
			clock.days_elapsed += 1
			if gs.economy_dirty:
				gs.economy_dirty = false
				Eco.recompute(gs)
		var stopped := false
		for tag in gs.nations:
			if gs.nations[tag].capitulated:
				stopped = true
		var initial_owner := Array(gs.province_owner)
		# ---- what the score is and what could be asked
		var cases := []
		for war in gs.wars.values():
			var scores := {}
			for tag in [war.a, war.b]:
				var parts: Dictionary = Pea.score_parts(gs, war, tag)
				scores[tag] = _bits_map(parts)
			for pair in [[war.a, war.b], [war.b, war.a]]:
				var taker: String = pair[0]
				var giver: String = pair[1]
				var held := []
				var unheld := []
				for id in gs.nations[giver].provinces:
					if gs.province_controller[id] == taker:
						held.append(id)
					elif held.size() + unheld.size() < 40:
						unheld.append(id)
				var prices := []
				for id in held.slice(0, 4) + unheld.slice(0, 3):
					prices.append([id, B(Pea.province_price(gs, id, taker, giver))])
				var capital: int = gs.nations[giver].capital
				var variants := {
					"white": [],
					"held1": [{"kind": "province", "ids": held.slice(0, 1)}] if not held.is_empty() else [],
					"held2": [{"kind": "province", "ids": held.slice(0, 2)}] if held.size() > 1 else [],
					"unheld1": [{"kind": "province", "ids": unheld.slice(0, 1)}] if not unheld.is_empty() else [],
					"capital": [{"kind": "province", "ids": [capital]}],
					"held_unheld": [{"kind": "province", "ids": held.slice(0, 1) + unheld.slice(0, 1)}] if not held.is_empty() and not unheld.is_empty() else [],
					"indemnity": [{"kind": "indemnity", "share": 0.1, "months": 12}],
					"indemnity_big": [{"kind": "indemnity", "share": 0.9, "months": 12}],
					"indemnity_long": [{"kind": "indemnity", "share": 0.1, "months": 100}],
					"disarm": [{"kind": "disarm_border", "years": 3}],
					"disarm_long": [{"kind": "disarm_border", "years": 50}],
					"fleet": [{"kind": "fleet_limit", "years": 2}],
					"release": [{"kind": "release_ally", "nation": "GBR"}, {"kind": "release_ally", "nation": "XXX"}],
					"combo": [{"kind": "province", "ids": held.slice(0, 1)}, {"kind": "indemnity", "share": 0.05, "months": 6}] if not held.is_empty() else [],
					"empty_province": [{"kind": "province", "ids": []}],
					"all_held": [{"kind": "province", "ids": held.duplicate()}] if held.size() > 1 else [],
					"everything": [{"kind": "province", "ids": Array(gs.nations[giver].provinces)}],
				}
				var checks := {}
				for name in variants:
					for mode in ["demand", "offer"]:
						var from: String = taker if mode == "demand" else giver
						var to: String = giver if mode == "demand" else taker
						var c: Dictionary = Pea.check(gs, from, to, mode, variants[name])
						checks["%s|%s" % [name, mode]] = {"ok": c.ok, "reason": c.reason, "cost": B(c.cost), "budget": B(c.get("budget", 0.0)) if c.has("budget") else "", "forced": c.forced, "taker": c.taker, "giver": c.giver}
				var cand := held + unheld
				cand.sort_custom(func(x: int, y: int) -> bool: return Pea.province_price(gs, x, taker, giver) > Pea.province_price(gs, y, taker, giver))
				var picks := []
				for budget in [5.0, 30.0, 1000.0]:
					var pk: Dictionary = Pea.pick_takeable(gs, taker, giver, cand, func(id: int) -> float: return Pea.province_price(gs, id, taker, giver), budget)
					picks.append([budget, pk.ids, B(pk.spent)])
				cases.append({"war": [war.a, war.b], "taker": taker, "giver": giver, "picks": picks, "scores": scores, "prices": prices, "variants": variants, "checks": checks,
						"forced": Pea.is_forced(gs, taker, giver), "occupied": B(Pea.occupied_share(gs, taker, giver)), "capital_points": B(Pea.capital_points(gs, taker, giver)),
						"max_cession": Pea.max_cession(gs, giver), "capital_taken_by": Pea.capital_taken_by(gs, giver)})
		# a month's business with the wars still on: battle points fade
		Pea.step_month(gs)
		var early := _snapshot(gs, initial_owner, Mil)
		var early_points := []
		for war in gs.wars.values():
			early_points.append(_bits_map(war.battle_points))
		early["points"] = early_points
		# ---- making peace, war by war
		var plans := []
		var after := []
		var wars_now: Array = gs.wars.values().duplicate()
		var which := 0
		for war in wars_now:
			var sa: float = Pea.war_score(gs, war, war.a)
			var sb: float = Pea.war_score(gs, war, war.b)
			var taker: String = war.a if sa >= sb else war.b
			var giver: String = war.other(taker)
			var demands := []
			var pre := {}
			if which == 0:
				# the loser's people will not fight on: it can be made to give what the taker holds, for more than the score
				gs.nations[giver].war_support = 0.0
				pre["war_support"] = {giver: 0.0}
				gs.nations[giver].treasury = -5000.0
				pre["treasury"] = {giver: -5000.0}
			elif which == 1:
				# most of the loser is held, and an old rivalry stands above what ceding ground would add
				var controllers := []
				var count := 0
				for id in gs.nations[giver].provinces:
					if id != gs.nations[giver].capital and count < int(gs.nations[giver].provinces.size() * 0.8):
						gs.set_controller(id, taker)
						controllers.append([id, taker])
						count += 1
				pre["controllers"] = controllers
				pre["rivalries"] = {"%s>%s" % [giver, taker]: 70.0}
			elif which == 2:
				# the capital is taken and the people are weary
				var cap: int = gs.nations[giver].capital
				gs.set_controller(cap, taker)
				pre["controllers"] = [[cap, taker]]
				gs.nations[giver].war_support = 20.0
				pre["war_support"] = {giver: 20.0}
			if which == 1:
				war.battle_points[taker] = 150.0
				pre["battle_points"] = {taker: 150.0}
			if pre.has("controllers") or pre.has("rivalries"):
				for k in pre.get("rivalries", {}):
					gs.rivalries[k] = pre.rivalries[k]
				Eco.recompute(gs)
			for k in pre.get("treasury", {}):
				gs.nations[k].treasury = pre.treasury[k]
			var candidates := []
			var held := []
			for id in gs.nations[giver].provinces:
				if gs.province_controller[id] == taker:
					held.append(id)
			held.sort_custom(func(x: int, y: int) -> bool: return Pea.province_price(gs, x, taker, giver) > Pea.province_price(gs, y, taker, giver))
			var budget: float = maxf(Pea.war_score(gs, war, taker), 0.0) * (1.5 if Pea.is_forced(gs, taker, giver) else 0.8)
			var picked: Dictionary = Pea.pick_takeable(gs, taker, giver, held, func(id: int) -> float: return Pea.province_price(gs, id, taker, giver), budget)
			if not picked.ids.is_empty():
				candidates.append({"kind": "province", "ids": picked.ids})
			var release := ""
			for t in gs.treaties:
				if t.end_day < 0 and (t.kind == "alliance" or t.kind == "guarantee") and (t.a == giver or t.b == giver):
					var other: String = t.other(giver)
					if other != taker and release == "":
						release = other
			var extras := [{"kind": "indemnity", "share": 0.01, "months": 1}, {"kind": "disarm_border", "years": 1}, {"kind": "fleet_limit", "years": 1}, {"kind": "indemnity", "share": 0.02, "months": 3}]
			if release != "":
				extras.append({"kind": "release_ally", "nation": release})
			if which % 3 == 1:
				extras = extras.slice(0, 1)
			elif which % 3 == 2:
				extras = extras.slice(3, 5)
			candidates.append_array(extras)
			for cand in candidates:
				var trial := demands.duplicate()
				trial.append(cand)
				if Pea.check(gs, taker, giver, "demand", trial).ok:
					demands = trial
			# works under construction in the first province asked for (they are lost with the ground)
			for d in demands:
				if d.kind == "province" and not pre.has("job"):
					gs.nations[giver].construction.append(Eco.new_job(d.ids[0], "railway", 800.0, 40))
					pre["job"] = [giver, d.ids[0], "railway", 800.0, 40]
			var parts := _bits_map(Pea.score_parts(gs, war, taker))
			var c: Dictionary = Pea.check(gs, taker, giver, "demand", demands)
			if not c.ok:
				demands = []
				c = Pea.check(gs, taker, giver, "demand", demands)
			var refusal := {}
			if which == wars_now.size() - 1:
				# the offer is refused: the proposer must wait before asking again
				var off0 := {"id": gs.next_offer_id, "war_id": war.id, "from": taker, "to": giver, "mode": "demand", "taker": taker, "giver": giver, "demands": [], "cost": 0.0, "forced": false, "day": clock.days_elapsed}
				gs.next_offer_id += 1
				Pea._resolve(gs, off0, false)
				var blocked: Dictionary = Pea.check(gs, taker, giver, "demand", [])
				var by_player: Dictionary = Pea.check(gs, camp.player, giver if camp.player != giver else taker, "demand", [])
				refusal = {"offer": [off0.id, off0.war_id], "reason": blocked.reason, "player_reason": by_player.reason, "cooldown": gs.peace_cooldown.duplicate()}
				clock.days_elapsed += 31
				c = Pea.check(gs, taker, giver, "demand", demands)
			var method := "direct"
			var pending := []
			var pending_reason := ""
			var spoiled := false
			var offer_id := 0
			if giver == camp.player:
				method = "player"
				var r: Dictionary = Pea.propose(gs, taker, giver, "demand", demands)
				for o in gs.pending_offers:
					pending.append([o.id, o.from, o.to, o.mode, o.cost, o.forced])
				offer_id = gs.pending_offers[0].id if not gs.pending_offers.is_empty() else 0
				var pending_check: Dictionary = Pea.check(gs, taker, giver, "demand", demands)
				pending_reason = pending_check.reason
				# the ground it asked for is lost to a third nation before the answer: the offer is no longer valid
				for d in demands:
					if d.kind == "province" and not spoiled and camp.name == "south":
						gs.transfer_province(d.ids[0], "POR")
						spoiled = true
				var answered: bool = Pea.answer(gs, offer_id, true)
				plans.append({"taker": taker, "giver": giver, "pre": pre, "parts": parts, "demands": demands, "method": method, "ok": c.ok, "cost": B(c.cost), "forced": c.forced, "pending": pending, "answered": answered, "propose_accepted": r.accepted == null, "pending_reason": pending_reason, "spoiled": spoiled, "refusal": refusal})
			else:
				var offer := {"id": gs.next_offer_id, "war_id": war.id, "from": taker, "to": giver, "mode": "demand", "taker": taker, "giver": giver,
						"demands": demands, "cost": c.cost, "forced": c.forced, "day": clock.days_elapsed}
				gs.next_offer_id += 1
				Pea.make_peace(gs, war, offer)
				plans.append({"taker": taker, "giver": giver, "pre": pre, "parts": parts, "demands": demands, "method": method, "ok": c.ok, "cost": B(c.cost), "forced": c.forced, "pending": [], "answered": true, "propose_accepted": false, "pending_reason": "", "spoiled": false, "refusal": refusal})
			after.append(_snapshot(gs, initial_owner, Mil))
			which += 1
		# any war still on (an offer the player lost the ground for) ends in a white peace, so the AI has no war to make offers in
		for war in gs.wars.values().duplicate():
			var taker2: String = war.a
			var giver2: String = war.b
			var c2: Dictionary = Pea.check(gs, taker2, giver2, "demand", [])
			var offer2 := {"id": gs.next_offer_id, "war_id": war.id, "from": taker2, "to": giver2, "mode": "demand", "taker": taker2, "giver": giver2,
					"demands": [], "cost": c2.cost, "forced": c2.forced, "day": clock.days_elapsed}
			gs.next_offer_id += 1
			Pea.make_peace(gs, war, offer2)
			plans.append({"taker": taker2, "giver": giver2, "pre": {}, "parts": {}, "demands": [], "method": "direct", "ok": c2.ok, "cost": B(c2.cost), "forced": c2.forced, "pending": [], "answered": true, "propose_accepted": false, "pending_reason": "", "spoiled": false, "refusal": {}})
			after.append(_snapshot(gs, initial_owner, Mil))
		# ---- the months after (the wars are over: nothing for the AI to offer)
		var months := []
		for m in 14:
			for d in 30:
				clock.days_elapsed += 1
			Eco.step_month(gs)
			Pea.step_month(gs)
			months.append(_snapshot(gs, initial_owner, Mil))
		result[camp.name] = {"player": camp.player, "wars": camp.wars, "goals": goals, "works": works, "orders": orders, "days": days, "stopped": stopped, "cases": cases,
				"plans": plans, "after": after, "months": months, "early": early}
		print(camp.name, ": ", cases.size(), " sides, ", plans.size(), " peaces, stopped: ", stopped)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _border_target(gs: Node, Mil: GDScript, tag: String, enemy: String, from: int, index: int) -> int:
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
