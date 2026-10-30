extends SceneTree
## A long soak test: the whole game run for years with the AI playing every nation and random
## commands (valid and not) thrown at it, checking the state's invariants every month, saving
## and loading in the middle and counting the script errors. Prints "VIOLATION ..." lines.
## Run: godot --headless --path . -s res://tools/soak.gd -- seed player years
## (then look for VIOLATION and SCRIPT ERROR in the output).

var gs: Node
var clock: Node
var rng := RandomNumberGenerator.new()
var violations := 0
var seen := {}


var _classes := {}


func _k(file: String):
	if not _classes.has(file):
		_classes[file] = load("res://scripts/sim/%s.gd" % file)
	return _classes[file]


func _bad(msg: String) -> void:
	# One line for each kind of problem, and a count.
	var key := msg.substr(0, 60)
	violations += 1
	if seen.has(key):
		seen[key] += 1
		return
	seen[key] = 1
	print("VIOLATION day %d: %s" % [clock.days_elapsed, msg])


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 1
	var player: String = args[1] if args.size() > 1 else "ESP"
	var years := int(args[2]) if args.size() > 2 else 3
	rng.seed = seed_value
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player(player)
	gs.ai_enabled = true
	var started := Time.get_ticks_msec()
	for day in years * 365:
		_fuzz()
		clock.advance_day()
		if day % 30 == 0:
			_check_state()
		if day == 400 or day == 900:
			_check_save_load()
	print("SOAK seed %d player %s: %d days, %d violations (%d kinds), %.0f ms a day" % [seed_value, player, years * 365, violations, seen.size(), float(Time.get_ticks_msec() - started) / (years * 365)])
	print("AI declarations: %s, wars begun %d" % [str(gs.ai_declarations), gs.wars.size()])
	quit(0)


# ---------------------------------------------------------------------------- invariants

func _finite(v: Variant) -> bool:
	if v is float:
		return is_finite(v)
	return true


func _check_state() -> void:
	var count: int = gs.province_owner.size()
	for tag in gs.nations:
		var n = gs.nations[tag]
		if not (is_finite(n.treasury) and n.treasury > -5000.0):
			_bad("%s treasury %s" % [tag, str(n.treasury)])
		if n.war_support < -0.01 or n.war_support > 100.01 or not is_finite(n.war_support):
			_bad("%s war support %s" % [tag, str(n.war_support)])
		if n.manpower < 0:
			_bad("%s manpower %d" % [tag, n.manpower])
		if n.weariness < 0.0 or n.weariness > 1.0 or not is_finite(n.weariness):
			_bad("%s weariness %s" % [tag, str(n.weariness)])
		for k in n.budget:
			if n.budget[k] is float and not is_finite(n.budget[k]):
				_bad("%s budget %s = %s" % [tag, k, str(n.budget[k])])
		for id in n.provinces:
			if id < 1 or id >= count or gs.province_owner[id] != tag:
				_bad("%s lists province %d it does not own" % [tag, id])
				break
		for job in n.construction:
			if gs.province_owner[job.province] != tag:
				_bad("%s builds in foreign province %d" % [tag, job.province])
			if job.points_left < -0.001 or job.points_left > job.points_total + 0.001:
				_bad("%s job points %s of %s" % [tag, str(job.points_left), str(job.points_total)])
	for id in gs.armies:
		var a = gs.armies[id]
		if not gs.nations.has(a.tag):
			_bad("army %d of unknown nation %s" % [id, a.tag])
			continue
		if a.units.is_empty():
			_bad("empty army %d (%s)" % [id, a.tag])
		if a.province < 1 or a.province >= count:
			_bad("army %d in province %d" % [id, a.province])
		for u in a.units:
			if not (is_finite(u.strength) and u.strength > 0.0 and u.strength <= 1.0001):
				_bad("unit strength %s in army %d" % [str(u.strength), id])
			if not (is_finite(u.morale) and u.morale >= -0.001 and u.morale <= 1.0001):
				_bad("unit morale %s in army %d" % [str(u.morale), id])
			for cat in u.equip:
				if not (is_finite(u.equip[cat]) and u.equip[cat] >= -0.001):
					_bad("unit equip %s = %s" % [cat, str(u.equip[cat])])
	for tag in gs.nations:
		for other in gs.nations:
			if gs.at_war(tag, other) != gs.at_war(other, tag):
				_bad("war between %s and %s is not symmetric" % [tag, other])
	for fid in gs.fleets:
		var f = gs.fleets[fid]
		if f.ships.is_empty():
			_bad("empty fleet %d (%s)" % [fid, f.tag])


func _state_hash() -> int:
	var h := 17
	for tag in gs.nations:
		var n = gs.nations[tag]
		h = hash([h, tag, snappedf(n.treasury, 0.001), n.manpower, n.provinces.size(), n.construction.size(), snappedf(n.war_support, 0.001)])
	for id in range(1, gs.province_owner.size()):
		h = hash([h, gs.province_owner[id], gs.province_controller[id]])
	var ids: Array = gs.armies.keys()
	ids.sort()
	for id in ids:
		h = hash([h, id, gs.armies[id].tag, gs.armies[id].province, gs.armies[id].units.size()])
	return h


func _check_save_load() -> void:
	var SaveGame = load("res://scripts/sim/save_game.gd")
	SaveGame.dir = "user://soak_saves_%d/" % rng.seed
	var path: String = SaveGame.dir + "soak.sav"
	var before := _state_hash()
	var day: int = clock.days_elapsed
	var player: String = gs.player_tag
	var err: String = gs.save_game(path)
	if err != "":
		_bad("save failed: " + err)
		return
	err = gs.load_game(path)
	if err != "":
		_bad("load failed: " + err)
		return
	gs.ai_enabled = true
	if clock.days_elapsed != day or gs.player_tag != player:
		_bad("load changed the day (%d to %d) or the player" % [day, clock.days_elapsed])
	if _state_hash() != before:
		_bad("a save and load changed the state")
	DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------- fuzz

func _tag() -> String:
	var tags: Array = gs.nations.keys()
	return tags[rng.randi() % tags.size()] if rng.randf() > 0.03 else "XXX"


func _province(tag := "") -> int:
	if tag != "" and gs.nations.has(tag) and rng.randf() < 0.85 and not gs.nations[tag].provinces.is_empty():
		var list: Array = gs.nations[tag].provinces
		return list[rng.randi() % list.size()]
	return rng.randi_range(-2, gs.province_owner.size() + 2)


func _army_id(tag: String) -> int:
	var mine: Array = []
	for a in gs.armies.values():
		if a.tag == tag:
			mine.append(a.id)
	if mine.is_empty() or rng.randf() < 0.1:
		return rng.randi_range(-1, 400)
	return mine[rng.randi() % mine.size()]


func _fuzz() -> void:
	var count := rng.randi_range(0, 4)
	for i in count:
		var tag := _tag()
		var cmd = null
		match rng.randi() % 10:
			0:
				var types := ["civilian_factory", "construction_sector", "port", "railway", "trench", "fortification", "bogus"]
				cmd = _k("construct_building").new(tag, _province(tag), types[rng.randi() % types.size()])
			1:
				var types2 := ["civilian_factory", "trench", "fortification", "railway"]
				cmd = _k("mass_construct_building").new(tag, types2[rng.randi() % types2.size()], rng.randi_range(0, 30), rng.randf_range(0.0, 600.0))
			2:
				cmd = _k("move_army").new(tag, _army_id(tag), _province(tag) if rng.randf() < 0.5 else _province())
			3:
				var kinds := ["infantry", "cavalry", "artillery", "bogus"]
				cmd = _k("raise_units").new(tag, _province(tag), kinds[rng.randi() % kinds.size()], rng.randi_range(0, 4))
			4:
				var pol := ["standing_army", "mobilization", "bogus"]
				cmd = _k("set_economy_policy").new(tag, pol[rng.randi() % pol.size()], rng.randf_range(-0.2, 1.4))
			5:
				cmd = _k("declare_war").new(tag, _tag())
			6:
				cmd = _k("propose_peace").new(tag, _tag(), "demand" if rng.randf() < 0.5 else "offer", [])
			7:
				cmd = _k("split_army").new(tag, _army_id(tag), [0] as Array[int])
			8:
				cmd = _k("buy_points").new(tag)
			9:
				if rng.randf() < 0.5:
					cmd = _k("gift").new(tag, _tag(), rng.randf_range(-5.0, 20.0))
				else:
					var ids: Array[int] = [_army_id(tag), _army_id(tag)]
					cmd = _k("merge_armies").new(tag, ids)
		if cmd != null:
			gs.issue(cmd)
