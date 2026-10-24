extends SceneTree
## A playthrough of the scenario as the player at the United Kingdom, Germany, Belgium and Italy,
## in the real map scene so that every panel and overlay reacts to a hundred days of play: the
## player builds, raises and moves an army, works on relations and sends a fleet, the AI plays the
## rest. Afterwards the world must still make sense (no NaN, no negative stock, every army and
## fleet somewhere real, every province owned), and the hundred days must stay inside a time
## budget. Prints the scenario load time, memory and the time a day costs.
## Run: godot --headless --path . -s res://tests/playthrough_test.gd

const DAYS := 100
## Seconds a hundred days may take in the real map scene (generous: the guard is for a runaway,
## not for tuning).
const BUDGET_SECONDS := 90.0
const LOAD_BUDGET_SECONDS := 20.0

var _failures := 0
var gs: Node
var Clock: Node
var MapData: Node
var main: Node
var _C := {}


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	Clock = root.get_node("Clock")
	MapData = root.get_node("MapData")
	for pair in [["ConstructBuilding", "construct_building"], ["RaiseUnits", "raise_units"], ["MoveArmy", "move_army"],
			["ImproveRelations", "improve_relations"], ["MoveFleet", "move_fleet"], ["Economy", "economy"], ["Military", "military"]]:
		_C[pair[0]] = load("res://scripts/sim/%s.gd" % pair[1])
	var UiSettings = load("res://scripts/ui/ui_settings.gd")
	UiSettings.path = "user://test_playthrough_settings.cfg"
	load("res://scripts/sim/save_game.gd").dir = "user://test_playthrough_saves/"
	var t := Time.get_ticks_msec()
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var load_s := (Time.get_ticks_msec() - t) / 1000.0
	print("      scenario load: %.2f s, static memory %.0f MB, %d provinces, %d sea zones" % [
			load_s, OS.get_static_memory_usage() / 1048576.0, MapData.provinces.size() - 1, MapData.sea_zones.size() - 1])
	_check(load_s < LOAD_BUDGET_SECONDS, "the scenario loads in under %d s (%.2f s)" % [LOAD_BUDGET_SECONDS, load_s])
	for tag in ["GBR", "GER", "BEL", "ITA"]:
		await _play_as(tag)
	DirAccess.remove_absolute(UiSettings.path)
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _play_as(tag: String) -> void:
	if main != null:
		main.queue_free()
		await process_frame
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player(tag)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	gs.pending_joins.clear()
	var map_view: Sprite2D = main.get_node("MapView")
	var nation = gs.nations[tag]
	var did := PackedStringArray()

	# The player's first moves.
	for id in nation.provinces:
		var done := false
		for type in _C.Economy.building_ids():
			if _C.Economy.build_problem(gs, tag, id, type).is_empty() and gs.issue(_C.ConstructBuilding.new(tag, id, type)):
				did.append("built " + type)
				done = true
				break
		if done:
			break
	var unit_type: String = _C.Military.cfg.unit_types.keys()[0]
	for id in nation.provinces:
		if _C.RaiseUnits.problem(gs, tag, id, unit_type, 1).is_empty() and gs.issue(_C.RaiseUnits.new(tag, id, unit_type, 1)):
			did.append("raised " + unit_type)
			break
	for other in gs.nations:
		if other != tag and gs.issue(_C.ImproveRelations.new(tag, other)):
			did.append("relations with " + other)
			break
	for f in gs.fleets.values():
		if f.tag == tag and f.is_in_port():
			var zones: Array = MapData.zones_of_port(f.port)
			if not zones.is_empty() and gs.issue(_C.MoveFleet.new(tag, f.id, zones[0], 0)):
				did.append("fleet to sea")
			break
	for mode in map_view.Mode.values():
		map_view.set_mode(mode)
	map_view.set_mode(map_view.Mode.POLITICAL)

	var t := Time.get_ticks_msec()
	for day in DAYS:
		Clock.advance_day()
		if day % 10 == 0:
			await process_frame
		if not gs.pending_joins.is_empty():
			gs.pending_joins.clear()
		if not gs.pending_offers.is_empty():
			gs.pending_offers.clear()
		if day == 20:
			_move_an_army(tag)
	var seconds := (Time.get_ticks_msec() - t) / 1000.0
	print("      %s: %s; %d days in %.1f s (%.0f ms a day), %d armies, %d fleets, %d wars" % [
			tag, ", ".join(did), DAYS, seconds, seconds * 10.0, gs.armies.size(), gs.fleets.size(), gs.wars.size()])
	_check(seconds < BUDGET_SECONDS, "%s: %d days in the map scene take under %d s" % [tag, DAYS, BUDGET_SECONDS])
	_check(_sane(), "%s: the world still makes sense after %d days" % [tag, DAYS])


func _move_an_army(tag: String) -> void:
	for a in gs.armies.values():
		if a.tag == tag:
			for n in _C.Military.neighbors_for(gs, tag, a.province):
				if gs.issue(_C.MoveArmy.new(tag, a.id, n)):
					return


## No number has gone bad and nothing stands where it cannot.
func _sane() -> bool:
	var ok := true
	for tag in gs.nations:
		var n = gs.nations[tag]
		for pair in [["treasury", n.treasury], ["manpower", float(n.manpower)], ["war_support", n.war_support], ["blockade", n.blockade]]:
			if is_nan(pair[1]) or is_inf(pair[1]):
				printerr("  %s %s is %s" % [tag, pair[0], pair[1]])
				ok = false
		if n.manpower < 0:
			printerr("  %s manpower is negative" % tag)
			ok = false
	for id in range(1, gs.province_owner.size()):
		if not gs.nations.has(gs.province_owner[id]) or not gs.nations.has(gs.province_controller[id]):
			printerr("  province %d has no owner" % id)
			ok = false
			break
	for a in gs.armies.values():
		if a.province < 1 or a.province >= gs.province_owner.size():
			if not a.embarked():
				printerr("  army %d is nowhere" % a.id)
				ok = false
		if a.men() < 0:
			ok = false
	for f in gs.fleets.values():
		if f.zone < 0 or f.zone >= MapData.sea_zones.size() or f.ships.is_empty():
			printerr("  fleet %d is nowhere or empty" % f.id)
			ok = false
	return ok
