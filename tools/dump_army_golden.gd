extends SceneTree
## Writes what the GDScript does with armies and the men in them, for the Rust port (rust/fs_sim) to reproduce: units raised and
## trained (and where they join), armies put on exercise, units sent home, armies split, merged and handed units, generals
## assigned and freed (the AI's nations put their best free general in command of their biggest army without one), a nation
## that loses its land. The days run in the game's order (economy, navy, army). Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_army_golden.gd -- rust/fs_sim/tests/golden/army.json

var gs: Node
var clock: Node
var Eco: GDScript
var Mil: GDScript
var NavyCls: GDScript


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	Eco = load("res://scripts/sim/economy.gd")
	Mil = load("res://scripts/sim/military.gd")
	NavyCls = load("res://scripts/sim/navy.gd")
	var peace_dir := _make_peace_copy("july_1914")
	var campaigns := [
		{"name": "raise_and_train", "player": "POR", "actions": [
			["raise", "GBR", 0, "infantry", 3], ["raise", "GBR", 0, "cavalry", 2], ["raise", "GBR", 0, "artillery", 1], ["raise", "GBR", 1, "infantry", 1],
			["raise", "GBR", 0, "infantry", 99999], ["raise", "GBR", 0, "nonsense", 1], ["raise", "GBR", 0, "infantry", 0], ["raise", "FRA", 999, "infantry", 1],
			["raise", "GER", -1, "infantry", 2], ["days", 20, 5], ["days", 20, 5],
			["train", "GBR", true, 2], ["train", "GER", true, 3], ["days", 30, 5], ["train", "GBR", false, 1], ["days", 40, 10], ["split", "FRA", 0, [0]],
			["raise", "FRA", 0, "infantry", 4], ["raise", "FRA", 0, "cavalry", 3], ["days", 35, 7],
			["train_foreign", "GBR", "FRA"], ["war", "GER", "FRA"], ["seize_capital", "FRA", "GER"], ["raise", "FRA", 0, "infantry", 1],
			["split", "GBR", 0, [0]], ["raise", "GBR", 0, "cavalry", 2], ["train", "GBR", true, 3], ["order_from", "GBR", 0], ["days", 31, 6]]},
		{"name": "demobilize", "player": "POR", "actions": [
			["raise", "GER", 0, "infantry", 6], ["raise", "GER", 0, "artillery", 3], ["days", 31, 31], ["demob", "GER", 0, -1], ["demob", "GER", 0, 3], ["demob", "GER", 0, -1], ["demob", "FRA", 1, 2],
			["demob", "FRA", 0, -1], ["war", "RUS", "AUH"], ["demob", "RUS", 0, 1], ["days", 10, 5]]},
		{"name": "handling", "player": "GBR", "actions": [
			["split", "GBR", 0, [0]], ["split", "GBR", 0, [0, 1]], ["split", "GBR", 1, [0, 0]], ["split", "GBR", 0, [99]], ["merge", "GBR", [0, -1]], ["merge", "GBR", [0, 0]],
			["merge", "GBR", [0, 1]], ["transfer", "GBR", 0, [0], -1], ["transfer", "GBR", -1, [0, 1], 0], ["transfer", "GBR", 0, [0], 0], ["assign", "GBR", 0, 1],
			["assign", "GBR", 1, 1], ["assign", "GBR", 1, -1], ["assign", "GBR", 0, 0], ["assign", "GBR", 1, 0], ["assign", "FRA", 0, 1], ["assign", "GBR", 99, 1],
			["days", 3, 1], ["merge", "GBR", [0, -2]], ["days", 3, 1], ["split", "GBR", 0, [0, 1, 2]], ["merge", "GBR", [-1, 0]], ["days", 2, 1],
			["days", 6, 6], ["split", "GBR", 0, [0]], ["assign", "GBR", 1, -1], ["merge", "GBR", [0, -1]], ["split", "GBR", 0, [0]], ["assign", "GBR", 0, -1], ["merge", "GBR", [0, -1]],
			["split", "GBR", 0, [0]], ["transfer", "GBR", -1, [0], 0], ["transfer", "GBR", 0, [0], 1], ["split", "GBR", 0, [0]], ["transfer", "GBR", -1, [0], 0], ["days", 2, 1]]},
		{"name": "ai_generals", "player": "POR", "actions": [
			["split", "FRA", 0, [0]], ["days", 2, 1], ["split", "GER", 0, [0, 1]], ["split", "GER", 1, [0]], ["days", 2, 1], ["merge", "GER", [0, -1]], ["days", 2, 1],
			["wipe", "FRA", 0], ["days", 3, 1], ["wipe", "FRA", 0], ["wipe", "GER", 1], ["days", 3, 1], ["assign", "GER", 0, 0], ["days", 2, 1],
			["split", "GER", 0, [0]], ["split", "GER", 2, [0, 1]], ["split", "GER", 3, [0]], ["wipe", "GER", 0], ["wipe", "GER", 1], ["days", 3, 1]]},
		{"name": "collapse", "player": "POR", "actions": [
			["raise", "BEL", 0, "infantry", 2], ["days", 2, 1], ["war", "GER", "BEL"], ["seize_all", "BEL", "GER"], ["days", 3, 1], ["days", 3, 1]]},
	]
	var result := []
	for camp in campaigns:
		gs.player_tag = ""
		gs.load_scenario(peace_dir)
		gs.ai_enabled = false
		gs.set_player(camp.player)
		Eco.recompute(gs)
		var log := []
		var snaps := [_snapshot()]
		for act in camp.actions:
			_play(act, log, snaps)
		result.append({"name": camp.name, "player": camp.player, "log": log, "snaps": snaps})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _day() -> void:
	gs.in_day_step = true
	Eco.step_day(gs)
	NavyCls.step_day(gs)
	Mil.step_day(gs)
	gs.in_day_step = false
	if gs.economy_dirty:
		gs.economy_dirty = false
		gs.budget_dirty = false
		Eco.recompute(gs)
	elif gs.budget_dirty:
		gs.budget_dirty = false
		Eco.refresh_now(gs)
	clock.days_elapsed += 1


func _nth(ids: Array, k: int) -> int:
	if k < 0:
		k = ids.size() + k
	return ids[k] if k >= 0 and k < ids.size() else 9999


func _army_ids(tag: String) -> Array:
	var out := []
	for a in Mil.armies_of(gs, tag):
		out.append(a.id)
	return out


func _play(act: Array, log: Array, snaps: Array) -> void:
	match act[0]:
		"war":
			gs.set_war(act[1], act[2], true, "none", 0, {})
			log.append(act)
		"raise":
			var province: int = act[2]
			if province == 0:
				province = gs.nations[act[1]].capital
			elif province == 1:
				province = _other_province(act[1])
			var cmd: GDScript = load("res://scripts/sim/raise_units.gd")
			var ok: bool = cmd.new(act[1], province, act[3], act[4]).execute(gs)
			log.append(["raise", act[1], province, act[3], act[4], ok])
		"train":
			var ids: Array[int] = []
			var all := _army_ids(act[1])
			for i in mini(act[3], all.size()):
				ids.append(all[i])
			var cmd: GDScript = load("res://scripts/sim/set_training.gd")
			var ok: bool = cmd.new(act[1], ids, act[2]).execute(gs)
			log.append(["train", act[1], ids, act[2], ok])
		"order_from":
			# the first army standing in the nation's capital (or the other province, with 1) is sent to a neighbouring province
			var here: int = gs.nations[act[1]].capital if act[2] == 0 else _other_province(act[1])
			var moved = null
			for a in Mil.armies_of(gs, act[1]):
				if a.province == here:
					moved = a
					break
			var ok := false
			var target := 0
			if moved != null:
				for n in Mil.neighbors(here):
					if gs.province_owner[n] == act[1]:
						target = n
						break
				var cmd: GDScript = load("res://scripts/sim/move_army.gd")
				ok = cmd.new(act[1], moved.id, target).execute(gs)
			log.append(["order", act[1], moved.id if moved != null else 0, target, ok])
		"train_foreign":
			var ids: Array[int] = []
			ids.append(_army_ids(act[2])[0])
			var cmd: GDScript = load("res://scripts/sim/set_training.gd")
			var ok: bool = cmd.new(act[1], ids, true).execute(gs)
			log.append(["train", act[1], ids, true, ok])
		"seize_capital":
			var cap: int = gs.nations[act[1]].capital
			gs.set_controller(cap, act[2])
			Eco.recompute(gs)
			log.append(["seize_all", act[1], act[2], [cap]])
		"demob":
			var cmd: GDScript = load("res://scripts/sim/demobilize_units.gd")
			var id := 0
			if act[2] == 1:
				id = _army_ids(act[1])[0]
			var ok: bool = cmd.new(act[1], id, act[3]).execute(gs)
			log.append(["demob", act[1], id, act[3], ok])
		"split":
			var ids := _army_ids(act[1])
			var id: int = _nth(ids, act[2])
			var idx: Array[int] = []
			idx.assign(act[3])
			var cmd: GDScript = load("res://scripts/sim/split_army.gd")
			var c = cmd.new(act[1], id, idx)
			var ok: bool = c.execute(gs)
			log.append(["split", act[1], id, act[3], ok, c.new_army_id])
		"merge":
			var ids := _army_ids(act[1])
			var picked: Array[int] = []
			for i in act[2]:
				picked.append(_nth(ids, i))
			var cmd: GDScript = load("res://scripts/sim/merge_armies.gd")
			var ok: bool = cmd.new(act[1], picked).execute(gs)
			log.append(["merge", act[1], picked, ok])
		"transfer":
			var ids := _army_ids(act[1])
			var idx: Array[int] = []
			idx.assign(act[3])
			var cmd: GDScript = load("res://scripts/sim/transfer_units.gd")
			var from: int = _nth(ids, act[2])
			var to: int = _nth(ids, act[4])
			var ok: bool = cmd.new(act[1], from, idx, to).execute(gs)
			log.append(["transfer", act[1], from, act[3], to, ok])
		"assign":
			var gens := []
			for g in gs.generals.values():
				if g.tag == act[1]:
					gens.append(g.id)
			var ids := _army_ids(act[1])
			var gid: int = _nth(gens, act[2])
			var aid := 0
			if act[3] != 0:
				aid = _nth(ids, act[3] - 1 if act[3] > 0 else act[3])
			var cmd: GDScript = load("res://scripts/sim/assign_general.gd")
			var ok: bool = cmd.new(act[1], gid, aid).execute(gs)
			log.append(["assign", act[1], gid, aid, ok])
		"wipe":
			# the nation's first army is destroyed (its general is freed on the next day)
			var ids := _army_ids(act[1])
			var gone := _nth(ids, act[2])
			gs.armies.erase(gone)
			log.append(["wipe", act[1], gone])
		"seize_all":
			var list := Array(gs.nations[act[1]].provinces).duplicate()
			for id in list:
				gs.set_controller(id, act[2])
			Eco.recompute(gs)
			log.append(["seize_all", act[1], act[2], list])
		"days":
			for i in act[1]:
				_day()
				var shot: bool = i % act[2] == act[2] - 1 or i == act[1] - 1
				log.append(["day", shot])
				if shot:
					snaps.append(_snapshot())
			return
	snaps.append(_snapshot())
	log.append(["shot"])


func _other_province(tag: String) -> int:
	var cap: int = gs.nations[tag].capital
	for id in gs.nations[tag].provinces:
		if id != cap:
			return id
	return cap


func _snapshot() -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		var rec := []
		for r in n.recruiting:
			rec.append([r.type, r.province, r.days_left])
		nations.append([B(n.treasury), n.manpower, n.men_in_units, n.men_exercising, rec, B(n.budget.net)])
	var armies := []
	for a in gs.armies.values():
		var units := []
		for u in a.units:
			units.append([u.type, B(u.strength), B(u.morale), B(u.experience)])
		armies.append([a.id, a.tag, a.display_name, a.province, a.general_id, B(a.general_skill), units, a.path.size(), a.still_days, a.training, a.attacking])
	var generals := []
	for g in gs.generals.values():
		generals.append([g.id, g.tag, g.army_id, B(g.skill)])
	return {"day": clock.days_elapsed, "nations": nations, "armies": armies, "generals": generals, "counters": [gs.next_army_id, gs.next_general_id]}


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
