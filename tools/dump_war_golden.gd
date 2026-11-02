extends SceneTree
## Writes what the GDScript armies do in a war, for the Rust port (rust/fs_sim) to reproduce: wars between neighbours, armies
## sent over the borders with the game's own MoveArmy command, then Economy.step_day and Military.step_day each day with the AI
## off. A summary of every nation is kept each day and the whole of the armies every few days; the run is cut short before the
## day on which a nation would capitulate or lose its capital, which the port does not do yet. Floats are the bits of their
## 64-bit value.
##   godot --headless --path . -s res://tools/dump_war_golden.gd -- rust/fs_sim/tests/golden/war.json


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var Eco: GDScript = load("res://scripts/sim/economy.gd")
	var Mil: GDScript = load("res://scripts/sim/military.gd")
	var MoveCmd: GDScript = load("res://scripts/sim/move_army.gd")
	var result := {}
	var peace_dir := _make_peace_copy("july_1914")
	var campaigns := [
		{"name": "west", "wars": [["GER", "FRA"], ["GER", "BEL"]], "days": 150},
		{"name": "east", "wars": [["AUH", "SRB"], ["RUS", "AUH"], ["RUS", "GER"]], "days": 150},
		{"name": "south", "wars": [["ITA", "AUH"], ["OTT", "GRE"], ["BUL", "SRB"]], "days": 150},
	]
	for camp in campaigns:
		gs.load_scenario(peace_dir)
		gs.ai_enabled = false
		for w in camp.wars:
			gs.set_war(w[0], w[1], true)
		# Works on the ground the armies go for, so that the defenders dig in: trenches and fortifications at the border provinces.
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
		# Armies sent at each other over the borders: up to three of each side's, to the nearest ground of the enemy; and two
		# more deep into the enemy's country, far from their own supply.
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
				var deep := 0
				for a in Mil.armies_of(gs, pair[0]):
					if deep >= 2:
						break
					if not a.path.is_empty():
						continue
					var far := _deep_target(gs, Mil, pair[0], pair[1], a.province, 14)
					if far == 0:
						continue
					var dcmd = MoveCmd.new(pair[0], a.id, far)
					var dok: bool = dcmd.execute(gs)
					orders.append([pair[0], a.id, far, dok])
					if dok:
						deep += 1
		var initial_controllers := Array(gs.province_controller)
		var days := []
		var checkpoints := []
		var stopped := ""
		var capitals := {}
		for tag in gs.nations:
			capitals[tag] = gs.nations[tag].capital
		for day in camp.days:
			Eco.step_day(gs)
			Mil.step_day(gs)
			clock.days_elapsed += 1
			if gs.economy_dirty:
				gs.economy_dirty = false
				Eco.recompute(gs)
			# stop before anything the port does not do yet
			for tag in gs.nations:
				if gs.nations[tag].capitulated or gs.nations[tag].capital != capitals[tag]:
					stopped = "day %d: %s capitulated or moved its capital" % [day + 1, tag]
			if stopped != "":
				break
			days.append(_summary(gs))
			if (day + 1) % 5 == 0:
				checkpoints.append({"day": day + 1, "armies": _armies(gs), "wars": _wars(gs), "changed": _changed(gs, initial_controllers),
						"occupation": _occupation(gs), "last_battle": _last_battle(gs), "engagements": gs.engagements.size(),
						"supply": _supply(gs, Mil) if (day + 1) % 30 == 0 else []})
			if (day + 1) % 30 == 0:
				Eco.step_month(gs)
		result[camp.name] = {"wars": camp.wars, "works": works, "orders": orders, "days": days, "checkpoints": checkpoints, "stopped": stopped,
				"initial_armies": null}
		print(camp.name, ": ", days.size(), " days, ", orders.size(), " orders, stopped: ", stopped)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


## The enemy province nearest (in hops) to where the army stands that borders the sender's own ground, the `index`th of them.
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


## The enemy province farthest (in hops, up to `limit`) from where the army stands, of the enemy's own ground.
func _deep_target(gs: Node, Mil: GDScript, tag: String, enemy: String, from: int, limit: int) -> int:
	var seen := {from: 0}
	var queue := [from]
	var best := 0
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if seen[cur] >= limit:
			continue
		for n in Mil.neighbors(cur):
			if not seen.has(n):
				seen[n] = seen[cur] + 1
				queue.append(n)
				if gs.province_owner[n] == enemy and gs.province_controller[n] == enemy:
					best = n
	return best


## What each side could supply, province by province (every third), and the reach of its cities there.
func _supply(gs: Node, Mil: GDScript) -> Array:
	var out := []
	for tag in ["GER", "RUS", "AUH", "FRA", "ITA", "SRB"]:
		for id in range(1, gs.province_owner.size(), 3):
			var cost: float = Mil.supply_cost(gs, tag, id)
			out.append([tag, id, "inf" if cost == INF else B(cost), B(Mil.city_aura(gs, tag, id))])
	return out


func _summary(gs: Node) -> Array:
	var rows := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		rows.append([n.men_in_units, n.manpower, B(n.deaths_month), B(n.men_lost_month), B(n.war_support), B(n.prestige), B(n.munitions)])
	return rows


func _armies(gs: Node) -> Array:
	var out := []
	for a in gs.armies.values():
		var units := []
		for u in a.units:
			units.append([u.type, B(u.strength), B(u.morale), B(u.experience)])
		out.append([a.id, a.tag, a.province, a.path.duplicate(), B(a.move_days_left), a.still_days, a.attacking, a.fighting, a.supplied,
				a.landing_days, a.landed_supply, units])
	return out


func _wars(gs: Node) -> Array:
	var out := []
	for w in gs.wars.values():
		var cap := {}
		for t in w.captured:
			cap[t] = [w.captured[t].provinces, w.captured[t].population]
		out.append({"a": w.a, "b": w.b, "last_fight_day": w.last_fight_day, "losses": _bits(w.losses), "attrition": _bits(w.attrition),
				"surrendered": _bits(w.surrendered), "battle_points": _bits(w.battle_points), "captured": cap})
	return out


func _bits(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = B(d[k])
	return out


func _changed(gs: Node, initial: Array) -> Array:
	var out := []
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] != initial[id]:
			out.append([id, gs.province_controller[id]])
	return out


func _occupation(gs: Node) -> Array:
	var ids: Array = gs.occupation.keys()
	ids.sort()
	var out := []
	for id in ids:
		out.append([id, gs.occupation[id].tag, gs.occupation[id].days])
	return out


func _last_battle(gs: Node) -> Array:
	var ids: Array = gs.last_battle_day.keys()
	ids.sort()
	var out := []
	for id in ids:
		out.append([id, gs.last_battle_day[id]])
	return out


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
