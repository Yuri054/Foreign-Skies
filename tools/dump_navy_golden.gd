extends SceneTree
## Writes what the GDScript navy does, for the Rust port (rust/fs_sim) to reproduce: fleets sailing through sea zones, meeting
## and fighting (hits, sinkings, routs and retreats), repaired in port and worn down at sea, ships being built, armies embarked
## and landed from the sea, and the grip on the sea that blockades a nation's trade. The days run in the game's own order
## (economy, navy, army). After each action or few days the fleets, who holds each zone, the battles, the blockade, the armies and
## the wars' losses are written down. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_navy_golden.gd -- rust/fs_sim/tests/golden/navy.json

var gs: Node
var clock: Node
var Eco: GDScript
var Mil: GDScript
var NavyCls: GDScript
var Map: Node


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
	Map = root.get_node("MapData")
	Eco = load("res://scripts/sim/economy.gd")
	Mil = load("res://scripts/sim/military.gd")
	NavyCls = load("res://scripts/sim/navy.gd")
	var peace_dir := _make_peace_copy("july_1914")
	var campaigns := [
		{"name": "north_sea", "player": "POR", "actions": [
			["war", "GBR", "GER"],
			["move_zone_of", "GBR", "Grand Fleet", 394], ["move_zone_of", "GBR", "Battle Cruiser Fleet", 394], ["days", 14, 2],
			["move_zone_of", "GER", "High Seas Fleet", 394], ["days", 20, 1], ["move_zone_of", "GBR", "Channel Fleet", 394], ["days", 30, 3],
			["move_port", "GER", "High Seas Fleet", 394], ["days", 20, 5], ["move_port", "GBR", "Grand Fleet", 330], ["days", 40, 5]]},
		{"name": "adriatic", "player": "POR", "actions": [
			["war", "ITA", "AUH"], ["war", "FRA", "AUH"],
			["move_zone_of", "ITA", "Squadra di Taranto", 442], ["move_zone_of", "AUH", "k.u.k. Kriegsmarine", 442], ["days", 25, 1],
			["move_zone_of", "FRA", "Armee Navale", 442], ["days", 30, 2], ["move_port", "ITA", "Squadra di Taranto", 501], ["days", 20, 4]]},
		{"name": "blockade", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["war", "FRA", "GER"],
			["move_zone_of", "GBR", "Grand Fleet", 394], ["move_zone_of", "GBR", "Channel Fleet", 302], ["move_zone_of", "FRA", "Armee Navale", 302],
			["days", 60, 5], ["move_zone_of", "GBR", "Western Squadron", 536], ["days", 60, 6], ["peace", "GBR", "GER"], ["days", 40, 8]]},
		{"name": "landing", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["gather", "GBR", "Channel Fleet"],
			["send", "GBR", "Channel Fleet", 394], ["days", 30, 1], ["days", 30, 5]]},
		{"name": "landing_friendly", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["war", "GER", "BEL"], ["gather", "GBR", "Channel Fleet"],
			["send", "GBR", "Channel Fleet", 89], ["days", 20, 1], ["days", 20, 5]]},
		{"name": "embark_by_hand", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["gather", "GBR", "Channel Fleet"], ["embark", "GBR", "Channel Fleet"], ["embark", "GBR", "Channel Fleet"],
			["disembark", "GBR", "Channel Fleet", 294], ["embark", "GBR", "Channel Fleet"], ["move_zone_of", "GBR", "Channel Fleet", 302],
			["days", 3, 1], ["disembark", "GBR", "Channel Fleet", 302], ["days", 12, 3], ["disembark", "GBR", "Channel Fleet", 302], ["days", 10, 5],
			["disembark", "GBR", "Channel Fleet", 394], ["days", 10, 5]]},
		{"name": "convoy_sunk", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["gather", "GBR", "Channel Fleet"], ["send", "GBR", "Channel Fleet", 394],
			["move_zone_of", "GER", "High Seas Fleet", 394], ["days", 25, 1], ["days", 30, 5]]},
		{"name": "building", "player": "POR", "actions": [
			["raise", "GBR", 330, "destroyer", 2], ["raise", "GBR", 330, "dreadnought", 1], ["raise", "GBR", 289, "cruiser", 1], ["raise", "GBR", 1, "destroyer", 1],
			["raise", "GER", 394, "submarine", 3], ["raise", "GBR", 330, "destroyer", 9], ["days", 120, 20], ["days", 160, 20], ["days", 100, 20]]},
		{"name": "slugfest", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["weaken", "GER", "High Seas Fleet", 0, 0.07], ["weaken", "GER", "High Seas Fleet", 1, 0.2], ["weaken", "GER", "High Seas Fleet", 8, 0.06],
			["move_zone_of", "GBR", "Grand Fleet", 394], ["move_zone_of", "GER", "High Seas Fleet", 394], ["days", 30, 1], ["move_zone_of", "GBR", "Battle Cruiser Fleet", 394],
			["days", 30, 2]]},
		{"name": "convoy_drowned", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["gather", "GBR", "Channel Fleet"], ["weaken", "GBR", "Channel Fleet", 4, 0.049], ["weaken", "GBR", "Channel Fleet", 5, 0.049],
			["send", "GBR", "Channel Fleet", 394], ["move_zone_of", "GER", "High Seas Fleet", 394], ["days", 6, 1], ["weaken", "GBR", "Channel Fleet", 6, 0.049], ["days", 30, 2]]},
		{"name": "launch", "player": "POR", "actions": [
			["raise", "GBR", 330, "destroyer", 2], ["raise", "GBR", 289, "cruiser", 1], ["raise", "GER", 394, "submarine", 1], ["days", 20, 5], ["rush", "GBR", 0.00001],
			["days", 3, 1], ["raise", "GBR", 330, "destroyer", 1], ["rush", "GBR", 0.0], ["rush", "GER", 0.0], ["days", 2, 1], ["days", 6, 3]]},
		{"name": "yard", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["spawn", "GBR", 330, "Tender", "destroyer", 1, 1.0], ["raise", "GBR", 330, "destroyer", 1], ["rush", "GBR", 0.0], ["days", 2, 1],
			["move_zone_of", "GBR", "Tender", 394], ["days", 2, 1], ["raise", "GBR", 330, "cruiser", 1], ["raise", "GBR", 330, "destroyer", 1], ["rush", "GBR", 0.0], ["days", 2, 1],
			["weaken", "GBR", "Grand Fleet", 0, 0.5], ["raise", "GBR", 330, "destroyer", 1], ["control", 330, "GER"], ["rush", "GBR", 0.0], ["days", 6, 1],
			["control", 330, "GBR"], ["days", 4, 1]]},
		{"name": "subs", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["spawn", "GBR", 330, "Submarines", "submarine", 3, 1.0], ["spawn", "GER", 394, "U-boats", "submarine", 3, 1.0],
			["spawn", "GBR", 289, "Lone", "destroyer", 1, 0.06], ["move_zone_of", "GBR", "Submarines", 394], ["move_zone_of", "GER", "U-boats", 394],
			["move_zone_of", "GBR", "Lone", 394], ["move_zone_of", "GER", "High Seas Fleet", 394], ["days", 40, 1], ["days", 20, 4]]},
		{"name": "convoy_hit", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["gather", "GBR", "Channel Fleet"], ["move_zone", "GER", "High Seas Fleet", 5], ["days", 8, 4],
			["weaken", "GBR", "Channel Fleet", 4, 0.06], ["weaken", "GBR", "Channel Fleet", 5, 0.06], ["weaken", "GBR", "Channel Fleet", 6, 0.06],
			["send", "GBR", "Channel Fleet", 394], ["days", 20, 1], ["days", 20, 4]]},
		{"name": "embark_limits", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["gather", "GBR", "Grand Fleet"], ["embark", "GBR", "Grand Fleet"], ["send", "GBR", "Grand Fleet", 394],
			["gather", "GBR", "Channel Fleet"], ["order", "GBR", 1, 289, true], ["embark", "GBR", "Channel Fleet"], ["days", 3, 1], ["order", "GBR", 1, 294, true], ["days", 40, 8],
			["embark", "GBR", "Channel Fleet"]]},
		{"name": "landing_held", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["control", 394, "GBR"], ["gather", "GBR", "Channel Fleet"], ["send", "GBR", "Channel Fleet", 394], ["days", 20, 2], ["days", 20, 5]]},
		{"name": "pinned", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["move_zone_of", "GBR", "Grand Fleet", 394], ["pin", "GER", 0.5], ["days", 8, 2], ["pin", "GER", -1.0], ["days", 16, 4], ["pin", "GBR", 0.3], ["days", 4, 2]]},
		{"name": "outlets", "player": "POR", "actions": [
			["war", "GBR", "GER"], ["move_zone", "GBR", "Grand Fleet", 1], ["move_zone", "GBR", "Battle Cruiser Fleet", 2], ["move_zone", "GBR", "Western Squadron", 17],
			["move_zone", "GBR", "Channel Fleet", 22], ["days", 40, 4], ["move_zone_of", "GBR", "Grand Fleet", 394], ["days", 40, 4], ["move_zone", "GBR", "Battle Cruiser Fleet", 34],
			["days", 60, 6]]},
		{"name": "orders", "player": "GBR", "actions": [
			["move_zone_of", "GBR", "Grand Fleet", 330], ["move_zone_of", "GBR", "Grand Fleet", 394], ["days", 3, 1], ["move_zone_of", "GBR", "Grand Fleet", 394],
			["move_port", "GBR", "Grand Fleet", 394], ["move_zone_of", "GBR", "Grand Fleet", 394], ["days", 6, 1], ["mission", "GBR", "Grand Fleet", "support"],
			["mission", "GBR", "Grand Fleet", "nonsense"], ["move_port", "GBR", "Grand Fleet", 330], ["days", 20, 2]]},
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


func _fleet(tag: String, name: String) -> Object:
	for f in gs.fleets.values():
		if f.tag == tag and f.display_name == name:
			return f
	return null


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


func _play(act: Array, log: Array, snaps: Array) -> void:
	match act[0]:
		"war":
			gs.set_war(act[1], act[2], true, "none", 0, {})
			log.append(act)
		"peace":
			gs.set_war(act[1], act[2], false)
			log.append(act)
		"move_zone_of", "move_port":
			var f = _fleet(act[1], act[2])
			var zone := 0
			var port := 0
			if act[0] == "move_zone_of":
				zone = Map.zones_of_port(act[3])[0]
			else:
				port = act[3]
			var cmd: GDScript = load("res://scripts/sim/move_fleet.gd")
			var ok: bool = cmd.new(act[1], f.id, zone, port).execute(gs)
			log.append(["move", act[1], f.id, zone, port, ok])
		"mission":
			var f = _fleet(act[1], act[2])
			var cmd: GDScript = load("res://scripts/sim/set_fleet_mission.gd")
			var ok: bool = cmd.new(act[1], f.id, act[3]).execute(gs)
			log.append(["mission", act[1], f.id, act[3], ok])
		"raise":
			var cmd: GDScript = load("res://scripts/sim/raise_ships.gd")
			var ok: bool = cmd.new(act[1], act[2], act[3], act[4]).execute(gs)
			log.append(["raise", act[1], act[2], act[3], act[4], ok])
		"gather":
			# the nearest army that can walk to the fleet's port (the lowest army id of the nation), then the days it takes
			var f = _fleet(act[1], act[2])
			var chosen = null
			for a in Mil.armies_of(gs, act[1]):
				if chosen == null or a.id < chosen.id:
					chosen = a
			var cmd: GDScript = load("res://scripts/sim/move_army.gd")
			var ok: bool = cmd.new(act[1], chosen.id, f.port).execute(gs)
			log.append(["order", act[1], chosen.id, f.port, ok])
			var days := 0
			while days < 80 and not (chosen.province == f.port and chosen.path.is_empty()):
				_day()
				log.append(["day", false])
				days += 1
			snaps.append(_snapshot())
			log.append(["shot"])
			return
		"embark":
			var f = _fleet(act[1], act[2])
			var cmd: GDScript = load("res://scripts/sim/embark_army.gd")
			var chosen = null
			for a in Mil.armies_of(gs, act[1]):
				if not a.embarked() and a.province == f.port and (chosen == null or a.id < chosen.id):
					chosen = a
			if chosen == null:
				log.append(["embark", act[1], 0, f.id, false])
			else:
				var ok: bool = cmd.new(act[1], chosen.id, f.id).execute(gs)
				log.append(["embark", act[1], chosen.id, f.id, ok])
		"send":
			var f = _fleet(act[1], act[2])
			var aboard := []
			var pick = null
			for a in Mil.armies_of(gs, act[1]):
				if not a.embarked() and a.province == f.port and (pick == null or a.id < pick.id):
					pick = a
			if pick != null:
				aboard.append(pick.id)
			var cmd: GDScript = load("res://scripts/sim/send_overseas.gd")
			var ids: Array[int] = []
			ids.assign(aboard)
			var ok: bool = cmd.new(act[1], f.id, ids, act[3]).execute(gs)
			log.append(["send", act[1], f.id, ids, act[3], ok])
		"spawn":
			var nf = NavyCls.new_fleet(gs, act[1], act[3], act[2])
			var sh: GDScript = load("res://scripts/sim/ship.gd")
			for i in act[5]:
				nf.ships.append(sh.new(act[4], act[6]))
			log.append(["spawn", act[1], act[2], act[3], act[4], act[5], act[6]])
		"move_zone":
			var f = _fleet(act[1], act[2])
			var cmd: GDScript = load("res://scripts/sim/move_fleet.gd")
			var ok: bool = cmd.new(act[1], f.id, act[3], 0).execute(gs)
			log.append(["move", act[1], f.id, act[3], 0, ok])
		"control":
			gs.set_controller(act[1], act[2])
			Eco.recompute(gs)
			log.append(["control", act[1], act[2]])
		"pin":
			gs.nations[act[1]].blockade_pinned = act[2]
			log.append(["pin", act[1], act[2]])
		"weaken":
			var f = _fleet(act[1], act[2])
			f.ships[act[3]].strength = act[4]
			log.append(["weaken", act[1], f.id, act[3], act[4]])
		"rush":
			for j in gs.nations[act[1]].shipbuilding:
				j.points_left = act[2]
			log.append(act)
		"disembark":
			var f = _fleet(act[1], act[2])
			var cmd: GDScript = load("res://scripts/sim/disembark_army.gd")
			var id := 0
			for a in gs.armies.values():
				if a.fleet_id == f.id:
					id = a.id
			var ok: bool = cmd.new(act[1], id, act[3]).execute(gs)
			log.append(["disembark", act[1], id, act[3], ok])
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


func _ship(s) -> Array:
	return [s.type, B(s.strength), B(s.morale)]


func _battle(b: Dictionary) -> Array:
	var sunk := {}
	for k in b.sunk:
		sunk[k] = b.sunk[k]
	var ships := {}
	for k in b.start_ships:
		ships[k] = b.start_ships[k]
	return [b.id, b.zone, b.start_day, b.days, b.fleets.keys(), ships, _bits_map(b.lost), sunk, b.winner, b.active]


func _snapshot() -> Dictionary:
	var fleets := []
	for f in gs.fleets.values():
		var ships := []
		for s in f.ships:
			ships.append(_ship(s))
		fleets.append([f.id, f.tag, f.display_name, f.zone, f.port, Array(f.path).duplicate(), f.dest_port, B(f.move_days_left), f.entering, f.landing,
				f.mission, f.fighting, f.engaged, f.retreating, f.days_out, ships])
	var control := []
	for z in gs.sea_control:
		var c: Dictionary = gs.sea_control[z]
		control.append([z, Array(c.holders).duplicate(), c.contested, _bits_map(c.power)])
	var battles := []
	for z in gs.sea_battles:
		battles.append(_battle(gs.sea_battles[z]))
	var archive := []
	for id in gs.sea_battle_archive:
		archive.append(_battle(gs.sea_battle_archive[id]))
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		nations.append([B(n.blockade), B(n.blockade_target), B(n.blockade_applied), Array(n.blockade_by).duplicate(), n.ships_lost, n.shipbuilding.size(),
				B(n.treasury), B(n.budget.net), B(n.men_lost_month), B(n.deaths_month), n.manpower])
	var armies := []
	for a in gs.armies.values():
		armies.append([a.id, a.tag, a.province, a.fleet_id, a.path.size(), a.landing_days, a.landed_supply, a.attacking, a.fighting, a.supplied, B(a.men())])
	var wars := []
	for w in gs.wars.values():
		wars.append([w.a, w.b, w.last_fight_day, _bits_map(w.losses)])
	return {"day": clock.days_elapsed, "fleets": fleets, "control": control, "battles": battles, "archive": archive, "nations": nations,
			"armies": armies, "wars": wars, "counters": [gs.next_fleet_id, gs.next_battle_id, gs.budget_dirty], "econ": gs.economy_dirty}


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
