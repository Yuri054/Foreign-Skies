extends SceneTree
## Headless test of the tutorial: the steps in data/tutorial.json can each be finished by doing
## the thing the data names, a nation with no fleet skips the fleet step, a step can be skipped
## and the whole tutorial ended, the offer is made once, and a half-done tutorial does not
## disturb saving.
## Run: godot --headless --path . -s res://tests/tutorial_test.gd

const DIR := "user://test_tutorial_saves/"

var _failures := 0
var gs: Node
var Clock: Node
var main: Node
var tut: Control
var map_view: Sprite2D
var camera: Camera2D
var MapView
var _C_ConstructBuilding
var _C_RaiseUnits
var _C_MoveArmy
var _C_DesignateFront
var _C_ImproveRelations
var _C_MoveFleet
var _C_Economy
var _C_Military


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
	var UiSettings = load("res://scripts/ui/ui_settings.gd")
	UiSettings.path = "user://test_tutorial_settings.cfg"
	DirAccess.remove_absolute(UiSettings.path)
	load("res://scripts/sim/save_game.gd").dir = DIR
	MapView = load("res://scripts/map/map_view.gd")
	_C_ConstructBuilding = load("res://scripts/sim/construct_building.gd")
	_C_RaiseUnits = load("res://scripts/sim/raise_units.gd")
	_C_MoveArmy = load("res://scripts/sim/move_army.gd")
	_C_DesignateFront = load("res://scripts/sim/designate_front.gd")
	_C_ImproveRelations = load("res://scripts/sim/improve_relations.gd")
	_C_MoveFleet = load("res://scripts/sim/move_fleet.gd")
	_C_Economy = load("res://scripts/sim/economy.gd")
	_C_Military = load("res://scripts/sim/military.gd")

	var steps: Array = load("res://scripts/ui/tutorial.gd").load_steps()
	_check(steps.size() >= 10 and steps.size() <= 16, "the tutorial has about sixteen steps (%d)" % steps.size())
	var ok := true
	for s in steps:
		ok = ok and s.has("id") and s.has("title") and s.has("text") and s.has("done")
	_check(ok, "every step has an id, a title, a message and a completion condition")

	await _open_map("GBR")
	_test_offer()
	await _test_each_step(steps)
	await _test_skip_end_and_requires()
	await _test_saving()

	DirAccess.remove_absolute(UiSettings.path)
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _open_map(tag: String) -> void:
	if main != null:
		main.queue_free()
		await process_frame
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.set_player(tag)
	gs.pending_joins.clear()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	tut = get_first_node_in_group("tutorial")
	map_view = main.get_node("MapView")
	camera = main.get_node("Camera")


func _test_offer() -> void:
	_check(not tut.was_offered(), "the tutorial has not been offered yet")
	tut.after_nation_chosen()
	_check(tut.visible and not tut.active, "the first new game offers it")
	tut.decline_offer()
	_check(not tut.visible and tut.was_offered(), "declining closes the offer and remembers it")
	tut.after_nation_chosen()
	_check(not tut.visible, "it is not offered a second time")
	tut.requested = true
	tut.after_nation_chosen()
	_check(tut.active and tut.index == 0 and not tut.requested, "the menu's Tutorial button starts it at once")
	tut.end_tutorial()


## Does what a step names, through the real game where it can.
func _do(step: Dictionary) -> bool:
	var done: Dictionary = step.done
	var tag: String = gs.player_tag
	if done.has("signal"):
		match done.signal:
			"camera":
				camera.position += Vector2(300, 0)
				tut._process(0.1)
			"province_selected":
				map_view.province_selected.emit(5)
			"mode_changed":
				map_view.set_mode(MapView.Mode.TERRAIN)
			"game_saved":
				return gs.save_game(DIR + "tutorial.sav") == ""
		return true
	if done.has("window"):
		get_first_node_in_group(done.window).toggle()
		tut._process(0.1)
		return true
	if done.has("mode"):
		map_view.set_mode(MapView.Mode[done.mode[0]])
		return true
	if done.has("ack"):
		tut._got_it.pressed.emit()
		return true
	var nation = gs.nations[tag]
	match done.command:
		"ConstructBuilding":
			for id in nation.provinces:
				for type in _C_Economy.building_ids():
					if _C_Economy.build_problem(gs, tag, id, type).is_empty():
						return gs.issue(_C_ConstructBuilding.new(tag, id, type))
			return false
		"RaiseUnits":
			var type: String = _C_Military.cfg.unit_types.keys()[0]
			for id in nation.provinces:
				if _C_RaiseUnits.problem(gs, tag, id, type, 1).is_empty():
					return gs.issue(_C_RaiseUnits.new(tag, id, type, 1))
			return false
		"SetFocus":
			return gs.issue(load("res://scripts/sim/set_focus.gd").new(tag, load("res://scripts/sim/focus.gd").tree_of(tag)[0].id))
		"SetEconomyPolicy":
			return gs.issue(load("res://scripts/sim/set_economy_policy.gd").new(tag, "standing_army", float(nation.peacetime_army + 12000)))
		"MoveArmy":
			for a in gs.armies.values():
				if a.tag == tag:
					for n in _C_Military.neighbors_for(gs, tag, a.province):
						if gs.issue(_C_MoveArmy.new(tag, a.id, n)):
							return true
			return false
		"DesignateFront":
			var line: Array[int] = [nation.provinces[0]]
			return gs.issue(_C_DesignateFront.new(tag, "Test", line))
		"ImproveRelations":
			for other in gs.nations:
				if other != tag and gs.issue(_C_ImproveRelations.new(tag, other)):
					return true
			return false
		"PressDemand":
			var C = load("res://scripts/sim/crisis.gd")
			var goal: Dictionary = load("res://scripts/sim/war_goal.gd").concession_goal({"kind": "indemnity", "share": 0.05, "months": 6})
			nation.diplomacy_points = maxf(nation.diplomacy_points, 100.0)
			for other in load("res://scripts/sim/diplomacy.gd").neighbor_nations(gs, tag):
				if gs.issue(load("res://scripts/sim/press_demand.gd").new(tag, other, "", {"demand": C.demand_for(goal), "goal": goal})):
					return true
			return false
		"MoveFleet":
			for f in gs.fleets.values():
				if f.tag == tag:
					var zones: Array = root.get_node("MapData").zones_of_port(f.port) if f.is_in_port() else [f.zone]
					return gs.issue(_C_MoveFleet.new(tag, f.id, zones[0], 0))
			return false
	return false


func _test_each_step(steps: Array) -> void:
	tut.start()
	_check(tut.active and tut.index == 0, "starting the tutorial shows the first step")
	var reached := 0
	for i in steps.size():
		var step: Dictionary = tut.current()
		if step.is_empty():
			break
		_check(step.id == steps[i].id, "step %d is %s" % [i + 1, steps[i].id])
		var did := _do(step)
		_check(did, "  the player can do it: %s" % str(step.done))
		_check(tut.index != i or not tut.active, "  and doing it finishes the step")
		reached += 1
		# Time may have to be allowed to pass for nothing here: the next step must follow at once.
	_check(not tut.active and reached == steps.size(), "the last step ends the tutorial")
	tut.end_tutorial()


func _test_skip_end_and_requires() -> void:
	tut.start()
	tut.skip_step()
	_check(tut.index == 1, "skipping a step moves on")
	# Doing something else does not finish the step.
	gs.command_issued.emit("MoveFleet")
	_check(tut.index == 1, "a command the step does not name changes nothing")
	var seen := []
	tut.step_changed.connect(func(i: int) -> void: seen.append(i))
	tut.end_tutorial()
	_check(not tut.active and not tut.visible, "the tutorial can be ended at any step")
	_check(tut.current().is_empty(), "an ended tutorial has no step")
	_check(tut.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the overlay lets every click through")

	# A nation with no fleet skips the fleet step.
	await _open_map("SRB")
	var has_fleet := false
	for f in gs.fleets.values():
		has_fleet = has_fleet or f.tag == "SRB"
	_check(not has_fleet, "Serbia has no fleet")
	tut.start()
	var ids: Array = []
	for i in tut.steps.size():
		if tut.current().is_empty():
			break
		ids.append(tut.current().id)
		tut.skip_step()
	_check(not ("fleet" in ids) and "save" in ids, "the fleet step is skipped for a nation without ships")


func _test_saving() -> void:
	await _open_map("GBR")
	tut.start()
	tut.skip_step()
	tut.skip_step()
	var before: int = tut.index
	var path := DIR + "half.sav"
	_check(gs.save_game(path) == "", "a game saves with the tutorial half done")
	_check(tut.index == before and tut.active, "and saving does not move the tutorial")
	var days: int = Clock.days_elapsed
	_check(gs.load_game(path) == "" and Clock.days_elapsed == days, "it loads again")
	var snapshot: Dictionary = load("res://scripts/sim/save_game.gd").snapshot(gs)
	_check(not snapshot.state.has("tutorial") and not str(snapshot).contains("Tutorial"), "the save holds nothing of the tutorial")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(DIR + "tutorial.sav")
