extends SceneTree
## Writes what the GDScript army groups and attack lines do, for the Rust port (rust/fs_sim) to reproduce: armies on a front given a plan (a broad push, a spearhead, an invasion), planning built up
## and spent, the attack launched and sent in at the odds the plan asks, phases taken one after another, and, as in the front test, the AI's armies each sent to hold a province, the player's
## divisions spread along the line as detachments of their army (reach by cohesion, pinned by hand orders, merging back), a line
## that follows the war as ground changes hands, and a fallback line in the nation's own ground. The days run in the game's order
## (economy, navy, army). Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_group_golden.gd -- rust/fs_sim/tests/golden/group.json

var gs: Node
var clock: Node
var Eco: GDScript
var Mil: GDScript
var NavyCls: GDScript
var created := {}
var Map: Node


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	Map = root.get_node("MapData")
	Eco = load("res://scripts/sim/economy.gd")
	Mil = load("res://scripts/sim/military.gd")
	NavyCls = load("res://scripts/sim/navy.gd")
	var peace_dir := _make_peace_copy("july_1914")
	var campaigns := [
		{"name": "groups", "player": "GBR", "actions": [
			["group", "GBR", "Home", 3], ["group", "GBR", "", 2], ["group", "GBR", "Bad", 0], ["free_general", "GBR", 1], ["free_general", "GBR", 2], ["marshal", "GBR", 1, 0], ["marshal", "GBR", 1, 1], ["marshal", "GBR", 1, 2], ["marshal", "GBR", 2, 1],
			["marshal", "GBR", 1, -1], ["days", 3, 1], ["marshal", "GBR", 1, 3], ["assign_group", "GBR", 2, 1], ["assign_group", "GBR", 1, 2], ["assign_group", "GBR", 0, 2],
			["assign_group", "FRA", 1, 1], ["wipe_id", "GBR", 1], ["days", 3, 1], ["disband", "GBR", 1], ["disband", "GBR", 2], ["days", 2, 1]]},
		{"name": "ai_groups", "player": "POR", "actions": [
			["group", "GER", "Corps", 4], ["free_general", "GER", 1], ["free_general", "GER", 3], ["marshal", "GER", 1, 1], ["marshal", "GER", 1, 3], ["days", 5, 1], ["stack", "GER", 3], ["front", "GER", "", "FRA", "line", 0], ["war", "GER", "FRA"],
			["assign", "GER", 1, 2], ["days", 20, 5]]},
		{"name": "attack_lines", "player": "GER", "actions": [
			["group", "GER", "Army", 3], ["alcreate", "GER", 1, "FRA", 0], ["alset", "GER", 1, true], ["war", "GER", "FRA"], ["front", "GER", "", "FRA", "line", 0],
			["alcreate", "GER", 1, "FRA", 0], ["alcreate", "GER", 9, "FRA", 0], ["alcreate", "GER", 1, "GER", 0], ["alcreate", "GER", 1, "FRA", 77], ["alset", "GER", 1, false],
			["peace_fra"], ["days", 3, 1], ["aldelete", "GER", 1], ["aldelete", "GER", 1]]},
	]
	var result := []
	for camp in campaigns:
		gs.player_tag = ""
		gs.load_scenario(peace_dir)
		gs.ai_enabled = false
		gs.pressure_ai = false
		gs.set_player(camp.player)
		Eco.recompute(gs)
		created = {}
		gs.control_version = 0
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


func _front_ids() -> Array:
	return gs.fronts.keys()


func _play(act: Array, log: Array, snaps: Array) -> void:
	match act[0]:
		"war":
			gs.set_war(act[1], act[2], true, "none", 0, {})
			log.append(act)
		"front":
			var cmd: GDScript = load("res://scripts/sim/designate_front.gd")
			var anchor := 0
			var against: String = act[3]
			if act[5] == 1:
				var border: Array = Mil.border_provinces(gs, act[1], against)
				anchor = border[border.size() / 2] if not border.is_empty() else 0
			var typed: Array[int] = []
			var c = cmd.new(act[1], act[2], typed, against, act[4], anchor)
			var ok: bool = c.execute(gs)
			log.append(["front", act[1], act[2], [], against, act[4], anchor, ok, c.front_id])
		"chain", "garrison":
			var cmd: GDScript = load("res://scripts/sim/designate_front.gd")
			var own: Array = Array(gs.nations[act[1]].provinces)
			var line: Array[int] = []
			var kind := "garrison"
			if act[0] == "chain":
				kind = act[4]
				var at: int = own[act[2]]
				line.append(at)
				while line.size() < act[3]:
					var next := 0
					for n in Mil.neighbors(line[-1]):
						if gs.province_owner[n] == act[1] and not line.has(n):
							next = n
							break
					if next == 0:
						break
					line.append(next)
			else:
				for i in act[2]:
					line.append(own[i])
			var c = cmd.new(act[1], "", line, "", kind, 0)
			var ok: bool = c.execute(gs)
			log.append(["front", act[1], "", line, "", kind, 0, ok, c.front_id])
		"bad_chain":
			var cmd: GDScript = load("res://scripts/sim/designate_front.gd")
			var own: Array = Array(gs.nations[act[1]].provinces)
			var line: Array[int] = [own[0], own[act[2]]]
			var c = cmd.new(act[1], "", line, "", "line", 0)
			var ok: bool = c.execute(gs)
			log.append(["front", act[1], "", line, "", "line", 0, ok, c.front_id])
		"setline":
			var ids_f: Array = _front_ids()
			var fid: int = ids_f[act[2] - 1]
			var own: Array = Array(gs.nations[act[1]].provinces)
			var line: Array[int] = [own[act[3]]]
			while line.size() < act[4]:
				var next := 0
				for n in Mil.neighbors(line[-1]):
					if gs.province_owner[n] == act[1] and not line.has(n):
						next = n
						break
				if next == 0:
					break
				line.append(next)
			var cmd: GDScript = load("res://scripts/sim/set_front_line.gd")
			var ok: bool = cmd.new(act[1], fid, line).execute(gs)
			log.append(["setline", act[1], fid, line, ok])
		"forts":
			var ids_f: Array = _front_ids()
			var f = gs.fronts[ids_f[act[2] - 1]]
			for i in f.provinces.size():
				if i % 2 == 0:
					gs.province_buildings[f.provinces[i]]["fortification"] = act[3]
			log.append(["forts", Array(f.provinces).duplicate(), act[3]])
		"group":
			var list: Array = Mil.armies_of(gs, act[1])
			var ids: Array[int] = []
			for i in mini(act[3], list.size()):
				ids.append(list[i].id)
			var cmd: GDScript = load("res://scripts/sim/create_army_group.gd")
			var c = cmd.new(act[1], act[2], ids)
			var ok: bool = c.execute(gs)
			log.append(["group", act[1], act[2], ids, ok, c.group_id])
		"free_general":
			var gens2 := []
			for g in gs.generals.values():
				if g.tag == act[1]:
					gens2.append(g.id)
			var gid2: int = gens2[act[2]]
			var cmd: GDScript = load("res://scripts/sim/assign_general.gd")
			var ok: bool = cmd.new(act[1], gid2, 0).execute(gs)
			log.append(["free_general", act[1], gid2, ok])
		"marshal":
			var gens := []
			for g in gs.generals.values():
				if g.tag == act[1]:
					gens.append(g.id)
			var gid := 0
			if act[3] >= 0:
				gid = gens[act[3]] if act[3] < gens.size() else 9999
			var gids: Array = gs.army_groups.keys()
			var grp: int = gids[act[2] - 1] if act[2] - 1 < gids.size() else 9999
			var cmd: GDScript = load("res://scripts/sim/set_marshal.gd")
			var ok: bool = cmd.new(act[1], grp, gid).execute(gs)
			log.append(["marshal", act[1], grp, gid, ok])
		"assign_group":
			var gids: Array = gs.army_groups.keys()
			var grp: int = 0
			if act[2] > 0:
				grp = gids[act[2] - 1] if act[2] - 1 < gids.size() else 9999
			var list: Array = Mil.armies_of(gs, act[1])
			var ids: Array[int] = []
			for i in mini(2, list.size()):
				ids.append(list[list.size() - 1 - i].id)
			var cmd: GDScript = load("res://scripts/sim/assign_to_group.gd")
			var ok: bool = cmd.new(act[1], grp, ids).execute(gs)
			log.append(["assign_group", act[1], grp, ids, ok])
		"disband":
			var gids: Array = gs.army_groups.keys()
			var grp: int = gids[act[2] - 1] if act[2] - 1 < gids.size() else 9999
			var cmd: GDScript = load("res://scripts/sim/disband_army_group.gd")
			var ok: bool = cmd.new(act[1], grp).execute(gs)
			log.append(["disband", act[1], grp, ok])
		"alcreate":
			var gids: Array = gs.army_groups.keys()
			var grp: int = gids[act[2] - 1] if act[2] - 1 < gids.size() else 9999
			var front := 0
			if act[4] == 77:
				front = 77
			var cmd: GDScript = load("res://scripts/sim/create_attack_line.gd")
			var c = cmd.new(act[1], grp, act[3], front)
			var ok: bool = c.execute(gs)
			log.append(["alcreate", act[1], grp, act[3], front, ok, c.line_id])
		"alset":
			var ids_l: Array = gs.attack_lines.keys()
			var lid: int = ids_l[act[2] - 1] if act[2] - 1 < ids_l.size() else 9999
			var cmd: GDScript = load("res://scripts/sim/set_attack_line.gd")
			var ok: bool = cmd.new(act[1], lid, act[3]).execute(gs)
			log.append(["alset", act[1], lid, act[3], ok])
		"aldelete":
			var ids_l: Array = gs.attack_lines.keys()
			var lid: int = ids_l[act[2] - 1] if act[2] - 1 < ids_l.size() else 9999
			var cmd: GDScript = load("res://scripts/sim/delete_attack_line.gd")
			var ok: bool = cmd.new(act[1], lid).execute(gs)
			log.append(["aldelete", act[1], lid, ok])
		"peace_fra":
			gs.set_war("GER", "FRA", false)
			log.append(["peace", "GER", "FRA"])
		"plan":
			var spec: Array = String(act[3]).split(":")
			var line: Array[int] = []
			match spec[0]:
				"border":
					var enemy: String = spec[1]
					var mine: String = act[1]
					for id in Mil.border_provinces(gs, enemy, mine):
						if line.size() < int(spec[2]):
							line.append(id)
				"capital":
					line.append(gs.nations[spec[1]].capital)
				"port":
					for id in gs.nations[spec[1]].provinces:
						if line.is_empty() and not Map.zones_of_port(id).is_empty():
							line.append(id)
			var cmd: GDScript = load("res://scripts/sim/plan_offensive.gd")
			var armies: Array = Mil.armies_of(gs, act[1])
			var army_id: int = armies[0].id if not armies.is_empty() else 9999
			var c = cmd.new(act[1], army_id, act[2], line, act[4], act[5])
			var ok: bool = c.execute(gs)
			log.append(["plan", act[1], army_id, act[2], line, act[4], act[5], ok, c.offensive_id])
		"setoff":
			var oid: int = act[2]
			var value = act[4]
			if typeof(value) == TYPE_STRING and String(value).begins_with("border:"):
				var spec: Array = String(value).split(":")
				var arr := []
				for id in Mil.border_provinces(gs, spec[1], act[1]):
					if arr.size() < int(spec[2]):
						arr.append(id)
				value = arr
			var cmd: GDScript = load("res://scripts/sim/set_offensive.gd")
			var ok: bool = cmd.new(act[1], oid, act[3], value).execute(gs)
			log.append(["setoff", act[1], oid, act[3], value, ok])
		"assign":
			var fid: int = 0
			var ids_f: Array = _front_ids()
			if act[2] > 0:
				fid = ids_f[act[2] - 1] if act[2] - 1 < ids_f.size() else 9999
			var armies: Array[int] = []
			for a in Mil.armies_of(gs, act[1]):
				if a.parent_id == 0 and (act[3] == 0 or armies.size() < act[3]):
					armies.append(a.id)
			var cmd: GDScript = load("res://scripts/sim/assign_to_front.gd")
			var ok: bool = cmd.new(act[1], fid, armies).execute(gs)
			log.append(["assign", act[1], fid, armies, ok])
		"cohesion":
			var ids_f: Array = _front_ids()
			var fid: int = ids_f[act[2] - 1]
			var cmd: GDScript = load("res://scripts/sim/set_front_policy.gd")
			var ok: bool = cmd.new(act[1], fid, "cohesion", act[3]).execute(gs)
			log.append(["cohesion", act[1], fid, act[3], ok])
		"anchors":
			var ids_f: Array = _front_ids()
			var fid: int = ids_f[act[2] - 1]
			var f = gs.fronts[fid]
			var picks: Array[int] = []
			for i in act[3]:
				if i < f.provinces.size():
					picks.append(f.provinces[i])
			var cmd: GDScript = load("res://scripts/sim/set_front_anchors.gd")
			var ok: bool = cmd.new(act[1], fid, picks).execute(gs)
			log.append(["anchors", act[1], fid, picks, ok])
		"delfront":
			var ids_f: Array = _front_ids()
			var fid: int = ids_f[act[2] - 1]
			var cmd: GDScript = load("res://scripts/sim/delete_front.gd")
			var ok: bool = cmd.new(act[1], fid).execute(gs)
			log.append(["delfront", act[1], fid, ok])
		"front_order":
			# a hand order sends the k-th stack of the nation to a province of the enemy's border
			var stacks: Array = Mil.armies_of(gs, act[1])
			var a = stacks[mini(act[3], stacks.size() - 1)]
			var target := 0
			for id in Mil.border_provinces(gs, act[2], act[1]):
				target = id
				break
			var cmd: GDScript = load("res://scripts/sim/move_army.gd")
			var ok: bool = cmd.new(act[1], a.id, target).execute(gs)
			log.append(["order", act[1], a.id, target, ok])
		"seize_border":
			var border: Array = Mil.border_provinces(gs, act[1], act[2])
			var taken := []
			for i in mini(act[3], border.size()):
				gs.set_controller(border[i], act[2])
				taken.append(border[i])
			Eco.recompute(gs)
			log.append(["seize", act[2], taken])
		"stack":
			var list: Array = Mil.armies_of(gs, act[1])
			var first = list[0]
			var n := 0
			for i in range(1, list.size()):
				if act[2] > 0 and n >= act[2] - 1:
					break
				first.units.append_array(list[i].units)
				gs.armies.erase(list[i].id)
				n += 1
			log.append(["stack", act[1], first.id, n])
		"wipe_id":
			var list: Array = Mil.armies_of(gs, act[1])
			var gone = list[act[2]]
			gs.armies.erase(gone.id)
			log.append(["wipe", gone.id])
		"wipe":
			var stacks: Array = Mil.armies_of(gs, act[1])
			var gone = stacks[act[2]]
			gs.armies.erase(gone.id)
			log.append(["wipe", gone.id])
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


func _snapshot() -> Dictionary:
	var fronts := []
	for id in gs.fronts:
		var f = gs.fronts[id]
		var slots := {}
		for k in f.slots:
			slots[str(k)] = f.slots[k]
		var retry := {}
		for k in f.retry:
			retry[str(k)] = f.retry[k]
		var w := []
		for x in f.weights:
			w.append(B(x))
		var dep := Array(f.deploying.keys())
		dep.sort()
		fronts.append([f.id, Array(f.provinces).duplicate(), Array(f.army_ids).duplicate(), slots, Array(f.order).duplicate(), w, f.dirty, retry, dep, f.spread, f.cohesion,
				Array(f.anchors).duplicate(), f.weights_day, f.line_stamp])
	var armies := []
	for a in gs.armies.values():
		armies.append([a.id, a.tag, a.display_name, a.province, a.parent_id, a.front_id, a.pin, a.prepared, a.units.size(), a.path.size(), a.still_days, a.general_id, B(a.men()),
				a.fighting, B(a.move_days_left), a.fleet_id])
	var offs := []
	for id in gs.offensives:
		var o = gs.offensives[id]
		offs.append([o.id, o.tag, o.army_id, o.kind, o.phases.duplicate(true), o.phase, o.aggressiveness, o.port, o.active, o.launched, o.done])
	var planning := []
	for a in gs.armies.values():
		planning.append(B(a.planning))
	var groups := []
	for id in gs.army_groups:
		var g = gs.army_groups[id]
		groups.append([g.id, g.tag, g.display_name, Array(g.army_ids).duplicate(), g.marshal_id])
	var lines := []
	for id in gs.attack_lines:
		var l = gs.attack_lines[id]
		lines.append([l.id, l.tag, l.display_name, l.group_id, l.enemy, l.front_id, l.active, l.wait])
	var gens := []
	for g in gs.generals.values():
		gens.append([g.id, g.army_id, g.group_id])
	var powers := []
	for a in gs.armies.values():
		powers.append([a.group_id, B(a.power())])
	var fleets := []
	for f in gs.fleets.values():
		fleets.append([f.id, f.zone, f.port, f.landing])
	return {"day": clock.days_elapsed, "fronts": fronts, "armies": armies, "counters": [gs.next_front_id, gs.next_army_id, gs.next_offensive_id], "offs": offs, "planning": planning, "fleets": fleets, "groups": groups, "lines": lines, "gens": gens, "powers": powers, "gcounters": [gs.next_group_id, gs.next_attack_line_id]}


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
